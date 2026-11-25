# Dev teardown plan (proposed, not yet approved or executed)

Goal: stop billing for the dev environment while keeping what is needed to rebuild it later.
Terraform state backend (`polandcentral`, storage `chatopentofu`) is **not touched**.
Each step is a reviewed `terragrunt plan -destroy` followed by `terragrunt destroy`, in the order below.
Stop at the first unexpected resource, error, or dependency.

## 0. Decisions (approved 2026-11-25)

| # | Item | Options | Recommendation |
|---|---|---|---|
| D1 | Operator secret vault | **APPROVED, created:** `chat-ops-cf816eae-kv` in `chat-shared-rg`, RBAC, public access on with default Deny, allowed IP `185.72.186.2/32`, Secrets Officer for your user only | Created; no private endpoint |
| D2 | Container Registry `websecchatacr` (Basic, ~€0.85/month) | **KEEP** |
| D3 | Cosmos account `chat-cosmos-cf816eae` (free tier) | **KEEP account, remove data** (dev DB `chat-dev`, container, private endpoint) |
| D4 | Dev data (Postgres `chat`, Redis, Blob `attachments`, Cosmos `chat-dev`) | **WIPE** (accepted) |
| D5 | Azure Communication Services / Email | **KEEP** (in `chat-dev-rg`) |
| D6 | Web PubSub Free (`chat-dev-cf816eae-wps`, Sweden Central) | **KEEP.** Free tier: 1 unit, 20 concurrent connections, 20k messages/day; no idle charge (verify in billing) |

## 1. Preparation (before any destroy)

1. **Done:** operator vault created (D1).
2. Store, by hand, in the operator vault:
   - `postgresql-admin-password` (chatadmin)
   - `cloudflare-origin-key` (private key) and `cloudflare-origin-cert` (PEM)
   - `database-url`, `redis-url`, `better-auth-secret` (copies of the dev values, for rebuild)
   - Verify each with `az keyvault secret show --query id` (names only).
3. Record the working release values from `deploy/environments/dev/chat-values.yaml` (already committed).
4. Remove the **temporary** operator grants now, if still present:
   - `live/dev/operator-aks-access` (cluster-admin role and AKS DNS link)
   - `live/dev/operator-secret-access` (Secrets Officer on the app vault)
   - `live/dev/operator-redis-access` (already removed)

## 2. Destroy order

| Step | Stack | Why / notes |
|---|---|---|
| 2.1 | Cloudflare DNS record `chat` (manual) | Remove so it does not point at a released public IP |
| 2.2 | `live/dev/operator-access` | Operator VM, Bastion, NSG, subnet, NIC. Deleting the VM also deletes its OS disk (default). Operator-only |
| 2.3 | `live/dev/aks` | Deletes the cluster, node pool, and its managed load balancer and resource group. Also invalidates the earlier admin kubeconfig |
| 2.4 | `live/dev/redis-private-endpoint`, then `live/dev/redis` | Redis cache (~€0.22 per 3 days, largest data-service cost) |
| 2.5 | `live/dev/cosmos-private-endpoint`, then `live/dev/cosmos-db` (DB and container only) | Keep account per D3; removes data and the endpoint |
| 2.6 | `live/dev/blob-private-endpoint`, then `live/dev/blob-storage` | Destroys `attachments` data (D4) |
| 2.7 | `live/dev/key-vault-private-endpoint`, then `live/dev/key-vault` | App vault: soft-deleted for 7 days, purge protection off. Operator copies live in the D1 vault |
| 2.8 | — | Web PubSub kept (D6). Do not destroy `live/dev/pubsub` |
| 2.9 | `live/dev/postgresql` | Server and database (D4). Requires the admin password input |
| 2.10 | `live/dev/postgresql-network` | Sweden VNet and peering. Destroy only after 2.9 |
| 2.11 | `live/dev/workload-federation`, `live/dev/workload-identity` | Federated credential and app identity |
| 2.12 | `live/dev/network` | VNet, subnets, static egress and gateway public IPs (€0.12 per 3 days) |
| 2.13 | Private DNS zones left in `chat-dev-rg` (Redis, Blob, Vault, Cosmos, Postgres) | Removed with their stacks; confirm none remain |
| 2.14 | — | `chat-dev-rg` is **kept** (holds Web PubSub, ACS/Email). Empty of billable items after steps above |
| 2.15 | — | Email/ACS kept (D5) |
| 2.16 | — | ACR and Cosmos account kept (D2, D3) |

