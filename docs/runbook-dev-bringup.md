# Dev environment: reconstruction bring-up runbook

**Status (2026-11-25): the dev app environment has been destroyed.** The shared ACR, shared Cosmos account (empty), Web PubSub Free, ACS/Email, operator secrets vault and Terraform state backend remain. See [`teardown-plan.md`](teardown-plan.md) for the executed teardown and kept-resource inventory. Guarded `scripts/infra-up.sh` and `scripts/infra-down.sh` plus VM-local Ansible automation have now been added, but have not been run against Azure. This remains an unverified reconstruction workflow, not a tested one-command clean-room rebuild. See [`../scripts/README.md`](../scripts/README.md) for design, source publication requirements, safety gates and validation status.

This document separates **what is automated by checked-in code** from **operator actions still manual**. The workstation wrapper runs guarded Terragrunt workflows; after bring-up, Azure VM Run Command asks the operator VM to check out public `main` and run Ansible locally. The automation is new and untested against Azure. Do not paste secret values into terminals, command arguments, Git, Terraform state inputs, logs, or chat.

## 1. What is automated, and what is manual

### Automated by checked-in configuration

- **Terraform/OpenTofu via Terragrunt:** Azure resources represented by `live/shared/` and `live/dev/` stacks and their `modules/`. A reviewed `plan` describes changes; the operator runs `apply` for each approved stack. Terraform does not provision every runtime user/configuration item.
- **GitHub Actions image publishing:** `.github/workflows/publish-image.yml` in the app repository builds and pushes the app and migrator images to the shared ACR using GitHub OIDC. The publisher identity and federation are in `live/shared/github-publisher/`. Confirm workflow/repository IDs and branch subject before use.
- **Helm chart:** `deploy/chat/` templates a service account, ConfigMap, CSI `SecretProviderClass`, app Deployment/Service, optional migration Job, Gateway and HTTPRoute. The namespace is created by Helm's `--create-namespace` option or beforehand; it is not a chart template. The chart is not deployed by CI. Environment-specific, non-secret values are in `deploy/environments/dev/chat-values.yaml`.
- **AKS add-ons:** the AKS Terraform module enables workload identity and the Key Vault Secrets Store CSI add-on. This does not itself ensure the app can read secrets; federated identity, vault RBAC, networking, and a mounted CSI volume must also work.
- **Guarded orchestration:** `scripts/infra-up.sh` applies ordered Terragrunt stacks after individual plan approval, then invokes the operator VM via Azure Run Command. The VM checks out public GitHub `main`, obtains temporary AKS admin credentials through its managed identity, and runs `ansible/playbooks/site.yml`. `scripts/infra-down.sh` follows the dev teardown order with per-stack destroy-plan review and explicit typed approval. Neither script was executed.

### Manual / not yet automated

- Azure subscription login, region/policy/cost review, and individual Terraform plan/apply approval.
- GitHub repository configuration and the image-publishing workflow run/verification.
- GitHub repository configuration and the image-publishing workflow run/verification. Image digests must be pinned in the dev values file and exist in ACR before Ansible deploys.
- Cloudflare DNS record creation/update and SSL mode; DNS remains a manual Cloudflare action.
- Azure subscription/policy/region/SKU/cost review and individual plan approvals.
- The Ansible and Run Command workflow itself has not yet been validated on a rebuilt VM. See [`../scripts/README.md`](../scripts/README.md) for VM-to-vault network/RBAC requirements and safe failure behavior.
- Temporary operator role revocation and cost monitoring after teardown.
- Verification, temporary access revocation and teardown.

## 2. Before starting: current status and safety checks

1. Reconfirm the subscription and Azure for Students policy. Historical subscription: `cf816eae-f4d9-4db4-bfa6-bda71e2cbf68`; tenant: `d0da435b-a7e7-4d74-a4ae-f72cf8f3b2db`. These IDs are identifiers, not credentials.
2. Confirm you are in the infra repository on the intended branch, and that no untracked secret files will be added or committed.
3. For `scripts/infra-up.sh`, confirm `az`, Terragrunt, Git and Python are installed on the workstation. The wrapper prompts to use `~/.ssh/chat-operator.pub` and sets `OPERATOR_SSH_PUBLIC_KEY` itself; answering no selects an alternate public-key file. A missing/unreadable default or selected file aborts. OpenTofu/Helm/kubectl/Ansible are installed by Terragrunt/cloud-init for their respective host. For the manual fallback commands, install Helm and kubectl on the machine that can reach the private API.
4. Set the subscription explicitly for each shell session:

   ```bash
   export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
   az account show --query '{subscription:id,tenant:tenantId,name:name}' -o table
   ```

   Stop unless the subscription is the intended Azure for Students subscription.
