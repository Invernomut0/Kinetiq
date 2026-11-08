#!/usr/bin/env python3
"""Package owner-authorized direct GA4 credentials; never echo values or evaluate dotenv."""

import argparse
import json
import plistlib
import re
import stat
import sys
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCE = "KinetiqGA4Configuration.plist"
MAX_BYTES = 65_536
KEYS = {"KINETIQ_GA4_MEASUREMENT_ID": "measurement_id",
        "KINETIQ_GA4_API_SECRET": "api_secret"}
PLACEHOLDERS = {"CHANGEME", "CHANGE_ME", "YOUR_API_SECRET", "API_SECRET", "SECRET", "TODO"}


class InvalidConfiguration(ValueError):
    """Categorical rejection without credential-bearing diagnostics."""


class SafeArgumentParser(argparse.ArgumentParser):
    """Suppress rejected arguments, which could accidentally contain secrets."""

    def error(self, message: str) -> None:
        self.exit(2, "KINETIQ_GA4_ARGUMENTS_REJECTED\n")


def validated(value: object) -> dict[str, str]:
    """Accept only Web stream identifiers and ingestion secrets, never admin fields."""
    if not isinstance(value, dict) or set(value) != {"measurement_id", "api_secret"}:
        raise InvalidConfiguration()
    if any(type(item) is not str for item in value.values()):
        raise InvalidConfiguration()
    if (not re.fullmatch(r"G-[A-Z0-9]+", value["measurement_id"])
            or len(value["measurement_id"]) > 256
            or not re.fullmatch(r"[A-Za-z0-9_-]{1,256}", value["api_secret"])
            or any("REPLACE" in item.upper() or "PLACEHOLDER" in item.upper()
                                     or item.upper() in PLACEHOLDERS
                   for item in value.values())):
        raise InvalidConfiguration()
    return dict(value)


def read_bounded(path: Path) -> bytes:
    """Reject nonregular and oversized inputs before parsing their contents."""
    try:
        if not stat.S_ISREG(path.stat().st_mode):
            raise InvalidConfiguration()
        with path.open("rb") as stream:
            data = stream.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise InvalidConfiguration()
        return data
    except OSError:
        raise InvalidConfiguration() from None


def load_env(path: Path) -> dict[str, str] | None:
    """Parse two root-local keys as data, without expansion, execution or sibling reads."""
    try:
        path.lstat()
    except FileNotFoundError:
        return None
    except OSError:
        raise InvalidConfiguration() from None
    try:
        text = read_bounded(path).decode("utf-8")
    except UnicodeError:
        raise InvalidConfiguration() from None
    result = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        key = key.strip()
        if key not in KEYS:
            continue
        if not separator or KEYS[key] in result:
            raise InvalidConfiguration()
        value = value.strip()
        if value.startswith(("\"", "'")):
            if len(value) < 2 or value[-1] != value[0]:
                raise InvalidConfiguration()
            value = value[1:-1]
        result[KEYS[key]] = value
    return validated(result) if result else None


def load_resource(path: Path) -> dict[str, str]:
    """Read a bounded bundle resource with the same closed schema as the runtime."""
    try:
        return validated(plistlib.loads(read_bounded(path)))
    except Exception:
        raise InvalidConfiguration() from None


def configure(app: Path, env: Path) -> bool:
    """Copy only the two approved fields into the main app, removing stale absence."""
    if app.suffix != ".app":
        raise InvalidConfiguration()
    try:
        info = plistlib.loads(read_bounded(app / "Contents/Info.plist"))
        if info.get("CFBundleIdentifier") != "io.github.invernomut0.Kinetiq":
            raise InvalidConfiguration()
    except Exception:
        raise InvalidConfiguration() from None
    config = load_env(env)
    destination = app / "Contents/Resources" / RESOURCE
    if config is None:
        destination.unlink(missing_ok=True)
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    # No dotenv/admin material is copied; the distributed ingestion secret is extractable.
    destination.touch(mode=0o600, exist_ok=True)
    destination.chmod(0o600)
    destination.write_bytes(plistlib.dumps(config))
    return True


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never forward a query-string secret to another location."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def web_client_id(installation_id: uuid.UUID) -> str:
    """Match Swift's numeric Web identity mapping; do not send a hyphenated UUID."""
    return str(installation_id.int >> 96) + "." + str(installation_id.int & 0xFFFFFFFF)


def validation_payload() -> dict:
    """Build a validation-only Web session; measured preparation is not app engagement."""
    started = time.perf_counter_ns()
    parameters = {"feature": "privacy_settings", "session_id": int(time.time())}
    payload = {"client_id": web_client_id(uuid.uuid4()),
               "consent": {"ad_user_data": "DENIED", "ad_personalization": "DENIED"},
               "validation_behavior": "ENFORCE_RECOMMENDATIONS",
               "events": [{"name": "feature_used", "params": parameters}]}
    elapsed = (time.perf_counter_ns() - started) // 1_000_000
    if elapsed > 0:
        parameters["engagement_time_msec"] = elapsed
    return payload


def validate_remote(config: dict[str, str]) -> int:
    """Validate event structure only; Google does not authenticate secrets here."""
    endpoint = "https://www.google-analytics.com/debug/mp/collect?"
    url = endpoint + urllib.parse.urlencode(validated(config))
    payload = validation_payload()
    request = urllib.request.Request(url, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=10) as response:
            status = response.status
            data = response.read(MAX_BYTES + 1)
        if status != 200 or len(data) > MAX_BYTES:
            raise InvalidConfiguration()
        result = json.loads(data)
        messages = result.get("validationMessages")
        if not isinstance(messages, list):
            raise InvalidConfiguration()
        print("KINETIQ_GA4_VALIDATION_MESSAGES=" + str(len(messages)))
        if messages:
            print("KINETIQ_GA4_PAYLOAD_REJECTED")
            return 1
    except Exception:
        print("KINETIQ_GA4_VALIDATION_FAILURE; no request or values logged")
        return 1
    print("KINETIQ_GA4_PAYLOAD_VALID; secret authentication and report ingestion NOT verified")
    return 0


def main() -> int:
    """Emit fixed statuses only; network validation requires an explicit flag."""
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("--env", type=Path, default=ROOT / ".env")
    parser.add_argument("--app", type=Path, default=ROOT / "build/Kinetiq.app")
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()
    try:
        if args.validate:
            config = load_env(args.env)
            if config is None:
                raise InvalidConfiguration()
            return validate_remote(config)
        present = configure(args.app, args.env)
    except Exception:
        print("KINETIQ_GA4_CONFIGURATION_REJECTED; no values logged", file=sys.stderr)
        return 1
    print("KINETIQ_GA4_CONFIGURATION_" + ("PRESENT" if present else "ABSENT"))
    return 0


if __name__ == "__main__":
    sys.exit(main())