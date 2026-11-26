# PostgreSQL provisioning: dev record and automation requirements

This is a record of the dev setup and a specification for future automation, **not an implemented or tested prod runbook**. There is no `live/prod/` stack yet. Review region, sizing, security, backups, cost, access and data-loss implications before provisioning or changing any environment. Never reuse dev credentials for prod.

## Provisioned infrastructure

The user reviewed and applied the dev Terragrunt stacks individually. The relevant configuration is:

- `live/dev/network`: the Belgium Central app VNet (`10.1.0.0/16`). Its original PostgreSQL delegated subnet is not used by the current Swedish server.
- `live/dev/postgresql-network`: the Sweden Central VNet (`10.2.0.0/16`), PostgreSQL delegated subnet (`10.2.1.0/24`) and two-way peering with the Belgium VNet. Cross-region traffic can incur charges. The separate temporary operator subnet was added later by `operator-access`.
- `live/dev/postgresql`: server `chat-dev-cf816eae-se-pg` in Sweden Central; PostgreSQL 17, default SKU `B_Standard_B1ms` with creation fallbacks to `B_Standard_B2s` and `B_Standard_B2ms` on capacity/SKU-availability errors, 32 GiB storage, seven-day backups, no geo-redundant backups, no configured HA, delegated private networking, public network access disabled, and `require_secure_transport = on`. It also creates database `chat` and the private DNS zone/links to both VNets. The Belgium-created zone and its original link were retained when Sweden was added; the stable DNS link prefix prevents a server rename from replacing them.
- The server administrator is `chatadmin`. During the original provisioning, its password was supplied at apply time via the sensitive, ephemeral OpenTofu input `TF_VAR_administrator_password` and AzureRM's write-only `administrator_password_wo`; it was not intentionally stored in the Terraform plan or state. The guarded workflow checks the operator vault first and reuses an already-staged admin secret across retries; it generates and writes a new random version only if no server and no secret exist. The secret is supplied to local Terragrunt through the child process environment. For an existing server, the wrapper selects its actual SKU to avoid accidental resize. Increment `administrator_password_version` for an intentional rotation of an existing server and review the plan. On a new server, it tries B1ms, then B2s, then B2ms only after capacity/SKU-availability errors; plans are regenerated for each candidate. Azure CLI lists B2ms as region-supported in Sweden Central, but this does not guarantee current allocation capacity. The Retail Prices API returned about $0.0796/hour for B2ms compute. Production SKU selection remains separate.

Azure previously failed to allocate `B_Standard_B1ms` and `B_Standard_B2s` in Belgium Central. A Sweden attempt using the original name returned `InvalidResourceLocation`, despite subsequent Azure list/GET checks not finding that server. A distinct `-se-pg` name then succeeded in Sweden. The user's latest rebuild attempt received `RegionalAllocationFailed` for B1ms and B2s in Sweden Central, followed by `SkuNotAvailable` for B2ats_v2, after the private DNS zone/links were created; the resulting state has not yet been verified. Azure CLI's regional list includes B2ms but not B2ats_v2. SKU listings, name checks and a successful plan do **not** guarantee allocation. These dev choices are not automatically appropriate or available in prod.

Azure reported the dev server `Ready`. The operator VM resolved the server through the private DNS path to `10.2.1.4` and reached port 5432. The operator connected to `chat` as `chatadmin` with `PGSSLMODE=verify-full`, `PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt`, and `psql -W`; `\conninfo` showed the private address and TLS 1.3. The Ubuntu `psql` 14 client displayed a major-version warning against server 17; the commands below succeeded, but match client/server major versions for future automation where possible. Private networking, peering, DNS and TLS must be checked again for each environment.

## Out-of-band SQL performed for dev

Terraform created the database but **did not create the application login or its grants**. In the private `psql` session, the user ran:

```sql
CREATE ROLE chat_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
```

The user then ran `\password chat_app` and entered the new application password at the hidden prompts. The password is separate from the administrator password and must not be placed in SQL source, command-line arguments, shell history, logs, Git, Terraform state, or chat. The role was granted:

```sql
GRANT CONNECT, CREATE ON DATABASE chat TO chat_app;
GRANT USAGE, CREATE ON SCHEMA public TO chat_app;
```

The user connected again as `chat_app` over TLS and verified that it could log in and had `CREATE` on the database and public schema. With explicit approval, the `chat-db-migrate-5546c94` AKS Job completed on 2026-11-25 and reported migrations applied, using the immutable migrator image built from commit `5546c94fe25caebb22b6d1033c6b024bcfcf7291`. One migration removes duplicate reactions before changing a primary key. The app itself and Redis integration have not yet been smoke-tested. These grants are **not managed by Terraform** and will be lost when the server is destroyed unless recreated.

