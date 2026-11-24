# Infrastructure TODO — current state and remaining work

> **Snapshot:** checked-in configuration originally reviewed at infra commit `7327eb7` (`2026-11-20`), with subsequent updates noted below. Application docs/code and Azure deployment state were inspected separately. This is a repository snapshot, **not** proof that Azure resources exist or have been applied. Verify the live subscription before describing anything as deployed.
>
> **Operating target:** dev 2–3 sessions/week (about 4–6 hours total); prod showcase about 2 hours/week. AKS is disposable; dev data is disposable; retain prod data/services if the measured cost fits. Total project spend must stay below the hard **$100 USD credit ceiling**.

## Current state

### Checked-in dev/shared Terragrunt stacks

- `live/dev/resource-group`
- `live/dev/network`
- `live/dev/cosmos-db`
- `live/dev/cosmos-private-endpoint`
- `live/dev/blob-storage`
- `live/dev/blob-private-endpoint`
- `live/dev/key-vault`
- `live/dev/key-vault-private-endpoint`
- `live/dev/postgresql`
- `live/dev/redis`
- `live/dev/redis-private-endpoint`
- `live/dev/email-communication-service`
- `live/dev/aks`
- `live/dev/workload-identity`
- `live/dev/workload-federation`
- `live/shared/resource-group`
- `live/shared/container-registry`
- `live/shared/cosmos-db-account`

There is no `live/prod/` environment yet. These paths show intended configuration only; actual Azure state and spend have not been verified.

### Checked-in module directories

`aks`, `blob-storage`, `container-registry`, `cosmos-db-account`, `cosmos-db-namespace`, `email-communication-service`, `key-vault`, `network`, `postgresql`, `private-endpoint`, `redis`, `resource-group`, `workload-identity`, and `workload-federation`.

Module directories are not equivalent to complete modules, environment stacks, or applied resources. Review the older `modules/cosmosdb` against the account/namespace modules before using it.

### Important current configuration details

- `live/root.hcl` configures an Azure remote-state backend and requires an explicit, UUID-formatted `ARM_SUBSCRIPTION_ID` for both the backend and provider. The backend's existence, access, location, and charges have not been verified.
- Regional resource groups, VNet, AKS, ACR, and Cosmos account use `polandcentral`; keep that region unless service/SKU availability or cost blocks it.
- `live/dev/network` creates a VNet, an AKS subnet, and a private-endpoint subnet. The dev Cosmos private endpoint stack configures a private DNS zone and VNet link; it has not been deployed or tested.
- The AKS module configures a private API server, AKS-managed private DNS, no public API FQDN, and Run Command enabled. This configuration has not been applied or tested. It uses a Free management tier, `Standard_D2als_v7` nodes with autoscaling min 1/max 2, workload identity/OIDC, and Key Vault CSI support.
- The shared ACR stack configures Basic registry `websecchatacr`, a public endpoint, and the admin account disabled. Basic does not support anonymous pulls. The GitHub OIDC publisher and full Entra-only access policy remain to be implemented and verified; the dev AKS configuration grants its kubelet `AcrPull`. The shared stack uses a different state key than the former dev stack; inspect/migrate any existing state explicitly rather than assuming a path move migrates it.
- The shared Cosmos account has free tier enabled. Dev's `live/dev/cosmos-db` uses database `chat-dev`, container `messages`, provisioned throughput `400`, and configures a database-scoped Cosmos data-plane role for the dev workload identity. The identity and AKS federation are separate stacks so they survive cluster replacement independently. None of this has been deployed or access-tested.
- The dev ACS stack currently creates an Email Communication Service resource. A verified sender/domain and complete email configuration are not represented by the current stack. ACS has no traditional Private Link endpoint; use authenticated outbound calls and consider Network Security Perimeter only if the subscription supports it without unacceptable preview risk.
- Dev Blob Storage configures a private `attachments` container, a container-scoped workload role, public access and Shared Key disabled, and a private endpoint/DNS stack. Name availability, private provisioning/management access, and application access are not yet verified.
- Dev Key Vault configures RBAC, private networking, a workload secrets-reader role, seven-day soft delete, and no purge protection. Provider settings prevent automatic vault purge/recovery. Secret provisioning, CSI access, and name availability still need validation.
- Dev PostgreSQL configures a delegated subnet, private DNS, TLS, a `chat` database, and write-only ephemeral administrator password. `POSTGRESQL_SKU` must be selected after availability and cost review; `TF_VAR_administrator_password` must be supplied securely for OpenTofu operations. The application login, private operator access, credentials in Key Vault, lifecycle and backups are not yet tested. Increment the password version input on rotation.
- Dev Azure Managed Redis configures TLS, key authentication for the app's single `ioredis` connection, private endpoint/DNS, and disabled public access. `REDIS_SKU` and `REDIS_HIGH_AVAILABILITY` require explicit availability/cost review. The provider exports access keys into state even though no key is output; secure state and provision `REDIS_URL` into Key Vault through a private, approved operator path. DNS, connection compatibility, name availability, and lifecycle remain untested.
- Dev has no Terragrunt stack yet for Web PubSub. Other data-service private endpoints/DNS, a Gateway API controller/route, and `live/prod/` stacks are still missing.
- The `chat-webapp` repo has one GitHub Actions CI workflow for checks/tests; no image-publish or deployment workflow and no Kubernetes deployment/Gateway manifests were found. The app itself has a Dockerfile and working local Compose/emulator setup.
- The application code implements Better Auth/PostgreSQL sessions, server-mediated HTTP message writes, PostgreSQL membership authorization, Cosmos persistence, server-to-user Web PubSub events, and Redis/Web PubSub fallbacks. Azure integration has not been runtime-tested in this review.

