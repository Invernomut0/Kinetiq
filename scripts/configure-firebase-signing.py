#!/usr/bin/env python3
"""Gate Firebase's private Data Protection group on actual Apple signing metadata."""

import argparse
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.parsers.expat import ExpatError

BUNDLE_ID = "io.github.invernomut0.Kinetiq"
BLOCKED = "KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF"
READY = "KINETIQ_FIREBASE_SIGNING_PRIVATE_GROUP_READY"
FAILURE = "KINETIQ_FIREBASE_SIGNING_FAILURE"


class SafeArgumentParser(argparse.ArgumentParser):
    """Suppress command-line values, including the selected signing identity."""

    def error(self, message: str) -> None:
        self.exit(2, FAILURE + "\n")


def parse_team_identifier(text: str) -> str | None:
    """Accept one exact Apple team line only; ad-hoc or ambiguous metadata fails closed."""
    if re.search(r"^Signature=adhoc$", text, re.MULTILINE):
        return None
    lines = [line for line in text.splitlines() if line.startswith("TeamIdentifier=")]
    if len(lines) != 1:
        return None
    match = re.fullmatch(r"TeamIdentifier=([A-Z0-9]{10})", lines[0])
    return match.group(1) if match else None


def codesign(*arguments: str) -> subprocess.CompletedProcess:
    """Capture all signature output locally, never emitting identity/certificate material."""
    return subprocess.run(["/usr/bin/codesign", *arguments], capture_output=True,
                          timeout=120, check=False)


def signing_metadata(app: Path) -> str:
    """Read signature metadata only, without any Keychain item operation."""
    result = codesign("-d", "--verbose=4", str(app))
    if result.returncode != 0:
        raise ValueError()
    return (result.stdout + result.stderr).decode("utf-8", errors="replace")


def configure(app: Path, identity: str) -> bool:
    """Re-sign only an already Apple-signed main app with its single private group."""
    metadata = signing_metadata(app)
    team = parse_team_identifier(metadata)
    if team is None or not identity or identity == "-":
        return False
    identifiers = [line for line in metadata.splitlines() if line.startswith("Identifier=")]
    if identifiers != ["Identifier=" + BUNDLE_ID] or app.suffix != ".app":
        raise ValueError()
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError()
    # No sandbox, shared/default group, credential, or invented signing team.
    entitlements = {"keychain-access-groups": [team + "." + BUNDLE_ID]}
    with tempfile.TemporaryDirectory(prefix="kinetiq-signing-") as temporary:
        path = Path(temporary) / "entitlements.plist"
        path.write_bytes(plistlib.dumps(entitlements))
        result = codesign("--force", "--options", "runtime", "--sign", identity,
                          "--entitlements", str(path), str(app))
    if result.returncode != 0 or parse_team_identifier(signing_metadata(app)) != team:
        raise ValueError()
    actual = codesign("-d", "--entitlements", ":-", str(app))
    if actual.returncode != 0 or plistlib.loads(actual.stdout) != entitlements:
        raise ValueError()
    if codesign("--verify", "--deep", "--strict", str(app)).returncode != 0:
        raise ValueError()
    return True


def main() -> int:
    """Print only fixed gate status; absent Apple capability is a successful blocked gate."""
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--identity", required=True)
    args = parser.parse_args()
    try:
        ready = configure(args.app, args.identity)
    except (OSError, ValueError, TypeError, AttributeError, ExpatError, plistlib.InvalidFileException,
            subprocess.SubprocessError):
        print(FAILURE)
        return 1
    print(READY if ready else BLOCKED)
    return 0


if __name__ == "__main__":
    sys.exit(main())