#!/usr/bin/env bash
# Provision dev infrastructure locally, then trigger VM-local Ansible via Azure Run Command.
# By default each changing stack is reviewed and approved individually; -y opts into auto-approving all up-stack applies.
set -euo pipefail
set +x
umask 077
if [[ -t 1 ]]; then
  export FORCE_COLOR=1 CLICOLOR_FORCE=1
  export TERM="${TERM:-xterm-256color}"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_SUBSCRIPTION_ID="cf816eae-f4d9-4db4-bfa6-bda71e2cbf68"
PUBLIC_REPO="https://github.com/nkdm1/chat-infra.git"

stacks=(
  live/shared/resource-group
  live/shared/container-registry
  live/shared/github-publisher
  live/shared/cosmos-db-account
  live/dev/resource-group
  live/dev/network
  live/dev/workload-identity
  live/dev/postgresql-network
  live/dev/postgresql
  live/dev/cosmos-db
  live/dev/cosmos-private-endpoint
  live/dev/key-vault
  live/dev/key-vault-private-endpoint
  live/dev/operator-vault-private-endpoint
  live/dev/blob-storage
  live/dev/blob-private-endpoint
  live/dev/pubsub
  live/dev/email-communication-service
  live/dev/redis
  live/dev/redis-private-endpoint
  live/dev/operator-access
  live/dev/operator-vault-access
  live/dev/aks
  live/dev/operator-aks-access
  live/dev/workload-federation
  live/dev/operator-secret-access
  live/dev/operator-redis-access
)

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

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
  printf 'WARNING: -y will auto-approve every changing listed up-stack, including shared stacks. Plans remain visible, but per-stack review prompts are skipped.\n'
fi

for tool in az terragrunt git python3 base64; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required tool not found: $tool"
done
[[ -d "$ROOT/live" && -d "$ROOT/modules" ]] || fail "Run this script from a valid infra checkout"
source "$ROOT/scripts/lib/load-operator-ssh-key.sh"
load_operator_ssh_public_key || fail "Could not load an approved operator SSH public key"
[[ "$(git -C "$ROOT" remote get-url origin)" == *"github.com:nkdm1/chat-infra.git"* || "$(git -C "$ROOT" remote get-url origin)" == "$PUBLIC_REPO" ]] || fail "Unexpected origin remote"

actual_subscription="$(az account show --query id -o tsv)"
[[ "$actual_subscription" == "$EXPECTED_SUBSCRIPTION_ID" ]] || fail "Azure CLI is logged into the wrong subscription"
export ARM_SUBSCRIPTION_ID="$actual_subscription"

deleted_app_vault="$(az keyvault list-deleted --query "[?name=='chat-dev-cf816eae-kv'].name | [0]" -o tsv)" || fail "Could not check soft-deleted Key Vaults; verify Key Vault name availability before provisioning"
[[ -z "$deleted_app_vault" ]] || fail "The app Key Vault is still soft-deleted; complete the reviewed infra-down workflow (including its explicit purge confirmation) or handle the vault explicitly before provisioning"

# The VM must fetch playbooks from public main. Stop before any apply if local
# infra/Ansible code differs from the published branch or has uncommitted files.
git -C "$ROOT" fetch --quiet origin main || fail "Could not fetch public origin/main"
relevant_paths=(scripts ansible modules live deploy/environments/dev/chat-values.yaml)
if ! git -C "$ROOT" diff --quiet origin/main -- "${relevant_paths[@]}"; then
  fail "Local automation/Terraform differs from origin/main; publish/merge the reviewed commit before provisioning"
fi
if [[ -n "$(git -C "$ROOT" status --porcelain -- "${relevant_paths[@]}")" ]]; then
  fail "Relevant files have uncommitted changes; commit and publish them before provisioning"
fi

run_terragrunt() {
  local mode="$1" stack="$2" action
  shift 2
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
    python3 "$ROOT/scripts/terragrunt_with_postgres_admin_secret.py" --mode "$mode" -- terragrunt "$@"
  else
    terragrunt "$@"
  fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

confirm_apply() {
  local stack="$1" approval
  [[ -t 0 ]] || fail "Apply approval for $stack requires an interactive terminal"
  while true; do
    printf 'Apply the reviewed plan for %s? [Y/n] ' "$stack"
    IFS= read -r approval || fail "No approval input received for $stack; stopped"
    case "$approval" in
      ""|Y|y|yes|YES|Yes) return 0 ;;
      N|n|NO|no|No) fail "Apply declined for $stack; stopped" ;;
      *) printf 'Please answer Y or n.\n' ;;
    esac
  done
}

