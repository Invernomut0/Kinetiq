#!/usr/bin/env python3
"""Validate optional Firebase client metadata; never consume environment or credentials."""

import argparse
import plistlib
import re
import stat
import sys
from pathlib import Path
from xml.parsers.expat import ExpatError

MAX_BYTES = 65_536
PROJECT_ID = "kinetiq-75593"
BUNDLE_ID = "io.github.invernomut0.Kinetiq"
REQUIRED_KEYS = ("GOOGLE_APP_ID", "GCM_SENDER_ID", "API_KEY", "PROJECT_ID", "BUNDLE_ID")
# Analytics needs no Auth, messaging, database, storage or administrator metadata.
CLIENT_KEYS = (*REQUIRED_KEYS, "PLIST_VERSION")
SAFETY_DEFAULTS = dict.fromkeys((
    "FIREBASE_ANALYTICS_COLLECTION_ENABLED",
    "FIREBASE_DATA_COLLECTION_DEFAULT_ENABLED",
    "GOOGLE_ANALYTICS_DEFAULT_ALLOW_ANALYTICS_STORAGE",
    "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE",
    "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA",
    "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS",
    "GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED",
    "GOOGLE_ANALYTICS_REGISTRATION_WITH_AD_NETWORK_ENABLED",
    "FirebaseAutomaticScreenReportingEnabled",
    "FirebaseAppDelegateProxyEnabled",
), False)


class InvalidConfiguration(ValueError):
    """Categorical failure only; never embeds the input in an exception."""


class SafeArgumentParser(argparse.ArgumentParser):
    """Never echo rejected command-line values or paths."""

    def error(self, message: str) -> None:
        self.exit(2, "Firebase client configuration arguments rejected.\n")


def reject_admin_fields(value: object) -> None:
    """Reject credential fields even inside unknown nested client metadata."""
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise InvalidConfiguration()
            normalized = key.lower().replace("-", "_")
            if ("private_key" in normalized or "privatekey" in normalized
                    or "service_account" in normalized
                    or "serviceaccount" in normalized
                    or normalized in ("client_email", "client_x509_cert_url", "token_uri")
                    or (normalized == "type" and child == "service_account")):
                raise InvalidConfiguration()
            reject_admin_fields(child)
    elif isinstance(value, list):
        for child in value:
            reject_admin_fields(child)


def validated(value: object) -> dict[str, str]:
    """Return only allowlisted, typed, host-specific client metadata."""
    if not isinstance(value, dict):
        raise InvalidConfiguration()
    reject_admin_fields(value)
    if any(type(value.get(key)) is not str for key in REQUIRED_KEYS):
        raise InvalidConfiguration()
    app_id = re.fullmatch(r"1:([0-9]+):ios:[0-9A-Fa-f]+", value["GOOGLE_APP_ID"])
    if (app_id is None or not re.fullmatch(r"[0-9]+", value["GCM_SENDER_ID"])
            or app_id.group(1) != value["GCM_SENDER_ID"]
            or not re.fullmatch(r"AIza[A-Za-z0-9_-]{35}", value["API_KEY"])
            or value["PROJECT_ID"] != PROJECT_ID or value["BUNDLE_ID"] != BUNDLE_ID):
        raise InvalidConfiguration()
    if "PLIST_VERSION" in value and (type(value["PLIST_VERSION"]) is not str
                                     or value["PLIST_VERSION"] != "1"):
        raise InvalidConfiguration()
    return {key: value[key] for key in CLIENT_KEYS if key in value}


def load_client(path: Path) -> dict[str, str]:
    """Read at most 65537 bytes to reject oversized plists before parsing."""
    try:
        if not stat.S_ISREG(path.stat().st_mode):
            raise InvalidConfiguration()
        with path.open("rb") as stream:
            raw = stream.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise InvalidConfiguration()
        return validated(plistlib.loads(raw))
    except (OSError, ValueError, TypeError, OverflowError, RecursionError, ExpatError,
            plistlib.InvalidFileException):
        raise InvalidConfiguration() from None


def configure(plist_path: Path, firebase_path: Path, config: str) -> bool:
    """Keep product/version intact, default collection off and copy only main-app config."""
    if config not in ("debug", "release"):
        raise InvalidConfiguration()
    # Only genuine absence disables Analytics; directories and unreadable input fail.
    try:
        firebase_path.lstat()
        present = True
    except FileNotFoundError:
        present = False
    except OSError:
        raise InvalidConfiguration() from None
    client = load_client(firebase_path) if present else None
    destination = None
    if plist_path.name == "Info.plist" and plist_path.parent.name == "Contents":
        destination = plist_path.parent / "Resources/GoogleService-Info.plist"
        if plist_path.parent.parent.suffix != ".app":
            raise InvalidConfiguration()
    if present and destination is None:
        raise InvalidConfiguration()
    with plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise InvalidConfiguration()
    for key in tuple(info):
        if key.startswith("TELEMETRY_POSTHOG_") or key == "TELEMETRY_ENVIRONMENT":
            del info[key]
    info.update(SAFETY_DEFAULTS)
    if destination is not None:
        if client is None:
            destination.unlink(missing_ok=True)
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(plistlib.dumps(client))
    plist_path.write_bytes(plistlib.dumps(info))
    return present


def main() -> int:
    """Emit fixed status only, even on parsing/filesystem errors (no tracebacks)."""
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("--plist", type=Path, required=True)
    parser.add_argument("--firebase-file", type=Path, default=Path("GoogleService-Info.plist"))
    parser.add_argument("--config", choices=("debug", "release"), default="release")
    args = parser.parse_args()
    try:
        present = configure(args.plist, args.firebase_file, args.config)
    except (OSError, ValueError, TypeError, OverflowError, RecursionError, ExpatError,
            plistlib.InvalidFileException):
        print("Firebase client configuration rejected; no values logged.", file=sys.stderr)
        return 1
    print("Firebase client configuration " + ("present." if present else "absent."))
    return 0


if __name__ == "__main__":
    sys.exit(main())