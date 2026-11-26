#!/usr/bin/env python3
"""Run a Terragrunt command with the PostgreSQL admin secret held only in memory.

The secret is read/written through the Key Vault REST API. It is never emitted
by this helper or placed in a command argument. A temporary workstation IP rule
is removed before the child Terragrunt command starts.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import os
import secrets
import signal
import string
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Callable

SUBSCRIPTION_ID = "cf816eae-f4d9-4db4-bfa6-bda71e2cbf68"
VAULT_NAME = "chat-ops-cf816eae-kv"
VAULT_RESOURCE_GROUP = "chat-shared-rg"
SECRET_NAME = "postgresql-admin-password"
VAULT_API_VERSION = "7.4"
PUBLIC_IP_URL = "https://api.ipify.org"


class SafeError(Exception):
    """An error whose message is safe to show to the operator."""


def run_az(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["az", *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def ask_yes_no(prompt: str) -> bool:
    while True:
        print(f"{prompt} [Y/n] ", end="", file=sys.stderr, flush=True)
        try:
            response = input().strip().lower()
        except EOFError as exc:
            raise SafeError("Interactive confirmation was not available; stopped") from exc
        if response in ("", "y", "yes"):
            return True
        if response in ("n", "no"):
            return False
        print("Please answer Y or n.", file=sys.stderr, flush=True)


def postgres_server_exists(resource_group: str, server_name: str) -> bool:
    result = run_az([
        "postgres", "flexible-server", "show",
        "--resource-group", resource_group,
        "--name", server_name,
        "--subscription", SUBSCRIPTION_ID,
        "--query", "name", "--output", "tsv",
    ])
    if result.returncode == 0 and result.stdout.strip():
        return True
    error = result.stderr.lower()
    if "resourcenotfound" in error or "was not found" in error or "could not be found" in error:
        return False
    raise SafeError("Could not determine whether the PostgreSQL server already exists; stopped")


def get_public_ipv4() -> str:
    try:
        with urllib.request.urlopen(PUBLIC_IP_URL, timeout=10) as response:
            raw = response.read(128).decode("ascii").strip()
        return str(ipaddress.IPv4Address(raw))
    except Exception as exc:
        raise SafeError("Could not determine the workstation public IPv4 address; stopped") from exc


def get_vault_network_config() -> tuple[str, str, list[str]]:
    result = run_az([
        "keyvault", "show",
        "--name", VAULT_NAME,
        "--resource-group", VAULT_RESOURCE_GROUP,
        "--subscription", SUBSCRIPTION_ID,
        "--query",
        "{publicNetworkAccess:properties.publicNetworkAccess,defaultAction:properties.networkAcls.defaultAction,ipRules:properties.networkAcls.ipRules[].value}",
        "--output", "json",
    ])
    if result.returncode != 0:
        raise SafeError("Could not inspect operator-vault network settings; stopped")
    try:
        data = json.loads(result.stdout)
        public_access = str(data.get("publicNetworkAccess") or "Enabled")
        default_action = str(data.get("defaultAction") or "Deny")
        rules = data.get("ipRules") or []
        return public_access, default_action, [str(rule) for rule in rules]
    except Exception as exc:
        raise SafeError("Could not parse operator-vault network settings; stopped") from exc


def is_ip_allowed(ip: str, rules: list[str]) -> bool:
    address = ipaddress.ip_address(ip)
    for rule in rules:
        try:
            if address in ipaddress.ip_network(rule, strict=False):
                return True
        except ValueError:
            continue
    return False


def get_access_token() -> str:
    result = run_az([
        "account", "get-access-token",
        "--resource", "https://vault.azure.net",
        "--subscription", SUBSCRIPTION_ID,
        "--query", "accessToken",
        "--output", "tsv",
    ])
    token = result.stdout.strip()
    if result.returncode != 0 or not token:
        raise SafeError("Could not obtain an Azure Key Vault access token; stopped")
    return token


def key_vault_request(method: str, token: str, value: str | None = None) -> str | None:
    url = (
        f"https://{VAULT_NAME}.vault.azure.net/secrets/"
        f"{urllib.parse.quote(SECRET_NAME, safe='')}?api-version={VAULT_API_VERSION}"
    )
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    body = None
    if method == "PUT":
        headers["Content-Type"] = "application/json"
        body = json.dumps({"value": value}).encode("utf-8")
    request = urllib.request.Request(url, data=body, headers=headers, method=method)

    for attempt in range(30):
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                payload = response.read()
            if method == "GET":
                try:
                    stored_value = json.loads(payload).get("value")
                except Exception as exc:
                    raise SafeError("Key Vault returned an invalid secret response; stopped") from exc
                if not isinstance(stored_value, str) or not stored_value:
                    raise SafeError("The operator-vault admin secret is empty; stopped")
                return stored_value
            return None
        except urllib.error.HTTPError as exc:
            if exc.code == 403 and attempt < 29:
                if attempt == 0:
                    print("Key Vault access is not ready; waiting briefly for firewall or RBAC propagation.", file=sys.stderr)
                time.sleep(2)
                continue
            if exc.code == 404 and method == "GET":
                raise SafeError("The PostgreSQL admin secret is missing from the operator vault; stopped") from exc
            raise SafeError(f"Key Vault {method} failed with HTTP {exc.code}; stopped") from exc
        except urllib.error.URLError as exc:
            if attempt < 29:
                time.sleep(2)
                continue
            raise SafeError("Could not reach the operator Key Vault; stopped") from exc
    raise SafeError("Key Vault request did not complete; stopped")


def with_temporary_vault_access(operation: Callable[[str], str]) -> str:
    ip = get_public_ipv4()
    public_access, default_action, rules = get_vault_network_config()
    if public_access.lower() == "disabled":
        raise SafeError("Operator-vault public network access is disabled; cannot use a workstation IP rule")

    needs_rule = default_action.lower() == "deny" and not is_ip_allowed(ip, rules)
    if needs_rule and not ask_yes_no(
        f"Temporarily allow workstation IP {ip} to access the operator vault?"
    ):
        raise SafeError("Temporary operator-vault IP access was declined; stopped")

    added_rule = False
    result_value: str | None = None
    operation_error: BaseException | None = None
    cleanup_failed = False
    try:
        if needs_rule:
            # Set before calling Azure so cleanup is attempted even if the CLI
            # reports an error after the service accepted the rule.
            added_rule = True
            result = run_az([
                "keyvault", "network-rule", "add",
                "--name", VAULT_NAME,
                "--resource-group", VAULT_RESOURCE_GROUP,
                "--ip-address", ip,
                "--subscription", SUBSCRIPTION_ID,
            ])
            if result.returncode != 0:
                raise SafeError("Could not add the temporary operator-vault IP rule; stopped")
        result_value = operation(get_access_token())
    except BaseException as exc:
        operation_error = exc
    finally:
        if added_rule:
            result = run_az([
                "keyvault", "network-rule", "remove",
                "--name", VAULT_NAME,
                "--resource-group", VAULT_RESOURCE_GROUP,
                "--ip-address", ip,
                "--subscription", SUBSCRIPTION_ID,
            ])
            cleanup_failed = result.returncode != 0

    if cleanup_failed:
        raise SafeError(
            f"Temporary operator-vault access could not be removed for {ip}; remove this IP rule manually"
        ) from operation_error
    if operation_error is not None:
        raise operation_error
    if not isinstance(result_value, str) or not result_value:
        raise SafeError("Key Vault operation returned no admin secret; stopped")
    return result_value


def generate_admin_password() -> str:
    # Meet common Azure PostgreSQL complexity requirements without introducing
    # shell/SQL metacharacters that need special handling.
    alphabet = string.ascii_letters + string.digits + "_-"
    chars = [
        secrets.choice(string.ascii_lowercase),
        secrets.choice(string.ascii_uppercase),
        secrets.choice(string.digits),
        secrets.choice("_-"),
    ]
    chars.extend(secrets.choice(alphabet) for _ in range(44))
    secrets.SystemRandom().shuffle(chars)
    return "".join(chars)


def ensure_secret(resource_group: str, server_name: str) -> str:
    if postgres_server_exists(resource_group, server_name):
        print("PostgreSQL server exists; reusing the current operator-vault admin secret.", file=sys.stderr)
        return with_temporary_vault_access(lambda token: key_vault_request("GET", token) or "")

    if not ask_yes_no(
        "No PostgreSQL server exists. Write a new random PostgreSQL admin secret version "
        "to the operator vault before planning the server?"
    ):
        raise SafeError("PostgreSQL admin-secret staging was declined; stopped without changing Key Vault")
    password = generate_admin_password()

    def write_secret(token: str) -> str:
        key_vault_request("PUT", token, password)
        return password

    print("Writing the new PostgreSQL admin secret to the operator vault; the value will not be displayed.", file=sys.stderr)
    return with_temporary_vault_access(write_secret)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("ensure", "read"), required=True)
    parser.add_argument("--resource-group", default="chat-dev-rg")
    parser.add_argument("--server-name", default="chat-dev-cf816eae-se-pg")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Terragrunt command after --")
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("provide a command to run after --")
    return args


def main() -> int:
    args = parse_args()
    if args.mode == "ensure":
        password = ensure_secret(args.resource_group, args.server_name)
    else:
        password = with_temporary_vault_access(
            lambda token: key_vault_request("GET", token) or ""
        )

    child_env = os.environ.copy()
    child_env["TF_VAR_administrator_password"] = password
    # Drop the parent's reference before starting Terragrunt; the child receives
    # the variable only in its environment, never in argv.
    del password
    try:
        return subprocess.run(args.command, env=child_env, check=False).returncode
    except OSError:
        raise SafeError("Could not start the requested Terragrunt command; stopped")
    finally:
        child_env.pop("TF_VAR_administrator_password", None)


if __name__ == "__main__":
    signal.signal(signal.SIGINT, lambda *_: sys.exit(130))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, lambda *_: sys.exit(129))
    try:
        raise SystemExit(main())
    except SafeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        print("ERROR: Secret handling failed; no secret value was printed", file=sys.stderr)
        raise SystemExit(1)
