#!/bin/bash
# Clean-rebuild and relaunch mux0 Debug app (no cache).
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Killing running mux0…"
pkill -f "Debug/mux0.app" 2>/dev/null || true
sleep 1

echo "==> Cleaning Xcode build cache…"
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug clean >/dev/null

echo "==> Removing DerivedData for mux0…"
rm -rf ~/Library/Developer/Xcode/DerivedData/mux0-*

echo "==> Building (fresh)…"
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build | tail -3

APP=$(find ~/Library/Developer/Xcode/DerivedData -name "mux0.app" -type d 2>/dev/null | head -1)
if [ -z "$APP" ]; then
  echo "!! mux0.app not found after build" >&2
  exit 1
fi

echo "==> Refreshing LaunchServices registration for $APP"
# Avoid stale LS cache from an earlier failed launch (e.g. after an rpath
# or Info.plist change) making `open` refuse to relaunch the rebuilt app.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "==> Launching: $APP"
open "$APP"
sleep 1
pgrep -lf "Debug/mux0.app" || echo "!! launch failed"
