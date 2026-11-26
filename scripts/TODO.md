# Script TODO

- [ ] Make `-y` a true non-interactive mode for `infra-up.sh` and `infra-down.sh`: do not prompt; automatically accept all confirmations and approvals. If required non-secret inputs (such as the operator SSH public-key file) are unavailable, fail with a clear error rather than prompting.
- [ ] Discuss and design best-effort behavior for `infra-down.sh`: attempt to destroy as many stacks/resources as possible even when individual destroys fail, then report all failures and any resources that remain.
