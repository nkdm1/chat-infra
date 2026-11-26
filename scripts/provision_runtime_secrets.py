"""Provision the dev app's Redis URL and Better Auth secret in its Key Vault.

Adapted from the recoverable Terragrunt-cache copy of the 2026-11-25
operator-VM script. Requires an Azure VM system-assigned identity with:
- `Microsoft.Cache/redisEnterprise/databases/listKeys/action` on the target DB
- Key Vault secret write permission on the app vault

This script does not create `database-url`, set PostgreSQL credentials, or
handle Cloudflare TLS. It fails closed if either target secret already exists.
Configuration is through non-secret environment variables; secret values are
kept in memory and are never printed.
"""

from __future__ import annotations

import json
import os
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request

from keyvault_mi import get_access_token

ARM_BASE = "https://management.azure.com"
ARM_API_VERSION = "2025-07-01"
VAULT_API_VERSION = "7.4"
TARGET_SECRETS = ("redis-url", "better-auth-secret")


class ProvisionError(RuntimeError):
    """Safe-to-log provisioning error; does not include secret values."""


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ProvisionError(f"Missing required environment variable: {name}")
    return value


def request_json(request: urllib.request.Request) -> tuple[dict, int]:
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response), response.status
    except urllib.error.HTTPError as exc:
        raise ProvisionError(f"Azure request failed (HTTP {exc.code})") from None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        raise ProvisionError("Azure request failed; check private DNS, network, and identity") from None


def vault_headers(vault_token: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {vault_token}",
        "Content-Type": "application/json",
    }


def list_secret_names(vault_url: str, headers: dict[str, str]) -> set[str]:
    next_url = f"{vault_url}/secrets?api-version={VAULT_API_VERSION}"
    names: set[str] = set()
    while next_url:
        page, _ = request_json(urllib.request.Request(next_url, headers=headers))
        for item in page.get("value", []):
            secret_id = item.get("id", "")
            names.add(secret_id.rstrip("/").rsplit("/", 1)[-1].lower())
        next_url = page.get("nextLink", "")
    return names


def put_secret(vault_url: str, name: str, value: str, headers: dict[str, str]) -> int:
    url = f"{vault_url}/secrets/{urllib.parse.quote(name, safe='')}?api-version={VAULT_API_VERSION}"
    request = urllib.request.Request(
        url,
        data=json.dumps({"value": value}).encode("utf-8"),
        headers=headers,
        method="PUT",
    )
    _, status = request_json(request)
    return status


def main() -> int:
    vault_name = required_env("APP_KEY_VAULT_NAME")
    subscription_id = required_env("ARM_SUBSCRIPTION_ID")
    resource_group = required_env("REDIS_RESOURCE_GROUP")
    redis_name = required_env("REDIS_ENTERPRISE_NAME")
    redis_host = required_env("REDIS_HOSTNAME")
    redis_database = os.environ.get("REDIS_DATABASE_NAME", "default").strip() or "default"

    for name, value in (
        ("APP_KEY_VAULT_NAME", vault_name),
        ("REDIS_RESOURCE_GROUP", resource_group),
        ("REDIS_ENTERPRISE_NAME", redis_name),
        ("REDIS_DATABASE_NAME", redis_database),
    ):
        if "/" in value or "?" in value:
            raise ProvisionError(f"Invalid resource name in {name}")
    if "/" in subscription_id or "?" in subscription_id:
        raise ProvisionError("Invalid subscription identifier")
    if not redis_host or "/" in redis_host or "@" in redis_host:
        raise ProvisionError("Invalid Redis hostname")

    vault_url = f"https://{vault_name}.vault.azure.net"
    vault_token = get_access_token("https://vault.azure.net")
    headers = vault_headers(vault_token)
    existing = list_secret_names(vault_url, headers)
    conflicts = existing.intersection(TARGET_SECRETS)
    if conflicts:
        raise ProvisionError(
            "Target secret(s) already exist; no values were changed. Inspect metadata and handle rotation explicitly."
        )

    arm_token = get_access_token(ARM_BASE + "/")
    database_path = "/".join(
        urllib.parse.quote(part, safe="")
        for part in (
            "subscriptions",
            subscription_id,
            "resourceGroups",
            resource_group,
            "providers",
            "Microsoft.Cache",
            "redisEnterprise",
            redis_name,
            "databases",
            redis_database,
        )
    )
    key_url = f"{ARM_BASE}/{database_path}/listKeys?api-version={ARM_API_VERSION}"
    key_request = urllib.request.Request(
        key_url,
        data=b"{}",
        headers={
            "Authorization": f"Bearer {arm_token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    key_response, _ = request_json(key_request)
    redis_key = key_response.get("primaryKey")
    if not isinstance(redis_key, str) or not redis_key:
        raise ProvisionError("Redis key response did not contain a primary key")

    redis_url = (
        "rediss://default:"
        + urllib.parse.quote(redis_key, safe="")
        + "@"
        + redis_host
        + ":10000"
    )
    auth_secret = secrets.token_urlsafe(32)

    # Check-then-write is intentionally non-atomic. If a write fails partway,
    # stop and review secret metadata before retrying; this script never overwrites.
    for name, value in (("redis-url", redis_url), ("better-auth-secret", auth_secret)):
        status = put_secret(vault_url, name, value, headers)
        print(f"{name}: stored (HTTP {status})")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProvisionError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
