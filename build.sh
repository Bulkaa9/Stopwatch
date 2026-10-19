#!/bin/bash
# Builds build/Stopwatch.app (Apple Silicon only).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Stopwatch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
    -target arm64-apple-macos13.0 \
    Sources/Stopwatch/*.swift \
    -o "$APP/Contents/MacOS/Stopwatch"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $APP"
