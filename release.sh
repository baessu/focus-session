#!/bin/bash
# Build a Release, sign it for Sparkle auto-update, refresh appcast.xml, and
# build the drag-install .dmg.
#
# One-time setup:
#   1) Build once (so Sparkle's tools are fetched), then run:
#        build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
#      It prints an EdDSA public key and stores the private key in your Keychain.
#   2) Paste that public key into project.yml → SUPublicEDKey.
#
# Per release:
#   - Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml first
#     (CFBundleVersion must strictly increase for Sparkle to see the update).
#   - ./release.sh <version>
#
# Usage: ./release.sh 1.2
set -e
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version>}"
APP_NAME="FocusSession"
REPO="baessu/focus-session"
SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"

echo "▸ Generating project…"
xcodegen generate >/dev/null

echo "▸ Building Release (universal: arm64 + x86_64)…"
xcodebuild -project FocusSession.xcodeproj -scheme FocusSession \
  -configuration Release -derivedDataPath build build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="build/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "✗ Build product not found"; exit 1; }
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "✗ Sparkle tools missing at $SPARKLE_BIN"; exit 1; }

echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "▸ Zipping for Sparkle…"
STAGE="$(mktemp -d)"
ditto -c -k --keepParent "$APP" "$STAGE/$APP_NAME-$VERSION.zip"

echo "▸ Signing update + refreshing appcast.xml…"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --link "https://github.com/$REPO" \
  -o appcast.xml \
  "$STAGE"

echo "▸ Building drag-install dmg…"
./package.sh "$VERSION"

echo ""
echo "✓ appcast.xml refreshed · $STAGE/$APP_NAME-$VERSION.zip · dist/$APP_NAME-$VERSION.dmg"
echo ""
echo "Next:"
echo "  gh release create v$VERSION \\"
echo "    dist/$APP_NAME-$VERSION.dmg \"$STAGE/$APP_NAME-$VERSION.zip\" \\"
echo "    --title \"$APP_NAME $VERSION\" --notes \"…\""
echo "  git add appcast.xml project.yml && git commit -m \"$VERSION\" && git push"
echo ""
echo "(Sparkle reads appcast.xml from the repo raw URL; committing it publishes the update.)"