5. Review allowed Azure regions and service/SKU availability. Historical policy allowed Germany West Central, Sweden Central, Denmark East, Poland Central and Belgium Central; Spain Central was denied for ACR. Historical PostgreSQL/VM capacity failures caused PostgreSQL and operator resources to use Sweden Central. These are observations, not a promise that policy/capacity is unchanged.
6. Review the monthly cost exposure and remaining credit before applying. Private endpoints, static IPs, Bastion, VMs, AKS nodes, Redis, PostgreSQL and ACR can incur charges. A Free SKU does not mean every related resource or traffic is free. See `deploy/cost-review.md` and monitor Cost Analysis after creation.
7. Ensure the operator-only secrets are available through the approved password manager/vault. Do not put the PostgreSQL administrator password in the app-readable vault. The dev app vault has seven-day soft delete. `infra-down.sh` purges the soft-deleted dev app vault only after its Terraform destroy and a separate exact typed confirmation; this permanently deletes its runtime secrets. `infra-up.sh` stops if the fixed vault name is still soft-deleted. The operator vault is not purged. If its network allowlist no longer includes your current public IP, do not widen it or reuse a stale IP copied from this document.

**Important:** execute one stack at a time. For each stack, run `terragrunt plan`, inspect the full plan, then run `terragrunt apply` yourself only after you approve it. Do not use `-auto-approve`. If a plan errors because an upstream dependency has not been applied, stop and follow the dependency order below.

## 3. Infrastructure stacks (ordered; guarded wrapper or manual)

Run each command from the infra repository root. The environment variables are shown in separate commands so their purpose is visible. The PostgreSQL administrator password must be supplied through an approved secret-safe process; **do not paste a literal password into an `export` command**. The guarded wrappers set `OPERATOR_SSH_PUBLIC_KEY` from the selected public-key file. The current PostgreSQL module expects the ephemeral `TF_VAR_administrator_password` input and AzureRM write-only field; the operator VM also retrieves this password from the operator vault later to configure the application login.

Example pattern for **each** stack:

```bash
cd live/shared/resource-group
terragrunt plan
```

Read the complete plan. If correct, apply interactively:

```bash
terragrunt apply
```

Then move to the next stack. Return to the repo root with `cd ../..` as needed, or open a new terminal at the repository root. Repeat the two-command plan/apply pattern for every stack below. `ARM_SUBSCRIPTION_ID` must remain set.

