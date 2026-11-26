#!/usr/bin/env bash
# Destroy only the dev stacks listed in docs/teardown-plan.md.
# Every changing destroy requires a reviewed plan and explicit local approval.
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_SUBSCRIPTION_ID="cf816eae-f4d9-4db4-bfa6-bda71e2cbf68"

# Temporary grants and federation must be removed while their dependencies exist.
# Workload federation is deliberately destroyed before AKS to avoid stale state.
stacks=(
  live/dev/operator-aks-access
  live/dev/operator-secret-access
  live/dev/operator-redis-access
  live/dev/operator-vault-access
  live/dev/workload-federation
  live/dev/operator-access
  live/dev/aks
  live/dev/redis-private-endpoint
  live/dev/redis
  live/dev/cosmos-private-endpoint
  live/dev/cosmos-db
  live/dev/blob-private-endpoint
  live/dev/blob-storage
  live/dev/operator-vault-private-endpoint
  live/dev/key-vault-private-endpoint
  live/dev/key-vault
  live/dev/postgresql
  live/dev/postgresql-network
  live/dev/workload-identity
  live/dev/network
)

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
command -v az >/dev/null 2>&1 || fail "Required tool not found: az"
command -v terragrunt >/dev/null 2>&1 || fail "Required tool not found: terragrunt"

actual_subscription="$(az account show --query id -o tsv)"
[[ "$actual_subscription" == "$EXPECTED_SUBSCRIPTION_ID" ]] || fail "Azure CLI is logged into the wrong subscription"
export ARM_SUBSCRIPTION_ID="$actual_subscription"
[[ -n "${POSTGRESQL_SKU:-}" ]] || fail "Set POSTGRESQL_SKU to the configured, reviewed server SKU"
export POSTGRESQL_SKU
[[ -n "${OPERATOR_SSH_PUBLIC_KEY:-}" ]] || fail "Load the approved operator SSH public key into OPERATOR_SSH_PUBLIC_KEY"
export OPERATOR_SSH_PUBLIC_KEY
[[ -n "${TF_VAR_administrator_password:-}" ]] || fail "Load TF_VAR_administrator_password through the approved secret-safe process"

cat <<'EOF'
This command will destroy dev stacks only. It will not destroy shared services,
chat-dev-rg, chat-shared-rg, or the Terraform state backend.
Before continuing, remove or verify absence of the Cloudflare `chat` DNS record.
EOF
printf "After that manual DNS check, type exactly 'dns-removed' to continue: "
IFS= read -r dns_confirmation
[[ "$dns_confirmation" == "dns-removed" ]] || fail "DNS removal was not confirmed; stopped"

for stack in "${stacks[@]}"; do
  stack_dir="$ROOT/$stack"
  [[ -f "$stack_dir/terragrunt.hcl" ]] || fail "Missing stack configuration: $stack"
  printf '\n========== Terragrunt destroy plan: %s ==========\n' "$stack"
  plan_output="$(mktemp)"
  if ! (cd "$stack_dir" && terragrunt plan -destroy -no-color) 2>&1 | tee "$plan_output"; then
    rm -f "$plan_output"
    fail "Destroy plan failed for $stack; stopped without destroying this stack"
  fi
  if grep -Eq 'No changes\.' "$plan_output"; then
    printf 'No changes for %s; skipping destroy.\n' "$stack"
    rm -f "$plan_output"
    continue
  fi
  rm -f "$plan_output"
  printf "Review the destroy plan above. To approve this stack, type exactly: destroy %s\n> " "$stack"
  IFS= read -r approval
  [[ "$approval" == "destroy $stack" ]] || fail "Destroy approval not received for $stack; stopped"
  (cd "$stack_dir" && terragrunt destroy)
done

cat <<'EOF'
Listed dev stacks are destroyed. Verify Azure resources and Cost Analysis against
docs/teardown-plan.md. Shared resources, chat-dev-rg, chat-shared-rg and state were
intentionally retained. Stop if any unexpected resource remains or charges continue.
EOF
