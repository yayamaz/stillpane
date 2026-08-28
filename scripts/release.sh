#!/bin/bash
# Cuts a stillpane release: signed + notarized app, dmg, GitHub release.
#
# What it does, in order: verify the tree is releasable, build the app signed
# with the Developer ID identity (hardened runtime + timestamp via
# build-app.sh), notarize and staple the app itself (so a copy dragged out of
# the dmg carries its own ticket and first launch works offline), build a dmg
# with an /Applications alias, notarize and staple the dmg, then publish a
# GitHub release with the dmg and its SHA-256. It also regenerates
# dist/stillpane.rb (Homebrew cask) and dist/version.json (update-check feed)
# for the tap repo and stillpane.dev.
#
# Needs: a "Developer ID Application" identity in the keychain, a notarytool
# keychain profile (default name: stillpane-notary), and gh authenticated.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${STILLPANE_NOTARY_PROFILE:-stillpane-notary}"
REPO_SLUG="yayamaz/stillpane"
TEAM_ID="7NV7GLDW87"
# The publisher requirement the install skill enforces; a release that cannot
# satisfy it must never ship, so it gates this script too.
REQUIREMENT="=anchor apple generic and identifier \"app.stillpane.Stillpane\" and certificate leaf[subject.OU] = \"${TEAM_ID}\""

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' "/Developer ID Application/ && /${TEAM_ID}/ {print \$2; exit}")
if [ -z "$IDENTITY" ]; then
    echo "No Developer ID Application identity for team ${TEAM_ID} in the keychain." >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree not clean - commit or discard first." >&2
    exit 1
fi
git fetch --tags origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "Local main and origin/main differ - push (or pull) first so the release tag lands on the released commit." >&2
    exit 1
fi
# The commit every artifact of this run describes. Build and notarization
# take minutes; the re-check before publishing catches anything that moved
# the tree in the meantime.
RELEASE_SHA=$(git rev-parse HEAD)

VERSION=$(grep -o 'version = "[^"]*"' Sources/StillpaneCore/Version.swift | cut -d'"' -f2)
TAG="v${VERSION}"
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists on origin - bump Version.swift first." >&2
    exit 1
fi

# The app tells users to update the plugin when their install is older than
# expectedPluginVersion; a release where that constant and the plugin
# manifest disagree would nag users about a version that does not exist.
PLUGIN_VERSION=$(grep -o '"version": *"[^"]*"' .claude-plugin/plugin.json | cut -d'"' -f4)
EXPECTED_PLUGIN=$(grep -o 'expectedPluginVersion = "[^"]*"' Sources/StillpaneCore/Version.swift | cut -d'"' -f2)
if [ "$PLUGIN_VERSION" != "$EXPECTED_PLUGIN" ]; then
    echo "expectedPluginVersion ($EXPECTED_PLUGIN) does not match .claude-plugin/plugin.json ($PLUGIN_VERSION)." >&2
    exit 1
fi

# A commit's SHA cannot name the commit that contains it, so the marketplace
# pin is written one commit after the release content: HEAD must be that pin
# commit and the pinned SHA must be its parent. Without this gate a release
# could ship pointing users' plugin installs at a stale tree.
PINNED_SHA=$(grep -o '"sha": *"[0-9a-f]\{40\}"' .claude-plugin/marketplace.json | cut -d'"' -f4)
if [ "$PINNED_SHA" != "$(git rev-parse HEAD~1)" ]; then
    echo "marketplace.json pins $PINNED_SHA, but the release's parent commit is $(git rev-parse HEAD~1)." >&2
    echo "Ship sequence: commit the version bumps, then pin that commit's SHA in marketplace.json as its own commit." >&2
    exit 1
fi
PINNED_PLUGIN=$(git show "$PINNED_SHA:.claude-plugin/plugin.json" | grep -o '"version": *"[^"]*"' | cut -d'"' -f4)
if [ "$PINNED_PLUGIN" != "$PLUGIN_VERSION" ]; then
    echo "The pinned tree carries plugin version $PINNED_PLUGIN, not $PLUGIN_VERSION." >&2
    exit 1
