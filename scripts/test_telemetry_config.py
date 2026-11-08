"""Real host and optional owner plist regressions; no fabricated valid keys or network."""

import importlib.util
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("telemetry_config", Path(__file__).with_name("configure-telemetry.py"))
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class TelemetryConfigTests(unittest.TestCase):
    """Exercise missing metadata and categorical rejection on real host plist copies."""

    def setUp(self):
        """Create a disposable main app layout from the unchanged repository plist."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / "Kinetiq.app/Contents/Info.plist"
        self.target.parent.mkdir(parents=True)
        self.source = Path(__file__).resolve().parent.parent / "Resources/Info.plist"
        self.original_bytes = self.source.read_bytes()
        self.target.write_bytes(self.original_bytes)
        self.client = self.root / "GoogleService-Info.plist"
        self.destination = self.target.parent / "Resources/GoogleService-Info.plist"

    def assert_rejected(self, raw: bytes):
        """Invalid metadata must neither alter the host plist nor copy configuration."""
        self.client.write_bytes(raw)
        with self.assertRaises(MODULE.InvalidConfiguration) as caught:
            MODULE.configure(self.target, self.client, "release")
        self.assertEqual(str(caught.exception), "")
        self.assertEqual(self.target.read_bytes(), self.original_bytes)
        self.assertFalse(self.destination.exists())

    def test_missing_configuration_preserves_product_and_version(self):
        for config in ("debug", "release"):
            with self.subTest(config=config):
                self.assertFalse(MODULE.configure(self.target, self.client, config))
                result = plistlib.loads(self.target.read_bytes())
                for key, value in plistlib.loads(self.original_bytes).items():
                    self.assertEqual(result[key], value)
                self.assertFalse(self.destination.exists())
                for key in MODULE.SAFETY_DEFAULTS:
                    self.assertIs(result[key], False)

    def test_missing_configuration_removes_stale_copy(self):
        self.destination.parent.mkdir()
        self.destination.write_bytes(b"invalid stale metadata")
        self.assertFalse(MODULE.configure(self.target, self.client, "release"))
        self.assertFalse(self.destination.exists())

    def test_strips_legacy_keys_and_overrides_enabled_defaults(self):
        info = plistlib.loads(self.original_bytes)
        info.update({key: True for key in MODULE.SAFETY_DEFAULTS})
        info.update({"TELEMETRY_POSTHOG_TOKEN": "", "TELEMETRY_POSTHOG_HOST": "",
                     "TELEMETRY_POSTHOG_OTHER": "", "TELEMETRY_ENVIRONMENT": "development"})
        self.target.write_bytes(plistlib.dumps(info))
        MODULE.configure(self.target, self.client, "release")
        result = plistlib.loads(self.target.read_bytes())
        self.assertFalse(any(key.startswith("TELEMETRY_POSTHOG_") for key in result))
        self.assertNotIn("TELEMETRY_ENVIRONMENT", result)
        for key in MODULE.SAFETY_DEFAULTS:
            self.assertIs(result[key], False)

    def test_malformed_and_oversized_configuration(self):
        for raw in (b"", b"not a plist", b"<plist><dict>",
                    b'<?xml version="1.0"?><plist><dict>', b"x" * 65_537):
            with self.subTest(size=len(raw)):
                self.assert_rejected(raw)

    def test_non_dictionary_configuration(self):
        for value in ([], "invalid", True, 42):
            self.assert_rejected(plistlib.dumps(value))

    def test_required_types_and_missing_fields(self):
        self.assert_rejected(self.original_bytes)
        for key in MODULE.REQUIRED_KEYS:
            for value in (True, 42, [], {}, b"invalid"):
                with self.subTest(key=key, kind=type(value).__name__):
                    self.assert_rejected(plistlib.dumps({key: value}))

    def test_invalid_identifiers_and_api_keys(self):
        # Deliberately invalid strings only: official-valid metadata needs owner review.
        data = dict.fromkeys(MODULE.REQUIRED_KEYS, "invalid")
        data.update(PROJECT_ID=MODULE.PROJECT_ID, BUNDLE_ID=MODULE.BUNDLE_ID)
        for invalid in ("", "AIza", "AIza invalid", "AIza" + "é" * 35, "AIza" + "a" * 36):
            data["API_KEY"] = invalid
            self.assert_rejected(plistlib.dumps(data))

    def test_service_account_and_private_key_fields(self):
        for key in ("private_key", "private_key_id", "privateKey", "service_account", "serviceAccount",
                    "client_email", "token_uri"):
            self.assert_rejected(plistlib.dumps({key: "invalid"}))
            with self.assertRaises(MODULE.InvalidConfiguration):
                MODULE.reject_admin_fields({"unknown": [{key: "invalid"}]})
        self.assert_rejected(plistlib.dumps({"type": "service_account"}))

    def test_directory_and_dangling_symlink_are_not_missing(self):
        self.client.mkdir()
        with self.assertRaises(MODULE.InvalidConfiguration):
            MODULE.configure(self.target, self.client, "release")
        self.client.rmdir()
        self.client.symlink_to(self.root / "absent")
        with self.assertRaises(MODULE.InvalidConfiguration):
            MODULE.configure(self.target, self.client, "release")

    def test_saver_configuration_is_rejected(self):
        saver = self.root / "Kinetiq.saver/Contents/Info.plist"
        saver.parent.mkdir(parents=True)
        saver.write_bytes(self.original_bytes)
        with self.assertRaises(MODULE.InvalidConfiguration):
            MODULE.configure(saver, self.client, "release")
        self.assertEqual(saver.read_bytes(), self.original_bytes)

    def test_fixed_cli_output_has_no_configuration_leak(self):
        self.client.write_bytes(b"invalid-client-metadata-do-not-emit")
        args = [sys.executable, str(Path(__file__).with_name("configure-telemetry.py")),
                "--plist", str(self.target), "--firebase-file", str(self.client)]
        result = subprocess.run(args, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "Firebase client configuration rejected; no values logged.\n")
        self.client.unlink()
        result = subprocess.run(args, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "Firebase client configuration absent.\n")
        self.assertEqual(result.stderr, "")
        result = subprocess.run(args + ["--config", "do-not-emit"],
                    capture_output=True, text=True, check=False)
        self.assertTrue(result.returncode == 2)
        self.assertTrue(result.stdout == "")
        self.assertTrue(result.stderr == "Firebase client configuration arguments rejected.\n")


class RealFirebaseConfigTests(unittest.TestCase):
    """Validate owner-supplied root metadata without displaying any of its values."""

    def setUp(self):
        """Use the actual root plist read-only and a disposable app destination."""
        TelemetryConfigTests.setUp(self)
        self.owner_file = self.source.parent.parent / "GoogleService-Info.plist"
        if not self.owner_file.exists():
            self.skipTest("Owner-supplied root Firebase client plist is unavailable.")
        self.owner_bytes = self.owner_file.read_bytes()
        self.owner_metadata = plistlib.loads(self.owner_bytes)
        self.addCleanup(self.assert_owner_unchanged)

    def assert_owner_unchanged(self):
        """Compare original bytes at cleanup time, exposing only a boolean on failure."""
        self.assertTrue(self.owner_file.read_bytes() == self.owner_bytes)

    def test_real_metadata_allowlist_and_exact_host(self):
        client = MODULE.load_client(self.owner_file)
        self.assertTrue(client.get("PROJECT_ID") == MODULE.PROJECT_ID)
        self.assertTrue(client.get("BUNDLE_ID") == MODULE.BUNDLE_ID)
        self.assertTrue(set(client).issubset(MODULE.CLIENT_KEYS))
        self.assertTrue(all(type(value) is str for value in client.values()))
        self.assertTrue(all(client[key] == self.owner_metadata[key] for key in client))

    def test_real_sanitized_copy_preserves_source_and_safety(self):
        for config in ("debug", "release"):
            self.assertTrue(MODULE.configure(self.target, self.owner_file, config))
            copied = plistlib.loads(self.destination.read_bytes())
            self.assertTrue(copied == MODULE.load_client(self.owner_file))
            self.assertTrue(set(copied).issubset(MODULE.CLIENT_KEYS))
            self.assertTrue(self.owner_file.read_bytes() == self.owner_bytes)
            info = plistlib.loads(self.target.read_bytes())
            self.assertTrue(all(info[key] is False for key in MODULE.SAFETY_DEFAULTS))
            original = plistlib.loads(self.original_bytes)
            self.assertTrue(all(info[key] == value for key, value in original.items()))

    def test_real_cli_fixed_output(self):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).with_name("configure-telemetry.py")),
             "--plist", str(self.target), "--firebase-file", str(self.owner_file)],
            capture_output=True, text=True, check=False)
        self.assertTrue(result.returncode == 0)
        self.assertTrue(result.stdout == "Firebase client configuration present.\n")
        self.assertTrue(result.stderr == "")

    def test_real_metadata_wrong_host_and_admin_fields_rejected(self):
        for key in ("PROJECT_ID", "BUNDLE_ID", "GCM_SENDER_ID", "PLIST_VERSION"):
            data = dict(self.owner_metadata)
            data[key] = "invalid"
            with self.assertRaises(MODULE.InvalidConfiguration):
                MODULE.validated(data)
        data = dict(self.owner_metadata)
        data["unknown"] = {"private_key": "invalid"}
        with self.assertRaises(MODULE.InvalidConfiguration):
            MODULE.validated(data)


class FirebaseArtifactTests(unittest.TestCase):
    """Exercise actual downloaded binary layout/licensing and real core privacy resources."""

    def setUp(self):
        """Require real local artifacts, never creating replacement frameworks or licenses."""
        self.root = Path(__file__).resolve().parent.parent
        spec = importlib.util.spec_from_file_location(
            "telemetry_bundle", Path(__file__).with_name("verify-telemetry-bundle.py"))
        assert spec is not None and spec.loader is not None
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        for name, provider in self.module.ANALYTICS_FRAMEWORKS.items():
            if not (self.root / ".build/artifacts" / provider / name / (name + ".xcframework")).is_dir():
                self.skipTest("Actual Firebase/GAM binary artifacts are unavailable.")
        self.frameworks = self.module.macos_frameworks(self.root)

    def test_real_native_macos_layout_and_architectures(self):
        """Use metadata and lipo to prove both native slices, not advertising/Catalyst ones."""
        self.assertTrue(set(self.frameworks) == {"FirebaseAnalytics", "GoogleAppMeasurement"})
        for name, (framework, slice_path, binary) in self.frameworks.items():
            self.assertTrue(slice_path.name == "macos-arm64_x86_64")
            self.assertTrue(binary.relative_to(slice_path).as_posix() ==
                            name + ".framework/Versions/A/" + name)
            if sys.platform == "darwin":
                self.module.verify_native_binary(binary)
            self.assertTrue(framework.is_dir())

    def test_real_distribution_license_discovery(self):
        """Prove discovery against actual distribution files, including versioned resources."""
        for framework, slice_path, _ in self.frameworks.values():
            expected = {path.resolve() for directory in
                        (framework, framework.parent, framework.parent.parent)
                        for path in self.module.license_files(directory)}
            expected.update(path.resolve() for path in slice_path.rglob("*")
                            if path.is_file() and path.name.upper().startswith(
                                ("LICENSE", "LICENCE", "COPYING", "NOTICE", "PATENTS")))
            self.assertTrue(set(self.module.binary_license_files(framework, slice_path)) == expected)

    def test_real_bundle_google_params_entry_is_not_sentry(self):
        """Reproduce the substring collision using the actual linked Google protobuf symbols."""
        app = self.root / "build/Kinetiq.app/Contents"
        binary = app / "MacOS/Kinetiq"
        if sys.platform != "darwin" or not binary.is_file():
            self.skipTest("Actual built native Firebase app is unavailable.")
        result = subprocess.run(["/usr/bin/nm", "-a", str(binary)],
                                capture_output=True, text=True, timeout=120, check=False)
        self.assertEqual(result.returncode, 0)
        self.assertTrue("APMPBDeepLinkGadParamsEntry" in result.stdout)
        self.assertTrue(self.module.removed(result.stdout), "The old broad filter must reproduce the collision")
        self.assertIsNone(self.module.REMOVED_BINARY.search(result.stdout))
        self.module.verify_removed_binary_providers(binary)
        self.module.verify_removed_binary_providers(
            app / "Resources/Kinetiq.saver/Contents/MacOS/KinetiqScreenSaver")

    def test_real_binary_copyright_metadata_is_preserved_without_relicensing(self):
        """ZIPs omit terms; preserve the official podspec copyright and original GAM documents."""
        if sys.platform != "darwin":
            self.skipTest("Native lipo validation requires macOS.")
        if all(self.module.binary_license_files(framework, slice_path)
               for framework, slice_path, _ in self.frameworks.values()):
            self.skipTest("Actual binary distribution terms are present; missing-terms case unavailable.")
        candidates = [self.root / ".build/out/Products/Release", self.root / ".build/out/Products/Debug"]
        candidates.extend(self.root.glob(".build/*/release"))
        candidates.extend(self.root.glob(".build/*/debug"))
        bin_dir = next((path for path in candidates if (path / self.module.CORE_BUNDLE).is_dir()), None)
        if bin_dir is None:
            self.skipTest("Actual built core privacy bundle is unavailable.")
        with tempfile.TemporaryDirectory() as temporary:
            resources = Path(temporary) / "Resources"
            self.module.package_resources(self.root, bin_dir, resources)
            inventory = plistlib.loads((resources / "FirebasePackaging.plist").read_bytes())
            original = self.root / ".build/checkouts/firebase-ios-sdk/FirebaseAnalytics.podspec"
            self.assertTrue("Copyright 2022 Google" in original.read_text())
            for name in self.frameworks:
                metadata = resources / "ThirdPartyLicenses/binary" / name / "FirebaseAnalytics.podspec"
                self.assertTrue(metadata.read_bytes() == original.read_bytes())
                self.assertTrue(str(metadata.relative_to(resources)) in inventory["BinaryLicenses"][name])
            measurement = self.root / ".build/checkouts/googleappmeasurement"
            for filename in ("LICENSE", "README.md"):
                copied = resources / "ThirdPartyLicenses/binary/GoogleAppMeasurement" / filename
                self.assertTrue(copied.read_bytes() == (measurement / filename).read_bytes())
            manifests = list((resources / self.module.CORE_BUNDLE).rglob("PrivacyInfo.xcprivacy"))
            self.assertTrue(len(manifests) == 1)
            self.assertTrue(manifests[0].read_bytes() == (
                self.root.parent / "TelemetrySDK/Sources/Invernomut0Telemetry/PrivacyInfo.xcprivacy").read_bytes())


if __name__ == "__main__":
    unittest.main()