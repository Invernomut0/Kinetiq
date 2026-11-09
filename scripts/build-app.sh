#!/usr/bin/env bash
# Copyright (C) 2026 José Gurruchaga
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds and packages build/Kinetiq.app as a universal binary (Apple Silicon and Intel).
# Signs with the "Apple Development" identity if one exists (or SIGN_IDENTITY): with a stable signature
# macOS keeps the Accessibility and Screen Recording permissions across builds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
bash scripts/verify-telemetry-sdk.sh
ARCHS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" "${ARCHS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)"

APP="build/Kinetiq.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Kinetiq" "$APP/Contents/MacOS/Kinetiq"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Optional owner-supplied Firebase client plist: safe metadata only, collection off.
python3 scripts/configure-telemetry.py --plist "$APP/Contents/Info.plist" --config "$CONFIG"
# Owner-authorized Web GA4 direct transport; only two .env fields, never admin credentials.
python3 scripts/configure-ga4.py --app "$APP"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
# Metal shaders and textures of the close effects (SwiftPM resource bundle, found in Contents/Resources).
cp -R "$BIN_DIR/Kinetiq_KinetiqEffects.bundle" "$APP/Contents/Resources/"
# All dependency resource bundles, selected native macOS binary privacy, verbatim terms.
python3 scripts/verify-telemetry-bundle.py --package-resources --bin-dir "$BIN_DIR"
cp NOTICE "$APP/Contents/Resources/ThirdPartyNotices.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp ../TelemetrySDK/LICENSE "$APP/Contents/Resources/TelemetrySDK-LICENSE.txt"

# A genuine ScreenSaver.framework module; the app installs this only after explicit opt-in.
SAVER="$APP/Contents/Resources/Kinetiq.saver"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
cp LICENSE NOTICE "$SAVER/Contents/Resources/"
cp "$BIN_DIR/libKinetiqScreenSaver.dylib" "$SAVER/Contents/MacOS/KinetiqScreenSaver"
cp Resources/ScreenSaver-Info.plist "$SAVER/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$SAVER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD" "$SAVER/Contents/Info.plist"

# Icon Composer icon: actool generates Assets.car (Liquid Glass) and a fallback Kinetiq.icns.
xcrun actool Resources/Kinetiq.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon Kinetiq \
    --output-partial-info-plist "$(mktemp -t kinetiq-icon)" > /dev/null

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ { print $2; exit }')}"
# Suppress certificate/identity details even if normal signing fails.
sign_product() {
    if ! codesign "$@" >/dev/null 2>&1; then
        echo "KINETIQ_PRODUCT_SIGNING_FAILURE" >&2
        exit 1
    fi
}
if [[ -n "${IDENTITY:-}" ]]; then
    sign_product --force --options runtime --sign "$IDENTITY" "$SAVER"
    sign_product --force --options runtime --sign "$IDENTITY" "$APP"
else
    sign_product --force --options runtime --sign - \
        -r='designated => identifier "io.github.invernomut0.Kinetiq.ScreenSaver"' "$SAVER"
    # Ad-hoc: pin the requirement to the bundle id, otherwise macOS ties the Accessibility and
    # Screen Recording grants to the binary hash and asks again after every build.
    sign_product --force --options runtime --sign - \
        -r='designated => identifier "io.github.invernomut0.Kinetiq"' "$APP"
fi
# Only the actual post-sign TeamIdentifier can authorize a private Data Protection group.
# Native Firebase stays blocked/off on ad-hoc; GA4 direct transport does not use this scope.
python3 scripts/configure-firebase-signing.py --app "$APP" --identity "${IDENTITY:--}"
echo "KINETIQ_PRODUCT_SIGNING_COMPLETE"
echo "$APP"
