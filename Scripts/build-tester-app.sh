#!/bin/bash
# Builds RPetsTester and wraps it in a minimal RPetsTester.app bundle so it shows up as a proper
# app in the Dock (double-clickable, "Keep in Dock"-able). Run: ./Scripts/build-tester-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG" --product RPetsTester

BIN=".build/$CONFIG/RPetsTester"
APP=".build/RPetsTester.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/RPetsTester"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>RPets Tester</string>
    <key>CFBundleDisplayName</key>        <string>RPets Tester</string>
    <key>CFBundleIdentifier</key>         <string>com.rpets.tester</string>
    <key>CFBundleExecutable</key>         <string>RPetsTester</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>NSPrincipalClass</key>           <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>    <true/>
</dict>
</plist>
PLIST

echo "Built $APP"
open "$APP"
