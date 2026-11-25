# Dev environment bring-up runbook (as executed 2026-11-25)

Purpose: reproduce the working dev environment with Ansible (or equivalent) without manual Bastion work.
This records what was actually done, in order, with the lessons learned. Secrets are **never** written here:
see "Secrets" below. Identifiers (subscription, tenant, client IDs, names) are not secrets.

Subscription: `cf816eae-f4d9-4db4-bfa6-bda71e2cbf68` (Azure for Students). Tenant: `d0da435b-a7e7-4d74-a4ae-f72cf8f3b2db`.
Dev region: `belgiumcentral`. Exception: Web PubSub (`swedencentral`), PostgreSQL + its VNet (`swedencentral`), operator VM/Bastion (`swedencentral`).
Reason: Belgium Central could not allocate PostgreSQL (B1ms and B2s, `RegionalAllocationFailed`) and the operator VM size; Sweden Central was used for those.

## 0. Preconditions

- Azure CLI logged in to the subscription above; OpenTofu and Terragrunt installed.
- `ARM_SUBSCRIPTION_ID` set explicitly for every Terragrunt command.
- Subscription resource providers registered: ContainerRegistry, DBforPostgreSQL, Cache, DocumentDB, KeyVault, ManagedIdentity (plus those already registered).
- GitHub repo variables/secrets for the publish workflow: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` as **GitHub Actions secrets** (not variables).
- The subscription's Azure Policy allows only Germany West Central, Sweden Central, Denmark East, Poland Central and Belgium Central. **Spain Central is denied** for ACR. Verify before any region change.

## 1. Infrastructure (Terragrunt stacks, in this order)

Apply each stack individually with `terragrunt apply` after reviewing its plan. Order matters because of dependencies.

| # | Stack | Result |
|---|-------|--------|
| 1 | `live/shared/resource-group` | `chat-shared-rg` (Spain Central, created before the policy denial; keeps existing) |
| 2 | `live/shared/container-registry` | ACR `websecchatacr` (Basic, admin disabled, Belgium Central) |
| 3 | `live/shared/github-publisher` | Identity `chat-github-publisher`, federated credential for `repo:nkdm1/chat@<owner-id>/chat@<repo-id>:ref:refs/heads/main`, `AcrPush` on the registry. Owner ID `148000728`, repo ID `1409133021` |
| 4 | `live/shared/cosmos-db-account` | `chat-cosmos-cf816eae` (free tier, public access off) |
| 5 | `live/dev/resource-group` | `chat-dev-rg` |
| 6 | `live/dev/network` | VNet `chat-dev-vnet` `10.1.0.0/16`, AKS subnet `10.1.1.0/24`, PE subnet `10.1.2.0/24`, static egress IP and gateway IP |
| 7 | `live/dev/workload-identity` | `chat-dev-app` managed identity |
| 8 | `live/dev/workload-federation` | Federated credential `chat/chat-app` on the AKS OIDC issuer |
| 9 | `live/dev/cosmos-db` | DB `chat-dev`, container `messages`, data role for the app identity |
| 10 | `live/dev/cosmos-private-endpoint` | Cosmos private endpoint + DNS |
| 11 | `live/dev/key-vault` | `chat-dev-cf816eae-kv` (RBAC, public access off, purge protection off, 7-day soft delete) |
| 12 | `live/dev/key-vault-private-endpoint` | Vault private endpoint + DNS; Sweden VNet link added |
| 13 | `live/dev/blob-storage` | `chatdevcf816eaest` (no shared keys, public off) |
| 14 | `live/dev/blob-private-endpoint` | Blob private endpoint + DNS |
| 15 | `live/dev/pubsub` | Web PubSub `chat-dev-cf816eae-wps` **Free_F1 in Sweden Central**, no network ACLs (Free rejects them); local auth off |
| 16 | `live/dev/email-communication-service` | ACS `chat-dev-acs` + Email `chat-dev-email` with Azure-managed domain `56d14771-a18f-48cd-b308-c7f85d6d543f.azurecomm.net` |
| 17 | `live/dev/redis` | Managed Redis `chat-dev-cf816eae-redis` `Balanced_B0`, TLS, port 10000 |
| 18 | `live/dev/redis-private-endpoint` | Redis private endpoint + DNS |
| 19 | `live/dev/postgresql-network` | Sweden VNet `chat-dev-postgresql-vnet` `10.2.0.0/16`, delegated subnet `10.2.1.0/24`, peering with `chat-dev-vnet` |
| 20 | `live/dev/postgresql` | Server `chat-dev-cf816eae-se-pg` Sweden Central, PG 17, `B_Standard_B1ms`, private, TLS required; DB `chat`. Needs `POSTGRESQL_SKU=B_Standard_B1ms` and the admin password (see Secrets) |
| 21 | `live/dev/aks` | AKS `chat-dev-aks`, Free tier, private API, 1 system node `Standard_D2s_v4` (autoscale 1–2), pods `10.3.0.0/22`, services `10.3.4.0/24`, DNS `10.3.4.10`. CIDRs must not overlap PostgreSQL `10.2.0.0/16` |
| 22 | `live/dev/operator-access` | **Temporary** operator VM + Bastion Developer (Sweden). See "Temporary access" |
| 23 | `live/dev/operator-secret-access` | **Temporary** Key Vault Secrets Officer for the VM identity |
| 24 | `live/dev/operator-redis-access` | **Temporary** custom role for Redis `listKeys` |
| 25 | `live/dev/operator-aks-access` | **Temporary** AKS DNS link + Cluster Admin role for the VM identity |

Known Terragrunt gotchas met:
- Dependencies are resolved from applied state; a plan alone does not create outputs.
- AKS `chat-dev-aks` needs `OPERATOR_SSH_PUBLIC_KEY` and `POSTGRESQL_SKU` in the environment where those stacks are planned.
- Stacks that reference `dependency.postgresql_network` need that stack applied first.

## 2. In-cluster components (run via `az aks command invoke`; the API is private)

Required because the Kubernetes API is private and reachable only from the VNet.

1. Gateway API CRDs (standard channel, v1.4.1):
   `curl -fsSLO https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml` then `kubectl apply -f`.
   Note: `kubectl kustomize` against GitHub fails inside AKS Run Command (no `git`); use the release file.
2. NGINX Gateway Fabric 2.9.1:
   `helm upgrade --install nginx-gateway-fabric oci://ghcr.io/nginx/charts/nginx-gateway-fabric --version 2.9.1 -n nginx-gateway --create-namespace --wait`.
   Result: GatewayClass `nginx` accepted.
