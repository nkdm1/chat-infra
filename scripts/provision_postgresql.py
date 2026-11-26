"""Create/verify the dev chat_app login and its database-url secret.

Runs only on the operator VM using its system-assigned managed identity.
Secret values are kept in process memory, never printed, and never passed as
command-line arguments. The Key Vault read/write helper uses the VM IMDS token.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
import secrets
import sys
from urllib.parse import quote, unquote, urlsplit

import psycopg2
from psycopg2 import sql

from keyvault_mi import (
    KeyVaultSecretNotFound,
    get_secret,
    set_secret_if_absent,
)

APP_ROLE = "chat_app"
DATABASE_NAME = "chat"
ADMIN_ROLE = "chatadmin"


class ProvisionError(RuntimeError):
    """Safe-to-log error with no credential material."""


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ProvisionError(f"Missing required environment variable: {name}")
    return value


def make_database_url(host: str, password: str) -> str:
    return (
        f"postgres://{APP_ROLE}:{quote(password, safe='')}@{host}:5432/"
        f"{DATABASE_NAME}?sslmode=verify-full"
    )


def scram_verifier(password: str) -> str:
    """Build PostgreSQL's SCRAM-SHA-256 verifier so cleartext is not in SQL."""
    iterations = 4096
    salt = os.urandom(16)
    salted_password = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    client_key = hmac.new(salted_password, b"Client Key", hashlib.sha256).digest()
    stored_key = hashlib.sha256(client_key).digest()
    server_key = hmac.new(salted_password, b"Server Key", hashlib.sha256).digest()

    b64 = lambda value: base64.b64encode(value).decode("ascii")
    return (
        f"SCRAM-SHA-256${iterations}:{b64(salt)}$"
        f"{b64(stored_key)}:{b64(server_key)}"
    )


def parse_app_password(database_url: str, expected_host: str) -> str:
    parsed = urlsplit(database_url)
    if (
        parsed.scheme not in ("postgres", "postgresql")
        or parsed.hostname != expected_host
        or parsed.port != 5432
        or unquote(parsed.username or "") != APP_ROLE
        or unquote(parsed.path.lstrip("/")) != DATABASE_NAME
        or parsed.query != "sslmode=verify-full"
    ):
        raise ProvisionError("Existing database-url does not match the expected dev connection")
    password = unquote(parsed.password or "")
    if not password:
        raise ProvisionError("Existing database-url has no password")
    return password


def connect(host: str, database: str, username: str, password: str):
    try:
        return psycopg2.connect(
            host=host,
            port=5432,
            dbname=database,
            user=username,
            password=password,
            sslmode="verify-full",
            sslrootcert="/etc/ssl/certs/ca-certificates.crt",
            connect_timeout=15,
        )
    except psycopg2.Error:
        raise ProvisionError("PostgreSQL connection failed; verify private DNS, TLS, and credentials") from None


def main() -> int:
    operator_vault = required_env("OPERATOR_KEY_VAULT_NAME")
    app_vault = required_env("APP_KEY_VAULT_NAME")
    postgres_host = required_env("POSTGRES_HOST")

    if any(char in postgres_host for char in "/:@?#"):
        raise ProvisionError("POSTGRES_HOST must be a DNS hostname only")

    admin_password = get_secret(operator_vault, "postgresql-admin-password")
    try:
        database_url = get_secret(app_vault, "database-url")
        app_password = parse_app_password(database_url, postgres_host)
        database_secret_was_present = True
    except KeyVaultSecretNotFound:
        app_password = secrets.token_urlsafe(32)
        database_url = make_database_url(postgres_host, app_password)
        database_secret_was_present = False

    # Refuse to adopt an unexpected existing role without its app secret.
    with connect(postgres_host, "postgres", ADMIN_ROLE, admin_password) as conn:
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, "
                "rolreplication, rolbypassrls FROM pg_roles WHERE rolname = %s",
                (APP_ROLE,),
            )
            role = cursor.fetchone()

    if role and not database_secret_was_present:
        raise ProvisionError("chat_app exists but database-url is absent; manual recovery is required")

    if role and database_secret_was_present:
        # Prove the stored app credential matches instead of silently rotating it.
        with connect(postgres_host, DATABASE_NAME, APP_ROLE, app_password):
            pass
        if role != (True, False, False, False, False, False):
            raise ProvisionError("Existing chat_app role has unexpected attributes; manual review required")

    if not database_secret_was_present:
        # Store first so an interrupted run can resume with the same password.
        set_secret_if_absent(app_vault, "database-url", database_url)

    with connect(postgres_host, "postgres", ADMIN_ROLE, admin_password) as conn:
        with conn.cursor() as cursor:
            if not role:
                cursor.execute(
                    sql.SQL(
                        "CREATE ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE "
                        "NOREPLICATION PASSWORD {}"
                    ).format(sql.Identifier(APP_ROLE), sql.Literal(scram_verifier(app_password)))
                )
            cursor.execute(
                sql.SQL("GRANT CONNECT, CREATE ON DATABASE {} TO {}")
                .format(sql.Identifier(DATABASE_NAME), sql.Identifier(APP_ROLE))
            )
            cursor.execute(
                sql.SQL("GRANT USAGE, CREATE ON SCHEMA public TO {}")
                .format(sql.Identifier(APP_ROLE))
            )

    with connect(postgres_host, DATABASE_NAME, APP_ROLE, app_password):
        pass

    print("database-url: verified" if database_secret_was_present else "database-url: created")
    print("chat_app role: verified" if role else "chat_app role: created")
    print("approved grants: ready")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProvisionError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        print("Provisioning failed; check role, network, and secret metadata", file=sys.stderr)
        raise SystemExit(1)