| Order | Stack | Purpose / dependency notes |
|---|---|---|
| 1 | `live/shared/resource-group` | Shared resource group; historically `chat-shared-rg`. Existing shared RG is retained. |
| 2 | `live/shared/container-registry` | Shared Basic ACR `websecchatacr`; images remain between dev sessions. |
| 3 | `live/shared/github-publisher` | GitHub OIDC publisher identity and `AcrPush` role. Confirm immutable GitHub owner/repository IDs and approved branch subject. |
| 4 | `live/shared/cosmos-db-account` | Shared Cosmos account; free-tier account was kept. Review throughput and data retention. |
| 5 | `live/dev/resource-group` | Dev resource group. |
| 6 | `live/dev/network` | Belgium Central VNet and app/AKS/private endpoint subnets, network-owned static IPs. |
| 7 | `live/dev/workload-identity` | App managed identity. |
| 8 | `live/dev/postgresql-network` | Sweden Central PostgreSQL VNet/subnet and peering to dev VNet. |
| 9 | `live/dev/postgresql` | Private PostgreSQL server and database. Requires an explicitly chosen `POSTGRESQL_SKU` and protected `TF_VAR_administrator_password`; set these only using the module's documented safe mechanism. |
| 10 | `live/dev/cosmos-db` | Dev database/container and app data role on shared Cosmos account. |
| 11 | `live/dev/cosmos-private-endpoint` | Private route/DNS from dev VNet to Cosmos. |
| 12 | `live/dev/key-vault` | App runtime vault; never put administrator credentials here. |
| 13 | `live/dev/key-vault-private-endpoint` | Creates app-vault private DNS zone and route; links the operator VNet. |
| 14 | `live/dev/operator-vault-private-endpoint` | Private endpoint to retained operator vault using the existing Key Vault private DNS zone; adds recurring endpoint cost. |
| 15 | `live/dev/blob-storage` | Dev attachment storage. |
| 16 | `live/dev/blob-private-endpoint` | Private route/DNS to Blob. |
| 17 | `live/dev/pubsub` | Web PubSub Free in Sweden Central; verify free-tier limits and billing. |
| 18 | `live/dev/email-communication-service` | ACS and Email managed-domain sender. |
| 19 | `live/dev/redis` | Managed Redis, TLS and selected SKU. |
| 20 | `live/dev/redis-private-endpoint` | Private Redis endpoint/DNS. |
| 21 | `live/dev/operator-access` | Temporary Sweden operator VM + Bastion. The VM now uses `chatoperator` (avoids the Ubuntu `operator` group collision), installs tools through cloud-init and clones public `main`. |
| 22 | `live/dev/operator-vault-access` | Grants the VM identity Key Vault Secrets User on the operator vault; it can read all secrets in that vault. |
| 23 | `live/dev/aks` | Private AKS cluster. AKS private API is not reachable from a normal laptop. |
| 24 | `live/dev/operator-aks-access` | Temporary cluster-admin credential retrieval role and private AKS DNS link. |
| 25 | `live/dev/workload-federation` | Apply after AKS exists: this stack reads the AKS OIDC issuer output and app identity output. Do not force mock outputs. |
| 26 | `live/dev/operator-secret-access` | Temporary Secrets Officer role on app vault, used to provision runtime secrets. Review least-privilege scope. |
| 27 | `live/dev/operator-redis-access` | Temporary Redis key-read role for runtime-secret provisioning. |

The order above follows the current Terragrunt dependency blocks. `scripts/infra-up.sh` encodes this order, prints each plan, and requires a stack-specific approval before each apply; the manual pattern above is the fallback. `live/dev/workload-federation` needs both the app identity and AKS OIDC issuer, so AKS must be applied first. If a dependency error conflicts with the order, stop and inspect the dependency rather than bypassing it. Some resources are retained in shared state; a plan should show no-op for those, not recreate them blindly.

### Applying sensitive PostgreSQL input

Do not use a command-line literal like `TF_VAR_administrator_password='...'`: it is exposed to shell history and process inspection. Do not assume a hidden prompt exists unless the current module/provider supports it. Use the approved secure environment/secret-injection mechanism from the password manager and verify that the plan does not display the value. If a safe input path cannot be established, stop and implement one before applying PostgreSQL.

## 4. Image publishing