3. Application namespace `chat` exists. Service account `chat-app` was created outside Helm; mark ownership before the next install or let `--take-ownership` adopt it.
4. Secret Store CSI driver is an AKS add-on (`azurekeyvaultsecretsprovider`). Workload identity is enabled.
5. TLS secret `chat-tls` (type `kubernetes.io/tls`) in `chat`, created from the Cloudflare Origin CA certificate for `chat.nkdm.io` and `dev.chat.nkdm.io`. Created by `install-chat-tls.py` (hidden prompts; checks the key matches the cert, the SAN, and refuses to overwrite).
6. Migration release (one-shot): `helm upgrade --install chat ./chat -f values.yaml` with `migration.enabled: true`, a **unique job name** (`chat-db-migrate-<sha>`), and the migrator digest. It completed with "migrations applied".
7. App release: same chart with `app.enabled: true`, `migration.enabled: false`, `hostname: chat.nkdm.io`, `tlsSecretName: chat-tls`, `gatewayPublicIpName: chat-dev-vnet-gateway-ip`, `gatewayPublicIpResourceGroup: chat-dev-rg`. Values file: `deploy/environments/dev/chat-values.yaml` (non-secret).

Verified after deploy: pods `chat` and `chat-nginx` Running, Gateway `chat` Programmed at `9.160.34.163`, HTTPRoute for `chat.nkdm.io`, `/api/health` returns 200 in-cluster.

## 3. Public DNS and TLS (Cloudflare)

- DNS record `A  chat  9.160.34.163`, **Proxied**. (The public IP is `chat-dev-vnet-gateway-ip`.)
- SSL/TLS mode: **Full (strict)**.
- Edge certificate: Universal SSL covers only one subdomain level. `dev.chat.nkdm.io` is NOT covered and gives "not covered by a certificate". Use `chat.nkdm.io` (or buy Advanced Certificate Manager).

## 4. Application configuration gotchas

