#!/usr/bin/env bash
# Validate the external local dependency without printing any source/configuration diff.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="../TelemetrySDK"
EXPECTED="$(cat Documentation/telemetry-sdk-revision.txt)"
if [[ "$(git -C "$SDK" rev-parse HEAD)" != "$EXPECTED" ]] ||
   ! git -C "$SDK" diff --quiet HEAD -- ||
   [[ -n "$(git -C "$SDK" ls-files --others --exclude-standard)" ]]; then
    echo "TelemetrySDK revision or checkout is not approved." >&2
    exit 1
fi
echo "TelemetrySDK pin and clean checkout verified."