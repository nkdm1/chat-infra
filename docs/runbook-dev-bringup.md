# Dev environment: reconstruction bring-up runbook

**Status (updated 2026-11-27): the dev app environment was previously torn down, then the user began a rebuild.** Their `infra-up.sh` run reached PostgreSQL creation and failed with Azure `RegionalAllocationFailed` for `B_Standard_B1ms`; its output shows the private DNS zone and VNet links created before the failure. The resulting Azure/Terraform state has not been independently checked. The operator VM/access stacks occur later in the order and were not reached by that run. The new fallback, temporary-role cleanup and VM-deallocation workflow is code-only and unverified against Azure. See [`teardown-plan.md`](teardown-plan.md) for the earlier teardown and [`../scripts/README.md`](../scripts/README.md) for the new workflow and validation status.

This document separates **what is automated by checked-in code** from **operator actions still manual**. The workstation wrapper runs guarded Terragrunt workflows; after bring-up, Azure VM Run Command asks the operator VM to check out public `main` and run Ansible locally. The automation is new and untested against Azure. Do not paste secret values into terminals, command arguments, Git, Terraform state inputs, logs, or chat.

## 1. What is automated, and what is manual

### Automated by checked-in configuration

- **Terraform/OpenTofu via Terragrunt:** Azure resources represented by `live/shared/` and `live/dev/` stacks and their `modules/`. A reviewed `plan` describes changes; the operator runs `apply` for each approved stack. Terraform does not provision every runtime user/configuration item.
- **GitHub Actions image publishing:** `.github/workflows/publish-image.yml` in the app repository builds and pushes the app and migrator images to the shared ACR using GitHub OIDC. The publisher identity and federation are in `live/shared/github-publisher/`. Confirm workflow/repository IDs and branch subject before use.
- **Helm chart:** `deploy/chat/` templates a service account, ConfigMap, CSI `SecretProviderClass`, app Deployment/Service, optional migration Job, Gateway and HTTPRoute. The namespace is created by Helm's `--create-namespace` option or beforehand; it is not a chart template. The chart is not deployed by CI. Environment-specific, non-secret values are in `deploy/environments/dev/chat-values.yaml`.
- **AKS add-ons:** the AKS Terraform module enables workload identity and the Key Vault Secrets Store CSI add-on. This does not itself ensure the app can read secrets; federated identity, vault RBAC, networking, and a mounted CSI volume must also work.
- **Guarded orchestration:** By default, `scripts/infra-up.sh` displays each colored Terragrunt plan, saves that exact plan temporarily, and asks `Apply the reviewed plan? [Y/n]` before applying it. Enter/Y accepts; n stops. `infra-up.sh -y` skips per-stack prompts and passes `-auto-approve` to mutating commands. The wrapper starts the operator VM if deallocated, invokes it via Azure VM Run Command, and checks a success marker emitted only after Ansible exits successfully. Only then does it destroy the four temporary operator-access stacks and deallocate the VM. On failed/unconfirmed Ansible or cleanup, the VM remains running for troubleshooting. The VM checks out public GitHub `main`, obtains temporary AKS admin credentials through its managed identity, and runs `ansible/playbooks/site.yml`. `scripts/infra-down.sh` follows the dev teardown order; `-y` auto-approves listed dev destroys, while Cloudflare DNS and app-vault purge confirmations remain required.

### Manual / not yet automated

- Azure subscription login, region/policy/cost review, and individual Terraform plan/apply approval.
- GitHub repository configuration and the image-publishing workflow run/verification.
- GitHub repository configuration and the image-publishing workflow run/verification. Image digests must be pinned in the dev values file and exist in ACR before Ansible deploys.
- Cloudflare DNS record creation/update and SSL mode; DNS remains a manual Cloudflare action.
- Azure subscription/policy/region/SKU/cost review and individual plan approvals.
- The Ansible and Run Command workflow itself has not yet been validated on a rebuilt VM. See [`../scripts/README.md`](../scripts/README.md) for VM-to-vault network/RBAC requirements and safe failure behavior.
- Verify the new post-success temporary-role revocation and VM deallocation; on failure, inspect and manually clean up any remaining grants/VM.
- Verify deployment, automatic temporary access revocation/deallocation, and eventual teardown.

## 2. Before starting: current status and safety checks

