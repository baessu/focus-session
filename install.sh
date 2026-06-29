#!/bin/bash
# Build FocusSession and install it to /Applications so it launches by icon click.
set -e
cd "$(dirname "$0")"

echo "▸ Generating project…"
xcodegen generate >/dev/null

echo "▸ Building (Debug)…"
xcodebuild -project FocusSession.xcodeproj -scheme FocusSession \
  -configuration Debug -derivedDataPath build build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="build/Build/Products/Debug/FocusSession.app"
[ -d "$APP" ] || { echo "✗ Build product not found"; exit 1; }

echo "▸ Installing to /Applications…"
# Quit any running instance(s) first so we don't end up with duplicate copies
# (e.g. a stale build-dir instance alongside the freshly installed one).
osascript -e 'tell application "FocusSession" to quit' >/dev/null 2>&1 || true
pkill -f "FocusSession.app/Contents/MacOS/FocusSession" 2>/dev/null || true
sleep 0.5

rm -rf /Applications/FocusSession.app
cp -R "$APP" /Applications/FocusSession.app

# Refresh icon caches + Launch Services so the new icon/app show up immediately.
touch /Applications/FocusSession.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f /Applications/FocusSession.app >/dev/null 2>&1 || true

echo "✓ Installed. Launch it from Launchpad / Spotlight / Applications."
open /Applications/FocusSession.app
