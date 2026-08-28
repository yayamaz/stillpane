#!/bin/bash
# Installs the stillpane menu bar app from the latest GitHub release.
#
# Trust model: curl attaches no quarantine attribute to what it downloads, so
# Gatekeeper would never assess this dmg on its own. The spctl assessment of
# the mounted app below IS the Gatekeeper check - notarization and platform
# policy - and the codesign requirement after it pins the publisher: only an
# app with stillpane's bundle identifier, signed under stillpane's Apple
# Developer Team ID, installs. Both are hard gates: any other notarized app
# named stillpane.app aborts the install.
set -euo pipefail

# A fixed system-only PATH, so a caller's environment cannot substitute the
# verification tools this script trusts.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

REPO="yayamaz/stillpane"
APP="/Applications/stillpane.app"
# The designated requirement every stillpane release satisfies: Apple's
# generic anchor, stillpane's bundle identifier, and its Team ID.
REQUIREMENT='=anchor apple generic and identifier "app.stillpane.Stillpane" and certificate leaf[subject.OU] = "7NV7GLDW87"'

if [ -d "$APP" ]; then
    # The publisher gate applies to an existing copy too: this script never
    # launches an app it has not verified. On failure it stands down rather
    # than deleting - the copy may be the user's own build, and removing it
    # is their call, not this script's.
    if ! codesign --verify --strict --deep -R "$REQUIREMENT" "$APP"; then
        echo "An app already at $APP does not match stillpane's signature" >&2
        echo "(bundle identifier and Developer Team ID), so it will not be" >&2
        echo "launched. If it is your own build, launch it yourself; otherwise" >&2
        echo "remove it and re-run this install." >&2
        exit 1
    fi
    # And the Gatekeeper assessment too: a revoked notarization ticket on a
    # previously installed copy must stop the launch the same way it stops a
    # fresh install.
    if ! spctl -a -t exec "$APP"; then
        echo "Gatekeeper REJECTED the app already at $APP, so it will not be" >&2
        echo "launched. Remove it and re-run this install." >&2
        exit 1
    fi
    echo "stillpane is already installed at $APP - launching it."
    open "$APP"
    exit 0
fi

echo "Fetching the latest release of ${REPO}..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")
TAG_NAME=$(printf '%s' "$RELEASE_JSON" \
    | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
DMG_URL=$(printf '%s' "$RELEASE_JSON" \
    | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | cut -d'"' -f4)
if [ -z "${TAG_NAME}" ] || [ -z "${DMG_URL}" ]; then
    echo "No tagged dmg release found in the latest release of ${REPO}." >&2
    exit 1
fi
VERSION="${TAG_NAME#v}"
# The asset must be exactly this repository's canonical dmg for the release
# tag, checked before any redirect is followed: a compromised API response
# cannot point elsewhere, and a stray or older asset cannot stand in for the
# tagged version.
case "$DMG_URL" in
    "https://github.com/${REPO}/releases/download/${TAG_NAME}/stillpane-${VERSION}.dmg") ;;
    *)
        echo "Release asset URL is not ${REPO}'s canonical dmg for ${TAG_NAME}: ${DMG_URL}" >&2
        exit 1
        ;;
esac

TMP=$(mktemp -d)
MOUNT=""
cleanup() {
    [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet || true
    rm -rf "$TMP"
}
trap cleanup EXIT

echo "Downloading $(basename "$DMG_URL")..."
curl -fsSL -o "$TMP/stillpane.dmg" "$DMG_URL"
echo "SHA-256: $(shasum -a 256 "$TMP/stillpane.dmg" | cut -d' ' -f1)"
echo "(secondary check: this should match the checksum in the release notes)"

MOUNT=$(hdiutil attach -nobrowse -readonly "$TMP/stillpane.dmg" \
    | awk -F'\t' '/\/Volumes\//{print $NF; exit}')
if [ ! -d "$MOUNT/stillpane.app" ]; then
    echo "The dmg does not contain stillpane.app - aborting." >&2
    exit 1
fi

# Hard gate one: an explicit Gatekeeper assessment of the app that will run.
if ! spctl -a -t exec -vv "$MOUNT/stillpane.app"; then
    echo "Gatekeeper REJECTED this app: it is not a notarized build." >&2
    echo "Nothing was installed. Do not bypass this check." >&2
    exit 1
fi
# Hard gate two: the stillpane publisher. Gatekeeper accepts any notarized
# app; this accepts only stillpane's bundle identifier signed under
# stillpane's Team ID.
if ! codesign --verify --strict --deep -R "$REQUIREMENT" "$MOUNT/stillpane.app"; then
    echo "This app is notarized but NOT a stillpane release: its signature" >&2
    echo "does not match stillpane's bundle identifier and Developer Team ID." >&2
    echo "Nothing was installed. Do not bypass this check." >&2
    exit 1
fi

# The signature gates prove the publisher; this proves the payload is the
# tagged version, so a validly signed but older build cannot be substituted
# under the latest tag.
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
    "$MOUNT/stillpane.app/Contents/Info.plist" 2>/dev/null || true)
if [ "$BUNDLE_VERSION" != "$VERSION" ]; then
    echo "The dmg contains stillpane ${BUNDLE_VERSION:-unknown}, but the release" >&2
    echo "tag is ${TAG_NAME}. Nothing was installed." >&2
    exit 1
fi

ditto "$MOUNT/stillpane.app" "$APP"
# Re-verify the installed copy before launching it: what runs is what was
# checked, not merely what was mounted.
if ! codesign --verify --strict --deep -R "$REQUIREMENT" "$APP"; then
    echo "The installed copy failed signature verification - removing it." >&2
    rm -rf "$APP"
    exit 1
fi
echo "Installed $APP."
open "$APP"
echo "stillpane launched - its setup assistant takes it from here."