1. Reconfirm the subscription and Azure for Students policy. Historical subscription: `cf816eae-f4d9-4db4-bfa6-bda71e2cbf68`; tenant: `d0da435b-a7e7-4d74-a4ae-f72cf8f3b2db`. These IDs are identifiers, not credentials.
2. Confirm you are in the infra repository on the intended branch, and that no untracked secret files will be added or committed.
3. For `scripts/infra-up.sh`, confirm `az`, Terragrunt, Git and Python 3.10+ are installed on the workstation. The wrapper prompts to use `~/.ssh/chat-operator.pub` and sets `OPERATOR_SSH_PUBLIC_KEY` itself; answering no selects an alternate public-key file. A missing/unreadable default or selected file aborts. OpenTofu/Helm/kubectl/Ansible are installed by Terragrunt/cloud-init for their respective host. For the manual fallback commands, install Helm and kubectl on the machine that can reach the private API.
4. Set the subscription explicitly for each shell session:

   ```bash
   export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
   az account show --query '{subscription:id,tenant:tenantId,name:name}' -o table
   ```

   Stop unless the subscription is the intended Azure for Students subscription.
5. Review allowed Azure regions and service/SKU availability. Historical policy allowed Germany West Central, Sweden Central, Denmark East, Poland Central and Belgium Central; Spain Central was denied for ACR. Historical PostgreSQL/VM capacity failures caused PostgreSQL and operator resources to use Sweden Central. These are observations, not a promise that policy/capacity is unchanged.
6. Review the monthly cost exposure and remaining credit before applying. Private endpoints, static IPs, VMs, AKS nodes, Redis, PostgreSQL and ACR can incur charges. The operator VM is deallocated after successful Ansible; Azure Bastion Developer is a separate free service and remains provisioned. See `deploy/cost-review.md` and monitor Cost Analysis after creation.
7. Ensure the operator-only Cloudflare TLS secrets are present in the approved operator vault. Do not put the PostgreSQL administrator password in the app-readable vault; `infra-up.sh` reuses an existing staged operator-vault password across PostgreSQL SKU retries and writes a new random version only if no secret exists. The dev app vault has seven-day soft delete. `infra-down.sh` purges the soft-deleted dev app vault only after its Terraform destroy and a separate exact typed confirmation; this permanently deletes its runtime secrets. `infra-up.sh` stops if the fixed vault name is still soft-deleted. The operator vault is not purged. If its network allowlist no longer includes your current public IP, do not widen it or reuse a stale IP copied from this document.

**Important:** By default, inspect the full plan and approve each changing stack individually. `infra-up.sh` applies the exact saved binary plan after the `[Y/n]` approval. Use `-y` only when you intentionally want every changing up-stack plan auto-approved; it passes OpenTofu's `-auto-approve` flag. `infra-down.sh -y` also auto-approves the listed dev destroys. For manual PostgreSQL operations, invoke Terragrunt through `scripts/terragrunt_with_postgres_admin_secret.py` so the ephemeral password is supplied without printing or entering it manually. If a plan errors because an upstream dependency has not been applied, stop and follow the dependency order below.

## 3. Infrastructure stacks (ordered; guarded wrapper or manual)

Run each command from the infra repository root. New PostgreSQL server creation tries `B_Standard_B1ms`, then `B_Standard_B2s`, then `B_Standard_B2ats_v2` when Azure reports a capacity/SKU-availability failure; each attempt receives a new plan. Existing servers retain their current SKU. Recheck region availability, policy, quota and cost before provisioning. The guarded wrappers load `OPERATOR_SSH_PUBLIC_KEY` from the selected public-key file. The PostgreSQL helper reuses a staged admin secret across retries and writes a new random version only if none exists. It temporarily adds the workstation IP to the vault firewall after a `[Y/n]` prompt, removes the rule before Terragrunt runs, and passes the password only in Terragrunt's process environment. The VM later reads the same value using its managed identity.

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
| 9 | `live/dev/postgresql` | Private PostgreSQL server and database. For a new server, fallback sequence is `B_Standard_B1ms` → `B_Standard_B2s` → `B_Standard_B2ats_v2` on capacity/SKU-availability errors. Existing server SKU is reused. B2ats_v2 has 2 vCores but 1 GiB memory; verify workload fit and current pricing. |
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
| 21 | `live/dev/operator-access` | Sweden operator VM + free Azure Bastion Developer. The VM uses `chatoperator`, installs tools through cloud-init and clones public `main`. After successful Ansible it is deallocated (not deleted); the Bastion resource remains.
| 22 | `live/dev/operator-vault-access` | Grants the VM identity Key Vault Secrets User on the operator vault; it can read all secrets in that vault. |
| 23 | `live/dev/aks` | Private AKS cluster. AKS private API is not reachable from a normal laptop. |
| 24 | `live/dev/operator-aks-access` | Temporary cluster-admin credential retrieval role and private AKS DNS link. |
| 25 | `live/dev/workload-federation` | Apply after AKS exists: this stack reads the AKS OIDC issuer output and app identity output. Do not force mock outputs. |
| 26 | `live/dev/operator-secret-access` | Temporary Secrets Officer role on app vault, used to provision runtime secrets. Review least-privilege scope. |
| 27 | `live/dev/operator-redis-access` | Temporary Redis key-read role for runtime-secret provisioning. |

