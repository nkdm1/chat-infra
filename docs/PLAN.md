# Chat application — implementation and deployment plan

## Status and source of truth

**Azure budget constraint:** this project has at most **$100 USD in Azure for Students credits**. This is a hard ceiling. Every Azure resource must be free when eligible or use the cheapest viable configuration. Verify current eligibility, remaining balance, regional pricing, and full lifecycle/dependency costs before planning or applying; include idle/retained charges and keep a safety margin. Cost alerts are not spending caps. Do not provision a change that could reach or exceed the ceiling.

The chat application has been implemented and runs locally against a Docker Compose service stack. This document records the implemented application architecture and its intended Azure deployment; it is not a proposal to replace the working app with a new frontend/backend split.

For code-level behavior, API routes, security controls, configuration names, and service degradation, see [`architecture.md`](architecture.md). For Azure resource setup and deployment steps, see [`azure-deployment.md`](azure-deployment.md). Keep those documents and this plan aligned when behavior changes.

## Implemented application architecture

A single Next.js application serves both the browser UI and server-side API. The browser makes authenticated HTTPS requests to the app for all writes. It receives real-time updates over Web PubSub; it does not send chat messages over the socket. The app persists messages before sending notifications and falls back to polling when realtime is unavailable.

```text
Browser ── HTTPS /api (reads and writes) ──▶ Next.js app (UI + API)
   ▲                                                ├── PostgreSQL: accounts and relationships
   │                                                ├── Cosmos DB: messages
   │                                                ├── Blob Storage: attachments
   │                                                ├── Redis: rate limits and ephemeral/derived state
   └──────── WebSocket receive-only ── Web PubSub ◀─┘

Email: Mailpit locally; Azure Communication Services Email in Azure
```

| Concern | Local development | Azure target | Application integration |
|---|---|---|---|
| UI and API | One Next.js app, `localhost:3000` | One container/image on AKS, port 3000 | Same-origin routes and cookies; no separate frontend service |
| Accounts, friendships, groups, read positions, reactions, reports | PostgreSQL 17 | Azure Database for PostgreSQL Flexible Server | Drizzle ORM |
| Messages | Cosmos DB emulator | Cosmos DB for NoSQL | Cosmos SDK; `messages` container partitioned by `/conversationId` |
| Attachments | Azurite | Azure Blob Storage | Blob SDK; private container, attachment access through app API |
| Realtime delivery | Web PubSub emulator | Azure Web PubSub | Server sends to users; browser connection is receive-only |
| Rate limits, presence, typing, unread state | Redis 7 | Azure Managed Redis | Redis protocol client; Redis is not the durable source of truth |
| Transactional email | Mailpit | ACS Email | SMTP locally; ACS endpoint and managed identity in Azure |

The local emulators are provided by `docker-compose.yml` and are accessed through the same service SDKs/protocols used by the app in Azure. The app also supports running directly with `pnpm dev` while these services run in Docker. This full local stack is an implemented development environment, not just a collection of unit-test fakes.

## Implemented behavior and invariants

- Better Auth uses PostgreSQL-backed database sessions. The app does not implement custom JWT access/refresh tokens.
- API routes authenticate the session, validate and authorize requests, apply origin checks to writes, enforce payload/rate limits, and return structured errors.
- Message writes go through HTTPS. The server validates/sanitizes content and checks conversation membership, stores the message in Cosmos DB, then sends realtime updates. Clients receive over Web PubSub and poll if realtime is unavailable.
- Cosmos messages use `/conversationId` as the partition key and an idempotent sender/client-message identifier. Edits and deletes use ETags; deletes are soft.
- PostgreSQL owns account and relational data. Cosmos owns durable messages. Redis is used for rate limiting, presence, typing, and unread state; optional Redis-dependent behavior can degrade without losing durable account/message data.
- Attachments are size/type checked, stored under random blob names, and served through the app. Moderation reports preserve message snapshots; admin actions are audited.
- Liveness/readiness routes are `/api/health` and `/api/ready`. PostgreSQL and Cosmos are readiness-critical; optional service failures are reported and handled according to the architecture document.

## Azure hosting and configuration

### Selected hosting topology

Deploy the **whole Next.js application (frontend and API together) as one Docker image on AKS**, behind one HTTPS hostname served through a Kubernetes Gateway API controller. Azure Static Web Apps (SWA) plus a separate AKS API is not the selected architecture: it would split the app and introduce cross-origin/cookie routing concerns without a need in the implemented application. Do not add an SWA deployment pipeline or separate frontend hosting unless the architecture is deliberately reviewed and the app is changed to support it.