## Ordered work

### 0. Mandatory subscription, cost, and state preflight — before any apply

- [ ] Confirm the active Azure subscription is the intended Azure for Students subscription; record the actual remaining credit and current project charges. Inventory existing resources before assuming the environment is empty.
- [x] Remove the hard-coded subscription fallback in `live/root.hcl`; require an explicit `ARM_SUBSCRIPTION_ID` for every plan/apply and verify it in the operator checklist below.
- [ ] Verify the configured remote state account/container exists, is in the intended subscription, has restricted access and locking, and has a recovery procedure. Include state storage/transactions in the project budget.
- [ ] Produce a resource-by-resource estimate for the **whole remaining credit**, including persistent prod PaaS, disposable dev stacks, both private DNS/endpoint paths, Gateway controller, public/static IPs, outbound data, backups, ACR, logs, and state. Check the official pricing calculator/actual subscription price; do not rely on a single service's headline or free tier.
- [ ] Test service/SKU availability in `polandcentral`. If any required service is unavailable or exceeds budget there, stop and get a region/design review before changing region or provisioning.
- [ ] Determine which services can be stopped, which continue billing when AKS is absent, and what deleting each individual Terragrunt stack removes. Record data-loss and recreation consequences. Alerts are not spending caps.
- [ ] Keep a safety margin under $100. Do not apply a stack if total lifetime/run-window costs could exhaust the remaining credit.

#### Read-only preflight observations — 2026-11-24

- The user confirmed the enabled `Azure for Students` subscription ending `b2fcbf68` as the intended target. Resource inventory returned resource groups `tofu-rg` and `websec`, and one resource: storage account `chatopentofu` in `tofu-rg`, `polandcentral`. This is a point-in-time inventory, not proof of all billing or data-plane activity.
- The `tfstate` container exists and was readable with Entra authentication. On 2026-11-24, Terragrunt rendered `dev/resource-group/tofu.tfstate` as the current dev resource-group key. That blob and the older `live/dev/resource-group/tofu.tfstate` have distinct state lineages; both current versions contain no resources or outputs. An older version of the latter recorded `chat-dev-rg`, which was absent from the read-only resource-group inventory. Blob versions remain available. This establishes the current configured key and observed history, not permission to migrate/delete either blob or restore an old version.
- Blob versioning is enabled; blob soft delete is disabled. Container-level and blob-level leases were unlocked at inspection time; this does not prove OpenTofu locking works. The storage account allows network access by default, while anonymous blob access is disabled. Review inherited access, network restrictions, recovery, and locking before treating the backend as verified.
- The user reported approximately $100 remaining student credit on 2026-11-24. Billing and consumption queries did not independently establish the credit balance or total project charges. The rest of the cost, region/SKU, quota, and backend checks remain open; do not run a plan based on these observations alone.

#### Operator subscription checklist — before each plan/apply

