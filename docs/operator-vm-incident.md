# Operator VM Bastion login incident

## Symptoms

The temporary `chat-dev-operator` VM was running and its Azure Bastion Developer resource was provisioned, but the browser SSH session repeatedly reported a connection error. No application credentials had been provisioned on the VM.

## Cause

Azure's VM resource reported success, but guest cloud-init provisioning had failed. Ubuntu already contained a system group named `operator`; cloud-init attempted to create the configured `operator` admin user with a same-named group and failed. Consequently the user and its authorized SSH key were never created.

A user-approved, non-secret Azure VM Run Command diagnostic showed that the SSH service was active and listening, and that connection attempts reached the VM but were rejected with `Invalid user operator`. This established that the immediate problem was the missing user, rather than proving a browser or firewall fault.

## Repair

With explicit user approval, Azure VM Run Command created the intended `operator` user using the existing `operator` group, installed the dedicated temporary **public** SSH key with restrictive file permissions, and configured passwordless sudo. The installed key's fingerprint matched the approved public key; the account password was locked. The private SSH key was not read by the assistant. The user then confirmed that browser SSH succeeded and `hostname` returned `chat-dev-operator`.

This was a **manual guest repair**, not a Terraform-managed fix. Cloud-init had reported an error, and recreating the VM with the same configured username can reproduce the problem. Before recreating it, select a nonconflicting admin username in the Terraform input and review the replacement plan. This temporary VM and its disk can incur charges and should be removed through an explicitly reviewed teardown after operator work is complete. No PostgreSQL administrator credential should be placed in the app-readable Key Vault, command text, logs, shell history, Terraform state, or chat.
