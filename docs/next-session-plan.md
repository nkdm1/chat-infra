# Next session plan (recorded 2026-11-25, before sleep)

## Current state
- The dev environment was previously torn down (see `docs/teardown-plan.md`, section 6); the user then started a rebuild. Their run reached `live/dev/postgresql`, created the private DNS zone and VNet links, then failed creating the B1ms server with Azure `RegionalAllocationFailed`. Inspect Azure and Terraform state before retrying; partial resources/state may remain. Later operator VM/access stacks were not reached in that run.
- Kept: Web PubSub Free, email/ACS, `websecchatacr`, Cosmos account (no data), operator vault `chat-ops-cf816eae-kv`, `chat-dev-rg`, `chat-shared-rg`, Terraform state backend.
- One leftover Terraform state entry: `live/dev/workload-federation` (no cost; cannot be read without the deleted AKS outputs).
- Runbook for rebuild: `docs/runbook-dev-bringup.md`. Non-secret chart values: `deploy/environments/dev/chat-values.yaml`.
- 2026-11-27 update: the soft-deleted dev app vault was purged after explicit user approval. The user supplied `~/.ssh/chat-operator.pub` and started `infra-up.sh -y`; PostgreSQL B1ms creation failed with `RegionalAllocationFailed` after its private DNS resources were created. Current resource/state status is not verified. The local follow-up code now adds capacity fallback, temporary-role cleanup after confirmed Ansible success, and operator VM deallocation; publish it before another run.

## 1. Cost monitoring (ongoing)
- Latest Cost Analysis shows €3.10 actual cost; this is acceptable. Continue monitoring for the next 24 hours, then review again for delayed charges.
- Check by meter: Virtual Network, Redis Cache, Virtual Machines, Public IP, Container Registry, Storage, Web PubSub and ACS.
- Expected after teardown: all dev lines at zero except Container Registry (~€0.03/day); Web PubSub/ACS should be zero idle. These estimates are historical and Cost Management can lag.
- Anything spiking or not dropping to zero: stop and investigate first, then shut it down.

## 2. Ansible (operator VM executes locally; no interactive VM login)
- [x] Added Ansible playbooks for PostgreSQL app-role/database URL, Redis runtime secrets, Gateway API CRDs, NGINX Gateway Fabric, TLS Secret, migration and app Helm releases.
- [x] Added VM cloud-init bootstrap, switched the guest username to `chatoperator`, and selected workstation-triggered Azure VM Run Command. The VM checks out public GitHub `main`; no Bastion/SSH login is part of automation.
- [x] Added Terragrunt code for operator-vault private connectivity/DNS and Key Vault Secrets User access for the VM identity. It is not applied and adds recurring private-endpoint cost.
- [ ] Publish/merge the reviewed code to public `main`, then test the full VM bootstrap/Ansible flow during an approved dev rebuild. The workstation has no `ansible-playbook`; no VM Run Command or infrastructure provisioning has been executed.

## 3. `infra up` / `infra down` scripts
- [x] Added workstation wrappers that use the active Azure CLI login for local Terragrunt and Azure VM Run Command; no Azure credentials are copied to the VM.
- [x] `infra up` prints saved plans, supports stack-level `-y`, tries PostgreSQL SKUs B1ms → B2s → B2ats_v2 on capacity/SKU-availability errors, and triggers VM-local Ansible. After confirmed Ansible success, it destroys temporary operator access grants and deallocates the VM; the next run recreates grants and starts the VM. This lifecycle is unverified against Azure.
- [x] `infra down` follows the teardown order, preserves shared resources and state, pauses for manual Cloudflare DNS deletion, and requires stack-specific destroy approval. Workload federation is destroyed before AKS to avoid stale Terragrunt dependencies.
- [x] Added a local Terragrunt password wrapper that reuses an existing operator-vault secret across PostgreSQL capacity retries and generates/writes one only if no secret exists. It temporarily opens/removes the workstation IP rule and supplies the password only in the Terragrunt child environment.
- [ ] Review and publish the current code, then inspect state before any retry. The user ran a PostgreSQL plan/apply; DNS resources succeeded and server creation failed with regional capacity. The assistant has not run Azure commands or VM Run Command. Key Vault access/secret staging, fallback retries, role cleanup, and VM deallocation remain unverified against Azure.

## 4. Monitoring (basic)
- Container Insights / Azure Monitor for AKS: node CPU and memory, pod restarts, node load.
- NGINX Gateway Fabric metrics: requests per minute, latency, 5xx rate.
- App-level: login/register success rate, Redis and PostgreSQL connection errors, Web PubSub connection count.
- Alerts with cost-safe thresholds only (alerts do not cap spend).

## 5. Populate `live/prod`
- Mirror the dev layout; use prod-specific names, separate vault, separate identities, separate DNS hostname.
- Decide prod retention (data kept vs. destroyed between sessions) before creating stateful resources.
- Do not apply until dev is verified end to end again.

## 6. Code review of Terragrunt/OpenTofu
- Remove unnecessary comments; unhardcode values (region, SKUs, IP ranges, usernames, subscription suffix) into inputs or locals.
- Fix leftover issues: the Cosmos `live/shared` formatting check, the `live/dev/operator-access` username collision (`operator` group), `live/dev/workload-federation` state entry, the `secret` and `temp.py` untracked files in the infra repo.
- Add the BETTER_AUTH_URL checksum annotation in the chart so config changes restart pods.

## 7. Learn the Kubernetes setup (deploy/ directory)
- Read `deploy/README.md`, `deploy/dev-operations.md`, `deploy/cost-review.md`, `deploy/chat/` (Chart.yaml, values.yaml, every template).
- Write a short walkthrough: how the app reaches the Gateway, how secrets flow Key Vault to CSI to pod, how the migration Job runs, how identity and RBAC are wired.