- [ ] Confirm the intended Azure for Students subscription and the signed-in account with `az account show` and `az account list`; do not assume the active subscription is correct.
- [ ] Set `ARM_SUBSCRIPTION_ID` explicitly to the verified subscription UUID, and compare it with the intended account and the configured remote-state subscription. The backend and provider both use this value; changing it can target a different state and resources.
- [ ] Complete the remaining credit, resource inventory, backend, availability, quota, and lifecycle cost checks above before planning or applying. A valid UUID alone does not verify the subscription or authorize provisioning.

### 1. Secure and stabilize network/state foundations

- [x] Configure AKS for a private control plane, AKS-managed private DNS, and Run Command; disable the public API FQDN. Changing an existing public cluster to private requires replacement; review the plan before any approved apply.
- [ ] Validate the private DNS and test operator access using manual `az aks command invoke` / portal Run Command with least-privilege Azure RBAC. This is the initial manual access path; do not add a permanent VPN/VM without cost review.
- [ ] Keep the app Gateway's public ingress separate from the private AKS API server. Select and price a compatible Gateway API controller; deploy only the necessary public HTTPS listener/routes.
- [ ] Allocate a stable Gateway public IP and a stable AKS outbound/egress IP in network-level stacks that survive cluster destruction/recreation. Verify they have no unintended inbound listener; cost them and document who owns them.
- [ ] Keep Cloudflare as DNS provider. Point `dev.chat.nkdm.io` to the dev Gateway and `chat.nkdm.io` to the prod Gateway. Select/test the Cloudflare proxy mode, end-to-end TLS certificate path, DNS updates, and recovery if an IP changes.
- [ ] Create private DNS zones and VNet links for every private endpoint. Ensure the shared Cosmos account resolves privately from dev and prod VNets.
- [ ] Restrict public service exposure as recorded in `plan.md`: private PostgreSQL, Cosmos, Blob Storage, Redis, and Key Vault; public Web PubSub `ClientConnection` only for browser WSS plus server REST restricted to fixed AKS egress IP; authenticated public ACR; authenticated outbound ACS Email.

### 2. Complete dev identity and private data services

- [ ] Review/apply existing shared and dev resource-group, network, ACR, Cosmos, ACS, and AKS plans one at a time after the preflight and network design are ready.
- [ ] Validate the configured dev Cosmos private endpoint/DNS and disabled account public access; add a separate prod private path when prod is built. Confirm the account is eligible for free tier and the aggregate `chat-dev` + `chat-prod` throughput and storage stay within allowances.
- [ ] Verify the configured dev Cosmos data-plane role for the dev workload identity is scoped to `chat-dev` and cannot access prod. The identity and database role are configured but not deployed or tested.
- [ ] Preserve an independent shared Cosmos account state stack. Implement dev database teardown/recreation so destroying `live/dev/cosmos-db` cannot destroy the shared account or `chat-prod`.
- [ ] Complete and validate private PostgreSQL: select an available/cost-reviewed SKU, configure a least-privilege application login and secret-backed `DATABASE_URL`, verify private operator access and TLS/backups, and test start/stop/delete/recreate. The server, database, delegated subnet and private DNS are configured but not deployed.
- [ ] Validate the configured private Blob Storage, `attachments` container, private endpoint/DNS, and container-scoped workload role. Verify operator provisioning and data-plane access with public access and Shared Key disabled; check the account name is available.
- [ ] Select an available/cost-reviewed Redis SKU and HA setting; validate the configured Azure Managed Redis private endpoint/DNS, TLS/key auth and application compatibility; provision `REDIS_URL` privately and test lifecycle. Preserve the app's Redis fallbacks; Redis is not the authorization source of truth.
- [ ] Validate the configured dev Key Vault private endpoint/DNS, workload identity and CSI access; establish a private operator path to provision secrets. Dev uses 7-day soft delete; purge protection is disabled for both environments by user decision. Choose prod retention before creation.
- [ ] Add Web PubSub with request-type/network ACLs: public client connections for browser WSS; client credentials only minted by the authenticated API and receive-only; REST API access only from the fixed AKS egress IP; deny other public request types. Verify the chosen tier's connection limits, pricing, and ACL behavior.
- [ ] Add the dev app workload identity/federated Kubernetes service-account credential `chat/chat-app`. Grant only required resource roles; verify Cosmos, Blob, Web PubSub and ACS permissions. Keep CI publish identity, kubelet image-pull identity, and human operator identity separate.
- [ ] Set Azure configuration from `chat-webapp/.env.example`: `AUTO_PROVISION=false`, no emulator `*_CONNECTION_STRING` values, non-secret settings in ConfigMap, `BETTER_AUTH_SECRET`/`DATABASE_URL`/`REDIS_URL` in Key Vault/CSI, and `COSMOS_DATABASE=chat-dev`.
- [ ] Finish ACS Email setup and verified sender/domain/DNS. Use the app's workload identity and least-privilege send role. Consider ACS Network Security Perimeter only as optional hardening if the subscription feature and preview terms are acceptable; do not make app delivery depend on it.
- [ ] Configure ACR with Entra-only operations: admin account off, no anonymous access, GitHub OIDC identity limited to `AcrPush`, AKS kubelet identity limited to `AcrPull`. Its public endpoint is an intentional exception because the GitHub-hosted runner is outside the VNet.