fi
# The pin commit must carry nothing but the pin itself: any other change in
# it lives in the released app yet is invisible to plugin installs, which
# fetch the pinned parent's tree.
PIN_DIFF=$(git diff --name-only "$PINNED_SHA" HEAD)
if [ "$PIN_DIFF" != ".claude-plugin/marketplace.json" ]; then
    echo "The pin commit must change only .claude-plugin/marketplace.json; it changes:" >&2
    echo "$PIN_DIFF" >&2
    exit 1
fi

# Installed plugins move only when plugin.json's version changes: `claude
# plugin update` no-ops at an unchanged version. Re-pinning a changed plugin
# tree without bumping that version ships new hooks that no existing install
# can ever reach, and no command the user runs would fix it.
PREV_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
if [ -n "$PREV_TAG" ] && [ "$PLUGIN_VERSION" = "$(git show "$PREV_TAG:.claude-plugin/plugin.json" \
    | grep -o '"version": *"[^"]*"' | cut -d'"' -f4)" ] \
    && ! git diff --quiet "$PREV_TAG" HEAD -- hooks skills; then
    echo "The plugin tree changed since $PREV_TAG but plugin.json is still $PLUGIN_VERSION." >&2
    echo "Existing installs would keep the old hooks. Bump the plugin version (and expectedPluginVersion) first." >&2
    git diff --name-only "$PREV_TAG" HEAD -- hooks skills >&2
    exit 1
fi

# The full CI gate, run locally: lint, unit tests, and the hook suite. The
# hooks are the plugin's execution surface - a release must never outrun the
# checks CI would have applied to the same tree.
find Sources Tests -name '*.swift' ! -name 'Wordmark.swift' -print0 \
    | xargs -0 swift format lint --strict --parallel Package.swift
swift test
bash Tests/HookTests.sh

STILLPANE_SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh
APP=dist/stillpane.app
DMG="dist/stillpane-${VERSION}.dmg"

codesign --verify --strict --deep -R "$REQUIREMENT" "$APP"

# notarytool submit --wait exits 0 even when Apple rejects the submission,
# so the status line is the real verdict.
notarize() {
    local out
    out=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)
    echo "$out"
    if ! echo "$out" | grep -q "status: Accepted"; then
        echo "Notarization of $1 was not accepted." >&2
        exit 1
    fi
}

ditto -c -k --keepParent "$APP" dist/stillpane-app.zip
notarize dist/stillpane-app.zip
rm dist/stillpane-app.zip
xcrun stapler staple "$APP"

# The styled window: stage read-write, let Finder lay it out (background,
# 128px icons, hidden entries parked outside the window bounds), compress
# read-only. The first run needs the terminal's Automation permission for
# Finder - macOS prompts once.
if [ -d /Volumes/stillpane ]; then
    echo "/Volumes/stillpane is already mounted - eject it first." >&2
    exit 1
fi
STAGE=$(mktemp -d)
mkdir -p "$STAGE/.background"
cp assets/dmg-background.tiff "$STAGE/.background/background.tiff"
chflags hidden "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
RW="dist/stillpane-rw.dmg"
hdiutil create -volname stillpane -srcfolder "$STAGE" -format UDRW -ov "$RW" >/dev/null
rm -rf "$STAGE"
MOUNT_DEV=$(hdiutil attach -readwrite -noverify "$RW" | awk '/\/Volumes\//{print $1; exit}')
osascript <<'LAYOUT'
tell application "Finder"
    tell disk "stillpane"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 860, 600}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "stillpane.app" of container window to {165, 185}
        set position of item "Applications" of container window to {495, 185}
        try
            set position of item ".background" of container window to {990, 990}
        end try
        try
            set position of item ".fseventsd" of container window to {1060, 990}
        end try
        update without registering applications
        delay 1
        close
    end tell
