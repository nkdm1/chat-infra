#!/usr/bin/env bash
# Destroy only the dev stacks listed in docs/teardown-plan.md.
# By default every changing destroy is reviewed and individually approved; -y opts into auto-approving the listed dev destroys.
set -euo pipefail
set +x
umask 077
if [[ -t 1 ]]; then
  export FORCE_COLOR=1 CLICOLOR_FORCE=1
  export TERM="${TERM:-xterm-256color}"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_SUBSCRIPTION_ID="cf816eae-f4d9-4db4-bfa6-bda71e2cbf68"
source "$ROOT/scripts/lib/load-operator-ssh-key.sh"

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

confirm_default_yes() {
  local prompt="$1" decline_message="$2" answer
  printf '%s [Y/n] ' "$prompt" >&2
  IFS= read -r answer || fail "$decline_message"
  case "$answer" in
    ""|y|Y|yes|YES|Yes) return 0 ;;
    n|N|no|NO|No) fail "$decline_message" ;;
    *) fail "Please answer Y or n; $decline_message" ;;
  esac
}

auto_approve=false
case $# in
  0) ;;
  1)
    case "$1" in
      -y) auto_approve=true ;;
      -h|--help) printf 'Usage: %s [-y]\n' "$0"; exit 0 ;;
      *) fail "Usage: $0 [-y]" ;;
    esac
    ;;
  *) fail "Usage: $0 [-y]" ;;
esac
if [[ "$auto_approve" == true ]]; then
  printf 'WARNING: -y will auto-approve every listed dev destroy. DNS removal and app-vault purge still require a [Y/n] response; pressing Enter accepts the default yes.\n'
fi

purge_dev_app_vault_if_deleted() {
  local deleted_app_vault remaining
  deleted_app_vault="$(az keyvault list-deleted --subscription "$EXPECTED_SUBSCRIPTION_ID" --query "[?name=='chat-dev-cf816eae-kv'].name | [0]" -o tsv)" || fail "Could not check the app Key Vault soft-delete state"
  if [[ -z "$deleted_app_vault" ]]; then
    printf 'No soft-deleted dev app Key Vault to purge.\n'
    return
  fi

  printf '\nThe dev app Key Vault is soft-deleted. Purging permanently deletes its secrets.\n'
  confirm_default_yes \
    "Permanently purge chat-dev-cf816eae-kv and its secrets?" \
    "App Key Vault purge was not approved; stopped"
  az keyvault purge \
    --name chat-dev-cf816eae-kv \
    --location belgiumcentral \
    --subscription "$EXPECTED_SUBSCRIPTION_ID"
  remaining="$(az keyvault list-deleted --subscription "$EXPECTED_SUBSCRIPTION_ID" --query "[?name=='chat-dev-cf816eae-kv'].name | [0]" -o tsv)" || fail "Could not verify app Key Vault purge"
  [[ -z "$remaining" ]] || fail "App Key Vault is still listed as soft-deleted; verify purge completion before bring-up"
  printf 'Dev app Key Vault purged; the operator vault was not touched.\n'
}

command -v az >/dev/null 2>&1 || fail "Required tool not found: az"
command -v terragrunt >/dev/null 2>&1 || fail "Required tool not found: terragrunt"
command -v python3 >/dev/null 2>&1 || fail "Required tool not found: python3"
load_operator_ssh_public_key || fail "Could not load an approved operator SSH public key"

actual_subscription="$(az account show --query id -o tsv)"
[[ "$actual_subscription" == "$EXPECTED_SUBSCRIPTION_ID" ]] || fail "Azure CLI is logged into the wrong subscription"
export ARM_SUBSCRIPTION_ID="$actual_subscription"
ip_approval_dir="$(mktemp -d)"
trap 'rm -rf "$ip_approval_dir"' EXIT
export OPERATOR_VAULT_IP_APPROVAL_FILE="$ip_approval_dir/operator-vault-ip-approved"
cat <<'EOF'
This command will destroy dev stacks only. It will not destroy shared services,
chat-dev-rg, chat-shared-rg, or the Terraform state backend. After the dev app
Key Vault stack is destroyed, the script can permanently purge its soft-deleted
vault after a separate Y/n confirmation. The operator vault is never purged.
Before continuing, remove or verify absence of the Cloudflare `chat` DNS record.
EOF
confirm_default_yes \
  "Have you removed or verified absence of the Cloudflare chat DNS record?" \
  "DNS removal was not confirmed; stopped"

run_terragrunt() {
  local stack="$1" action
  shift
  if [[ "$auto_approve" == true ]]; then
    case "${1:-}" in
      apply|destroy)
        action="$1"
        shift
        set -- "$action" -auto-approve "$@"
        ;;
    esac
  fi
  if [[ "$stack" == "live/dev/postgresql" ]]; then
    python3 "$ROOT/scripts/terragrunt_with_postgres_admin_secret.py" --mode read -- terragrunt "$@"
  else
    terragrunt "$@"
  fi
}

for stack in "${stacks[@]}"; do
  stack_dir="$ROOT/$stack"
  [[ -f "$stack_dir/terragrunt.hcl" ]] || fail "Missing stack configuration: $stack"
  printf '\n========== Terragrunt destroy plan: %s ==========\n' "$stack"
  plan_output="$(mktemp)"
  if ! (cd "$stack_dir" && run_terragrunt "$stack" plan -destroy) 2>&1 | tee "$plan_output"; then
    rm -f "$plan_output"
    fail "Destroy plan failed for $stack; stopped without destroying this stack"
  fi
  if grep -Eq 'No changes\.' "$plan_output"; then
    printf 'No changes for %s; skipping destroy.\n' "$stack"
    rm -f "$plan_output"
    if [[ "$stack" == "live/dev/key-vault" ]]; then
      purge_dev_app_vault_if_deleted
    fi
    continue
  fi
  rm -f "$plan_output"
  if [[ "$auto_approve" == true ]]; then
    printf 'Auto-approving the destroy plan for %s due to -y.\n' "$stack"
  else
    confirm_default_yes \
      "Review the plan above. Destroy resources in $stack?" \
      "Destroy approval not received for $stack; stopped"
  fi
  (cd "$stack_dir" && run_terragrunt "$stack" destroy)
  if [[ "$stack" == "live/dev/key-vault" ]]; then
    purge_dev_app_vault_if_deleted
  fi
done

cat <<'EOF'
Listed dev stacks are destroyed. Verify Azure resources and Cost Analysis against
docs/teardown-plan.md. Shared resources, chat-dev-rg, chat-shared-rg and state were
intentionally retained. Stop if any unexpected resource remains or charges continue.
EOF
