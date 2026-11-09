"""Offline GA4 packaging contracts; positive credentials come only from the owner."""

import importlib.util
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = Path(__file__).with_name("configure-ga4.py")
SPEC = importlib.util.spec_from_file_location("ga4_config", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class GA4ConfigTests(unittest.TestCase):
    """Check local rejection and absence without constructing valid credentials."""

    def setUp(self):
        """Copy actual app metadata into a disposable bundle, never the built app."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.app = self.root / "Kinetiq.app"
        self.info = self.app / "Contents/Info.plist"
        self.info.parent.mkdir(parents=True)
        self.original_info = (ROOT / "Resources/Info.plist").read_bytes()
        self.info.write_bytes(self.original_info)
        self.env = self.root / ".env"
        self.destination = self.app / "Contents/Resources" / MODULE.RESOURCE

    def reject_env(self, raw):
        """Assert rejection categorically and ensure no rejected resource is copied."""
        self.env.write_bytes(raw)
        with self.assertRaises(MODULE.InvalidConfiguration) as caught:
            MODULE.configure(self.app, self.env)
        self.assertTrue(str(caught.exception) == "", "REJECTION_DIAGNOSTIC_NOT_EMPTY")
        self.assertTrue(self.info.read_bytes() == self.original_info, "APP_INFO_CHANGED")
        self.assertFalse(self.destination.exists(), "REJECTED_RESOURCE_COPIED")

    def reject_resource(self, raw):
        """Read a temporary invalid resource, with no credential-bearing diagnostics."""
        resource = self.root / MODULE.RESOURCE
        resource.write_bytes(raw)
        with self.assertRaises(MODULE.InvalidConfiguration) as caught:
            MODULE.load_resource(resource)
        self.assertTrue(str(caught.exception) == "", "REJECTION_DIAGNOSTIC_NOT_EMPTY")

    def test_absent_configuration(self):
        """Missing dotenv leaves app metadata intact and analytics unconfigured."""
        self.assertIsNone(MODULE.load_env(self.env))
        self.assertFalse(MODULE.configure(self.app, self.env))
        self.assertFalse(self.destination.exists())
        self.assertTrue(self.info.read_bytes() == self.original_info, "APP_INFO_CHANGED")

    def test_numeric_web_client_identity_is_stable(self):
        """Regress the real Google VALUE_INVALID response to a raw hyphenated UUID."""
        identity = uuid.uuid4()
        encoded = MODULE.web_client_id(identity)
        self.assertTrue(re.fullmatch(r"[0-9]{1,10}\.[0-9]{1,10}", encoded) is not None,
                        "WEB_CLIENT_ID_FORMAT_INVALID")
        self.assertTrue(encoded == MODULE.web_client_id(identity), "WEB_CLIENT_ID_UNSTABLE")
        self.assertTrue(encoded != str(identity), "RAW_UUID_TRANSMITTED")

    def test_validation_only_payload_uses_actual_session_and_bounded_preparation_time(self):
        """Inspect the real local builder; never call a validation/collection endpoint."""
        before = int(time.time())
        started = time.perf_counter_ns()
        payload = MODULE.validation_payload()
        elapsed = (time.perf_counter_ns() - started) // 1_000_000
        after = int(time.time())
        self.assertEqual(set(payload), {"client_id", "consent", "validation_behavior", "events"})
        self.assertEqual(payload["validation_behavior"], "ENFORCE_RECOMMENDATIONS")
        self.assertEqual(payload["consent"], {"ad_user_data": "DENIED", "ad_personalization": "DENIED"})
        self.assertEqual(len(payload["events"]), 1)
        event = payload["events"][0]
        self.assertEqual(event["name"], "feature_used")
        parameters = event["params"]
        self.assertEqual(parameters["feature"], "privacy_settings")
        self.assertGreaterEqual(parameters["session_id"], before)
        self.assertLessEqual(parameters["session_id"], after)
        self.assertTrue(set(parameters) <= {"feature", "session_id", "engagement_time_msec"})
        if "engagement_time_msec" in parameters:
            self.assertGreater(parameters["engagement_time_msec"], 0)
            self.assertLessEqual(parameters["engagement_time_msec"], elapsed)

    def test_empty_and_unrelated_lines_are_absent(self):
        """Unrelated assignments and malformed unrelated lines are ignored as data."""
        for raw in (b"", b"# local configuration\n", b"OTHER=invalid\nUNRELATED no equals\n"):
            self.env.write_bytes(raw)
            self.assertIsNone(MODULE.load_env(self.env))
            self.assertFalse(MODULE.configure(self.app, self.env))

    def test_duplicate_keys(self):
        """Both recognized keys reject duplicates before any credentials can be used."""
        for key in MODULE.KEYS:
            self.reject_env((key + "=PLACEHOLDER\n" + key + "=PLACEHOLDER\n").encode())

    def test_partial_configuration(self):
        """A single recognized assignment is never a usable configuration."""
        for key in MODULE.KEYS:
            self.reject_env((key + "=PLACEHOLDER\n").encode())

    def test_recognized_key_without_equals(self):
        """Malformed recognized lines reject rather than silently disappearing."""
        for key in MODULE.KEYS:
            self.reject_env(key.encode())

    def test_placeholders(self):
        """Placeholder pairs are deliberately invalid, not replacement credentials."""
        for value in ("PLACEHOLDER", "REPLACE_ME", "replace_this"):
            self.reject_env(("KINETIQ_GA4_MEASUREMENT_ID=G-REPLACE\n"
                             "KINETIQ_GA4_API_SECRET=" + value + "\n").encode())

    def test_non_ascii_and_non_url_safe_identifiers(self):
        """Invalid Web identifiers cannot be used to form a request URL."""
        for value in ("G-é", "G-invalid", "G-A/B", "G-A?B", "G-A B", "G-", "native:invalid"):
            self.reject_env(("KINETIQ_GA4_MEASUREMENT_ID=" + value + "\n"
                             "KINETIQ_GA4_API_SECRET=PLACEHOLDER\n").encode())

    def test_oversized_65537_byte_inputs(self):
        """The bound applies even to otherwise ignored comments and plist bytes."""
        self.reject_env(b"#" + b"x" * 65_536)
        self.reject_resource(b"x" * 65_537)

    def test_exact_65536_byte_env_bound(self):
        """A maximum-size unrelated comment is valid absence, not an oversize error."""
        self.env.write_bytes(b"#" + b"x" * 65_535)
        self.assertIsNone(MODULE.load_env(self.env))

    def test_invalid_utf8_and_quotes(self):
        """Undecodable and unbalanced recognized input fails closed."""
        self.reject_env(b"\xff")
        for value in ('"PLACEHOLDER', "'PLACEHOLDER", '"'):
            self.reject_env(("KINETIQ_GA4_API_SECRET=" + value).encode())

    def test_invalid_plist_and_types(self):
        """Invalid plist syntax, root types and field types are rejected locally."""
        for raw in (b"", b"not a plist", b"<plist><dict>"):
            self.reject_resource(raw)
        for value in ([], True, "invalid", 42, {},
                      {"measurement_id": True, "api_secret": "PLACEHOLDER"},
                      {"measurement_id": "G-REPLACE", "api_secret": b"invalid"}):
            self.reject_resource(plistlib.dumps(value))

    def test_admin_extras_and_closed_schema(self):
        """Unknown and nested administrator material never belongs in the resource."""
        for key in ("private_key", "service_account", "client_email", "token_uri", "unknown"):
            value = {"measurement_id": "G-REPLACE", "api_secret": "PLACEHOLDER",
                     key: {"type": "service_account"}}
            self.reject_resource(plistlib.dumps(value))

    def test_main_app_only_rejects_saver(self):
        """Even real app metadata cannot authorize a saver destination."""
        saver = self.root / "Kinetiq.saver"
        target = saver / "Contents/Info.plist"
        target.parent.mkdir(parents=True)
        target.write_bytes(self.original_info)
        with self.assertRaises(MODULE.InvalidConfiguration):
            MODULE.configure(saver, self.env)
        self.assertTrue(target.read_bytes() == self.original_info, "SAVER_INFO_CHANGED")
        self.assertFalse((saver / "Contents/Resources" / MODULE.RESOURCE).exists())

    def test_wrong_bundle_identifier(self):
        """An explicitly invalid bundle identifier rejects the main-app copy."""
        info = plistlib.loads(self.original_info)
        info["CFBundleIdentifier"] = "invalid.bundle.identifier"
        self.info.write_bytes(plistlib.dumps(info))
        with self.assertRaises(MODULE.InvalidConfiguration):
            MODULE.configure(self.app, self.env)
        self.assertFalse(self.destination.exists())

    def test_stale_configuration_removed_when_env_absent(self):
        """Absence deletes a stale resource rather than keeping earlier provisioning."""
        self.destination.parent.mkdir()
        self.destination.write_bytes(b"invalid stale configuration")
        self.assertFalse(MODULE.configure(self.app, self.env))
        self.assertFalse(self.destination.exists())

    def test_nonregular_and_dangling_inputs(self):
        """Unreadable/nonregular presence is not optional absence."""
        self.env.mkdir()
        with self.assertRaises(MODULE.InvalidConfiguration):
            MODULE.load_env(self.env)
        self.env.rmdir()
        self.env.symlink_to(self.root / "missing")
        with self.assertRaises(MODULE.InvalidConfiguration):
            MODULE.load_env(self.env)

    def test_cli_fixed_absent_rejected_and_argument_statuses(self):
        """Only offline CLI modes execute; --validate is never invoked by tests."""
        args = [sys.executable, str(SCRIPT), "--app", str(self.app), "--env", str(self.env)]
        result = subprocess.run(args, capture_output=True, text=True, check=False)
        self.assertTrue(result.returncode == 0, "CLI_ABSENCE_FAILED")
        self.assertTrue(result.stdout == "KINETIQ_GA4_CONFIGURATION_ABSENT\n", "CLI_OUTPUT_INVALID")
        self.assertTrue(result.stderr == "", "CLI_DIAGNOSTIC_INVALID")
        self.env.write_bytes(b"KINETIQ_GA4_API_SECRET=PLACEHOLDER")
        result = subprocess.run(args, capture_output=True, text=True, check=False)
        self.assertTrue(result.returncode == 1, "CLI_REJECTION_FAILED")
        self.assertTrue(result.stdout == "", "CLI_OUTPUT_INVALID")
        self.assertTrue(result.stderr == "KINETIQ_GA4_CONFIGURATION_REJECTED; no values logged\n",
                        "CLI_DIAGNOSTIC_INVALID")
        result = subprocess.run(args + ["--invalid-option"], capture_output=True, text=True, check=False)
        self.assertTrue(result.returncode == 2, "CLI_ARGUMENT_REJECTION_FAILED")
        self.assertTrue(result.stdout == "", "CLI_OUTPUT_INVALID")
        self.assertTrue(result.stderr == "KINETIQ_GA4_ARGUMENTS_REJECTED\n", "CLI_DIAGNOSTIC_INVALID")


class RealOwnerGA4ConfigTests(unittest.TestCase):
    """Consume real owner dotenv only inside this process, with categorical failures."""

    def setUp(self):
        """Load only approved fields; absent owner provisioning explicitly skips."""
        GA4ConfigTests.setUp(self)
        try:
            self.config = MODULE.load_env(ROOT / ".env")
        except Exception:
            self.fail("OWNER_CONFIGURATION_REJECTED")
        if self.config is None:
            self.skipTest("OWNER_CONFIGURATION_ABSENT")
        self.env.write_bytes(self.env_bytes(self.config))

    @staticmethod
    def env_bytes(config):
        """Serialize only the two approved fields into temporary local test input."""
        return "".join(key + "=" + config[field] + "\n"
                       for key, field in MODULE.KEYS.items()).encode()

    def test_actual_owner_roundtrip(self):
        """Package and reload genuine owner configuration without displaying values."""
        self.assertTrue(MODULE.configure(self.app, self.env), "OWNER_COPY_FAILED")
        copied = MODULE.load_resource(self.destination)
        self.assertTrue(copied == self.config, "OWNER_ROUNDTRIP_MISMATCH")
        self.assertTrue(self.info.read_bytes() == self.original_info, "APP_INFO_CHANGED")
        self.assertTrue(MODULE.load_env(ROOT / ".env") == self.config, "OWNER_CONFIGURATION_CHANGED")
        self.assertTrue(self.destination.stat().st_mode & 0o777 == 0o600, "RESOURCE_MODE_INVALID")

    def test_exact_allowlist_ignores_unrelated_env_data(self):
        """Unrelated invalid admin/legacy lines stay out of the generated plist."""
        unrelated = b"OTHER=invalid\nprivate_key=invalid\nUNRELATED no equals\nexport OTHER=invalid\n"
        self.env.write_bytes(unrelated + self.env_bytes(self.config))
        self.assertTrue(MODULE.configure(self.app, self.env), "OWNER_COPY_FAILED")
        copied = plistlib.loads(self.destination.read_bytes())
        self.assertTrue(set(copied) == {"measurement_id", "api_secret"}, "RESOURCE_ALLOWLIST_INVALID")
        self.assertTrue(copied == self.config, "OWNER_ALLOWLIST_MISMATCH")
        self.assertFalse((self.destination.parent / ".env").exists(), "DOTENV_COPIED")

    def test_actual_owner_literal_quotes_and_unrelated_duplicates(self):
        """Literal quoted owner values survive; unrelated duplicates do not interfere."""
        raw = "# owner values\nOTHER=invalid\nOTHER=invalid\n" + "".join(
            key + "='" + self.config[field] + "'\n" for key, field in MODULE.KEYS.items())
        self.env.write_bytes(raw.encode())
        self.assertTrue(MODULE.load_env(self.env) == self.config, "OWNER_LITERAL_PARSE_MISMATCH")

    def test_actual_owner_secret_invalid_mutations(self):
        """A genuine identifier isolates invalid secret checks without invented IDs."""
        for invalid in ("", "PLACEHOLDER", "REPLACE_ME", "CHANGEME", "CHANGE_ME", "YOUR_API_SECRET",
                "API_SECRET", "SECRET", "TODO", "é", "a/b", "a+b", "a=b", "a b", "a" * 257):
            config = dict(self.config)
            config["api_secret"] = invalid
            with self.assertRaises(MODULE.InvalidConfiguration):
                MODULE.validated(config)

    def test_actual_owner_identifier_invalid_mutations(self):
        """A genuine secret isolates invalid identifier and placeholder checks."""
        for invalid in ("", "G-é", "G-invalid", "G-A/B", "G-A?B", "G-A B",
                        "G-REPLACE", "G-PLACEHOLDER", "G-" + "A" * 255):
            config = dict(self.config)
            config["measurement_id"] = invalid
            with self.assertRaises(MODULE.InvalidConfiguration):
                MODULE.validated(config)

    def test_actual_owner_resource_admin_extras(self):
        """Genuine valid fields still reject every unapproved resource field."""
        for key in ("private_key", "service_account", "client_email", "unknown"):
            config = dict(self.config)
            config[key] = {"type": "service_account"}
            with self.assertRaises(MODULE.InvalidConfiguration):
                MODULE.validated(config)

    def test_actual_owner_cli_fixed_present_status(self):
        """Offline packaging exposes presence only; no validation request is made."""
        result = subprocess.run([sys.executable, str(SCRIPT), "--app", str(self.app),
                                 "--env", str(self.env)], capture_output=True, text=True, check=False)
        self.assertTrue(result.returncode == 0, "OWNER_CLI_FAILED")
        self.assertTrue(result.stdout == "KINETIQ_GA4_CONFIGURATION_PRESENT\n", "CLI_OUTPUT_INVALID")
        self.assertTrue(result.stderr == "", "CLI_DIAGNOSTIC_INVALID")


if __name__ == "__main__":
    unittest.main()