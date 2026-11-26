import contextlib
import importlib.util
import io
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "terragrunt_with_postgres_admin_secret.py"
SPEC = importlib.util.spec_from_file_location("postgres_admin_secret", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class AdminSecretTests(unittest.TestCase):
    def test_yes_no_prompt_accepts_blank_default(self):
        with (
            mock.patch("builtins.input", return_value=""),
            contextlib.redirect_stderr(io.StringIO()) as stderr,
        ):
            self.assertTrue(MODULE.ask_yes_no("Proceed?"))
        self.assertIn("[Y/n]", stderr.getvalue())

    def test_yes_no_prompt_accepts_no(self):
        with (
            mock.patch("builtins.input", return_value="n"),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            self.assertFalse(MODULE.ask_yes_no("Proceed?"))

    def test_yes_no_prompt_retries_invalid_input(self):
        with (
            mock.patch("builtins.input", side_effect=["maybe", "Y"]),
            contextlib.redirect_stderr(io.StringIO()) as stderr,
        ):
            self.assertTrue(MODULE.ask_yes_no("Proceed?"))
        self.assertIn("Please answer Y or n.", stderr.getvalue())

    def test_generated_password_has_required_character_classes(self):
        value = MODULE.generate_admin_password()
        self.assertEqual(len(value), 48)
        self.assertRegex(value, r"^[A-Za-z0-9_-]{48}$")
        self.assertTrue(any(ch.islower() for ch in value))
        self.assertTrue(any(ch.isupper() for ch in value))
        self.assertTrue(any(ch.isdigit() for ch in value))
        self.assertTrue(any(ch in "_-" for ch in value))

    def test_cidr_rule_match(self):
        self.assertTrue(MODULE.is_ip_allowed("10.1.2.3", ["10.1.0.0/16"]))
        self.assertFalse(MODULE.is_ip_allowed("10.2.2.3", ["10.1.0.0/16"]))

    def test_new_server_stages_random_secret_without_printing_it(self):
        with (
            mock.patch.object(MODULE, "postgres_server_exists", return_value=False),
            mock.patch.object(MODULE, "ask_yes_no", return_value=True),
            mock.patch.object(MODULE, "with_temporary_vault_access", side_effect=lambda operation: operation("token")),
            mock.patch.object(MODULE, "key_vault_request", side_effect=[MODULE.SecretNotFound("missing"), None]) as request,
            contextlib.redirect_stderr(io.StringIO()) as stderr,
        ):
            value = MODULE.ensure_secret("chat-dev-rg", "chat-dev-cf816eae-dk-pg")

        self.assertEqual(request.call_args_list[0].args, ("GET", "token"))
        self.assertEqual(request.call_args_list[1].args, ("PUT", "token", value))
        self.assertNotIn(value, stderr.getvalue())

    def test_new_server_decline_does_not_write_secret(self):
        with (
            mock.patch.object(MODULE, "postgres_server_exists", return_value=False),
            mock.patch.object(MODULE, "ask_yes_no", return_value=False),
            mock.patch.object(MODULE, "with_temporary_vault_access", side_effect=lambda operation: operation("token")),
            mock.patch.object(MODULE, "key_vault_request", side_effect=MODULE.SecretNotFound("missing")) as request,
        ):
            with self.assertRaises(MODULE.SafeError):
                MODULE.ensure_secret("chat-dev-rg", "chat-dev-cf816eae-dk-pg")
        request.assert_called_once_with("GET", "token")

    def test_missing_server_reuses_staged_secret_on_retry(self):
        with (
            mock.patch.object(MODULE, "postgres_server_exists", return_value=False),
            mock.patch.object(MODULE, "ask_yes_no") as ask,
            mock.patch.object(MODULE, "with_temporary_vault_access", side_effect=lambda operation: operation("token")),
            mock.patch.object(MODULE, "key_vault_request", return_value="already-staged") as request,
            contextlib.redirect_stderr(io.StringIO()),
        ):
            value = MODULE.ensure_secret("chat-dev-rg", "chat-dev-cf816eae-dk-pg")

        self.assertEqual(value, "already-staged")
        request.assert_called_once_with("GET", "token")
        ask.assert_not_called()

    def test_existing_server_reuses_secret_without_writing(self):
        with (
            mock.patch.object(MODULE, "postgres_server_exists", return_value=True),
            mock.patch.object(MODULE, "with_temporary_vault_access", side_effect=lambda operation: operation("token")),
            mock.patch.object(MODULE, "key_vault_request", return_value="existing-value") as request,
            contextlib.redirect_stderr(io.StringIO()),
        ):
            value = MODULE.ensure_secret("chat-dev-rg", "chat-dev-cf816eae-dk-pg")

        self.assertEqual(value, "existing-value")
        request.assert_called_once_with("GET", "token")

    def test_temporary_ip_rule_approval_is_cached_for_wrapper_session(self):
        completed = subprocess.CompletedProcess([], 0, "", "")
        with tempfile.TemporaryDirectory() as temp_dir:
            approval_file = pathlib.Path(temp_dir) / "ip-approved"
            with (
                mock.patch.dict("os.environ", {"OPERATOR_VAULT_IP_APPROVAL_FILE": str(approval_file)}),
                mock.patch.object(MODULE, "get_public_ipv4", return_value="203.0.113.7"),
                mock.patch.object(MODULE, "get_vault_network_config", return_value=("Enabled", "Deny", [])),
                mock.patch.object(MODULE, "ask_yes_no", return_value=True) as ask,
                mock.patch.object(MODULE, "get_access_token", return_value="token"),
                mock.patch.object(MODULE, "run_az", return_value=completed) as run_az,
            ):
                self.assertEqual(MODULE.with_temporary_vault_access(lambda _token: "ok"), "ok")
                self.assertEqual(MODULE.with_temporary_vault_access(lambda _token: "ok"), "ok")

            ask.assert_called_once()
            self.assertEqual(run_az.call_count, 4)  # Add/remove still brackets each actual access.
            self.assertEqual(approval_file.read_text().strip(), "203.0.113.7")
            self.assertEqual(approval_file.stat().st_mode & 0o777, 0o600)

    def test_temporary_ip_rule_decline_does_not_change_firewall(self):
        with (
            mock.patch.object(MODULE, "get_public_ipv4", return_value="203.0.113.7"),
            mock.patch.object(MODULE, "get_vault_network_config", return_value=("Enabled", "Deny", [])),
            mock.patch.object(MODULE, "ask_yes_no", return_value=False),
            mock.patch.object(MODULE, "run_az") as run_az,
        ):
            with self.assertRaises(MODULE.SafeError):
                MODULE.with_temporary_vault_access(lambda _token: "unused")
        run_az.assert_not_called()

    def test_temporary_ip_rule_is_removed_after_success(self):
        completed = subprocess.CompletedProcess([], 0, "", "")
        with (
            mock.patch.object(MODULE, "get_public_ipv4", return_value="203.0.113.7"),
            mock.patch.object(MODULE, "get_vault_network_config", return_value=("Enabled", "Deny", [])),
            mock.patch.object(MODULE, "ask_yes_no", return_value=True),
            mock.patch.object(MODULE, "get_access_token", return_value="token"),
            mock.patch.object(MODULE, "run_az", return_value=completed) as run_az,
        ):
            result = MODULE.with_temporary_vault_access(lambda token: "safe-result")

        self.assertEqual(result, "safe-result")
        self.assertEqual(run_az.call_count, 2)
        self.assertIn("add", run_az.call_args_list[0].args[0])
        self.assertIn("remove", run_az.call_args_list[1].args[0])

    def test_temporary_ip_rule_cleanup_is_attempted_if_add_reports_failure(self):
        failed = subprocess.CompletedProcess([], 1, "", "failed")
        completed = subprocess.CompletedProcess([], 0, "", "")
        with (
            mock.patch.object(MODULE, "get_public_ipv4", return_value="203.0.113.7"),
            mock.patch.object(MODULE, "get_vault_network_config", return_value=("Enabled", "Deny", [])),
            mock.patch.object(MODULE, "ask_yes_no", return_value=True),
            mock.patch.object(MODULE, "run_az", side_effect=[failed, completed]) as run_az,
        ):
            with self.assertRaises(MODULE.SafeError):
                MODULE.with_temporary_vault_access(lambda _token: "unused")

        self.assertEqual(run_az.call_count, 2)
        self.assertIn("add", run_az.call_args_list[0].args[0])
        self.assertIn("remove", run_az.call_args_list[1].args[0])

    def test_temporary_ip_rule_is_removed_after_secret_request_failure(self):
        completed = subprocess.CompletedProcess([], 0, "", "")
        with (
            mock.patch.object(MODULE, "get_public_ipv4", return_value="203.0.113.7"),
            mock.patch.object(MODULE, "get_vault_network_config", return_value=("Enabled", "Deny", [])),
            mock.patch.object(MODULE, "ask_yes_no", return_value=True),
            mock.patch.object(MODULE, "get_access_token", return_value="token"),
            mock.patch.object(MODULE, "run_az", return_value=completed) as run_az,
        ):
            with self.assertRaises(MODULE.SafeError):
                MODULE.with_temporary_vault_access(lambda _token: (_ for _ in ()).throw(MODULE.SafeError("safe test error")))

        self.assertEqual(run_az.call_count, 2)
        self.assertIn("remove", run_az.call_args_list[1].args[0])


if __name__ == "__main__":
    unittest.main()
