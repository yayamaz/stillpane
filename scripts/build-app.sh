#!/bin/bash
# Builds dist/stillpane.app from the SwiftPM release binary.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/stillpane.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/stillpane "$APP/Contents/MacOS/stillpane"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The capture sound, played for every capture and by the setup rehearsal.
cp assets/capture.aiff "$APP/Contents/Resources/capture.aiff"

VERSION=$(grep -o 'version = "[^"]*"' Sources/StillpaneCore/Version.swift | cut -d'"' -f2)

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>stillpane</string>
    <key>CFBundleIdentifier</key><string>app.stillpane.Stillpane</string>
    <key>CFBundleName</key><string>stillpane</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc by default. A real identity (STILLPANE_SIGN_IDENTITY) keeps a stable
# designated requirement, so TCC grants survive rebuilds. A Developer ID
# identity also gets hardened runtime + a secure timestamp - both required
# for notarization.
SIGN_FLAGS=()
case "${STILLPANE_SIGN_IDENTITY:-}" in
    "Developer ID Application"*) SIGN_FLAGS+=(--options runtime --timestamp) ;;
esac
codesign --force ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} --sign "${STILLPANE_SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
