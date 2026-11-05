# TODO — Build `live/prod/` showcase environment

## Goal

`live/dev/` is pre-production (about 2–3 hours/week). `live/prod/` is a public, production-shaped showcase (about 30 minutes/week), not a 24/7 service. Keep the app architecture in [`azure-deployment.md`](azure-deployment.md): one Next.js UI/API image on AKS, behind one HTTPS origin.

Current IaC is only a dev resource-group stack, a resource-group module, and an ACS Email module. Build and test the reusable modules before copying the stack pattern to prod.

## 1. Preflight

- [ ] Treat the Azure for Students **$100 USD credit as a hard project-wide ceiling**, not a target. Every resource must be free when eligible or use the cheapest viable configuration. Check remaining credits and estimate full lifecycle cost—including dependencies, idle/retained charges, data transfer, logs, disks, IPs, load balancers, private endpoints, and DNS—before each plan/apply. Keep a safety margin; cost alerts are not spending caps. Do not apply a change that could consume the remaining credit or exceed $100.
- [ ] Require an explicit `ARM_SUBSCRIPTION_ID` for prod. Remove or guard the hard-coded fallback in `live/root.hcl` and verify the subscription before every prod plan.
- [ ] Choose the prod region, DNS name, VNet address ranges, and service SKUs.
- [ ] Create separate prod resource names, identities, secrets, databases, and Terragrunt state. Never reuse dev state, credentials, or data.
- [ ] Verify current pricing and student-credit eligibility in the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/), including startup time and services billed while idle. Planned runtime is not a cost estimate; check actual remaining credits before provisioning.
- [ ] Set Cost Management alerts and verify actual spend after each showcase. Alerts are not a spending cap, and must not be used as a substitute for the $100 pre-deployment budget gate.

## 2. Write modules and add `live/prod/` stacks in this order

Create one `live/prod/<stack>/terragrunt.hcl` per module, using the same reusable module sources as dev and the existing root include/state conventions. The state key must be unique to each prod stack.

| Order | Module / stack | Configure |
|---:|---|---|
| 1 | `resource-group` *(reuse)* | Dedicated prod resource group; prod tags and naming. |
| 2 | `network` *(new)* | VNet, AKS and reserved private-endpoint subnets, NSGs, and DNS as needed. Configure only the network exposure required by the selected Gateway API controller. Defer private-endpoint resources until a target service needs private access and their full cost is checked against remaining student credits. Price retained IPs, Gateway API implementation, endpoints, and NAT before enabling them. |
| 3 | `monitoring` *(new)* | Log Analytics, diagnostics, alerts, and cost-conscious log retention. |
| 4 | `container-registry` *(new)* | ACR for the app image; AKS pulls using its kubelet identity. |
| 5 | `key-vault` *(new)* | RBAC-enabled vault, soft delete/purge protection, and access for the AKS Secrets Store CSI driver. Store runtime secrets here, not in ConfigMaps or outputs. |
| 6 | `postgresql` *(new)* | PostgreSQL Flexible Server and `chat` database; TLS, private access, backup settings, and configurable compute/HA. |
| 7 | `cosmos-db` *(new)* | Cosmos DB for NoSQL; `chat` database and `messages` container partitioned on `/conversationId`; data-plane role assignment. |
| 8 | `storage` *(new)* | Storage account and private `attachments` blob container; secure transfer, access restrictions, and retention settings. |
| 9 | `managed-redis` *(new)* | Azure Managed Redis, TLS, capacity, network restrictions, and its data-plane access. |
| 10 | `web-pubsub` *(new)* | Azure Web PubSub and `chat` hub. Browser clients receive events; they do not write messages through Web PubSub. |
| 11 | `email-communication-service` *(extend existing)* | Add ACS Email/domain/sender configuration; document manual sender-domain DNS verification. |
| 12 | `aks` *(new)* | AKS, node pools/autoscaling, OIDC/workload identity, Key Vault CSI provider, ACR pull, monitoring, and a cost-reviewed Gateway API controller for HTTPS (`GatewayClass`, `Gateway`, `HTTPRoute`; no legacy `Ingress` resources). |
| 13 | `workload-identity` *(new)* | App identity, federated credential for `chat/chat-app`, and least-privilege roles for Cosmos, Blob, Web PubSub, ACS Email, and the CSI secret reader. |

