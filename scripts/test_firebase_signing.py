"""Offline signature-metadata tests; never fabricate a valid team or re-sign a real app."""

import importlib.util
import re
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("configure-firebase-signing.py")
SPEC = importlib.util.spec_from_file_location("firebase_signing", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
APP = SCRIPT.resolve().parent.parent / "build/Kinetiq.app"


class FirebaseSigningTests(unittest.TestCase):
    """Prove categorical rejection and inspect real signature metadata when available."""

    def test_malformed_and_missing_team(self):
        for text in ("", "TeamIdentifier=not set", "TeamIdentifier=invalid",
                     "TeamIdentifier=123", "TeamIdentifier=" + "A" * 11,
                     "TeamIdentifier=" + "a" * 10, " TeamIdentifier=invalid",
                     "TeamIdentifier=invalid\nTeamIdentifier=invalid",
                     "TeamIdentifier=invalid extra"):
            self.assertIsNone(MODULE.parse_team_identifier(text))

    def test_adhoc_metadata_is_blocked(self):
        self.assertIsNone(MODULE.parse_team_identifier("Signature=adhoc\nTeamIdentifier=not set"))

    def test_cli_argument_errors_are_fixed(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--unknown", "do-not-emit"],
                                capture_output=True, text=True, check=False)
        self.assertTrue(result.returncode == 2)
        self.assertTrue(result.stdout == "")
        self.assertTrue(result.stderr == MODULE.FAILURE + "\n")

    def real_metadata(self) -> str:
        """Read only an existing actual signature, skipping unavailable platform/artifact."""
        if sys.platform != "darwin" or not APP.is_dir():
            self.skipTest("Actual signed macOS app is unavailable.")
        try:
            return MODULE.signing_metadata(APP)
        except (OSError, ValueError, subprocess.SubprocessError):
            self.skipTest("Actual app signing metadata is unavailable.")

    def test_real_team_parser(self):
        text = self.real_metadata()
        team = MODULE.parse_team_identifier(text)
        if team is None:
            self.skipTest("Actual app has no valid Apple TeamIdentifier (ad-hoc/off).")
        self.assertTrue(re.fullmatch(r"[A-Z0-9]{10}", team) is not None)
        self.assertIsNone(MODULE.parse_team_identifier(text + "\nTeamIdentifier=" + team))
        self.assertIsNone(MODULE.parse_team_identifier(text + "\nSignature=adhoc"))
        self.assertIsNone(MODULE.parse_team_identifier(text.replace(team, team + " ")))

    def test_real_adhoc_cli_no_resign(self):
        text = self.real_metadata()
        if "Signature=adhoc" not in text:
            self.skipTest("Actual app is not ad-hoc; no signing mutation permitted in tests.")
        binary = APP / "Contents/MacOS/Kinetiq"
        before = binary.read_bytes()
        result = subprocess.run([sys.executable, str(SCRIPT), "--app", str(APP), "--identity", "-"],
                                capture_output=True, text=True, check=False)
        self.assertTrue(result.returncode == 0)
        self.assertTrue(result.stdout == MODULE.BLOCKED + "\n")
        self.assertTrue(result.stderr == "")
        self.assertTrue(binary.read_bytes() == before)


if __name__ == "__main__":
    unittest.main()