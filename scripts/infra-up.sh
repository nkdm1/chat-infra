#!/usr/bin/env bash
# Provision dev infrastructure locally, then trigger VM-local Ansible via Azure Run Command.
# By default each changing stack is reviewed and approved individually; -y auto-approves up-stack changes and temporary-role cleanup.
set -euo pipefail
set +x
umask 077
if [[ -t 1 ]]; then
  export FORCE_COLOR=1 CLICOLOR_FORCE=1
  export TERM="${TERM:-xterm-256color}"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_SUBSCRIPTION_ID="cf816eae-f4d9-4db4-bfa6-bda71e2cbf68"
POSTGRES_RESOURCE_GROUP="chat-dev-rg"
POSTGRES_SERVER_NAME="chat-dev-cf816eae-dk-pg"
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
  printf 'WARNING: -y auto-approves every changing listed up-stack (including shared stacks), PostgreSQL SKU fallbacks, and temporary-role cleanup. Plans remain visible, but review prompts are skipped; fallback SKUs may cost more or have different performance.\n'
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
export OPERATOR_VAULT_IP_APPROVAL_FILE="$tmp_dir/operator-vault-ip-approved"

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

get_postgresql_sku_candidates() {
  local server_json existing_sku server_tier server_state sku_prefix error_file
  error_file="$tmp_dir/postgresql-sku-query-error"
  if server_json="$(az postgres flexible-server show \
    --resource-group "$POSTGRES_RESOURCE_GROUP" \
    --name "$POSTGRES_SERVER_NAME" \
    --subscription "$EXPECTED_SUBSCRIPTION_ID" \
    --query '{sku:sku.name,tier:sku.tier,state:state}' -o json 2>"$error_file")"; then
    existing_sku="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("sku") or "")' <<< "$server_json")"
    server_tier="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tier") or "")' <<< "$server_json")"
    server_state="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("state") or "")' <<< "$server_json")"
    case "$server_tier" in
      Burstable) sku_prefix="B" ;;
      GeneralPurpose) sku_prefix="GP" ;;
      MemoryOptimized) sku_prefix="MO" ;;
      *) fail "Unrecognized PostgreSQL compute tier $server_tier; stopped" ;;
    esac
    case "$existing_sku" in
      Standard_*) existing_sku="${sku_prefix}_${existing_sku}" ;;
      B_Standard_*|GP_Standard_*|MO_Standard_*) ;;
      *) fail "Unrecognized PostgreSQL SKU $existing_sku; stopped" ;;
    esac
    [[ -n "$server_state" ]] || fail "PostgreSQL server state was empty; stopped"
    case "$server_state" in
      Ready|Stopped)
        # Reuse an existing server's real SKU to avoid planning an unintended resize.
        printf '%s\n' "$existing_sku"
        ;;
      Failed)
        # A failed prior create must advance past the SKU Azure reports on that resource.
        case "$existing_sku" in
          B_Standard_B1ms) printf '%s\n' B_Standard_B2s ;;
          B_Standard_B2s) fail "All configured Denmark East PostgreSQL SKUs were already attempted; inspect Azure state before retrying" ;;
          B_Standard_B2ms|B_Standard_B2ats_v2) fail "Failed PostgreSQL server uses SKU $existing_sku, which is not configured for Denmark East; inspect Azure state before retrying" ;;
          *) fail "PostgreSQL is in Failed state with unrecognized SKU $existing_sku; inspect Azure before retrying" ;;
        esac
        ;;
      *) fail "PostgreSQL server is in state $server_state; wait or inspect it before planning" ;;
    esac
  elif grep -Eqi 'ResourceNotFound|was not found|could not be found' "$error_file"; then
    printf '%s\n' B_Standard_B1ms B_Standard_B2s
  else
    cat "$error_file" >&2
    fail "Could not determine the PostgreSQL server SKU; stopped before planning it"
  fi
}

