# Agent implementation guide

> **Purpose:** Give coding and infrastructure agents a reliable implementation baseline. The chat application and its local developer environment already exist. Preserve the behavior documented here; do not follow obsolete proposals for a separately hosted SWA frontend, a second backend, custom JWT sessions, or client-originated Web PubSub message events.

## 1. Source of truth and current status

- The application implementation is in [`../../chat-webapp/`](../../chat-webapp/) (the sibling app repository); infrastructure code is in the parent directory of this `docs/` folder.
- Read [`architecture.md`](architecture.md) for implemented behavior, endpoints, security controls, service degradation, and known limitations.
- Read [`azure-deployment.md`](azure-deployment.md) for the selected Azure topology, configuration, secrets, roles, deployment sequence, and smoke tests.
- Read [`../../chat-webapp/README.md`](../../chat-webapp/README.md) for local setup and application checks. These docs in this directory are the implementation/deployment reference; update them when behavior changes.
- Application and local Compose environment are implemented. The OpenTofu/Terragrunt code here is only a partial Azure foundation; it is not evidence that the complete Azure stack has been provisioned. Inspect actual infrastructure state before relying on resources.

### Implemented application facts — do not contradict these

- One Next.js application serves both UI and API. The Azure target is **one application image on AKS behind one HTTPS origin**. SWA + separate AKS API is not the selected design.
- Local development supports both `docker compose up -d --build` (whole app and dependencies) and `pnpm dev` with dependencies in Docker. Local PostgreSQL, Cosmos DB, Blob Storage, Web PubSub, Redis, and Mailpit are provided by Compose.
- PostgreSQL stores accounts and relational data; Cosmos DB stores messages; Blob Storage stores attachments; Redis stores rate-limit and ephemeral/derived state; email is SMTP/Mailpit locally and ACS Email in Azure.
- Better Auth uses PostgreSQL-backed database sessions. Do not introduce custom JWT/refresh-token auth as an assumed next step.
- All client writes, including sending messages, go through authenticated HTTPS API routes. Browser Web PubSub connections receive updates only. The app uses polling as a realtime fallback; it does not accept chat writes through a Web PubSub event webhook.
- PostgreSQL is queried directly for relationship authorization. There is no Redis permission cache or transactional outbox in the implemented design.
- Azure runtime secrets belong in Key Vault, mounted using the AKS Secrets Store CSI Driver (synced to a Kubernetes Secret and exposed to the pod at runtime). ConfigMaps are for non-secret settings. Azure SDK-supported services use managed/workload identity where documented; PostgreSQL and Redis credentials remain explicit connection configuration.

## 2. Hard Azure budget constraint

This project uses an Azure for Students subscription with **$100 USD in credits; $100 is a hard ceiling, not a target**. Apply this rule to every resource, environment, and dependency:

- Prefer a genuinely free option when it meets the requirement; otherwise select the cheapest viable region, SKU, capacity, and runtime. Do not add paid availability, redundancy, monitoring retention, NAT, load-balancing, or private networking features without a documented need and cost review.
- Before adding or applying a resource, verify its current student-subscription eligibility, regional price, quota/free-tier limits, and costs while running, stopped, and retained. Include dependent resources and usage charges such as disks, IPs, load balancers, private endpoints, DNS, logs, backups, and data transfer.
- Estimate cumulative project spend against the **remaining** student credits, keep a safety margin, and do not plan or apply a change whose plausible cost could reach or exceed the $100 ceiling. Cost alerts are not spending caps. Do not assume a free tier applies without verifying its eligibility and limits.
- If the cheapest viable design still risks exceeding the remaining credits, stop and ask before provisioning; never silently trade the budget ceiling for availability or convenience.

## 3. Repository and change boundaries

### Application work

Application source, schema, migrations, runtime configuration, and tests are under [`../../chat-webapp/`](../../chat-webapp/). Before changing them:

1. Read the app's `AGENTS.md`, README, package scripts, relevant code, tests, and the architecture documentation.
2. Inspect the existing implementation before proposing new services or data models. Reuse Next.js, Better Auth, Drizzle, and existing service adapters.
3. Do not read, print, or commit `../../chat-webapp/.env`. Use [`../../chat-webapp/.env.example`](../../chat-webapp/.env.example) as the safe configuration reference.
4. Preserve the one-app deployment contract, same-origin session/CSRF model, and local emulator support.

