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
- `live/dev/pubsub`
- `live/dev/email-communication-service`
- `live/dev/aks`
- `live/dev/workload-identity`
- `live/dev/workload-federation`
- `live/shared/resource-group`
- `live/shared/container-registry`
- `live/shared/github-publisher`
- `live/shared/cosmos-db-account`

There is no `live/prod/` environment yet. These paths show intended configuration only; actual Azure state and spend have not been verified.

### Checked-in module directories

`aks`, `blob-storage`, `container-registry`, `cosmos-db-account`, `cosmos-db-namespace`, `email-communication-service`, `github-publisher`, `key-vault`, `network`, `postgresql`, `private-endpoint`, `pubsub`, `redis`, `resource-group`, `workload-identity`, and `workload-federation`.

Module directories are not equivalent to complete modules, environment stacks, or applied resources. Review the older `modules/cosmosdb` against the account/namespace modules before using it.

### Important current configuration details

- `live/root.hcl` configures an Azure remote-state backend and requires an explicit, UUID-formatted `ARM_SUBSCRIPTION_ID` for both the backend and provider. The backend's existence, access, location, and charges have not been verified.
- Regional resource groups, VNet, AKS, ACR, and Cosmos account use `polandcentral`; keep that region unless service/SKU availability or cost blocks it.
- `live/dev/network` configures a VNet, AKS, private-endpoint and delegated PostgreSQL subnets, and separate static egress and Gateway IPs. AKS uses a Standard Load Balancer with the network-owned egress IP. The IPs survive AKS deletion and continue to incur charges. The dev Cosmos private endpoint stack configures a private DNS zone and VNet link; none of this has been deployed or tested.
- The AKS module configures a private API server, AKS-managed private DNS, no public API FQDN, and Run Command enabled. This configuration has not been applied or tested. It uses a Free management tier, `Standard_D2als_v7` nodes with autoscaling min 1/max 2, workload identity/OIDC, and Key Vault CSI support.
- The shared ACR stack configures Basic registry `websecchatacr`, a public endpoint, and the admin account disabled. Basic does not support anonymous pulls. The GitHub OIDC publisher and full Entra-only access policy remain to be implemented and verified; the dev AKS configuration grants its kubelet `AcrPull`. The shared stack uses a different state key than the former dev stack; inspect/migrate any existing state explicitly rather than assuming a path move migrates it.
- The shared Cosmos account has free tier enabled. Dev's `live/dev/cosmos-db` uses database `chat-dev`, container `messages`, provisioned throughput `400`, and configures a database-scoped Cosmos data-plane role for the dev workload identity. The identity and AKS federation are separate stacks so they survive cluster replacement independently. None of this has been deployed or access-tested.
- The dev ACS stack configures an Email Communication Service, Azure-managed sender domain, linked Communication Service and sender/endpoint outputs. A custom role scoped to that Communication Service grants the app `CommunicationServices/read` and `/write` by user decision; write also permits service configuration changes. These reported SDK permissions, name availability, sender and delivery have not been verified. The AzureRM Communication Service resource exposes access keys in state even though they are not output; secure the backend. ACS has no traditional Private Link endpoint.
- Dev Blob Storage configures a private `attachments` container, a container-scoped workload role, public access and Shared Key disabled, and a private endpoint/DNS stack. Name availability, private provisioning/management access, and application access are not yet verified.
- Dev Key Vault configures RBAC, private networking, a workload secrets-reader role, seven-day soft delete, and no purge protection. Provider settings prevent automatic vault purge/recovery. Secret provisioning, CSI access, and name availability still need validation.
- Dev PostgreSQL configures a delegated subnet, private DNS, TLS, a `chat` database, and write-only ephemeral administrator password. `POSTGRESQL_SKU` must be selected after availability and cost review; `TF_VAR_administrator_password` must be supplied securely for OpenTofu operations. The application login, private operator access, credentials in Key Vault, lifecycle and backups are not yet tested. Increment the password version input on rotation.
- Dev Azure Managed Redis configures TLS, key authentication for the app's single `ioredis` connection, private endpoint/DNS, and disabled public access. Dev targets `Balanced_B0`; the user selected no Redis HA for either environment. Both still require availability/cost review and outage testing. The provider exports access keys into state even though no key is output; secure state and provision `REDIS_URL` into Key Vault through a private, approved operator path. DNS, connection compatibility, name availability, and lifecycle remain untested.
- Dev Web PubSub configures Free tier, public client connections and public Entra-authenticated REST, disabled local authentication, and a scoped custom workload role. The user accepted the public REST exposure because Free cannot use private endpoints. Verify regional free quota and the AzureRM ACL lifecycle, token issuance, send, disconnect, readiness and role permissions. The separate AzureRM resource manages ACLs after AzAPI creates the service; test drift, update and destroy behavior before provisioning.
- `deploy/chat/` contains an untested Helm chart for the app, manual migration and Gateway API route; `deploy/README.md` describes operator prerequisites. NGINX Gateway Fabric and Cloudflare Origin CA/Full (strict) were selected, but controller installation, TLS provisioning, Cloudflare DNS and end-to-end routing remain untested. `live/prod/` stacks are still missing.
- The app repo has a checks/tests CI workflow and an uncommitted image-publishing workflow. The latter waits for successful `main` push CI, builds runner and migrator images, uses GitHub OIDC, and does not deploy. The shared GitHub publisher identity restricts trust to `nkdm1/chat` on `main` and grants `AcrPush`; neither identity nor workflow has been tested live. `deploy/chat` contains the infrastructure repo's untested Kubernetes Helm chart.
- The application code implements Better Auth/PostgreSQL sessions, server-mediated HTTP message writes, PostgreSQL membership authorization, Cosmos persistence, server-to-user Web PubSub events, and Redis/Web PubSub fallbacks. Azure integration has not been runtime-tested in this review.

