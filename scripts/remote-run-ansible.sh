#!/usr/bin/env bash
# This script is sent to the operator VM by `az vm run-command invoke`.
# CONFIG_B64 contains non-secret resource metadata and non-secret Helm values.
set -euo pipefail

if ! timeout 10m cloud-init status --wait >/dev/null 2>&1; then
  echo "Operator VM bootstrap did not complete successfully; cloud-init diagnostics follow." >&2
  cloud-init status --long 2>&1 || true
  grep -Ei 'curl:|gpg:|error:|failed|traceback|returned non-zero|runcmd' /var/log/cloud-init-output.log | tail -n 40 >&2 || true
  grep -Ei 'curl:|gpg:|error:|failed|traceback|returned non-zero|runcmd' /var/log/cloud-init.log | tail -n 60 >&2 || true
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
printf '\nCHAT_ANSIBLE_SUCCESS_MARKER\n'
