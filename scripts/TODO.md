# Script TODO

- [x] Make `infra-up.sh -y` fully non-interactive: use the default operator public key, accept default-yes PostgreSQL secret/IP confirmations, disable OpenTofu input, and fail clearly if required inputs are unavailable.
- [ ] Decide whether `infra-down.sh -y` should also auto-accept DNS removal and app-vault purge; currently those remain `[Y/n]` confirmations (Enter accepts yes).
- [ ] Discuss and design best-effort behavior for `infra-down.sh`: attempt to destroy as many stacks/resources as possible even when individual destroys fail, then report all failures and any resources that remain.
