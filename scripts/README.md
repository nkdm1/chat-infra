# Infrastructure and operator automation

The shell wrappers and Ansible playbooks are code-only changes. The workstation needs Python 3.10+ for the secret helper. The assistant has not run them against Azure; the user started `infra-up.sh` separately and its result is unknown, so inspect current state before rerunning. Without `-y`, up/down retain per-stack approval. With `-y`, changing up applies and listed dev destroys use OpenTofu's `-auto-approve`; DNS and app-vault purge confirmations remain.

## Selected execution model

1. An administrator runs `scripts/infra-up.sh` on their workstation while authenticated with Azure CLI. Terragrunt runs locally using that account and the existing state backend.
2. After all stack plans are individually approved and applied, the workstation gathers only non-secret Terraform outputs and current non-secret dev Helm values.
3. The workstation uses Azure VM Run Command to trigger the private operator VM. No SSH/Bastion login is required for automation, and no Azure user credentials are copied to the VM.
4. The VM fetches **public GitHub `main`**, logs into Azure using its system-assigned managed identity, retrieves an admin kubeconfig into `/dev/shm`, and runs Ansible locally. It removes the temporary kubeconfig, Azure CLI cache and generated values file afterward.

`infra-up.sh` checks that relevant local files match published `origin/main` and stops before planning/applying if they do not. The playbooks will not be available to a VM until the reviewed changes are merged/published to `main` by the repository owner. This assistant will not push them.

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

These stacks are in the `infra-up.sh` dependency order. The assistant has not applied them; the user has started `infra-up.sh` separately, so inspect the actual current state before assuming they remain absent. Review the plans and confirm current network, DNS, RBAC, region, policy and cost. The local Azure principal also needs permission to manage the vault IP rule and read/set the named secret; the VM's Secrets User role does not grant those workstation permissions. The workstation's current IP is not admitted by the operator-vault firewall. The PostgreSQL helper temporarily adds only the workstation's public IPv4 rule (after typed confirmation) for a secret read/write, then removes it before Terragrunt runs. The private endpoint is intended for VM access; the VM does not use this workstation rule.

Existing temporary stacks also give the VM app-vault write access, Redis key-listing permission and AKS admin-credential retrieval rights. Those scopes are part of the plan and must be reviewed. AKS admin credentials are highly privileged; the VM uses them only for the Kubernetes playbook and deletes the temporary kubeconfig afterward.

## Wrapper safety

An Azure PostgreSQL SKU is the server's compute/performance tier and affects cost; it is not a password or database name. Dev HCL now pins `B_Standard_B1ms` (Burstable), matching the last successful server in Sweden Central. Confirm current policy, regional availability, quota and pricing before applying.

- `infra-up.sh` checks the active subscription is the known dev subscription and fails closed if the app vault is still soft-deleted. Dev PostgreSQL is pinned to `B_Standard_B1ms`. The wrapper prompts to use `~/.ssh/chat-operator.pub` by default; answering no selects another public-key file. A missing/unreadable default or selected key aborts. The helper reads the key file and sets `OPERATOR_SSH_PUBLIC_KEY` for Terragrunt.
- At the PostgreSQL stack, `terragrunt_with_postgres_admin_secret.py` checks whether the server exists. For a new server it generates a cryptographically random password and writes a new version of `postgresql-admin-password` to the operator vault; for an existing server it reads and reuses the current version. It temporarily allows the workstation IP only when needed, requires typed confirmation for the network rule and secret write, and removes any rule it added before invoking Terragrunt. The value is only placed in the child Terragrunt process environment; it is not printed or put in argv/state. For every changing up-stack, the wrapper displays colored plan output, saves that exact plan in an owner-only temporary directory, then asks `Apply the reviewed plan? [Y/n]` (Enter/Y accepts, n stops). It applies the saved plan, not a freshly recalculated plan. `-y` skips the per-stack prompt and adds `-auto-approve` to each apply; the default path remains per-stack `[Y/n]`.
- `infra-down.sh` retrieves the current password through the same temporary, typed-confirmation access path only for the PostgreSQL destroy plan/apply; it never rotates the secret. It then follows the teardown approvals and app-vault-only purge guard. After up completes, Ansible on the operator VM independently reads the admin secret through its managed identity. Neither wrapper sends secret values to the VM.
- `infra-down.sh` checks the subscription and uses the same pinned PostgreSQL SKU as the stack; it loads the operator SSH public key using the same prompt, then asks the operator to remove/verify the Cloudflare DNS record and reviews each dev-only destroy plan. Without `-y`, it requires a stack-specific typed approval before each destroy; with `-y`, it adds `-auto-approve` to each listed dev destroy. DNS and app-vault purge confirmations remain required. For the PostgreSQL stack it reads the current admin secret through the temporary access path, without rotating it. After the app Key Vault stack is destroyed, it separately requires the exact `purge chat-dev-cf816eae-kv` confirmation before purging that soft-deleted vault. It does not target shared stacks, the resource-group stack, retained ACS/Email, Web PubSub, ACR, Cosmos account, operator vault or state backend. It destroys workload federation before AKS so Terragrunt can still resolve the AKS dependency.
- The wrappers have not been executed. They should be tested against current state through plans only first. Stop on dependency errors, unexpected changes, stale federation state or missing outputs; do not repair state automatically.

## Recovered historical source

`archive/recovered_temp_py_2026-11-25.py` is the identical `temp.py` found in 19 ignored Terragrunt-cache copies. It writes `redis-url` and `better-auth-secret` to the **old app vault** and has old resource identifiers. **Do not run it.** `provision_runtime_secrets.py` is the parameterized adaptation.

The historical database-URL and TLS snippets were not recoverable. The current PostgreSQL/TLS helpers are new implementations based on the recorded procedures in `docs/postgresql-provisioning.md` and `docs/runtime-secret-provisioning.md`; they are not represented as recovered source.

## Validation and remaining prerequisites

- Python/Bash syntax, Ansible/cloud-init YAML parsing, generated-values parsing, HCL formatting, and seven mock-based password-helper unit tests passed. The helper has not been tested against Azure. Azure verification was limited to checking the active subscription and app-vault soft-delete state; after the user explicitly approved it, the soft-deleted dev app vault was purged. The assistant has not run a Terragrunt plan/apply/destroy, Key Vault IP-rule change/secret write, or VM Run Command. The user has since started `infra-up.sh` separately; inspect actual state/output before rerunning or assuming no resources changed.
- `ansible-playbook` and PyYAML are not installed in the workstation environment, so the playbooks have not been linted or executed.
- Cloud-init installs Ansible, Azure CLI, Helm, kubectl and Python libraries and clones public `main`. It changes VM `custom_data`; this will replace the VM if applied to an existing VM. The VM admin username is changed to `chatoperator` to avoid the previous Ubuntu group collision.
- Before a real bring-up: publish/merge the reviewed automation to `main`, ensure the app vault is not soft-deleted (a completed `infra-down.sh` includes a separately confirmed purge), verify the caller can manage the operator-vault IP rule and read/write the password secret, confirm the default SSH key file exists, confirm the VM image/agent and outbound network, validate current Azure outputs/API versions/region quotas and costs, and review every plan individually. Do not run `terragrunt apply` or `destroy` without separate user approval.
