#!/usr/bin/env bash
# This script is sent to the operator VM by `az vm run-command invoke`.
# CONFIG_B64 contains non-secret resource metadata and non-secret Helm values.
set -euo pipefail

if ! cloud-init status --wait >/dev/null 2>&1; then
  echo "Operator VM bootstrap did not complete successfully." >&2
  exit 1
fi

cd /opt/chat-infra
git fetch --quiet --depth=1 origin main
git checkout --quiet --force --detach FETCH_HEAD

if [[ ! -f scripts/operator-run-ansible.py || ! -f ansible/playbooks/site.yml ]]; then
  echo "Public main is missing the operator automation files." >&2
  exit 1
fi

printf '%s' '__CONFIG_B64__' | base64 --decode | python3 scripts/operator-run-ansible.py