For local development, follow the README. Typical checks are `pnpm check`, `pnpm lint`, `pnpm typecheck`, and `pnpm test`; tests may need Docker services. Run the production build when changes affect build/runtime packaging. Report checks and any environment-dependent failures accurately.

### Infrastructure work

The parent infrastructure directory owns OpenTofu/Terragrunt and Azure infrastructure. Current checked-in code there includes the dev resource-group stack and reusable resource-group and ACS Email modules. Inspect the existing root backend/provider configuration, modules, locks, naming, and state before changing it. Do not assume Key Vault, AKS, ACR, databases, storage, Redis, Web PubSub, or all identities/roles already exist.

Do not implement application product behavior in infrastructure code. Do not alter state, destroy resources, change production identity/RBAC scope, or apply a high-impact change without explicit human authorization. Keep secrets and credentials out of source, plans, outputs, ConfigMaps, and images.

## 4. Shared application-to-infrastructure contract

Use [`../../chat-webapp/.env.example`](../../chat-webapp/.env.example) and [`azure-deployment.md`](azure-deployment.md) as the configuration contract. Preserve these principles:

- Local emulator `*_CONNECTION_STRING` settings are for local development only. In Azure, leave those unset and configure service endpoints/account URLs instead.
- Set `AUTO_PROVISION=false` in Azure; OpenTofu provisions the Cosmos database/container and Blob container. Local development may use `AUTO_PROVISION=true`.
- Secret settings: `BETTER_AUTH_SECRET`, `DATABASE_URL`, and `REDIS_URL`; `SMTP_PASS` only when using SMTP. Use Key Vault + CSI to supply these at runtime.
- Non-secret settings include `BETTER_AUTH_URL`, `MAIL_FROM`, `EMAIL_PROVIDER`, ACS sender/endpoint, Cosmos names/endpoints, storage account/container, Web PubSub endpoint/hub/origin, and `AUTO_PROVISION`.
- Do not add `NEXT_PUBLIC_*` settings. The same Docker image must run across environments; configuration is supplied at runtime.
- Use workload identity for supported Azure services and the CSI driver's Key Vault access. Scope service roles to the required resource/data plane. Follow the deployment document's explicit identity and role table rather than inventing broader access.
- PostgreSQL and Redis authentication/network access are configured explicitly; do not assume Azure SDK managed identity automatically authenticates generic protocol clients.
- The public Gateway API hostname must match `BETTER_AUTH_URL`; keep browser and API same-origin. For new traffic routing, use an AKS-compatible Gateway API controller with `GatewayClass`, `Gateway`, and `HTTPRoute`, not legacy Kubernetes `Ingress` resources. The Ingress API is frozen (not formally deprecated); the controller implementation and cost must be reviewed.

## 5. Workstream A — application maintenance

The application is already implemented. Treat this section as rules for incremental maintenance, not a checklist to rebuild features.

1. Preserve current routes, API response conventions, Better Auth session behavior, same-origin cookie/CSRF requirements, and security controls documented in [`architecture.md`](architecture.md).
2. Keep writes on HTTPS. Web PubSub is receive-only for clients; use the existing authenticated API flow and server-side fan-out. Keep the polling fallback intact.
3. Preserve the data ownership boundary: PostgreSQL for accounts/relationships/read positions/reports, Cosmos for messages, Blob Storage for attachments, Redis for rate limits and ephemeral/derived state.
4. Keep request validation, authorization, rate limits, content/file checks, idempotency, structured error responses, and service-outage behavior covered by tests when touched.
5. Use existing adapters and official service SDKs/protocol clients. Keep local emulator configuration usable and do not require Azure credentials for normal local tests.
6. Update [`architecture.md`](architecture.md), [`azure-deployment.md`](azure-deployment.md), [`../../chat-webapp/.env.example`](../../chat-webapp/.env.example), and [`../../chat-webapp/README.md`](../../chat-webapp/README.md) only when their corresponding behavior/configuration/setup changes. Never document secrets or real user data.

**Application acceptance:** applicable tests/checks pass; local Compose or `pnpm dev` workflow remains usable; runtime configuration remains documented; no unsupported architecture is described as implemented.

## 6. Workstream B — complete the Azure deployment

The intended deployment is documented in [`azure-deployment.md`](azure-deployment.md). Build out the missing infrastructure to match it; do not substitute SWA or split frontend/backend hosting.

### B1. Foundation and resources