apply_postgresql_with_capacity_fallback() {
  local stack="live/dev/postgresql" stack_dir="$ROOT/live/dev/postgresql"
  local candidates_output sku plan_output plan_file apply_output
  local -a candidates=()
  candidates_output="$(get_postgresql_sku_candidates)" || fail "Could not select PostgreSQL SKU candidates"
  while IFS= read -r sku; do
    [[ -n "$sku" ]] && candidates+=("$sku")
  done <<< "$candidates_output"
  ((${#candidates[@]} > 0)) || fail "No PostgreSQL SKU candidates were selected"

  for sku in "${candidates[@]}"; do
    printf '\n========== Terragrunt plan: %s (SKU %s) ==========\n' "$stack" "$sku"
    plan_output="$tmp_dir/postgresql-${sku}-plan-output"
    plan_file="$tmp_dir/postgresql-${sku}.tfplan"
    apply_output="$tmp_dir/postgresql-${sku}-apply-output"
    if ! (cd "$stack_dir" && export POSTGRESQL_SKU="$sku" && run_terragrunt ensure "$stack" plan "-out=$plan_file") 2>&1 | tee "$plan_output"; then
      fail "PostgreSQL plan failed for SKU $sku; stopped without applying it"
    fi
    if grep -Eq 'No changes\.' "$plan_output"; then
      printf 'No changes for PostgreSQL SKU %s; skipping apply.\n' "$sku"
      return 0
    fi
    printf 'The reviewed binary plan is stored temporarily with owner-only permissions.\n'
    if [[ "$auto_approve" == true ]]; then
      printf 'Auto-approving the saved PostgreSQL plan for SKU %s due to -y.\n' "$sku"
    else
      confirm_apply "$stack (SKU $sku)"
    fi
    if (cd "$stack_dir" && export POSTGRESQL_SKU="$sku" && run_terragrunt read "$stack" apply "$plan_file") 2>&1 | tee "$apply_output"; then
      return 0
    fi
    if grep -Eiq 'RegionalAllocationFailed|SkuNotAvailable|InvalidSkuName|SKU[^[:alnum:]]+not available' "$apply_output"; then
      printf 'Azure could not allocate PostgreSQL SKU %s; retrying with the next configured SKU if available.\n' "$sku" >&2
      continue
    fi
    fail "PostgreSQL apply for SKU $sku failed for a non-capacity reason; stopped"
  done
  fail "PostgreSQL capacity failed for every configured SKU: ${candidates[*]}"
}

confirm_operator_access_cleanup() {
  local stack="$1" approval
  [[ -t 0 ]] || fail "Temporary role cleanup approval for $stack requires an interactive terminal"
  while true; do
    printf 'Remove temporary operator access for %s now that Ansible succeeded? [Y/n] ' "$stack"
    IFS= read -r approval || fail "No cleanup approval received for $stack; operator VM remains running"
    case "$approval" in
      ""|Y|y|yes|YES|Yes) return 0 ;;
      N|n|NO|no|No) fail "Cleanup declined for $stack; operator VM remains running with temporary access" ;;
      *) printf 'Please answer Y or n.\n' ;;
    esac
  done
}

remove_temporary_operator_access() {
  local stack stack_dir plan_output plan_file
  local -a access_stacks=(
    live/dev/operator-aks-access
    live/dev/operator-secret-access
    live/dev/operator-redis-access
    live/dev/operator-vault-access
  )
  printf '\nRemoving temporary operator permissions after verified Ansible success.\n'
  for stack in "${access_stacks[@]}"; do
    stack_dir="$ROOT/$stack"
    plan_output="$tmp_dir/cleanup-${stack//\//_}-plan-output"
    plan_file="$tmp_dir/cleanup-${stack//\//_}.tfplan"
    printf '\n========== Temporary-access destroy plan: %s ==========\n' "$stack"
    if ! (cd "$stack_dir" && run_terragrunt read "$stack" plan -destroy "-out=$plan_file") 2>&1 | tee "$plan_output"; then
      fail "Temporary-access destroy plan failed for $stack; VM remains running"
    fi
    if grep -Eq 'No changes\.' "$plan_output"; then
      printf 'No temporary access resources remain in %s.\n' "$stack"
      continue
    fi
    printf 'The exact temporary-access destroy plan is saved owner-only.\n'
    if [[ "$auto_approve" == true ]]; then
      printf 'Auto-approving temporary-access cleanup for %s due to -y.\n' "$stack"
    else
      confirm_operator_access_cleanup "$stack"
    fi
    (cd "$stack_dir" && run_terragrunt read "$stack" apply "$plan_file") || fail "Could not remove temporary access in $stack; VM remains running"
  done
}