The app repository is separate (`../chat-webapp`). Check out the intended branch and inspect `.github/workflows/publish-image.yml`. Configure GitHub Actions secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` from the publisher identity outputs; these are identifiers used for OIDC, not passwords. Confirm workflow permissions include `id-token: write`, run the publishing workflow, and verify both `chat` and `chat-migrator` tags/digests in ACR. Pin the Helm values to immutable digests, not mutable tags. No Azure client secret should be created for GitHub Actions.

## 5. PostgreSQL: create the app login (Ansible; not yet Azure-tested)

Terraform creates the server/database, but not the app role. The guarded `infra up` workflow runs `scripts/provision_postgresql.py` on the operator VM via Ansible. It reads the admin password from the operator vault in memory, creates or verifies `chat_app` and its grants, and writes `database-url` to the app vault without printing credentials. It refuses to reset an unexpected role/password state. The playbook is not yet tested against Azure; the interactive `psql` commands below are a manual recovery/reference procedure, not the normal workflow.

Historical command shape from the operator VM:

```bash
export PGSSLMODE=verify-full
export PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt
psql --host='<postgres-fqdn>' --username=chatadmin --dbname=chat --password
```

In the interactive `psql` session, create the app login and set its password with psql's hidden prompt:

```sql
CREATE ROLE chat_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
```

```psql
\password chat_app
```

Then grant the dev demo privileges:

```sql
GRANT CONNECT, CREATE ON DATABASE chat TO chat_app;
GRANT USAGE, CREATE ON SCHEMA public TO chat_app;
```

Verify the role and grants without displaying credentials. The same login is used by app and migrations and has DDL permissions; this is a dev-only compromise. Full rationale, verification queries, allocation incident, and production security requirements are in [`postgresql-provisioning.md`](postgresql-provisioning.md).

## 6. Runtime secrets (Ansible helpers; not yet Azure-tested)

The old database-URL and TLS snippets were not recovered. New implementations now exist: `scripts/provision_postgresql.py` creates/verifies `database-url`; the recovered Redis/Better Auth behavior is adapted in `scripts/provision_runtime_secrets.py`; and `scripts/provision_tls_secret.py` reads the Cloudflare certificate/key from the operator vault and applies `chat-tls` without writing the private key to a file. These run by Ansible on the operator VM. See `../scripts/README.md` for provenance and limitations. The three app secrets are:

- `database-url`: `chat_app` URL for the PostgreSQL database, with encoded userinfo and `sslmode=verify-full`.
- `redis-url`: TLS URL for the Redis `default` user/port 10000 and a Redis key.
- `better-auth-secret`: cryptographically random Better Auth secret.

Before the first automated run, review the plans for the operator-vault private endpoint and `Key Vault Secrets User` assignment, plus the temporary app-vault write role. Confirm private DNS/network and current secret names without displaying values. Secret-bearing Ansible tasks use `no_log`; never add secret values to command arguments, values files, Git, or Run Command input. Remove temporary app-vault/Redis/AKS grants on teardown.

Do not copy the PostgreSQL administrator password into the app vault: the app identity can read runtime secrets. The kept operator-only vault is `chat-ops-cf816eae-kv`. Its firewall currently permits the workstation IP, not a recreated VM; see `../scripts/README.md` for the required private endpoint/DNS and managed-identity permission before VM-side retrieval. Detailed historic behavior and future automation requirements are in [`runtime-secret-provisioning.md`](runtime-secret-provisioning.md).

## 7. Operator VM access and incident caveat

For automation, the workstation invokes Azure VM Run Command after Terragrunt finishes; the VM checks out public `main` and runs Ansible locally. The user does not need to log into the VM or distribute SSH credentials for this workflow. Run Command needs the VM agent and outbound access to Azure public endpoints. Bastion remains available for reviewed manual troubleshooting, but is not part of `infra up`.

The prior cloud-init failed because `operator` conflicted with an Ubuntu group. Terraform now configures `chatoperator` and cloud-init installs tools and clones `main`; these changes have not been applied or tested. A cloud-init `custom_data` change replaces an existing VM, so review its plan carefully. Full incident facts are in [`operator-vm-incident.md`](operator-vm-incident.md).

## 8. Kubernetes setup and release (Ansible via VM Run Command; private API)

Kubernetes here has three layers: (1) AKS gives nodes and a private API; (2) Gateway API + NGINX routes external HTTPS traffic to the app; (3) the Helm chart installs the app and connects it to Azure services/secrets. The order matters because later objects depend on earlier CRDs, identity and secrets.

### 8.1 Obtain a controlled Kubernetes operator path

`infra up` applies `operator-aks-access` only after the cluster exists. The workstation then invokes Azure VM Run Command; on the VM, `scripts/operator-run-ansible.py` authenticates as the system-assigned managed identity and calls `az aks get-credentials --admin --file /dev/shm/chat-aks-admin.kubeconfig`. Azure Resource Manager returns the admin kubeconfig because of the VM identity's Azure role; `kubectl` then uses that file to reach the private API over the VM's VNet/DNS path. The kubeconfig and Azure CLI cache are deleted when Ansible exits. Admin credentials are highly privileged; removing the Azure role alone would not revoke already-issued credentials. The script was not run against a rebuilt cluster. Do not put kubeconfig in Git or copy it to an uncontrolled laptop.

The VM Run Command path avoids a user Bastion/SSH login. Azure `az aks command invoke` remains an alternative for one-off operations, but is not used by this automation.

### 8.2 Install Gateway API and NGINX Gateway Fabric

The chart's Gateway and HTTPRoute are custom Kubernetes API resources. The Gateway API CRDs must exist before Helm creates them; NGINX Gateway Fabric watches those resources and provisions/configures the gateway data plane. The Ansible playbook installs the pinned CRDs and chart automatically after `infra up` has applied the AKS and operator access stacks; commands below are manual troubleshooting/reference steps.

From a trusted operator environment with `kubectl` and network access to the release asset, download the pinned standard CRDs:

```bash
curl -fL --output /tmp/gateway-api-standard-install.yaml \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
```

Inspect the source/version, then install:

```bash
kubectl apply --server-side -f /tmp/gateway-api-standard-install.yaml
```

Check CRDs become established:

```bash
kubectl wait --for=condition=Established --timeout=120s crd/gateways.gateway.networking.k8s.io
```

Install the pinned NGINX Gateway Fabric chart:

```bash
helm upgrade --install nginx-gateway-fabric \
  oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version 2.9.1 \
  --namespace nginx-gateway \
  --create-namespace \
  --wait
