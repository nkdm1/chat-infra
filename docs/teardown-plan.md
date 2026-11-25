# Dev teardown plan (proposed, not yet approved or executed)

Goal: stop billing for the dev environment while keeping what is needed to rebuild it later.
Terraform state backend (`polandcentral`, storage `chatopentofu`) is **not touched**.
Each step is a reviewed `terragrunt plan -destroy` followed by `terragrunt destroy`, in the order below.
Stop at the first unexpected resource, error, or dependency.

## 0. Decisions needed before executing

| # | Item | Options | Recommendation |
|---|---|---|---|
| D1 | Operator secret vault | Separate vault in `chat-shared-rg`, public access on, network ACL default Deny + your IP, RBAC for you only | Yes. Costs ~0. Not in the app identity's reach. Avoids keeping a private endpoint |
| D2 | Container Registry `websecchatacr` (Basic, ~€0.85/month) | Keep (images survive, rebuild skipped) / destroy (rebuild via CI) | Keep, unless the budget is critical |
| D3 | Cosmos account `chat-cosmos-cf816eae` (free tier) | Keep (no idle cost) / destroy | Keep account; destroy dev DB and its private endpoint |
| D4 | Dev data (Postgres `chat`, Redis, Blob `attachments`, Cosmos `chat-dev`) | Destroy and regenerate | Accept loss; no production data exists |
| D5 | Azure Communication Services / Email | Keep (no idle cost) / destroy | Keep |
| D6 | Web PubSub Free | Destroy | Destroy (recreate is free) |

## 1. Preparation (before any destroy)

1. Create the operator vault (D1) in `chat-shared-rg` with network default Deny, add your current public IP, and grant your user `Key Vault Secrets Officer` on it only.
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
| 2.5 | `live/dev/cosmos-private-endpoint`, then `live/dev/cosmos-db` (DB and container only) | Keep account per D3 |
| 2.6 | `live/dev/blob-private-endpoint`, then `live/dev/blob-storage` | Destroys `attachments` data (D4) |
| 2.7 | `live/dev/key-vault-private-endpoint`, then `live/dev/key-vault` | App vault: soft-deleted for 7 days, purge protection off. Operator copies live in the D1 vault |
| 2.8 | `live/dev/pubsub` | Web PubSub Free (D6) |
| 2.9 | `live/dev/postgresql` | Server and database (D4). Requires the admin password input |
| 2.10 | `live/dev/postgresql-network` | Sweden VNet and peering. Destroy only after 2.9 |
| 2.11 | `live/dev/workload-federation`, `live/dev/workload-identity` | Federated credential and app identity |
| 2.12 | `live/dev/network` | VNet, subnets, static egress and gateway public IPs (€0.12 per 3 days) |
| 2.13 | Private DNS zones left in `chat-dev-rg` (Redis, Blob, Vault, Cosmos, Postgres) | Removed with their stacks; confirm none remain |
| 2.14 | `live/dev/resource-group` | `chat-dev-rg`, only once it is empty |
| 2.15 | `live/dev/email-communication-service` | Only if D5 = destroy |
| 2.16 | `live/shared/container-registry`, `live/shared/cosmos-db-account` | Only if D2/D3 = destroy |

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

- Dev database contents and Blob attachments are lost (D4).
- Re-creating the environment later needs: GitHub publish image (still in ACR if D2 = keep), `docs/runbook-dev-bringup.md`, and the operator vault secrets.
- Cluster-admin credentials issued earlier become invalid when the AKS cluster is deleted.
- Cross-region PostgreSQL peering costs stop only after step 2.10.

## 5. Approval

Reply with decisions D1–D6 and approval for steps 1–2. I'll run each stack's destroy plan first, show it to you, and continue only after your go-ahead.
