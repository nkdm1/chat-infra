# Infrastructure and operator automation

The shell wrappers and Ansible playbooks are code-only changes. **They have not been run against Azure**, and the dev environment is currently destroyed. Review their plans before applying anything. Neither wrapper uses `-auto-approve`; `infra-down.sh` destroys only the listed dev stacks, one reviewed plan at a time.

## Selected execution model

1. An administrator runs `scripts/infra-up.sh` on their workstation while authenticated with Azure CLI. Terragrunt runs locally using that account and the existing state backend.
2. After all stack plans are individually approved and applied, the workstation gathers only non-secret Terraform outputs and current non-secret dev Helm values.
3. The workstation uses Azure VM Run Command to trigger the private operator VM. No SSH/Bastion login is required for automation, and no Azure user credentials are copied to the VM.
4. The VM fetches **public GitHub `main`**, logs into Azure using its system-assigned managed identity, retrieves an admin kubeconfig into `/dev/shm`, and runs Ansible locally. It removes the temporary kubeconfig, Azure CLI cache and generated values file afterward.

The code is being developed on the local `nk/working-demo` branch and is not pushed. `infra-up.sh` checks that relevant local files match published `origin/main` and stops before planning/applying if they do not. The playbooks will not be available to a VM until the reviewed changes are merged/published to `main` by the repository owner. This assistant will not push them.

Azure Run Command requires a healthy VM agent and outbound access from it to Azure public endpoints and GitHub/Helm/Gateway release endpoints. The workstation identity must be allowed to invoke VM Run Command. Run Command output is limited; secret-bearing Ansible tasks use `no_log`, and secret values are never included in the Run Command input.

## Ansible workflows

`ansible/playbooks/site.yml` runs these steps in order on the operator VM:

- `postgresql.yml`: `scripts/provision_postgresql.py` retrieves `postgresql-admin-password` from the operator vault in memory, creates/verifies the `chat_app` role and grants, and creates `database-url` in the app vault only if absent. It fails closed on an unexpected role/secret mismatch. The write is resumable if the role creation fails after the URL is stored.
- `runtime-secrets.yml`: `scripts/provision_runtime_secrets.py` creates Redis URL and Better Auth secret once. If both already exist, reruns leave them untouched; if only one exists, it stops for manual recovery. Redis keys are read from ARM in memory.
- `kubernetes.yml`: installs Gateway API v1.4.1 CRDs and NGINX Gateway Fabric 2.9.1, creates namespace `chat`, applies TLS via `scripts/provision_tls_secret.py`, runs the migration Helm release, then deploys the app release and waits for rollout.
- `preflight.yml`: checks required non-secret inputs and temporary access files are present.

The app's runtime passwords/keys are never copied into the operator vault, command arguments, values file, or repo. PostgreSQL and TLS helper failures emit generic messages; inspect Azure role/network metadata and Ansible task output, not secret values.

`render_dev_values.py` copies the pinned image digests from `deploy/environments/dev/chat-values.yaml` and replaces recreated non-secret identity, vault, endpoint and IP names with Terraform outputs. It writes only to stdout; the workstation passes the resulting YAML to the VM through Run Command. It refuses unpinned image references. It does not build/publish images or verify the referenced digests exist in ACR; image publishing/verification remains a prerequisite.

## Azure access needed

The Terraform additions are in:

- `live/dev/operator-vault-private-endpoint`: connects the retained `chat-ops-cf816eae-kv` to the existing private DNS zone and dev network. The operator VM VNet is peered into that network. This private endpoint adds recurring cost.
- `live/dev/operator-vault-access`: grants only the operator VM identity the built-in **Key Vault Secrets User** role at the operator-vault scope. This permits reading all secrets in that vault; it does not grant the app identity access.

These stacks are in the `infra-up.sh` dependency order, but have **not** been applied. The Azure user must review the plans and confirm current network, DNS, RBAC, region, policy and cost. The operator vault's current public firewall allows the workstation IP; the private endpoint is intended for VM access without widening that firewall.

Existing temporary stacks also give the VM app-vault write access, Redis key-listing permission and AKS admin-credential retrieval rights. Those scopes are part of the plan and must be reviewed. AKS admin credentials are highly privileged; the VM uses them only for the Kubernetes playbook and deletes the temporary kubeconfig afterward.

## Wrapper safety

- `infra-up.sh` checks the active subscription is the known dev subscription, fails closed if the destroyed app vault is still soft-deleted, requires a reviewed PostgreSQL SKU, approved `OPERATOR_SSH_PUBLIC_KEY`, and an already loaded `TF_VAR_administrator_password`, prints each Terragrunt plan and waits for a stack-specific typed approval before each apply. It then invokes Ansible through Azure VM Run Command. It never passes secret values to the VM.
- `infra-down.sh` checks the subscription and requires the current Terragrunt inputs (`POSTGRESQL_SKU`, `OPERATOR_SSH_PUBLIC_KEY`, and `TF_VAR_administrator_password`), then asks the operator to remove/verify the Cloudflare DNS record, then prints each destroy plan and requires a stack-specific typed approval before each `terragrunt destroy`. It does not target shared stacks, the resource-group stack, the retained ACS/Email, Web PubSub, ACR, Cosmos account, operator vault or state backend. It destroys workload federation before AKS so Terragrunt can still resolve the AKS dependency.
- The wrappers have not been executed. They should be tested against current state through plans only first. Stop on dependency errors, unexpected changes, stale federation state or missing outputs; do not repair state automatically.

## Recovered historical source

`archive/recovered_temp_py_2026-11-25.py` is the identical `temp.py` found in 19 ignored Terragrunt-cache copies. It writes `redis-url` and `better-auth-secret` to the **old app vault** and has old resource identifiers. **Do not run it.** `provision_runtime_secrets.py` is the parameterized adaptation.

The historical database-URL and TLS snippets were not recoverable. The current PostgreSQL/TLS helpers are new implementations based on the recorded procedures in `docs/postgresql-provisioning.md` and `docs/runtime-secret-provisioning.md`; they are not represented as recovered source.

## Validation and remaining prerequisites

- Python syntax and Bash syntax have been checked; Azure calls have not been made.
- `ansible-playbook` and PyYAML are not installed in the workstation environment, so the playbooks have not been linted or executed.
- Cloud-init installs Ansible, Azure CLI, Helm, kubectl and Python libraries and clones public `main`. It changes VM `custom_data`; this will replace the VM if applied to an existing VM. The VM admin username is changed to `chatoperator` to avoid the previous Ubuntu group collision.
- Before a real bring-up: publish/merge the reviewed automation to `main`, handle the app vault's seven-day soft-delete window explicitly (the wrapper never purges or recovers it), confirm the VM image/agent and outbound network, confirm operator Key Vault secret names without printing values, validate current Azure outputs/API versions/region quotas and costs, and review every plan individually. Do not run `terragrunt apply` or `destroy` without separate user approval.