### 3. Deploy and validate dev

- [ ] Add Kubernetes Deployment/Service/ConfigMap/SecretProviderClass and Gateway API manifests or Helm chart. Keep one app image and one HTTPS origin; do not add SWA or Web PubSub event webhooks.
- [ ] Implement/price the Gateway API controller and TLS for `dev.chat.nkdm.io`. Ensure user traffic reaches the app through Gateway only; the Kubernetes API server remains private.
- [ ] Add a GitHub Actions image workflow: PRs run existing checks; merge to default branch builds and pushes an immutable image tag to ACR using OIDC. Do not auto-deploy or auto-apply OpenTofu.
- [ ] Write manual `dev-start` and `dev-stop` runbooks. Start/prepare required data services; create/recreate AKS; deploy the chosen image; run the `migrator` image target as a one-off Kubernetes Job before rollout; smoke-test; then destroy AKS and any explicitly disposable dev data stacks. Preserve shared Cosmos account/state and any data the team elects to retain.
- [ ] Verify `/api/health` is process liveness. Verify `/api/ready` only fails for PostgreSQL/Cosmos; Redis and Web PubSub status may be degraded. Test Redis fallback, Web PubSub reconnect/polling, email verification, auth/revocation, conversations, message persistence, attachments, and admin features.
- [ ] Check the bill after dev sessions and record actual persistent/idle costs. Do not infer that the data services stopped when AKS was destroyed.

### 4. Add prod after dev acceptance

- [ ] Require dev end-to-end acceptance, working private networking, tested AKS recreate, stable host/IP behavior, and actual cost observations first.
- [ ] Create `live/prod/` by reusing the approved modules with distinct resource names, state keys, identity, secrets, app data, and `COSMOS_DATABASE=chat-prod`. Share the Cosmos account and ACR by deliberate choice; use a private endpoint/DNS path for the prod VNet and prod-scoped data access.
- [ ] Deploy the public route at `chat.nkdm.io`; keep AKS control plane private and data service public access disabled. Apply the Web PubSub client-connection/server-REST ACL and ACR/ACS identity policies consistently with dev.
- [ ] Keep prod data services and showcase data between weekly sessions when their measured retained cost fits the remaining $100 credit. Destroy/recreate the stateless prod AKS cluster between sessions. If the budget requires destroying stateful prod resources, record exactly which data will be lost and rebuild procedure before doing so.
- [ ] Write and test `showcase-start` / `showcase-stop` runbooks. After the showcase, verify actual spend, cluster deletion, PaaS retention, public IP/DNS behavior, and budget margin.

### 5. Documentation and scope hygiene

- [x] Consolidate `infra/docs/` to `plan.md` (desired state) and `todo.md` (current state/work remaining).
- [x] Align tracked `chat-webapp/PLAN.md` and `chat-webapp/AGENT-IMPLEMENTATION.md` to point at the canonical infra plan/todo; remove conflicting architecture proposals.
- [x] Make targeted consistency updates to `chat-webapp/docs/architecture.md` and `chat-webapp/docs/azure-deployment.md`, preserving their existing uncommitted changes.
- [ ] Workspace-level planning notes outside the infra and app Git repositories were not included in this reconciliation; review or retire them separately if they are still shared/used.
