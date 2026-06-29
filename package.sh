#!/bin/bash
# Build a Release .dmg for distribution (drag-to-Applications layout).
# Usage: ./package.sh [version]   e.g. ./package.sh 1.0
set -e
cd "$(dirname "$0")"

VERSION="${1:-$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/[^0-9.]//g')}"
VERSION="${VERSION:-1.0}"
APP_NAME="FocusSession"
VOL="$APP_NAME"

echo "▸ Generating project…"
xcodegen generate >/dev/null

echo "▸ Building Release (universal: arm64 + x86_64)…"
xcodebuild -project FocusSession.xcodeproj -scheme FocusSession \
  -configuration Release -derivedDataPath build build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="build/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "✗ Build product not found"; exit 1; }

# Re-apply a deep ad-hoc signature so the bundle is internally consistent
# (no Apple Developer ID — recipients open via right-click → Open the first time).
echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "▸ Staging .dmg contents…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag target

mkdir -p dist
DMG="dist/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

echo "▸ Creating $DMG…"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "✓ $DMG ($SIZE)"