## Ordered work

### 0. Mandatory subscription, cost, and state preflight — before any apply

- [ ] Confirm the active Azure subscription is the intended Azure for Students subscription; record the actual remaining credit and current project charges. Inventory existing resources before assuming the environment is empty.
- [x] Remove the hard-coded subscription fallback in `live/root.hcl`; require an explicit `ARM_SUBSCRIPTION_ID` for every plan/apply and verify it in the operator checklist below.
- [ ] Verify the configured remote state account/container exists, is in the intended subscription, has restricted access and locking, and has a recovery procedure. Include state storage/transactions in the project budget.
- [ ] Complete the two-month resource-by-resource estimate in `deploy/cost-review.md`, including persistent prod PaaS, disposable dev stacks, both private DNS/endpoint paths, Gateway controller, public/static IPs, outbound data, backups, ACR, logs, and state. Check the official pricing calculator/actual subscription price; the partial retail references are not a complete quote.
- [ ] Test service/SKU availability in `polandcentral`. If any required service is unavailable or exceeds budget there, stop and get a region/design review before changing region or provisioning.
- [ ] Determine which services can be stopped, which continue billing when AKS is absent, and what deleting each individual Terragrunt stack removes. Record data-loss and recreation consequences. Alerts are not spending caps.
- [ ] Keep a safety margin under $100. Do not apply a stack if total lifetime/run-window costs could exhaust the remaining credit.

#### Read-only preflight observations — 2026-11-24

