"""Read a secret from Key Vault using an Azure VM's system-assigned identity.

The VM must have network access to the vault and a narrowly-scoped Key Vault
Secrets User role. Secret values are returned to the caller in memory and are
never printed by this module.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from functools import lru_cache

IMDS_TOKEN_URL = "http://169.254.169.254/metadata/identity/oauth2/token"
KEY_VAULT_API_VERSION = "7.4"


class KeyVaultReadError(RuntimeError):
    """A safe-to-log Key Vault read failure (never includes response body)."""


class KeyVaultSecretNotFound(KeyVaultReadError):
    """The requested secret does not exist in the vault."""


class KeyVaultWriteError(RuntimeError):
    """A safe-to-log Key Vault write failure."""


@lru_cache(maxsize=4)
def get_access_token(resource: str) -> str:
    query = urllib.parse.urlencode(
        {"api-version": "2018-02-01", "resource": resource}
    )
    request = urllib.request.Request(
        f"{IMDS_TOKEN_URL}?{query}", headers={"Metadata": "true"}
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise KeyVaultReadError("Could not obtain a managed-identity token") from None

    token = payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise KeyVaultReadError("Managed-identity response did not contain a token")
    return token


def get_secret(vault_name: str, secret_name: str) -> str:
    """Return one enabled secret value from the named vault, without logging it."""
    if not vault_name or "." in vault_name or "/" in vault_name:
        raise ValueError("vault_name must be a Key Vault DNS label")
    if not secret_name or "/" in secret_name:
        raise ValueError("secret_name must be a Key Vault secret name")

    token = get_access_token("https://vault.azure.net")
    url = (
        f"https://{vault_name}.vault.azure.net/secrets/"
        f"{urllib.parse.quote(secret_name, safe='')}"
        f"?api-version={KEY_VAULT_API_VERSION}"
    )
    request = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise KeyVaultSecretNotFound("Key Vault secret does not exist") from None
        raise KeyVaultReadError(
            f"Key Vault secret read failed (HTTP {exc.code}); check network and RBAC"
        ) from None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        raise KeyVaultReadError("Key Vault secret read failed; check DNS and connectivity") from None

    value = payload.get("value")
    if not isinstance(value, str) or not value:
        raise KeyVaultReadError("Key Vault returned an empty or invalid secret")
    return value


def set_secret_if_absent(vault_name: str, secret_name: str, value: str) -> None:
    """Create a secret only when absent; never intentionally overwrite it.

    The existence check and write are not atomic. Callers must prevent concurrent
    writers and inspect metadata after any partial failure.
    """
    if not isinstance(value, str) or not value:
        raise ValueError("secret value must be a non-empty string")
    try:
        get_secret(vault_name, secret_name)
    except KeyVaultSecretNotFound:
        pass
    else:
        raise KeyVaultWriteError("Key Vault secret already exists; refusing to overwrite")

    token = get_access_token("https://vault.azure.net")
    url = (
        f"https://{vault_name}.vault.azure.net/secrets/"
        f"{urllib.parse.quote(secret_name, safe='')}"
        f"?api-version={KEY_VAULT_API_VERSION}"
    )
    request = urllib.request.Request(
        url,
        data=json.dumps({"value": value}).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="PUT",
    )
    try:
        with urllib.request.urlopen(request, timeout=15):
            return
    except urllib.error.HTTPError as exc:
        raise KeyVaultWriteError(f"Key Vault secret write failed (HTTP {exc.code})") from None
    except (urllib.error.URLError, TimeoutError):
        raise KeyVaultWriteError("Key Vault secret write failed; check DNS and connectivity") from None
