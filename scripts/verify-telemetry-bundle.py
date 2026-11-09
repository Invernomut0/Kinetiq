#!/usr/bin/env python3
"""Package and verify Firebase macOS resources and original license material offline."""

import argparse
import importlib.util
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path
from xml.parsers.expat import ExpatError

REMOVED = ("posthog", "sentry", "plcrash", "libwebp")
# Vendor spelling matters: Google's ParamsEntry and C++ sentry are not the Sentry SDK.
REMOVED_BINARY = re.compile(r"(?i:posthog|plcrash|libwebp)|Sentry|"
                            r"(?i:(?:^|[^A-Za-z0-9])(?:sentry_|sentrycrash|libsentry)|[/\\]sentry(?:[./\\]|$))")
SOURCE_PACKAGES = ("firebaseiossdk", "googleappmeasurement", "googleutilities", "nanopb",
                   "googledatatransport", "promises")
# No GoogleAppMeasurementIdentitySupport / advertising-support binary resources.
ANALYTICS_FRAMEWORKS = {"FirebaseAnalytics": "firebase-ios-sdk",
                        "GoogleAppMeasurement": "googleappmeasurement"}
CORE_BUNDLE = "Invernomut0Telemetry_Invernomut0Telemetry.bundle"


class MissingBinaryLicenses(ValueError):
    """Do not replace absent Analytics binary terms with wrapper/source licenses."""


class SafeArgumentParser(argparse.ArgumentParser):
    """Do not echo rejected argument values or paths."""

    def error(self, message: str) -> None:
        self.exit(2, "KINETIQ_TELEMETRY_BUNDLE_ARGUMENTS_REJECTED\n")


def removed(name: str) -> bool:
    """Recognize stale resources from removed providers, without opening their contents."""
    return any(part in name.lower() for part in REMOVED)


def copy_bundle(source: Path, resources: Path) -> None:
    """Copy a resource bundle, rejecting same-name conflicting dependency resources."""
    destination = resources / source.name
    if destination.exists():
        source_files = {path.relative_to(source): path for path in source.rglob("*") if path.is_file()}
        target_files = {path.relative_to(destination): path for path in destination.rglob("*") if path.is_file()}
        if source_files.keys() != target_files.keys():
            raise ValueError()
        if any(path.read_bytes() != target_files[name].read_bytes() for name, path in source_files.items()):
            raise ValueError()
    else:
        shutil.copytree(source, destination)