for stack in "${stacks[@]}"; do
  stack_dir="$ROOT/$stack"
  [[ -f "$stack_dir/terragrunt.hcl" ]] || fail "Missing stack configuration: $stack"
  if [[ "$stack" == "live/dev/postgresql" ]]; then
    apply_postgresql_with_capacity_fallback
    continue
  fi
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
export CHAT_VALUES_YAML
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

operator_power_state="$(az vm show --show-details --resource-group "$DEV_RESOURCE_GROUP" --name "chat-dev-operator" --query powerState -o tsv)" || fail "Could not inspect operator VM power state"
if [[ "$operator_power_state" != "VM running" ]]; then
  printf 'Starting the deallocated operator VM before Azure Run Command.\n'
  az vm start --resource-group "$DEV_RESOURCE_GROUP" --name "chat-dev-operator" || fail "Could not start the operator VM"
fi

gateway_public_ip="$(az network public-ip show --resource-group "$DEV_RESOURCE_GROUP" --name "$GATEWAY_PUBLIC_IP_NAME" --query ipAddress -o tsv)" || fail "Could not query the Gateway public IP"
[[ -n "$gateway_public_ip" && "$gateway_public_ip" != "None" ]] || fail "Gateway public IP is not allocated"
printf '\nCloudflare Gateway A-record target: %s\n' "$gateway_public_ip"
printf '\nAll infrastructure stacks are ready. Triggering Ansible on the operator VM via Azure Run Command.\n'
run_command_output="$tmp_dir/operator-run-command.json"
if ! az vm run-command invoke \
  --resource-group "$DEV_RESOURCE_GROUP" \
  --name "chat-dev-operator" \
  --command-id RunShellScript \
  --scripts "@$remote_script" \
  --output json >"$run_command_output"; then
  cat "$run_command_output" >&2
  fail "Azure Run Command invocation failed; temporary roles and running VM are retained for troubleshooting"
fi
cat "$run_command_output"
if ! grep -Fq 'CHAT_ANSIBLE_SUCCESS_MARKER' "$run_command_output"; then
  printf '\nAnsible success was not confirmed; fetching safe operator-host diagnostics via Azure Run Command.\n' >&2
  diagnostic_script='cloud-init status --long 2>&1 || true; echo "--- cloud-init output errors ---"; grep -Ei "curl:|gpg:|error:|failed|traceback|returned non-zero|runcmd" /var/log/cloud-init-output.log | tail -n 40 || true; echo "--- cloud-init log errors ---"; grep -Ei "curl:|gpg:|error:|failed|traceback|returned non-zero|runcmd" /var/log/cloud-init.log | tail -n 60 || true'
  az vm run-command invoke --resource-group "$DEV_RESOURCE_GROUP" --name "chat-dev-operator" --command-id RunShellScript --scripts "$diagnostic_script" --output json || printf 'Could not fetch operator-host diagnostics.\n' >&2
  fail "Ansible success was not confirmed by the VM; temporary roles and running VM are retained"
fi
gateway_public_ip_configuration="$(az network public-ip show --resource-group "$DEV_RESOURCE_GROUP" --name "$GATEWAY_PUBLIC_IP_NAME" --query ipConfiguration.id -o tsv)" || fail "Could not verify the Gateway public IP association; temporary access and the running operator VM are retained"
gateway_public_ip_configuration_lower="${gateway_public_ip_configuration,,}"
[[ "$gateway_public_ip_configuration_lower" == *"/loadbalancers/kubernetes/"* ]] || fail "Ansible reported success but the Gateway public IP is not attached to the AKS load balancer; temporary access and the running operator VM are retained"
printf 'Ansible succeeded and the Gateway IP is attached to the AKS load balancer; removing temporary access grants.\n'
remove_temporary_operator_access

az vm deallocate --resource-group "$DEV_RESOURCE_GROUP" --name "chat-dev-operator" || fail "Temporary roles were removed, but the operator VM could not be deallocated"
operator_power_state="$(az vm show --show-details --resource-group "$DEV_RESOURCE_GROUP" --name "chat-dev-operator" --query powerState -o tsv)" || fail "Could not verify operator VM power state after deallocation"
[[ "$operator_power_state" == "VM deallocated" ]] || fail "Operator VM did not reach the deallocated state (reported: $operator_power_state)"
printf 'Temporary operator grants removed and operator VM deallocated.\n'