1. Inspect current Terragrunt/OpenTofu state, existing dev resource-group stack, shared state/backend configuration, provider lock, and resource naming before editing. Keep environment state isolated and follow existing conventions.
2. Provision the reviewed Azure resources needed for the app: Key Vault, ACR, AKS with OIDC/workload identity, PostgreSQL Flexible Server, Cosmos DB for NoSQL (`chat` database, `messages` container partitioned by `/conversationId`), private Blob Storage container, Azure Managed Redis, Azure Web PubSub (`chat` hub), and ACS Email.
3. Resolve region/SKU availability, networking, DNS/TLS, cost, diagnostic, backup, and manual email sender-domain verification requirements before applying. Export non-secret endpoints/configuration only.
4. Keep OpenTofu state, plans, credentials, and generated secret values out of version control. Review every plan and require human approval for apply/destroy or privileged identity/RBAC changes.

### B2. Identities and configuration

1. Configure an AKS workload identity and Kubernetes service account for the application. Grant only the documented data-plane permissions for Cosmos, Blob Storage, Web PubSub, ACS Email, and Key Vault CSI access.
2. Configure the AKS image-pull identity for ACR. Keep human infrastructure access, any CI image-publishing identity, and runtime workload identity separate.
3. Store `BETTER_AUTH_SECRET`, `DATABASE_URL`, and `REDIS_URL` in Key Vault. Mount them into the app pod with the Secrets Store CSI Driver, synced to a Kubernetes Secret consumed through `envFrom`. Put non-secret values in `chat-config` ConfigMap.
4. Use the exact runtime names in [`../../chat-webapp/.env.example`](../../chat-webapp/.env.example) and [`azure-deployment.md`](azure-deployment.md). Do not copy local emulator connection strings into Azure; use managed identity for Azure SDK services where supported and explicit secret URLs for PostgreSQL/Redis.

### B3. Build and deployment

1. Build the Docker `runner` target and publish one immutable/versioned image to ACR. The image contains both Next.js UI and API and listens on port 3000.
2. Run the `migrator` target as a one-shot Kubernetes Job with the same database configuration before updating the app Deployment. Do not run schema migrations as an uncontrolled parallel startup action.
3. Deploy one AKS application Deployment using the workload-identity service account, Key Vault CSI mount/Secret, `chat-config`, and runtime configuration. Configure liveness `GET /api/health` and readiness `GET /api/ready`.
4. Install a cost-reviewed Gateway API controller and route one HTTPS domain to the app using `GatewayClass`, `Gateway`, and `HTTPRoute` resources. Do not create legacy Kubernetes `Ingress` resources. Set `BETTER_AUTH_URL` to that exact origin and retain same-origin API/cookie behavior.
5. Application rollout is an explicit operational step; do not claim CI/CD or automated deployment exists unless it is implemented and documented. Do not add an SWA workflow for this topology.

**Azure acceptance:** reviewed infrastructure plan matches the documented service/identity topology; no secrets appear in state outputs, logs, ConfigMaps, image, or source; the app starts with runtime configuration only; migrations complete; readiness and the documented registration, messaging, attachment, and realtime smoke tests pass.

## 7. Cross-workstream rollout order

1. Confirm the application/configuration contract and current cloud resource state.
2. Build out the isolated dev Azure foundation and runtime identity/secrets path.
3. Verify network access and service roles; manually complete ACS sender-domain verification where required.
4. Build/push the unified app image; apply database migrations as a one-off job.
5. Deploy the single Next.js app to AKS behind the same-origin HTTPS Gateway API route.
6. Smoke-test sign-up and Mailpit locally / ACS in Azure, login, friend flows, messages and history, realtime receive plus polling fallback, attachments, readiness, and admin flows.
7. Update both implementation docs and this guide for any accepted behavior or deployment changes.

## 8. Global agent rules

- Keep changes scoped and inspect before editing. Report changed files, checks run, and blockers.
- Treat `architecture.md` and `azure-deployment.md` in this directory as the application behavior and Azure deployment reference; do not leave planning documents contradicting them.
- Never run commands that print `.env` values or credentials. Never commit secrets, real email addresses, tokens, production data, state, plans, or generated credentials.
- Do not apply or destroy infrastructure, modify production state, or broaden privileged access without explicit approval.
- Do not claim the full Azure environment, pipelines, or roles are deployed unless verified from the actual environment.
- When in doubt about an architectural change, pause and get explicit approval before changing the documented baseline.