- `BETTER_AUTH_URL` is built from `hostname`. Changing the hostname updates the ConfigMap but **does not restart pods**. Run `kubectl rollout restart deploy/chat -n chat` after any hostname change, then verify `printenv BETTER_AUTH_URL`. Symptom if forgotten: sign-up fails with "Something went wrong" and logs show `Invalid origin`. Fix in chart: add a checksum annotation to the pod template.
- Sign-up was reported to fail until the restart; after restart the demo worked.
- Rate limiting logs a warning that no trusted client IP header is configured (`advanced.ipAddress`). Not blocking; fix before production.

## 5. Secrets (values must never be written in this repo, logs, or chat)

Stored in Key Vault `chat-dev-cf816eae-kv` (names only are verified; values were never displayed):
- `database-url`: `chat_app` login, DB `chat`, host `chat-dev-cf816eae-se-pg.postgres.database.azure.com`, `sslmode=verify-full`. Password is the non-admin one created in SQL.
- `redis-url`: `rediss://default:<key>@chat-dev-cf816eae-redis.belgiumcentral.redis.azure.net:10000`.
- `better-auth-secret`: random, generated on the VM.

Generated and held by the operator only:
- PostgreSQL admin password (`chatadmin`) for Terraform `administrator_password_wo` and admin SQL. Keep in the password manager; never in Key Vault.
- Cloudflare Origin CA private key (in the password manager and loaded into `chat-tls`).

Automation requirement: any Ansible role must fetch these from an approved secret source, pass them via stdin or `no_log`, never as CLI arguments, and must not overwrite an existing secret without an explicit rotate flag. Changing `better-auth-secret` logs out all users.

SQL for the app login (run as `chatadmin` in DB `chat`; the password comes from a prompt):
```sql
CREATE ROLE chat_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
\password chat_app
GRANT CONNECT, CREATE ON DATABASE chat TO chat_app;
GRANT USAGE, CREATE ON SCHEMA public TO chat_app;
```
Known limitation: this gives the app DDL rights (migrations share the login). Acceptable for the dev demo only.

## 6. Temporary access used (all must be removed or revoked after use)

- `operator-access`: VM `chat-dev-operator` (Standard_B2ls_v2, no public IP, key-only SSH, guest user `operator` created **manually** because cloud-init failed on the existing `operator` group) + Bastion Developer. Rebuild requires a non-conflicting username.
- `operator-secret-access`: Key Vault Secrets Officer on the VM identity (broad).
- `operator-redis-access`: Redis `listKeys` custom role (already destroyed).
- `operator-aks-access`: AKS DNS link + Azure Kubernetes Service Cluster Admin Role. **An admin kubeconfig was obtained** (in `/dev/shm` on the VM). Deleting the role does not revoke the issued client certificate; rotate cluster credentials (`az aks rotate-certs` or `az aks get-credentials --admin` rotation procedure) after teardown review.

## 7. Known incidents and fixes

| Symptom | Cause | Fix |
|---|---|---|
| Belgium PostgreSQL/VM `RegionalAllocationFailed` | Capacity | Move to Sweden Central |
| Sweden PostgreSQL create "exists in Belgium" | Azure name conflict report, not reproducible | Use distinct name `-se-pg` |
| Web PubSub Free `Free tier doesn't support setting network ACLs` | Free SKU | Omit ACL resource for Free |
| Operator VM cloud-init failed | `operator` group existed | Manual user creation (see incident doc) |
| Bastion "no response" disconnect | Guest had no user | Same as above |
| Gateway hostname "not covered by certificate" | Edge cert one-level limit | Use one-level hostname |
| Sign-up "something went wrong" | Stale `BETTER_AUTH_URL` | Rollout restart |

## 8. Teardown order (not yet executed)

Remove dependents first. Delete temporary access, then app/cluster, then endpoints, then data services, then network, then shared where safe. Keep Terraform state backend and `chat-shared-rg` state if you want to redeploy cheaply.

Inventory of billable items (2026-11-25): AKS cluster + node VM, static public IPs x2, Bastion Developer, operator VM + disk, Redis Balanced_B0, PostgreSQL B1ms + storage, Key Vault, Cosmos (free tier, but throughput billed beyond free allowance), Blob account, Web PubSub Free, ACS/Email, ACR Basic, private endpoints x5 + DNS zones, VNet peering (cross-region traffic). Current measured cost: VNet ~0.61 EUR (likely peering/egress/Bastion, to be confirmed in Cost Analysis), Redis ~0.22, VMs ~0.11, ACR ~0.09, rest < 0.05 EUR.