The user deliberately chose one non-admin login for the app and migrations because the current chart uses one `DATABASE_URL`. Drizzle creates its migration schema and tables, so the login needs schema-creation privileges. This means a compromised app can perform DDL within its granted scope; it is not a read/write-only account. Other default `PUBLIC` grants may also exist: the two explicit grants above are not proof that access is otherwise limited. Review a separate migration login and tighter runtime privileges for prod rather than silently assuming the dev trade-off is acceptable.

## Secret provisioning and current status

The user provisioned the application connection string as `database-url` in the dev private Key Vault using the operator VM, with URL components percent-encoded and `sslmode=verify-full`. A metadata-only check confirmed the secret name exists; its value was not read by the assistant. Verify the application's actual TLS/certificate behavior and secret retrieval separately; the `psql` verification above does not prove the app driver verifies the server certificate.

The dev app identity has vault-wide `Key Vault Secrets User` access. **Do not store the PostgreSQL administrator password in that app-readable vault.** The current workflow keeps it in the operator-only `chat-ops-cf816eae-kv` vault; the workstation helper writes a new secret version for a newly provisioned server, while the VM reads the same secret with managed identity for app-role setup. The temporary operator VM initially has no Key Vault secret-write role. The user selected the built-in `Key Vault Secrets Officer` role for temporary vault-scoped access; `live/dev/operator-secret-access` configures this separately so it can be reviewed and removed after use. This role can read, create, overwrite, delete and purge secrets in the vault; it was applied, verified and subsequently removed after use. The Swedish Key Vault DNS VNet link was applied, and the operator VM resolved the vault to `10.1.2.6` and reached port 443. The VM used its identity to provision secrets; see `docs/runtime-secret-provisioning.md`. See `deploy/dev-operations.md` for the private operator path and `docs/operator-vm-incident.md` for the VM's manually repaired login.

## Requirements for a future Ansible or equivalent implementation

1. Apply and verify the infrastructure and private operator path first. Resolve the environment-specific FQDN to its expected private address, connect with certificate and hostname verification, and fail closed if networking or TLS checks fail. Handle operator temporary roles and resources with an explicitly reviewed teardown.
2. Use separate dev/prod inputs and credentials. Keep the administrator credential in an operator-restricted secret manager, not the app vault. The dev wrapper may generate a new administrator password only when creating a fresh server; it must persist that value to the operator vault before the Azure create request and reuse it on retries/existing servers. Generate the separate app password only when creating the account or during an explicitly requested rotation, and store it in the environment's approved app vault. Don't rotate either password on every run.
3. Make account creation **idempotent**: query `pg_roles` by the configured role name; create the login only if absent. PostgreSQL's `CREATE ROLE` above has no `IF NOT EXISTS`. If the role already exists, verify its attributes and grants; do not silently take ownership of an unrelated role, overwrite its password, or remove other grants. Fail and ask for review on unexpected state.
4. Apply only the approved grants and verify them. If retaining the shared migration/runtime login, account for the database `CREATE` and public-schema `USAGE`/`CREATE` grants and explicitly accept the DDL exposure. If using separate identities, define and test the migration and runtime permissions independently; update the chart and secret mapping accordingly.
5. Keep secrets out of playbooks, inventory, Git, Terraform state, process arguments, shell history, CI output, and command logs. For Ansible, `no_log: true` is necessary for secret-bearing tasks but **not sufficient**: review transport, remote temporary files, process inspection, fact caching, error handling and cleanup. Use a secret-safe password-setting mechanism; do not build SQL by interpolating passwords into shell commands. Properly quote SQL identifiers and URL-encode connection-string components.
6. Verify a fresh app-login TLS connection, the effective role attributes and privileges, and Key Vault retrieval from the intended identity. Run migrations only after those checks and explicit approval. Test the application end to end, then revoke temporary operator permissions and review teardown. Record results without logging secrets.

Useful non-secret verification in a privileged `psql` session:

```sql
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole,
       rolreplication, rolbypassrls
FROM pg_roles WHERE rolname = 'chat_app';

SELECT has_database_privilege('chat_app', 'chat', 'CONNECT') AS can_connect,
       has_database_privilege('chat_app', 'chat', 'CREATE') AS can_create_schema,
       has_schema_privilege('chat_app', 'public', 'USAGE') AS can_use_public,
       has_schema_privilege('chat_app', 'public', 'CREATE') AS can_create_tables;
```

These checks do not reveal passwords and do not prove that no other inherited or `PUBLIC` privileges exist.
