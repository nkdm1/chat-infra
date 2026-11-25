# Next session plan (recorded 2026-11-25, before sleep)

## Current state
- Dev environment is torn down (see `docs/teardown-plan.md`, section 6). The app is offline.
- Kept: Web PubSub Free, email/ACS, `websecchatacr`, Cosmos account (no data), operator vault `chat-ops-cf816eae-kv`, `chat-dev-rg`, `chat-shared-rg`, Terraform state backend.
- One leftover Terraform state entry: `live/dev/workload-federation` (no cost; cannot be read without the deleted AKS outputs).
- Runbook for rebuild: `docs/runbook-dev-bringup.md`. Non-secret chart values: `deploy/environments/dev/chat-values.yaml`.

## 1. Cost monitoring (ongoing)
- Check Azure Cost Analysis (group by meter) daily for 48–72 h: Virtual Network, Redis Cache, Virtual Machines, Public IP, Container Registry, Storage.
- Expected after teardown: all dev lines at zero except Container Registry (~€0.03/day) and Web PubSub/ACS (should be zero idle).
- Anything spiking or not dropping to zero: stop and investigate first, then shut it down.

## 2. Ansible (configure via Bastion)
- Write playbooks for: PostgreSQL (app login `chat_app`, grants), Redis access setup, Kubernetes admin tasks (CSI, Gateway API CRDs, NGINX Gateway Fabric, `chat-tls` secret, Helm releases).
- Secret-bearing tasks must use `no_log`, take values from the operator vault, and never accept secrets as arguments.
- Run from the Bastion-reachable operator VM (or a runner inside the VNet). The VM itself is destroyed; recreate it via `live/dev/operator-access` when needed (choose a non-conflicting username).
- Document each playbook's inputs and expected outputs in the runbook.

## 3. `infra up` / `infra down` script
- Combine: Terragrunt stack order (`docs/runbook-dev-bringup.md` §1), Ansible playbooks (§2), Helm (§2.6–2.7), and teardown order (`docs/teardown-plan.md` §2).
- Require explicit confirmation on destroy; refuse to destroy `chat-shared-rg` and the state backend.
- Always print the plan and stop for approval; never auto-approve.

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
