# Project plan — desired state

> **Authority:** this is the project's desired architecture and infrastructure plan. [`todo.md`](todo.md) is the implementation/status list. Application behavior is described in [`chat-webapp/docs/architecture.md`](../../chat-webapp/docs/architecture.md); the app deployment reference is [`chat-webapp/docs/azure-deployment.md`](../../chat-webapp/docs/azure-deployment.md). Those references must agree with the decisions here. The app repo's `PLAN.md` and `AGENT-IMPLEMENTATION.md` are navigation/agent documents, not alternate architecture plans.

## Confirmed decisions and constraints

- **Hosting:** one Next.js application serves both UI and API from one Docker image on AKS. Do not split it onto Azure Static Web Apps or add a separate backend service.
- **Sessions:** keep Better Auth with PostgreSQL-backed sessions. Do not introduce custom access JWTs or refresh tokens.
- **Message writes:** browsers write through authenticated HTTPS API routes. The server validates and authorizes against PostgreSQL, persists messages to Cosmos DB, then publishes realtime notifications. Do not use Web PubSub event ingress/webhooks for chat writes.
- **Authorization:** PostgreSQL remains authoritative for conversation membership. Do not add a Redis permission cache or transactional outbox unless a later, measured requirement is explicitly approved.
- **Realtime:** browsers receive Web PubSub events only. The app backend issues short-lived client URLs after authentication; the client has no send/write roles. The backend publishes via `sendToUser` after persistence.
- **Cosmos topology:** one shared Cosmos DB account, with isolated `chat-dev` and `chat-prod` databases and environment-specific identities/access. The shared account is not an excuse to share application data or credentials.
- **Routing and names:** use NGINX Gateway Fabric in AKS with Gateway API for the public app route. Cloudflare proxies DNS in Full (strict) mode with a Cloudflare Origin CA certificate at the Gateway: `dev.chat.nkdm.io` is dev; `chat.nkdm.io` is the prod showcase. Review certificate provisioning and rotation before deployment.
- **Control plane:** AKS uses the Free management tier and a private Kubernetes API server. Use one system node pool, starting at one node with autoscaling capped at two, and no explicitly configured availability zones. The preferred `Standard_D2als_v7` and listed alternatives were unavailable or lacked quota in the checked regions, so the user provisionally selected `Standard_D2s_v4` for dev in Belgium Central; AKS compatibility and final capacity remain unverified. Microsoft documents B-series as unsupported for system pools, and its minimum size/node-count guidance conflicts; verify AKS acceptance and quota before choosing. The `p` SKUs are Arm64 and require compatible app, migration, controller and add-on images. A single node has no node-level redundancy. Operators initially manage the cluster manually with Azure `az aks command invoke` / Run Command, not a public Kubernetes API endpoint. The network stack owns separate static ingress and egress IPs; AKS uses a Standard Load Balancer for egress. The IPs remain billable when AKS is absent.
- **Email domains:** use an Azure-managed sender domain separately in each environment. Verify sender availability and delivery before use.
- **Redis availability:** use non-HA Redis in both environments by user decision; dev targets `Balanced_B0`. Redis is derived/ephemeral data and the app must tolerate downtime and data loss. Verify SKU availability and lifecycle cost before provisioning.
- **Registry:** share one Basic ACR, `websecchatacr`, between dev and prod in `live/shared/`. Its lower-cost public endpoint permits GitHub-hosted CI to publish images. Require Entra authentication; disable the admin account and anonymous pulls; grant only CI `AcrPush` and each AKS kubelet `AcrPull`.
- **Network boundary:** data services use private networking and have public access disabled where supported. The deliberate exceptions are described under [Network exposure](#network-exposure).
- **Deployment:** CI tests pull requests; a merge to the default branch builds and publishes an immutable image to ACR using GitHub OIDC. OpenTofu changes and AKS rollouts are reviewed and run manually; merges never auto-apply infrastructure or auto-deploy the app.
- **Region:** use `belgiumcentral` provisionally for dev and shared regional resources, with Web PubSub in `swedencentral` because it is not listed in Belgium. Cross-region latency, egress costs, Free-tier eligibility and service availability require verification. The existing empty `chat-shared-rg` remains in `spaincentral` and can contain resources in Belgium; do not replace or delete it without approval. The existing remote-state backend remains in `polandcentral`; changing the application region must not relocate or overwrite its state.
- **Lifecycle:** the project will be presented over about two months, not necessarily run continuously. Most resources can be destroyed between uses; if retention is too expensive, dev and prod data can be destroyed and regenerated for demonstrations with ad-hoc scripts. Record exactly what will be lost and prepare a tested rebuild procedure before destruction. Destroying AKS does not stop or delete independent PaaS resources.
- **Budget and schedule:** the whole project has a hard **$100 USD Azure for Students credit ceiling** over approximately two months. Dev is used about 2–3 two-hour sessions/week; prod is a roughly two-hour weekly showcase. Most resources are intended to be destroyed outside use windows if necessary. After preflight and explicit approval, run a bounded 24-hour trial and review actual charges to guide retention decisions; billing can lag, so the first reading may be incomplete.

## Application architecture

The application is one Next.js UI/API process. Locally it runs with Docker Compose emulators; Azure changes endpoint/configuration and identity, not the app's architectural shape.

```text
Browser ── HTTPS (all reads/writes, auth) ──▶ Next.js app on AKS
   ▲                                              ├── PostgreSQL: auth + relational data
   │                                              ├── Cosmos DB: durable messages
   │                                              ├── Blob Storage: attachments
   │                                              ├── Redis: rate limits + ephemeral/derived data
   │                                              └── ACS Email: verification mail
   └──── public WSS, short-lived receive-only URL ─ Web PubSub ◀── server sends events

Internet ── HTTPS ──▶ Cloudflare DNS ──▶ public Gateway API ──▶ AKS app
```

| Concern | Local development | Azure target | Owner / behavior |
|---|---|---|---|
| UI and API | One Next.js app | Same app image on AKS, port 3000 | One public HTTPS origin per environment; Better Auth cookies and same-origin write checks remain intact. |
| Accounts, sessions, friends, groups, read positions, reactions, reports | PostgreSQL | Azure Database for PostgreSQL Flexible Server | Drizzle and Better Auth. PostgreSQL is the membership/authorization source of truth. |
| Messages/history | Cosmos DB emulator | Cosmos DB for NoSQL | `messages` container, `/conversationId` partition key; `chat-dev` and `chat-prod` are separate databases in the shared account. |
| Attachments | Azurite | Azure Blob Storage | Private `attachments` container, accessed through the app. |
| Realtime | Web PubSub emulator | Azure Web PubSub | Browser receives; backend sends server events with `sendToUser`. Polling is the fallback. |
| Rate limits, presence, typing, unread/derived state | Redis | Azure Managed Redis | Best-effort/derived data with application fallbacks; not authoritative membership or durable message data. |
| Verification email | Mailpit | ACS Email | Server-to-service outbound API call using workload identity. This is not an inbound application webhook. |

### Request and failure behavior

- All chat writes use authenticated same-origin HTTPS API routes. The server checks the user's Better Auth session and conversation membership, persists the message, then publishes an event. The browser cannot write directly to Cosmos or send messages through Web PubSub.
- The backend returns a short-lived Web PubSub client URL only after authenticating the user. A browser can open its WSS connection with that URL, but cannot mint a URL for another identity or send/write via the connection. Do not log or cache the bearer URL.
- `GET /api/health` is liveness: it checks that the process is running. `GET /api/ready` fails only when PostgreSQL or Cosmos is down. Redis and Web PubSub report status but may degrade; Redis has fallbacks and the UI polls while Web PubSub is disconnected. A smoke test with all services healthy should still verify their status, but their being `ok` is not the readiness gate.
- Keep the current Better Auth/PostgreSQL session model, `sendToUser` fan-out, direct PostgreSQL authorization, and Redis fallbacks. Do not implement proposed JWT, event-webhook, Web PubSub group, permission-cache, or outbox designs from older plans.

## Environment and resource topology

### Dev first

Use a dedicated `live/dev/` environment and unique Terragrunt state keys. Complete and test dev before creating prod. Keep local Docker Compose as the normal local development path; use real Azure dev resources for cloud integration and end-to-end tests.

The app image is stateless. Environment state, runtime configuration, identities, and data services are separate from the AKS cluster so the cluster can be recreated without losing the retained prod data. Prod uses the proven dev module patterns with distinct names, state, identities, secrets, databases, and app data. The Cosmos account and container registry are deliberately shared; each environment retains its own app data and identity.

### Cosmos DB

The shared account is created once and remains separate from both environment database stacks. Dev uses `chat-dev`; prod uses `chat-prod`; both use a `messages` container with the same partition-key contract. The app's local `.env.example` may keep its emulator default `chat`; Azure must set the environment-specific database name. Set an environment-specific Cosmos data-plane identity and scope it to that environment's database/container. Verify that the account is eligible for Cosmos free tier and that the combined provisioned throughput/storage remain within the account allowance.

## Network exposure

Network policy distinguishes **network reachability** from **application authorization**. A public DNS name does not make an operation anonymous, and managed identity does not by itself make a public endpoint private.

### Public entry paths and constrained exceptions

1. **App:** internet users reach the app only over HTTPS through the public Gateway API route. Cloudflare hosts DNS for `dev.chat.nkdm.io` and `chat.nkdm.io`; enforce TLS to the app and set `BETTER_AUTH_URL` to each exact origin.
2. **Web PubSub:** use Free tier for each environment, subject to regional quota verification. Public `ClientConnection`/WSS uses short-lived backend-minted receive-only client URLs. Server REST is also publicly reachable but requires Entra authentication and the scoped app role; disable local/key authentication and deny public server connections and trace requests. The user accepted this network exposure because Free does not support private endpoints, and public IP rules cannot restrict only REST while admitting arbitrary browsers. The backend—not the browser—sends events.
3. **ACR:** the registry endpoint is publicly addressable for GitHub-hosted image publishing and AKS image pulls, but operations require Entra identity. No anonymous pulls or admin credentials; assign only `AcrPush` to the build identity and `AcrPull` to the AKS kubelet identity.
4. **ACS Email:** the app makes outbound HTTPS calls using its workload identity and a least-privilege email-sending role. ACS has no traditional Private Link endpoint. A Network Security Perimeter may be used as optional hardening if the subscription supports it without unacceptable preview/operational risk; it is not a prerequisite. Internet users receive no ACS identity/role and cannot send mail through the app's identity.

### Private paths

- Make the AKS control plane private; do not expose the Kubernetes API server to the public internet. Use `az aks command invoke` / Run Command for operator access initially, with the required Azure RBAC actions; this is a manual operations path, not a deployment runner.
- Use service-native private connectivity for PostgreSQL and Private Endpoints/private DNS for Cosmos DB, Blob Storage, Azure Managed Redis, and Key Vault. Disable their public network access wherever the service supports it. Link private DNS to each environment VNet; the shared Cosmos account must resolve privately from both dev and prod networks.
- Keep CI and app identities separate. Private endpoint rules do not replace workload identity/RBAC; public endpoint authentication does not replace network restrictions where those are available.
- The Gateway API controller, Cloudflare TLS/proxy mode, stable public Gateway IP, AKS outbound/static egress IP, private DNS, and exact endpoint resources must be costed and tested before apply. The app Gateway ingress IP and outbound egress IP have different purposes; neither should be assumed stable through cluster recreation unless explicitly managed outside the cluster.

Official constraints to verify during implementation: [Web PubSub network access control](https://learn.microsoft.com/en-us/azure/azure-web-pubsub/howto-secure-network-access-control), [Web PubSub private endpoints](https://learn.microsoft.com/en-us/azure/azure-web-pubsub/howto-secure-private-endpoints), [ACS Network Security Perimeter](https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/network-security-perimeter), [ACR private networking/SKUs](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-skus), and [private AKS operator access](https://learn.microsoft.com/en-us/azure/aks/access-private-cluster).

## Identity, secrets, and runtime configuration

- Use an AKS workload identity for the app service account `chat/chat-app`, with only the data-plane permissions needed for its environment. Use the AKS kubelet identity for ACR pulls. Keep GitHub OIDC image-push identity and human OpenTofu operator identity separate.
- Use Key Vault + AKS Secrets Store CSI Driver for runtime secrets. Keep non-secret settings in a ConfigMap. Never commit secret values, place them in images/build args, expose them through browser variables, or emit them in OpenTofu outputs/logs. Purge protection is disabled for both environments by user decision; dev vault soft-delete retention is 7 days. Choose prod retention separately before creation. Do not automatically purge or recover vaults on destroy/create.
- Runtime secrets include `BETTER_AUTH_SECRET`, `DATABASE_URL`, and `REDIS_URL`; `SMTP_PASS` is unnecessary when ACS is used. PostgreSQL and Redis credential/auth modes must match the selected Azure service configuration.
- Azure uses workload identity/managed identity where supported for Cosmos, Blob Storage, Web PubSub, and ACS. No local emulator `*_CONNECTION_STRING` values in Azure; set `AUTO_PROVISION=false`.
- Set environment-specific `COSMOS_DATABASE`, endpoints, hub/container names, `EMAIL_PROVIDER=acs`, and `BETTER_AUTH_URL`. Do not introduce `NEXT_PUBLIC_*` values.

## Provisioning, delivery, and operations

1. Before planning/provisioning, review the explicit target subscription, remaining credit, region/SKU availability, quotas/free tiers and remote state. List known trial rates, teardown scope and retained resources, and set a safety margin; the user prefers measuring charges after a bounded trial over attempting a complete forecast. Billing delays and unknown usage prevent a guarantee against exceeding the credit ceiling.
2. Run OpenTofu manually: inspect/review plans and apply only the approved stack. CI may run formatting/validation but never applies infrastructure.
3. GitHub Actions runs app checks on PRs. On merge to the default branch, build and push an immutable/versioned app image to ACR with OIDC. Do not auto-roll out to AKS.
4. Manually create/start the AKS cluster for a session, deploy the app with environment configuration, run the reviewed migration image as a one-off Kubernetes Job before rollout, and validate Gateway API/TLS. With the private control plane, use the approved `az aks command invoke` workflow.
5. Destroy/recreate AKS between use windows when cost-effective. Destroying AKS does **not** stop independent databases, Redis, Storage, Cosmos, ACS, ACR, Private Endpoints, DNS, or IP resources. Keep prod data services between weekly showcases only while they fit the aggregate credit limit. Dev data is disposable and may be destroyed; destroying `chat-dev` must never destroy the shared Cosmos account or `chat-prod` data.
6. Maintain separate `dev-start`/`dev-stop` and `showcase-start`/`showcase-stop` procedures. Destroy only explicitly selected stacks; never use a broad `run-all destroy` as a stop procedure. Verify the actual Azure bill after sessions.

## Cost and acceptance criteria

The $100 limit is total project credit, **not a monthly allowance and not $100 per environment**. Include compute runtime and everything billed while stopped/idle/retained: PostgreSQL, Redis, Cosmos throughput/storage beyond free limits, private endpoints/data processing, IPs/load balancers, DNS, ACR, Key Vault, backups, logs, state storage, and egress. Budgets/alerts notify but are not spending caps. Keep a safety margin; stop and review if the estimate can exceed remaining credit. Do not assume AKS is the only material cost.

The desired project state is reached when:

- Dev and prod have separate state, app identities, credentials, and application data; the Cosmos account and container registry are deliberately shared.
- The app Gateway and Web PubSub client connection accept intended public traffic; Web PubSub REST is also publicly reachable and Entra-restricted. Data stores use private connectivity/public access disabled. ACR and ACS public endpoint exceptions are identity-restricted as specified above.
- The app runs as one image on AKS, is reachable at its environment hostname over HTTPS, uses Better Auth sessions, private service endpoints, and server-mediated message writes.
- Authenticated message writes are persisted before server push; browser Web PubSub credentials are short-lived and receive-only; Redis/Web PubSub outages degrade as the app currently specifies.
- The dev AKS cluster can be created, deployed, smoke-tested, and destroyed without removing retained shared/prod state. Prod can be resumed for a weekly showcase with its data intact when budget allows.
- Before any apply, review availability, state, known costs and trial scope, and obtain explicit approval for the selected resources and teardown. Measure trial charges when billing data has arrived and reassess the remaining lifecycle against the $100 ceiling.

## Related application contract

The app repository is the source for runtime variable names and local setup: [`chat-webapp/.env.example`](../../chat-webapp/.env.example) and [`chat-webapp/README.md`](../../chat-webapp/README.md). Its architecture/deployment references are supporting detail; this plan is authoritative if wording differs.