For new traffic routing, use Gateway API resources (`GatewayClass`, `Gateway`, and `HTTPRoute`) with a compatible controller; do not create legacy Kubernetes `Ingress` resources. The Kubernetes Ingress API is frozen and no longer being developed, but is not formally deprecated or scheduled for removal; Gateway API is the recommended successor. Gateway API resources alone do not implement traffic handling—the controller and its cost must be selected and reviewed separately. See the [Kubernetes Gateway API documentation](https://kubernetes.io/docs/concepts/services-networking/gateway/).

The same-origin host is important for Better Auth cookies, CSRF origin checks, and verification links. Use the public origin as `BETTER_AUTH_URL`. The app has no `NEXT_PUBLIC_*` runtime configuration and the same image should run in every environment.

### Secrets and non-secret configuration

- Keep runtime secrets in Azure Key Vault and expose them to the AKS pod through the Secrets Store CSI Driver, synced to a Kubernetes Secret and made available to the container at runtime.
- Secret values include `BETTER_AUTH_SECRET`, `DATABASE_URL`, and `REDIS_URL`; `SMTP_PASS` is needed only if SMTP is used. Never put secrets in a ConfigMap, image, build argument, source control, or OpenTofu output.
- Put non-secret endpoints and application settings in a ConfigMap. Use managed/workload identity for Cosmos DB, Blob Storage, Web PubSub, and ACS where supported. PostgreSQL and Redis authentication remain explicit secret-backed connection configuration.
- Unset local emulator `*_CONNECTION_STRING` settings in Azure. Set Azure endpoints/account URLs instead. Keep `AUTO_PROVISION=false` in Azure; OpenTofu provisions Azure data resources.
- The runtime variable names are maintained in [`../../chat-webapp/.env.example`](../../chat-webapp/.env.example); Azure examples are in [`azure-deployment.md`](azure-deployment.md).

### Deployment sequence

1. Provision the Azure resources and identities with OpenTofu, including the Key Vault, ACR, AKS, PostgreSQL, Cosmos DB, Blob Storage, Redis, Web PubSub, and ACS Email resources. Confirm networking, DNS/TLS, role assignments, and manual ACS sender-domain verification.
2. Store runtime secrets in Key Vault; provide non-secret settings through the `chat-config` ConfigMap. Configure the CSI driver and runtime workload identity.
3. Build and push the app image to ACR. Run the separate `migrator` image target as a one-off Kubernetes Job before rolling out the application image.
4. Deploy one app container with the `chat-app` service account, port 3000, configuration from the ConfigMap and Key Vault-backed Secret, and probes for `/api/health` and `/api/ready`.
5. Route the HTTPS domain to the app and set `BETTER_AUTH_URL` to that exact public origin. Smoke-test registration/email verification, messaging, attachments, and service readiness.

The Azure deployment guide documents concrete resource settings, role assignments, environment values, and smoke tests. Infrastructure deployment and application rollout must be treated as separate operational steps; do not imply resources exist merely because the app supports them.

## Explicit decisions versus the earlier proposal

- **Hosting:** one unified Next.js UI/API on AKS replaces the earlier SWA frontend + AKS API split.
- **Secrets:** Key Vault plus the AKS Secrets Store CSI Driver replaces putting sensitive values in deployment configuration. ConfigMaps contain non-secret values only.
- **Local development:** Docker Compose emulates PostgreSQL, Cosmos DB, Blob Storage, Web PubSub, Redis, and email locally; Mailpit captures email. Local emulation is supported and documented.
- **Realtime:** HTTPS is the only message-write path; Web PubSub is receive-only for browser clients. The current app does not use a Web PubSub webhook to accept client message events.
- **Authentication:** Better Auth database sessions are implemented; a custom JWT/refresh-token scheme is not planned for this baseline.
- **Authorization/cache scope:** PostgreSQL checks relationships directly. There is no Redis permission cache or transactional outbox in the current implementation.
- **Azure access:** use managed identity/workload identity for supported Azure data-plane services; do not set emulator connection strings or local auto-provision behavior in Azure.

These choices are reflected in the companion `architecture.md` and `azure-deployment.md` in this directory and must not be replaced by superseded architecture text in older planning notes.

## Current infrastructure status and next work

Application behavior and the local developer environment are implemented. The checked-in infrastructure repository is not yet the complete Azure topology: it includes a dev resource-group stack and reusable resource-group and ACS Email modules, while the Azure deployment guide describes the intended broader deployment. Continue infrastructure work against that deployment guide, preserving its single-app AKS and Key Vault design. Verify actual Azure state before assuming a resource or role has been deployed.