- The user confirmed the enabled `Azure for Students` subscription ending `b2fcbf68` as the intended target. Resource inventory returned resource groups `tofu-rg` and `websec`, and one resource: storage account `chatopentofu` in `tofu-rg`, `polandcentral`. This is a point-in-time inventory, not proof of all billing or data-plane activity.
- The `tfstate` container exists and was readable with Entra authentication. On 2026-11-24, Terragrunt rendered `dev/resource-group/tofu.tfstate` as the current dev resource-group key. That blob and the older `live/dev/resource-group/tofu.tfstate` have distinct state lineages; both current versions contain no resources or outputs. An older version of the latter recorded `chat-dev-rg`, which was absent from the read-only resource-group inventory. Blob versions remain available. This establishes the current configured key and observed history, not permission to migrate/delete either blob or restore an old version.
- Blob versioning is enabled; blob soft delete is disabled. Container-level and blob-level leases were unlocked at inspection time; this does not prove OpenTofu locking works. The storage account allows network access by default, while anonymous blob access is disabled. Review inherited access, network restrictions, recovery, and locking before treating the backend as verified.
- The user reported approximately $100 remaining student credit on 2026-11-24. Billing and consumption queries did not independently establish the credit balance or total project charges. The rest of the cost, region/SKU, quota, and backend checks remain open; do not run a plan based on these observations alone.
- Subscription-scoped read-only VM SKU queries on 2026-11-24 report `Standard_D2als_v7` and `Standard_B2s` as `NotAvailableForSubscription` in `polandcentral`. The AKS stack still specifies the former and cannot be assumed deployable. `Standard_D2als_v7` appeared in `westeurope` with no location restriction but zones 1 and 3 restricted; quota, AKS node-pool compatibility, full zone behavior, cost and other service availability remain unverified. Some further queries timed out. Do not change region or provision without design review.
- A read-only PostgreSQL SKU query listed Burstable `Standard_B1ms` in `polandcentral`; that alone does not confirm quota, database creation, or subscription-specific cost.
- After the user requested the cheapest viable European VM and approved reviewing `spaincentral` provisionally, read-only compute SKU/usage queries found `Standard_D2s_v4` (2 vCPU, 8 GiB) and `Standard_D4s_v4` (4 vCPU, 16 GiB) without reported restrictions there. Remaining regional quota was 6 vCPU and the Dsv4 family quota was 4 vCPU. Neither capacity nor AKS compatibility is proven. Microsoft [system-pool guidance](https://learn.microsoft.com/en-us/azure/aks/use-system-pools) says 4 vCPU and two nodes, while its [AKS SKU limits](https://learn.microsoft.com/en-us/azure/aks/quotas-skus-regions) cites 2 vCPU/4 GiB; both say B-series is unsupported for system pools. Two 4-vCPU nodes exceed the observed regional and family quota; two 2-vCPU nodes exhaust the family quota and may prevent surge upgrades. Resolve the conflicting requirements and quota before selecting a configuration. No region or node change has been made.
- Provider metadata lists AKS, Managed Redis resource type, PostgreSQL Flexible Server, Cosmos DB, Storage, Key Vault, ACR and Web PubSub in Spain Central; the AKS version query returned versions. PostgreSQL lists Burstable `Standard_B1ms`. This is not SKU availability, capacity, free-tier eligibility or proof of successful deployment. ACS is global with data location `Europe`, not a Spain Central regional resource. Several required resource providers report `NotRegistered`; registration requires a separate authorized change. Redis B0, PubSub Free, ACR, Cosmos, private networking and name availability remain to be checked for the subscription. Spain Central remains only a candidate, not an approved region change.

#### Operator subscription checklist — before each plan/apply

- [ ] Confirm the intended Azure for Students subscription and the signed-in account with `az account show` and `az account list`; do not assume the active subscription is correct.
- [ ] Set `ARM_SUBSCRIPTION_ID` explicitly to the verified subscription UUID, and compare it with the intended account and the configured remote-state subscription. The backend and provider both use this value; changing it can target a different state and resources.
- [ ] Complete the remaining credit, resource inventory, backend, availability, quota, and lifecycle cost checks above before planning or applying. A valid UUID alone does not verify the subscription or authorize provisioning.

### 1. Secure and stabilize network/state foundations

- [x] Configure AKS for a private control plane, AKS-managed private DNS, and Run Command; disable the public API FQDN. Changing an existing public cluster to private requires replacement; review the plan before any approved apply.
- [ ] Validate the private DNS and test operator access using manual `az aks command invoke` / portal Run Command with least-privilege Azure RBAC. This is the initial manual access path; do not add a permanent VPN/VM without cost review.
- [ ] Price, install and validate NGINX Gateway Fabric with the private AKS API and the separately exposed HTTPS Gateway. Azure Application Gateway for Containers was not selected because Microsoft's current region list omits `polandcentral`.
- [ ] Validate the network-owned static Gateway and load-balancer egress IPs across AKS recreation. Verify no unintended inbound listener, price idle/active and load-balancer/SNAT costs, and test control-plane permissions and Gateway IP use.
- [ ] Configure and test Cloudflare proxied DNS, Full (strict) mode, Origin CA certificates and safe certificate rotation for `dev.chat.nkdm.io` and later `chat.nkdm.io`. Verify DNS updates and recovery if an IP changes.
- [ ] Create private DNS zones and VNet links for every private endpoint. Ensure the shared Cosmos account resolves privately from dev and prod VNets.
- [ ] Restrict public service exposure as recorded in `plan.md`: private PostgreSQL, Cosmos, Blob Storage, Redis, and Key Vault; public Web PubSub client connections and Entra-authenticated server REST on the Free tier; authenticated public ACR; authenticated outbound ACS Email.

### 2. Complete dev identity and private data services

- [ ] Review/apply existing shared and dev resource-group, network, ACR, Cosmos, ACS, and AKS plans one at a time after the preflight and network design are ready.
- [ ] Validate the configured dev Cosmos private endpoint/DNS and disabled account public access; add a separate prod private path when prod is built. Confirm the account is eligible for free tier and the aggregate `chat-dev` + `chat-prod` throughput and storage stay within allowances.
- [ ] Verify the configured dev Cosmos data-plane role for the dev workload identity is scoped to `chat-dev` and cannot access prod. The identity and database role are configured but not deployed or tested.
- [ ] Preserve an independent shared Cosmos account state stack. Implement dev database teardown/recreation so destroying `live/dev/cosmos-db` cannot destroy the shared account or `chat-prod`.
- [ ] Complete and validate private PostgreSQL: select an available/cost-reviewed SKU, configure a least-privilege application login and secret-backed `DATABASE_URL`, verify private operator access and TLS/backups, and test start/stop/delete/recreate. The server, database, delegated subnet and private DNS are configured but not deployed.
- [ ] Validate the configured private Blob Storage, `attachments` container, private endpoint/DNS, and container-scoped workload role. Verify operator provisioning and data-plane access with public access and Shared Key disabled; check the account name is available.
- [ ] Verify availability and cost of dev `Balanced_B0` Redis with HA disabled; validate its private endpoint/DNS, TLS/key auth and application compatibility; provision `REDIS_URL` privately and test lifecycle. Preserve the app's Redis fallbacks; Redis is not the authorization source of truth.
- [ ] Validate the configured dev Key Vault private endpoint/DNS, workload identity and CSI access; establish a private operator path to provision secrets. Dev uses 7-day soft delete; purge protection is disabled for both environments by user decision. Choose prod retention before creation.
- [ ] Validate Web PubSub Free quota, client and public Entra-authenticated REST access, disabled local authentication, workload role, 20-connection/20,000-message daily limits, and ACL behavior during create, drift, update and destroy. The user accepted publicly reachable REST because Free cannot use private endpoints.
- [ ] Add the dev app workload identity/federated Kubernetes service-account credential `chat/chat-app`. Grant only required resource roles; verify Cosmos, Blob, Web PubSub and ACS permissions. Keep CI publish identity, kubelet image-pull identity, and human operator identity separate.
- [ ] Set Azure configuration from `chat-webapp/.env.example`: `AUTO_PROVISION=false`, no emulator `*_CONNECTION_STRING` values, non-secret settings in ConfigMap, `BETTER_AUTH_SECRET`/`DATABASE_URL`/`REDIS_URL` in Key Vault/CSI, and `COSMOS_DATABASE=chat-dev`.
- [ ] Validate ACS Email delivery and the configured service-scoped custom read/write role. `/write` also permits changing the Communication Service; confirm the SDK's required permissions and replace with a narrower supported send permission if available. The user selected Azure-managed domains for both environments. Consider ACS Network Security Perimeter only as optional hardening if subscription support and preview terms are acceptable.
- [ ] Validate ACR Entra-only operations: admin account off, no anonymous access, configured GitHub OIDC identity limited to `AcrPush`, and AKS kubelet identity limited to `AcrPull`. Its public endpoint is an intentional exception because the GitHub-hosted runner is outside the VNet.

### 3. Deploy and validate dev

- [ ] Validate the `deploy/chat` Helm chart: Deployment, Service, ConfigMap, workload service account, SecretProviderClass, HTTPS Gateway/route and ordered one-off migration. It has been rendered locally but not applied; keep one app image and one HTTPS origin.
- [ ] Install/price NGINX Gateway Fabric and validate Cloudflare Origin CA TLS for `dev.chat.nkdm.io`. Ensure user traffic reaches the app through Gateway only; the Kubernetes API server remains private.
- [ ] Review and commit the uncommitted app-repo image workflow separately, set its Azure client/tenant/subscription variables from the approved publisher outputs, and test OIDC publication after preflight. It waits for successful CI on a `main` push, publishes runner/migrator SHA tags and reports immutable digests; it never auto-deploys or applies OpenTofu.
- [ ] Review and exercise the draft `deploy/dev-operations.md` start/stop checklist: prepare data services, recreate AKS/federation, migrate before rollout, smoke-test, then destroy only explicitly approved disposable stacks. Preserve shared Cosmos account/state and retained data; verify actual billing after stopping.
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
