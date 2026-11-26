#!/usr/bin/env python3
"""Run the repo's Ansible playbooks on the operator VM via Azure Run Command.

The JSON input contains only non-secret resource configuration and generated
non-secret Helm values. Azure credentials are obtained on this VM from its
system-assigned managed identity. Kubeconfig and Azure CLI cache live in
/dev/shm and are removed even when Ansible fails.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path("/opt/chat-infra")
ALLOWED_KEYS = {
    "ARM_SUBSCRIPTION_ID",
    "OPERATOR_KEY_VAULT_NAME",
    "APP_KEY_VAULT_NAME",
    "POSTGRES_HOST",
    "REDIS_HOSTNAME",
    "REDIS_ENTERPRISE_NAME",
    "DEV_RESOURCE_GROUP",
    "CHAT_VALUES_YAML",
}


class RunError(RuntimeError):
    """Safe-to-log runner error."""


def run_hidden(argv: list[str], env: dict[str, str], timeout: int = 60) -> bool:
    try:
        result = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def main() -> int:
    try:
        config = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise RunError("Run Command configuration was invalid") from None

    if not isinstance(config, dict) or set(config) != ALLOWED_KEYS:
        raise RunError("Run Command configuration keys did not match the allowlist")
    if any(not isinstance(value, str) or "\x00" in value for value in config.values()):
        raise RunError("Run Command configuration values were invalid")
    if not (REPO / "ansible/playbooks/site.yml").is_file():
        raise RunError("The checked-out main branch is missing the Ansible playbook")

    os.umask(0o077)
    workspace = Path(tempfile.mkdtemp(prefix="chat-run-", dir="/dev/shm"))
    values_path = workspace / "chat-values.yaml"
    kubeconfig_path = workspace / "chat-aks-admin.kubeconfig"
    ansible_tmp = workspace / "ansible-tmp"
    azure_config = workspace / "azure-cli"
    ansible_tmp.mkdir()
    azure_config.mkdir()

    try:
        values_path.write_text(config["CHAT_VALUES_YAML"], encoding="utf-8")
        values_path.chmod(0o600)

        env = os.environ.copy()
        env.update({key: value for key, value in config.items() if key != "CHAT_VALUES_YAML"})
        inventory_path = REPO / "ansible/inventory/localhost.yml"
        env.update(
            {
                "AZURE_CONFIG_DIR": str(azure_config),
                "KUBECONFIG": str(kubeconfig_path),
                "CHAT_VALUES_PATH": str(values_path),
                "ANSIBLE_CONFIG": str(REPO / "ansible/ansible.cfg"),
                "ANSIBLE_LOCAL_TEMP": str(ansible_tmp),
                "ANSIBLE_REMOTE_TEMP": str(ansible_tmp),
                "ANSIBLE_NOCOLOR": "1",
            }
        )

        inventory_result = subprocess.run(
            ["ansible-inventory", "--inventory", str(inventory_path), "--list"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            env=env,
            timeout=30,
            check=False,
        )
        try:
            inventory = json.loads(inventory_result.stdout)
        except (json.JSONDecodeError, TypeError):
            inventory = {}
        if inventory_result.returncode != 0 or "operator" not in inventory.get("_meta", {}).get("hostvars", {}):
            raise RunError("Ansible inventory is missing the required operator host")

        if not run_hidden(["az", "login", "--identity", "--allow-no-subscriptions", "--output", "none"], env):
            raise RunError("Azure managed-identity login failed")
        if not run_hidden(["az", "account", "set", "--subscription", config["ARM_SUBSCRIPTION_ID"]], env):
            raise RunError("Could not select the configured Azure subscription")

        credential_args = [
            "az",
            "aks",
            "get-credentials",
            "--resource-group",
            config["DEV_RESOURCE_GROUP"],
            "--name",
            "chat-dev-aks",
            "--admin",
            "--file",
            str(kubeconfig_path),
        ]
        for attempt in range(12):
            if run_hidden(credential_args, env, timeout=45):
                break
            if attempt == 11:
                raise RunError("AKS admin credentials were unavailable; check role assignment and cluster state")
            time.sleep(10)

        kubeconfig_path.chmod(0o600)
        if not run_hidden(["kubectl", "get", "nodes", "--request-timeout=20s"], env, timeout=30):
            raise RunError("Could not reach the private AKS API from the operator VM")

        result = subprocess.run(
            [
                "ansible-playbook",
                "--inventory",
                str(inventory_path),
                "ansible/playbooks/site.yml",
            ],
            cwd=REPO,
            env=env,
            check=False,
            timeout=80 * 60,
        )
        if result.returncode != 0:
            raise RunError("Ansible failed; inspect the non-secret task output and rerun after repair")
        print("Operator Ansible configuration completed")
        return 0
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RunError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        print("Operator automation failed; inspect safe output and VM agent status", file=sys.stderr)
        raise SystemExit(1)
