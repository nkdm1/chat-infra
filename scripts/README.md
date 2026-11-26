# Provisioning scripts (recovered and reusable components)

These scripts are starting points for the planned Ansible roles; they do not replace Terraform/Terragrunt, and they have not been run against the currently torn-down dev environment.

## Recovered source

`archive/recovered_temp_py_2026-11-25.py` is the identical `temp.py` found in 19 ignored Terragrunt cache directories. Its SHA-256 was the same in each copy. It performs the historical Redis key lookup and writes `redis-url` plus a generated `better-auth-secret` to the **old app vault**. The file contains old resource identifiers and the old app-vault name, and is preserved for provenance only. **Do not run it.** The old dev Redis and app vault were destroyed.

`provision_runtime_secrets.py` is a parameterized adaptation of that recovered script. It uses VM managed identity, reads a Redis key from Azure Resource Manager in memory, and writes only `redis-url` and `better-auth-secret` to the configured app vault. It does not print values, does not overwrite existing target secrets, and stops if either already exists. It does not create `database-url`, provision PostgreSQL roles, or create the Kubernetes TLS secret.

The other historical snippets were not recoverable as source files:

- `database-url` was created using an interactive Python snippet on the operator VM; only its behavior is recorded in `docs/runtime-secret-provisioning.md` and SQL setup in `docs/postgresql-provisioning.md`.
- Cloudflare TLS was loaded into Kubernetes `chat-tls` through a hidden-input operator procedure; no `install-chat-tls.py` source exists in the repo or the recovered cache.

Those procedures must be reimplemented and reviewed; this directory does not claim that recreated code is the exact original.

## Operator-only Key Vault

`keyvault_mi.py` contains `get_secret(vault_name, secret_name)`. It obtains a token from Azure VM IMDS using the VM's system-assigned identity and returns the value to its caller in process memory. It never prints the token or secret. Use it to retrieve these existing operator-vault secrets when a task needs them:

- `postgresql-admin-password`
- `cloudflare-origin-key`
- `cloudflare-origin-cert`

For example, a future Python task can call `get_secret("chat-ops-cf816eae-kv", "postgresql-admin-password")` and pass the returned value directly to a secret-aware library call. Never `print()` the result, place it in a command argument, or write it to a repository file. Ansible tasks using returned values must use `no_log: true`; also review temporary files, fact caching, process inspection and failure output.

### Required Azure setup before this works on a rebuilt VM

The helper uses the **VM's system-assigned managed identity**, not your workstation's Azure CLI login. The current operator vault is RBAC-enabled and its firewall allows your workstation's then-current public IP only. A new VM cannot read it as configured. Before running the helper:

1. Provide private network connectivity from the operator VM to `chat-ops-cf816eae-kv` (private endpoint, private DNS resolution for `privatelink.vaultcore.azure.net`, and VNet link). The dev VNets were destroyed, so this must be planned/applied with the rebuilt network.
2. Grant the VM identity `Key Vault Secrets User` at the operator vault scope, or preferably a custom role restricted to `get` on the required secret names. Do not grant the app identity access to this operator vault.
3. Keep the vault's public firewall closed except for the operator's workstation IP if that access remains necessary. Do not widen it to `0.0.0.0/0` to make the VM work.
4. Test only metadata/authorization first. Do not display values to verify access. Remove temporary permissions and endpoint/network resources only according to the approved lifecycle plan.

No Terraform was changed to add the operator vault private endpoint or role assignment; these are prerequisites for a future infrastructure plan, not resources currently deployed.

## Runtime secrets script inputs

`provision_runtime_secrets.py` requires these **non-secret** environment variables on the operator VM:

- `APP_KEY_VAULT_NAME`: newly created app/runtime vault (not the operator vault)
- `ARM_SUBSCRIPTION_ID`
- `REDIS_RESOURCE_GROUP`
- `REDIS_ENTERPRISE_NAME`
- `REDIS_HOSTNAME` (DNS hostname only, no scheme or port)
- optional `REDIS_DATABASE_NAME` (defaults to `default`)

The VM identity needs `Microsoft.Cache/redisEnterprise/databases/listKeys/action` on the Redis database and a write role scoped to the app vault. It needs network access to both Azure Resource Manager and the app vault. The operator vault secrets are not copied into the app vault. In particular, the PostgreSQL administrator password and Cloudflare key/certificate remain operator-only.

The two-secret check and writes are not atomic. If the first write succeeds and the second fails, stop and inspect secret metadata; do not rerun blindly. Rotation requires an explicit procedure. For future automation, implement the same guarantees in idempotent Ansible tasks rather than wrapping this script with an unsafe shell pipeline.

## Validation

Only syntax/import checks have been run; Azure calls were not run. This environment has no live operator VM, dev Redis, app vault or dev VNet. Before reuse, review role scopes, API versions, DNS, TLS, and current Azure resource names; test failures and partial-write behavior in a disposable environment. Never run against production without a separate reviewed configuration and credentials.