end tell
LAYOUT
rm -rf /Volumes/stillpane/.fseventsd
hdiutil detach "$MOUNT_DEV" -quiet
hdiutil convert "$RW" -format UDZO -o "$DMG" -ov >/dev/null
rm -f "$RW"
codesign --force --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
DMG_NAME="stillpane-${VERSION}.dmg"

cat > dist/stillpane.rb <<CASK
cask "stillpane" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/${REPO_SLUG}/releases/download/v#{version}/stillpane-#{version}.dmg"
  name "stillpane"
  desc "Press both Option keys and the frontmost window lands in your next Claude Code message"
  homepage "https://github.com/${REPO_SLUG}"

  depends_on macos: :sonoma

  app "stillpane.app"

  zap trash: [
    "~/.claude/stillpane",
    "~/Library/Preferences/app.stillpane.Stillpane.plist",
  ]
end
CASK

cat > dist/version.json <<JSON
{
  "version": "${VERSION}",
  "url": "https://github.com/${REPO_SLUG}/releases/tag/${TAG}"
}
JSON

NOTES="## Install

Download \`${DMG_NAME}\` below, open it, and drag stillpane into Applications.

Or with Homebrew:

    brew install ${REPO_SLUG%%/*}/tap/stillpane

## Checksum

SHA-256 (\`${DMG_NAME}\`): \`${SHA}\`"

# The dmg above was built from RELEASE_SHA's tree. Without this re-check,
# `gh release create` would mint the missing tag from whatever the default
# branch points at NOW - a tag describing different source from the signed
# artifact. The tag is created locally at the released commit, pushed, and
# the release is told to verify it.
if [ -n "$(git status --porcelain)" ] || [ "$(git rev-parse HEAD)" != "$RELEASE_SHA" ]; then
    echo "The tree changed during the build - the dmg was built from $RELEASE_SHA. Start over." >&2
    exit 1
fi
git tag "$TAG" "$RELEASE_SHA"
git push origin "refs/tags/$TAG"
gh release create "$TAG" "$DMG" --repo "$REPO_SLUG" --verify-tag --title "stillpane ${VERSION}" --notes "$NOTES"

echo
echo "Released ${TAG}."

# A local clone of yayamaz/homebrew-tap, one level above this repo (the
# private workspace keeps it at tap/, gitignored). Publishing the cask is
# part of the release, so the push here is deliberate.
TAP_DIR="${STILLPANE_TAP_DIR:-../tap}"
if [ -d "$TAP_DIR/Casks" ]; then
    # A leftover staged or dirty state in the tap clone would ride along with
    # the cask commit; this release publishes exactly one file.
    if [ -n "$(git -C "$TAP_DIR" status --porcelain)" ]; then
        echo "Tap checkout at $TAP_DIR is not clean - commit or discard there first." >&2
        exit 1
    fi
    cp dist/stillpane.rb "$TAP_DIR/Casks/stillpane.rb"
    git -C "$TAP_DIR" add Casks/stillpane.rb
    git -C "$TAP_DIR" commit -m "stillpane ${VERSION}" -- Casks/stillpane.rb
    git -C "$TAP_DIR" push origin HEAD:main
    echo "Tap cask updated and pushed."
else
    echo "Tap repo not found at $TAP_DIR - copy dist/stillpane.rb to Casks/stillpane.rb there and push."
fi

# The update feed lives in the maintainer's private infra, one level above
# this repo like the tap. Publishing it is what makes installed apps show
# "Update Available", so it is part of the release, not a separate ritual.
PUBLISH="${STILLPANE_PUBLISH_VERSION:-../scripts/publish-version.sh}"
if [ -x "$PUBLISH" ]; then
    "$PUBLISH"
else
    echo "Feed publisher not found at $PUBLISH - installed apps will not see ${VERSION} until dist/version.json is published to the update feed." >&2
    exit 1
fi