```

Verify its controller pods are Ready and its `GatewayClass` named `nginx` is Accepted before continuing. Confirm version compatibility and artifact provenance again before production.

### 8.3 Prepare namespace, service account, identity, and secrets

1. The Helm command in section 8.5 creates namespace `chat` (`--create-namespace`) and the chart template creates service account `chat-app`. The prior live setup created the namespace and service account outside Helm; on a rebuild, check whether either already exists before installing, and do not blindly re-create/adopt resources with different Helm ownership.
2. Confirm the Azure federated credential maps the AKS OIDC issuer and subject `system:serviceaccount:chat:chat-app` to the app managed identity. This is what lets the pod exchange its projected service-account token for Azure identity; no client secret is stored in Kubernetes.
3. Confirm the app identity has the intended Cosmos/Blob/Key Vault roles, and the vault's private endpoint/DNS works from AKS. The CSI driver is an AKS add-on; check its pods before debugging chart secrets.
4. The Ansible workflow provisions `database-url`, `redis-url`, and `better-auth-secret` before Helm. The chart's `SecretProviderClass` reads those Key Vault secrets using the workload client ID/tenant/vault name. The app pod mounts the CSI volume, and CSI syncs them into Kubernetes Secret `chat-runtime`. This means secrets are also present in Kubernetes secret storage; restrict cluster RBAC.
5. Ansible runs `scripts/provision_tls_secret.py`, which reads the Origin CA cert/key in memory from the operator vault, checks the key match, validity and hostname, then applies `chat-tls` over the private Kubernetes API. The private key is not written to a file or logged. This new helper is not yet Azure-tested.

### 8.4 Configure non-secret Helm values

`deploy/environments/dev/chat-values.yaml` is the operator-owned non-secret values file. It supplies pinned app/migrator image digests, workload identity client ID, tenant ID, Key Vault name, public hostname, TLS secret name, gateway public IP resource name/group, and Azure service endpoints. It must not contain passwords, tokens, Redis keys, database URLs or certificate private keys.

The checked-in dev values file still reflects the previous deployment. During `infra up`, `scripts/render_dev_values.py` replaces the recreated non-secret IDs/endpoints/IP names with current Terragrunt outputs; the pinned image digests remain from the checked-in file and must be published/verified in ACR before deployment. Keep this file as environment configuration, not a secret store.

| Values-file field | What belongs here | Why the chart needs it |
|---|---|---|
| `image`, `migrationImage` | Immutable ACR image references pinned by digest | Chooses the app and migration container images reproducibly |
| `workloadClientId`, `tenantId`, `keyVaultName` | IDs/name from the current identity and vault | Configures the Azure CSI provider to request secrets using workload identity |
| `hostname`, `tlsSecretName` | Public app hostname and Kubernetes TLS Secret name | Configures Gateway HTTPS listener and certificate reference; certificate/key contents do not go in values |
| `gatewayPublicIpName`, `gatewayPublicIpResourceGroup` | Name/group of the Terraform-owned static Gateway IP | Lets the NGINX Gateway service bind to the reserved address |
| `config.*` | Current Cosmos, Blob, PubSub, ACS endpoints and sender address | Non-secret runtime service configuration |
| `app.enabled`, `migration.enabled`, `migration.jobName` | Release phase switches and unique migration Job name | Ensures DB migration completes before exposing the app; these flags are changed between the two Helm upgrades |

Do not place `DATABASE_URL`, `REDIS_URL`, passwords, access keys, Better Auth secret, or certificate private key in the values file.

### 8.5 Run migration before application rollout

The chart has independent flags because a migration must finish successfully before the app is exposed. Ansible first installs the chart with `app.enabled: false`, `migration.enabled: true` and a unique Job name, waits for successful completion, then upgrades to `app.enabled: true`, `migration.enabled: false`. A failed migration stops the playbook before the app rollout. The commands below are manual recovery/reference steps. Do not put credentials in the values file.

From the infra repository root, install the chart into namespace `chat`:

```bash
helm upgrade --install chat ./deploy/chat \
  --namespace chat \
  --create-namespace \
  --values ./deploy/environments/dev/chat-values.yaml \
  --wait