def license_files(directory: Path) -> list[Path]:
    """Select verbatim licensing/notice files at a dependency distribution root."""
    return sorted(path for path in directory.iterdir() if path.is_file()
                  and path.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE", "PATENTS")))


def macos_frameworks(root: Path) -> dict[str, tuple[Path, Path, Path]]:
    """Resolve the actual no-ad macOS slices, not Catalyst or obsolete framework names."""
    artifacts = root / ".build/artifacts"
    result = {}
    for name, provider in ANALYTICS_FRAMEWORKS.items():
        framework = artifacts / provider / name / (name + ".xcframework")
        metadata = plistlib.loads((framework / "Info.plist").read_bytes())
        macos = [item for item in metadata["AvailableLibraries"]
                 if item.get("SupportedPlatform") == "macos"
                 and not item.get("SupportedPlatformVariant")
                 and {"arm64", "x86_64"}.issubset(item.get("SupportedArchitectures", []))]
        if len(macos) != 1:
            raise ValueError()
        slice_path = framework / macos[0]["LibraryIdentifier"]
        binary = slice_path / macos[0]["BinaryPath"]
        library = slice_path / macos[0]["LibraryPath"]
        if (slice_path.resolve().parent != framework.resolve()
                or not library.resolve().is_relative_to(slice_path.resolve())
                or not binary.resolve().is_relative_to(library.resolve())
                or not binary.is_file() or not binary.stat().st_size):
            raise ValueError()
        result[name] = (framework, slice_path, binary)
    return result


def binary_license_files(framework: Path, slice_path: Path) -> list[Path]:
    """Search distribution roots plus native versioned framework resources, deduplicated."""
    roots = {framework, framework.parent, framework.parent.parent, slice_path}
    files = {path.resolve() for directory in roots for path in license_files(directory)}
    for path in slice_path.rglob("*"):
        if (path.is_file() and path.name.upper().startswith(
                ("LICENSE", "LICENCE", "COPYING", "NOTICE", "PATENTS"))):
            files.add(path.resolve())
    return sorted(files)


def verify_native_binary(binary: Path) -> None:
    """Verify actual universal architecture evidence without printing tool output."""
    result = subprocess.run(["/usr/bin/lipo", "-archs", str(binary)],
                            capture_output=True, timeout=120, check=False)
    if result.returncode != 0 or not {b"arm64", b"x86_64"}.issubset(result.stdout.split()):
        raise ValueError()


def verify_removed_binary_providers(binary: Path) -> None:
    """Check both static symbols and dynamic links; never log subprocess output."""
    verify_native_binary(binary)
    for tool, arguments in (("/usr/bin/nm", ["-a"]), ("/usr/bin/otool", ["-L"])):
        result = subprocess.run([tool, *arguments, str(binary)],
                                capture_output=True, timeout=120, check=False)
        if result.returncode != 0 or REMOVED_BINARY.search(result.stdout.decode("utf-8", errors="replace")):
            raise ValueError()


def package_resources(root: Path, bin_dir: Path, resources: Path) -> None:
    """Copy SwiftPM resources and selected macOS binary-slice privacy plus original terms."""
    resources.mkdir(parents=True, exist_ok=True)
    for bundle in sorted(bin_dir.glob("*.bundle")):
        if bundle.name != "Kinetiq_KinetiqEffects.bundle" and not removed(bundle.name):
            copy_bundle(bundle, resources)
    licenses = resources / "ThirdPartyLicenses"
    packages = []
    for checkout in sorted((root / ".build/checkouts").iterdir()):
        normalized = checkout.name.lower().replace("-", "").replace("_", "")
        if normalized not in SOURCE_PACKAGES:
            continue
        files = license_files(checkout)
        if not files:
            raise ValueError()
        packages.append(normalized)
        destination = licenses / checkout.name
        destination.mkdir(parents=True, exist_ok=True)
        for path in files:
            shutil.copy2(path, destination / path.name)
    if "firebaseiossdk" not in packages:
        raise ValueError()
    core_manifests = list((resources / CORE_BUNDLE).rglob("PrivacyInfo.xcprivacy"))
    if len(core_manifests) != 1 or core_manifests[0].read_bytes() != (
            root.parent / "TelemetrySDK/Sources/Invernomut0Telemetry/PrivacyInfo.xcprivacy").read_bytes():
        raise ValueError()
    selected = []
    binary_licenses = {}
    artifacts = root / ".build/artifacts"
    for name, (framework, slice_path, binary) in macos_frameworks(root).items():
        verify_native_binary(binary)
        selected.append(name)
        for bundle in sorted(slice_path.rglob("*.bundle")):
            if any(bundle.rglob("PrivacyInfo.xcprivacy")):
                copy_bundle(bundle, resources)
        # Binary terms are not assumed Apache: preserve every distribution-level
        # LICENSE/NOTICE, keeping each original path distinct from source SDK terms.
        binary_terms = binary_license_files(framework, slice_path)
        if not binary_terms:
            # The official ZIPs contain no license file. Preserve their actual
            # distribution metadata rather than relabelling the binaries Apache.
            distribution = root / ".build/checkouts/firebase-ios-sdk"
            metadata = distribution / "FirebaseAnalytics.podspec"
            if not metadata.is_file() or "Copyright 2022 Google" not in metadata.read_text():
                raise MissingBinaryLicenses()
            destination = licenses / "binary" / name
            destination.mkdir(parents=True, exist_ok=True)
            shutil.copy2(metadata, destination / metadata.name)
            if name == "GoogleAppMeasurement":
                measurement = root / ".build/checkouts/googleappmeasurement"
                for path in license_files(measurement):
                    shutil.copy2(path, destination / path.name)
                shutil.copy2(measurement / "README.md", destination / "README.md")
            binary_licenses[name] = sorted(str(path.relative_to(resources)) for path in destination.iterdir())
            continue
        binary_licenses[name] = []
        for path in binary_terms:
            relative = path.relative_to(artifacts.resolve())
            destination = licenses / "binary" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            binary_licenses[name].append(str(destination.relative_to(resources)))
    inventory = {"SourcePackages": packages, "MacOSAnalyticsFrameworks": selected,
                 "BinaryLicenses": binary_licenses,
                 "Bundles": sorted(path.name for path in resources.glob("*.bundle")),
                 "Licenses": sorted(str(path.relative_to(resources)) for path in licenses.rglob("*") if path.is_file())}
    (resources / "FirebasePackaging.plist").write_bytes(plistlib.dumps(inventory))


def main() -> int:
    """Report fixed evidence only, without configuration values, paths or plist dumps."""
    root = Path(__file__).resolve().parent.parent
    resources = root / "build/Kinetiq.app/Contents/Resources"
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("--package-resources", action="store_true")
    parser.add_argument("--bin-dir", type=Path)
    args = parser.parse_args()
    try:
        if args.package_resources:
            if args.bin_dir is None:
                raise ValueError()
            package_resources(root, args.bin_dir, resources)
            print("KINETIQ_FIREBASE_RESOURCES_PACKAGED")
            return 0
        spec = importlib.util.spec_from_file_location("telemetry_configuration", root / "scripts/configure-telemetry.py")
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with (resources.parent / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        with (root / "Resources/Info.plist").open("rb") as stream:
            original = plistlib.load(stream)
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
            assert info[key] == original[key]
        for key in module.SAFETY_DEFAULTS:
            assert info[key] is False
        assert not any(key.startswith("TELEMETRY_POSTHOG_") or key == "TELEMETRY_ENVIRONMENT" for key in info)
        config_path = resources / "GoogleService-Info.plist"
        present = config_path.exists()
        if present:
            config = module.load_client(config_path)
            assert plistlib.loads(config_path.read_bytes()) == config
        ga4_spec = importlib.util.spec_from_file_location("ga4_configuration", root / "scripts/configure-ga4.py")
        assert ga4_spec is not None and ga4_spec.loader is not None
        ga4 = importlib.util.module_from_spec(ga4_spec)
        ga4_spec.loader.exec_module(ga4)
        ga4_path = resources / ga4.RESOURCE
        expected_ga4 = ga4.load_env(root / ".env")
        assert ga4_path.exists() == (expected_ga4 is not None)
        if expected_ga4 is not None:
            assert ga4.load_resource(ga4_path) == expected_ga4
        inventory = plistlib.loads((resources / "FirebasePackaging.plist").read_bytes())
        assert "firebaseiossdk" in inventory["SourcePackages"]
        assert "FirebaseAnalytics" in inventory["MacOSAnalyticsFrameworks"]
        assert set(inventory["MacOSAnalyticsFrameworks"]) == set(ANALYTICS_FRAMEWORKS)
        for name in ANALYTICS_FRAMEWORKS:
            assert inventory["BinaryLicenses"][name]
            assert all(filename in inventory["Licenses"] and filename.startswith("ThirdPartyLicenses/binary/")
                       for filename in inventory["BinaryLicenses"][name])
        assert inventory["Licenses"]
        for filename in inventory["Licenses"]:
            path = resources / filename
            assert path.resolve().is_relative_to(resources.resolve()) and path.is_file() and path.stat().st_size
        manifests = [resources / "PrivacyInfo.xcprivacy"]
        for name in inventory["Bundles"]:
            bundle = resources / name
            assert bundle.is_dir() and not removed(name)
            manifests.extend(bundle.rglob("PrivacyInfo.xcprivacy"))
        assert len(manifests) > 1
        for manifest in manifests:
            with manifest.open("rb") as stream:
                privacy = plistlib.load(stream)
            assert isinstance(privacy, dict)
            if "NSPrivacyTracking" in privacy:
                assert type(privacy["NSPrivacyTracking"]) is bool
        assert CORE_BUNDLE in inventory["Bundles"]
        core_manifests = list((resources / CORE_BUNDLE).rglob("PrivacyInfo.xcprivacy"))
        assert len(core_manifests) == 1
        assert core_manifests[0].read_bytes() == (
            root.parent / "TelemetrySDK/Sources/Invernomut0Telemetry/PrivacyInfo.xcprivacy").read_bytes()
        assert (resources / "TelemetrySDK-LICENSE.txt").read_bytes() == (root.parent / "TelemetrySDK/LICENSE").read_bytes()
        for filename in ("ThirdPartyNotices.txt", "LICENSE", "TelemetrySDK-LICENSE.txt"):
            assert (resources / filename).is_file()
        saver = resources / "Kinetiq.saver"
        verify_removed_binary_providers(resources.parent / "MacOS/Kinetiq")
        verify_removed_binary_providers(saver / "Contents/MacOS/KinetiqScreenSaver")
        assert not any(saver.rglob("GoogleService-Info*.plist"))
        assert not any(saver.rglob(ga4.RESOURCE))
        assert not any(removed(path.name) or path.name.startswith(".env")
                       or "serviceaccount" in path.name.lower().replace("-", "").replace("_", "")
                       for path in resources.parent.rglob("*"))
    except MissingBinaryLicenses:
        print("KINETIQ_FIREBASE_BINARY_LICENSES_MISSING_OWNER_REVIEW")
        return 1
    except (AssertionError, KeyError, OSError, ValueError, TypeError, OverflowError,
            RecursionError, ExpatError, plistlib.InvalidFileException, subprocess.SubprocessError):
        print("KINETIQ_TELEMETRY_BUNDLE_CHECK_FAILURE")
        return 1
    print("KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS")
    print("Main configuration validated; values withheld. Version preserved; macOS privacy and original licenses present.")
    print("Firebase client configuration " + ("present." if present else "absent."))
    return 0


if __name__ == "__main__":
    sys.exit(main())