The order above follows the current Terragrunt dependency blocks. `scripts/infra-up.sh` encodes this order, prints each colored plan, and saves the exact binary plan. By default it asks `Apply the reviewed plan? [Y/n]`; `-y` skips these per-stack prompts and auto-approves the applies. After Ansible success, the wrapper also reviews/destroys the temporary operator-access stacks and deallocates the VM; future bring-up recreates the grants and starts it. For a manual PostgreSQL plan/apply, from `live/dev/postgresql` set `POSTGRESQL_SKU` to the provider-format SKU matching the existing Azure server (for example, `B_Standard_B2s`) to avoid an unintended resize; for a new server, the default is B1ms. Then run `python3 ../../../scripts/terragrunt_with_postgres_admin_secret.py --mode ensure -- terragrunt plan`; after review, run the same command with `--mode read -- terragrunt apply`. The guarded wrapper reads an existing server's SKU automatically. `live/dev/workload-federation` needs both the app identity and AKS OIDC issuer, so AKS must be applied first. If a dependency error conflicts with the order, stop and inspect the dependency rather than bypassing it. Some resources are retained in shared state; a plan should show no-op for those, not recreate them blindly.

### PostgreSQL administrator secret lifecycle

The wrapper does not ask the operator to type or export the password. `scripts/terragrunt_with_postgres_admin_secret.py` reuses an already-staged secret across capacity retries; only when both server and secret are absent does it generate a password using Python's cryptographic random source and write it through the Key Vault HTTPS API body (not a CLI argument). It supplies the value to Terragrunt only as an ephemeral child-process environment value. On an existing server it fetches the latest secret instead of rotating it. Key Vault `set` creates a new secret version under the same name; it does not rewrite an older version. The helper temporarily allows only the workstation public IP after a `[Y/n]` confirmation and attempts to remove that rule before running Terragrunt. It aborts on access/cleanup errors; check the vault network rules if it reports cleanup failure. Never run with shell xtrace or print the helper's internal secret.

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

Do not copy the PostgreSQL administrator password into the app vault: the app identity can read runtime secrets. The kept operator-only vault is `chat-ops-cf816eae-kv`. The workstation currently needs a temporary firewall rule for the helper; the operator VM instead uses its private endpoint/DNS path and managed-identity role. See `../scripts/README.md` for access requirements. Detailed historic behavior and future automation requirements are in [`runtime-secret-provisioning.md`](runtime-secret-provisioning.md).

## 7. Operator VM access and incident caveat

For automation, the workstation invokes Azure VM Run Command after Terragrunt finishes; the VM checks out public `main` and runs Ansible locally. The user does not need to log into the VM or distribute SSH credentials for this workflow. Run Command needs the VM agent and outbound access to Azure public endpoints. Azure Bastion Developer remains available for reviewed manual troubleshooting, but the operator VM is deallocated after successful Ansible; start the VM before using Bastion.

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
- Verify the temporary operator role assignments/custom role were removed after successful Ansible and the VM was deallocated. On failure, inspect and remove remaining grants deliberately. Do not assume removing a role revokes an already-issued kubeconfig credential; deleting the cluster invalidates that cluster credential.
- Check Azure Cost Analysis daily for 48–72 hours because billing data lags. Destroy resources with individually reviewed Terragrunt plans using [`teardown-plan.md`](teardown-plan.md); retain shared services/state only by explicit choice.

## 10. Related records

- [`postgresql-provisioning.md`](postgresql-provisioning.md): what Terraform created, manual `chat_app` SQL/grants, TLS checks, limits and Ansible requirements.
- [`runtime-secret-provisioning.md`](runtime-secret-provisioning.md): historical runtime secret flow, temporary access and security/automation constraints.
- [`operator-vm-incident.md`](operator-vm-incident.md): cloud-init failure and manual guest repair.
- [`../deploy/README.md`](../deploy/README.md), [`../deploy/dev-operations.md`](../deploy/dev-operations.md), [`../deploy/cost-review.md`](../deploy/cost-review.md): Kubernetes and operational cautions.
- [`teardown-plan.md`](teardown-plan.md): approved choices and actual teardown record.