Helm releases (`chat`, `nginx-gateway-fabric`) and the `chat-tls` Secret go with the cluster in 2.3; no separate step is needed.

## 3. Verification after destruction

- `az resource list -g chat-dev-rg` returns nothing, or only expected kept items.
- No public IP, Bastion, VM, managed disk, load balancer, or AKS resource remains in any group.
- No private endpoints remain. Private DNS zones are gone unless deliberately kept.
- `az role assignment list` for the removed VM identity returns nothing.
- Cloudflare: no `chat` A record.
- Cost Management: the next daily check shows no new Virtual Network, Redis, VM, or Public IP charges. Expect late billing for the last hours, so check again after 48–72 hours.
- Terragrunt state for destroyed stacks is empty; the backend remains intact.

## 4. Risks accepted

- Dev database contents, Redis data and Blob attachments are lost (D4).
- Re-creating the environment later needs: container images (kept in ACR, D2), `docs/runbook-dev-bringup.md`, and the operator vault secrets.
- Cluster-admin credentials issued earlier become invalid when the AKS cluster is deleted.
- Cross-region PostgreSQL peering costs stop only after step 2.10.

## 5. Approval

Approved decisions are recorded above. Next: you store the secrets in `chat-ops-cf816eae-kv` (step 1.2), then I run destroy plans step by step and stop for your go-ahead before each destroy.

## 6. Execution record (2026-11-25, 19:40–20:34 UTC)

| Step | Result |
|---|---|
| 1.4 temporary access | `operator-aks-access` destroyed (2). `operator-secret-access` and `operator-redis-access` already had no resources |
| 2.1 Cloudflare `chat` record | Deleted manually by the user before 2.2 |
| 2.2 operator VM, Bastion, NSG, NIC, subnet | Destroyed (6) |
| 2.3 AKS `chat-dev-aks` | Destroyed (6); Helm releases, Gateway and `chat-tls` went with it |
| 2.4 Redis + endpoint | Destroyed (4) |
| 2.5 Cosmos endpoint + dev DB | Destroyed (6); account `chat-cosmos-cf816eae` kept |
| 2.6 Blob endpoint + storage | Destroyed (6) |
| 2.7 app Key Vault + endpoint | Destroyed (6); vault soft-deleted for 7 days |
| 2.8 Web PubSub | Skipped (kept, D6) |
| 2.9 PostgreSQL server + DB + DNS | Destroyed (6) |
| 2.10 Swedish network + peerings | Destroyed (4) |
| 2.11 federation + app identity | Identity destroyed (1); its federated credential is removed by Azure. **Federation state entry not removed**: Terragrunt cannot read that stack without the deleted AKS outputs. Harmless, no cost; clean later with a manual backend edit if desired |
| 2.12 Belgium VNet, subnets, public IPs | Destroyed (6) |
| 2.13 private DNS zones | Removed with their stacks (none remain) |
| 2.14 `chat-dev-rg` | Kept: holds Web PubSub and email/ACS |
| 2.15–2.16 | Kept (D2, D3, D5) |

Remaining: `chat-dev-cf816eae-wps` (Web PubSub Free), `chat-dev-acs` + `chat-dev-email`, `websecchatacr` (Basic), `chat-github-publisher`, `chat-cosmos-cf816eae` (free tier, no data), `chat-ops-cf816eae-kv` (operator secrets, public access restricted to 185.72.186.2). The Terraform state backend was not touched.

Verification done: no VMs, Bastion, AKS, private endpoints, or public IPs remain in any subscription resource group. Billing must be rechecked over the next 48–72 hours to confirm the Virtual Network, Redis, VM, and IP lines drop to zero.