Build the modules in this order. Apply them in the same dependency order: resource group → network/monitoring → ACR/Key Vault → data services/email → AKS → workload identity/roles. Independent data-service stacks can be applied in parallel after the network is ready.

## 3. Showcase configuration and deployment

- [ ] Set prod names, endpoints, and non-secret settings in `live/prod`; keep `BETTER_AUTH_SECRET`, `DATABASE_URL`, and `REDIS_URL` in Key Vault and mount them using CSI. Follow [`azure-deployment.md`](azure-deployment.md) and the app [`.env.example`](../../chat-webapp/.env.example) for exact variable names.
- [ ] Set `AUTO_PROVISION=false`; leave local emulator connection strings unset. Keep the same image for UI and API.
- [ ] Configure the public DNS/TLS name and set `BETTER_AUTH_URL` to that exact HTTPS origin.
- [ ] Run the app's `migrator` image as a reviewed one-off Kubernetes Job, then deploy the app image to AKS.
- [ ] Use demo accounts/data only. Test the same image in dev before deploying it to prod.

## 4. Weekly showcase lifecycle and cost controls

The environment only saves money if billable resources are stopped or removed—not merely if the app has no traffic.

- [ ] Create a `showcase-start` runbook: start AKS and PostgreSQL compute; recreate any disposable services; securely refresh changed secrets such as `REDIS_URL`; run migrations and smoke tests; then open the public demo endpoint.
- [ ] Create a `showcase-stop` runbook: close the demo window, stop AKS/PostgreSQL compute, and remove only explicitly disposable services. Never destroy the prod resource group or run a broad `terragrunt run-all destroy`.
- [ ] Keep persistent data, backups, storage, Key Vault, ACR, and Terraform state unless a separate deletion plan is approved. Include their idle charges in the estimate.
- [ ] AKS can be stopped between demos; verify related disks, IPs, and load balancers separately. PostgreSQL storage/backups may still incur charges while stopped, and a stopped server auto-starts after seven days—schedule the next start before then. See [AKS stop/start](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster) and [PostgreSQL stop/start](https://learn.microsoft.com/en-us/azure/postgresql/configure-maintain/how-to-stop-server).
- [ ] Managed Redis has no pause operation; if its idle cost is too high, isolate it in its own stack and delete/recreate it for demos. Its ephemeral state may be lost. See the [Managed Redis FAQ](https://learn.microsoft.com/en-us/azure/redis/planning-faq).
- [ ] Check free-tier limits before relying on them: Cosmos DB free tier applies to only one account per subscription; Web PubSub Free supports up to 20 concurrent connections and 20,000 messages/day. Use a paid Web PubSub tier only for a planned scale demo ([Cosmos DB](https://learn.microsoft.com/en-us/azure/cosmos-db/free-tier), [Web PubSub](https://azure.microsoft.com/en-us/pricing/details/web-pubsub/)).
- [ ] Verify the actual bill after each run and keep the total below the student credit with a safety margin.

## 5. Acceptance checklist

- [ ] Every prod stack has isolated state and targets the explicitly verified subscription.
- [ ] AKS starts; app identity, ACR pull, CSI secrets, service roles, and autoscaling work.
- [ ] `/api/health` and `/api/ready` pass; sign-up/email, messaging, realtime, attachments, and admin smoke tests pass during the demo.
- [ ] Run a bounded load test to demonstrate app/cluster scaling and Web PubSub fan-out without exceeding the showcase budget or service-tier limits.
- [ ] `showcase-stop` leaves no unintended compute/cache running and preserves required data/state.
- [ ] The public showcase is understood to be unavailable between its scheduled windows; reliability claims are scoped to the demo window.