for stack in "${stacks[@]}"; do
  stack_dir="$ROOT/$stack"
  [[ -f "$stack_dir/terragrunt.hcl" ]] || fail "Missing stack configuration: $stack"
  printf '\n========== Terragrunt plan: %s ==========\n' "$stack"
  plan_output="$tmp_dir/plan-output"
  plan_file="$tmp_dir/${stack//\//_}.tfplan"
  if ! (cd "$stack_dir" && run_terragrunt ensure "$stack" plan "-out=$plan_file") 2>&1 | tee "$plan_output"; then
    fail "Plan failed for $stack; stopped without applying this stack"
  fi
  if grep -Eq 'No changes\.' "$plan_output"; then
    printf 'No changes for %s; skipping apply.\n' "$stack"
    rm -f "$plan_file"
    continue
  fi
  printf 'The reviewed binary plan is stored temporarily with owner-only permissions.\n'
  if [[ "$auto_approve" == true ]]; then
    printf 'Auto-approving the saved plan for %s due to -y.\n' "$stack"
  else
    confirm_apply "$stack"
  fi
  (cd "$stack_dir" && run_terragrunt read "$stack" apply "$plan_file")
  rm -f "$plan_file"
done

# Read only non-secret Terraform outputs for the VM's Ansible configuration.
get_output() {
  local stack="$1" name="$2" value
  value="$(cd "$ROOT/$stack" && terragrunt output -raw "$name")" || fail "Could not read output $name from $stack"
  [[ -n "$value" ]] || fail "Empty output $name from $stack"
  printf '%s' "$value"
}

export POSTGRES_HOST="$(get_output live/dev/postgresql fqdn)"
export REDIS_HOSTNAME="$(get_output live/dev/redis hostname)"
redis_id="$(get_output live/dev/redis id)"
export REDIS_ENTERPRISE_NAME="${redis_id##*/}"
export DEV_RESOURCE_GROUP="$(get_output live/dev/resource-group name)"
export APP_KEY_VAULT_NAME="$(get_output live/dev/key-vault name)"
export WORKLOAD_CLIENT_ID="$(get_output live/dev/workload-identity client_id)"
export GATEWAY_PUBLIC_IP_NAME="$(get_output live/dev/network gateway_public_ip_name)"
export COSMOS_ENDPOINT="$(get_output live/shared/cosmos-db-account endpoint)"
export BLOB_ENDPOINT="$(get_output live/dev/blob-storage blob_endpoint)"
export WEB_PUBSUB_ENDPOINT="$(get_output live/dev/pubsub endpoint)"
export ACS_ENDPOINT="$(get_output live/dev/email-communication-service endpoint)"
export ACS_SENDER_ADDRESS="$(get_output live/dev/email-communication-service sender_address)"
export AZURE_TENANT_ID="$(az account show --query tenantId -o tsv)"
export OPERATOR_KEY_VAULT_NAME="chat-ops-cf816eae-kv"

CHAT_VALUES_YAML="$(python3 "$ROOT/scripts/render_dev_values.py")" || fail "Could not render non-secret Helm values"
[[ -n "$REDIS_ENTERPRISE_NAME" && "$REDIS_ENTERPRISE_NAME" != "$redis_id" ]] || fail "Could not parse Redis resource name"

config_file="$tmp_dir/operator-config.json"
remote_script="$tmp_dir/remote-run-ansible.sh"
python3 - "$config_file" <<'PY'
import json, os, sys
keys = (
    "ARM_SUBSCRIPTION_ID", "OPERATOR_KEY_VAULT_NAME", "APP_KEY_VAULT_NAME",
    "POSTGRES_HOST", "REDIS_HOSTNAME", "REDIS_ENTERPRISE_NAME",
    "DEV_RESOURCE_GROUP", "CHAT_VALUES_YAML",
)
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump({key: os.environ[key] for key in keys}, output)
PY
config_b64="$(base64 < "$config_file" | tr -d '\n')"
python3 - "$ROOT/scripts/remote-run-ansible.sh" "$remote_script" "$config_b64" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = "__CONFIG_B64__"
if source.count(marker) != 1:
    raise SystemExit("Remote runner template is invalid")
Path(sys.argv[2]).write_text(source.replace(marker, sys.argv[3]), encoding="utf-8")
PY
chmod 0600 "$remote_script"

printf '\nAll infrastructure stacks are ready. Triggering Ansible on the operator VM via Azure Run Command.\n'
az vm run-command invoke \
  --resource-group "$DEV_RESOURCE_GROUP" \
  --name "chat-dev-operator" \
  --command-id RunShellScript \
  --scripts "@$remote_script" \
  --output json
