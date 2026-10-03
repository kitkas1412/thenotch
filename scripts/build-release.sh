#!/bin/bash
# Builds a universal (Apple silicon + Intel) Release app, ad-hoc signed with
# the hardened runtime and entitlements, and packages it as a DMG and a zip
# in dist/.
#
# Without a paid Developer ID the app can't be notarized, so users have to
# allow it once in System Settings › Privacy & Security (see README).
#
# Usage: scripts/build-release.sh [expected-version]
#   expected-version (e.g. 0.1.0) must match MARKETING_VERSION if given.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/thenotch.app"

version=$(xcodebuild -project thenotch.xcodeproj -target thenotch -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }')
if [ -n "${1:-}" ] && [ "$1" != "$version" ]; then
  echo "error: expected version $1 but MARKETING_VERSION is $version" >&2
  exit 1
fi
echo "Building thenotch $version"

rm -rf "$DERIVED" "$DIST"
xcodebuild build \
  -project thenotch.xcodeproj \
  -scheme thenotch \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_ENTITLEMENTS="$ROOT/scripts/release.entitlements" \
  | grep -E '^(\*\*|error:)|warning: .*thenotch/' || true
[ -d "$APP" ] || { echo "error: build failed, $APP not found" >&2; exit 1; }

# Sanity checks: signature valid, hardened runtime on, Automation entitlement
# present, no debugging entitlement (get-task-allow) in a release.
codesign --verify --strict --deep "$APP"
signature=$(codesign -d --verbose=2 "$APP" 2>&1)
entitlements=$(codesign -d --entitlements - "$APP" 2>/dev/null)
grep -q 'flags=.*runtime' <<<"$signature" \
  || { echo "error: hardened runtime missing" >&2; exit 1; }
grep -q 'com.apple.security.automation.apple-events' <<<"$entitlements" \
  || { echo "error: apple-events entitlement missing" >&2; exit 1; }
if grep -q 'get-task-allow' <<<"$entitlements"; then
  echo "error: release build has get-task-allow" >&2
  exit 1
fi
# Sparkle: installed copies find updates at SUFeedURL and only install
# ones signed with the key matching SUPublicEDKey.
for key in SUFeedURL SUPublicEDKey; do
  value=$(/usr/libexec/PlistBuddy -c "Print $key" "$APP/Contents/Info.plist" 2>/dev/null || true)
  if [ -z "$value" ] || [[ "$value" == REPLACE_WITH_* ]]; then
    echo "error: $key is missing from Info.plist (Config/Info.plist)" >&2
    exit 1
  fi
done
# The app must actually launch: dyld refuses the embedded Sparkle.framework
# under the hardened runtime unless library validation allows it.
grep -q 'com.apple.security.cs.disable-library-validation' <<<"$entitlements" \
  || { echo "error: disable-library-validation entitlement missing; Sparkle won't load" >&2; exit 1; }
lipo -info "$APP/Contents/MacOS/thenotch"

mkdir -p "$DIST"
name="thenotch-$version"

# zip (ditto keeps extended attributes and symlinks intact)
ditto -c -k --keepParent "$APP" "$DIST/$name.zip"

# DMG with an Applications shortcut for drag-to-install
staging=$(mktemp -d)
cp -R "$APP" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "thenotch $version" -srcfolder "$staging" -ov -format UDZO "$DIST/$name.dmg" >/dev/null
rm -rf "$staging"

(cd "$DIST" && shasum -a 256 "$name.dmg" "$name.zip" > SHA256SUMS.txt)
echo "Done:"
ls -lh "$DIST"