```

The chart renders a one-shot Job and the required service account, ConfigMap and `SecretProviderClass`; it does not render the app Deployment/Gateway in migration-only mode. Wait for the uniquely named Job:

```bash
kubectl wait --for=condition=complete \
  --timeout=10m \
  job/<unique-migration-job-name> \
  --namespace chat
```

If the wait fails, stop, inspect the Job's status and non-secret logs, and fix the cause before deploying the app. The migration container gets `DATABASE_URL` from `chat-runtime`, which is synced by the CSI mount. The migration image runs database migrations; it does not create the PostgreSQL login.

After success, edit the same values file: set `migration.enabled: false` and `app.enabled: true`. Then upgrade the same Helm release:

```bash
helm upgrade chat ./deploy/chat \
  --namespace chat \
  --values ./deploy/environments/dev/chat-values.yaml \
  --wait
```

This renders the app Deployment and Service and HTTPS Gateway/HTTPRoute for the configured hostname. Verify rollout, endpoints and Gateway programming. For later migrations, plan explicitly: disabling the app may cause downtime, and migrations are not an automatic rollback.

Useful status checks (never print secret values):

```bash
kubectl get pods,svc,gateway,httproute -n chat
kubectl get gatewayclass nginx
kubectl rollout status deployment/chat -n chat
kubectl logs job/<migration-job-name> -n chat --tail=50
```

The prior deployment's `/api/health` returned 200 in-cluster. Test health and readiness endpoints after each rebuild. Add a checksum annotation for ConfigMap-derived settings: previously changing `hostname` updated the ConfigMap but did not restart pods, leaving a stale `BETTER_AUTH_URL`; a manual `kubectl rollout restart deployment/chat -n chat` fixed it. The chart fix is still pending.

### 8.6 DNS and HTTPS

Do not copy a previously allocated IP. After Terraform creates the network-owned gateway public IP, retrieve its current value:

```bash
az network public-ip show \
  --resource-group chat-dev-rg \
  --name chat-dev-vnet-gateway-ip \
  --query ipAddress -o tsv
```

Confirm the Gateway reports that address and is Programmed. In Cloudflare, create/update the proxied `A` record for `chat` using the current IP and set SSL/TLS mode to **Full (strict)**. The working hostname was `chat.nkdm.io`; Cloudflare Universal SSL did not cover the deeper hostname `dev.chat.nkdm.io`. Cloudflare's DNS record is manual and not managed by this Terragrunt repo. Verify external `/api/health`, sign-up, sign-in and email flows after deployment. If hostname changes, ensure pods restart so Better Auth sees the new `BETTER_AUTH_URL`.

## 9. Validation and close-out

- Confirm app pods, migrations, CSI mount, Gateway and HTTPRoute are healthy without printing secrets.
- Verify private DNS and TLS from the app/operator path; test PostgreSQL and Redis connections and app behavior (the previous secret-mount test did not prove successful DB/Redis connections).
- Verify DNS/Cloudflare Full (strict), health/readiness, registration, login and email delivery.
- Remove temporary operator role assignments and custom roles; remove the operator VM/Bastion when no longer required. Verify the roles are gone. Do not assume removing a role revokes an already-issued kubeconfig credential; deleting the cluster invalidates that cluster credential.
- Check Azure Cost Analysis daily for 48–72 hours because billing data lags. Destroy resources with individually reviewed Terragrunt plans using [`teardown-plan.md`](teardown-plan.md); retain shared services/state only by explicit choice.

## 10. Related records

- [`postgresql-provisioning.md`](postgresql-provisioning.md): what Terraform created, manual `chat_app` SQL/grants, TLS checks, limits and Ansible requirements.
- [`runtime-secret-provisioning.md`](runtime-secret-provisioning.md): historical runtime secret flow, temporary access and security/automation constraints.
- [`operator-vm-incident.md`](operator-vm-incident.md): cloud-init failure and manual guest repair.
- [`../deploy/README.md`](../deploy/README.md), [`../deploy/dev-operations.md`](../deploy/dev-operations.md), [`../deploy/cost-review.md`](../deploy/cost-review.md): Kubernetes and operational cautions.
- [`teardown-plan.md`](teardown-plan.md): approved choices and actual teardown record.
