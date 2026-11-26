# Next session plan (recorded 2026-11-25, before sleep)

## Current state
- Dev environment is torn down (see `docs/teardown-plan.md`, section 6). The app is offline.
- Kept: Web PubSub Free, email/ACS, `websecchatacr`, Cosmos account (no data), operator vault `chat-ops-cf816eae-kv`, `chat-dev-rg`, `chat-shared-rg`, Terraform state backend.
- One leftover Terraform state entry: `live/dev/workload-federation` (no cost; cannot be read without the deleted AKS outputs).
- Runbook for rebuild: `docs/runbook-dev-bringup.md`. Non-secret chart values: `deploy/environments/dev/chat-values.yaml`.
- 2026-11-27 update: the user pushed commit `320e79a` to public `origin/main`; local `main` is synchronized. The soft-deleted dev app vault was purged after explicit user approval. No infrastructure provisioning has started; the new teardown-purge change is being prepared locally and is not yet on `main`.

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
- [x] `infra up` prints each plan and requires stack-specific approval before apply, then triggers VM-local Ansible. It requires reviewed code on public `main` and renders fresh non-secret Helm values from Terraform outputs.
- [x] `infra down` follows the teardown order, preserves shared resources and state, pauses for manual Cloudflare DNS deletion, and requires stack-specific destroy approval. Workload federation is destroyed before AKS to avoid stale Terragrunt dependencies.
- [ ] Review scripts carefully and validate with read-only plans first. No Terragrunt plan/apply/destroy or Azure VM Run Command has been executed; wrapper behavior remains untested. The user-approved dev app-vault purge was performed separately on 2026-11-27.

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
