#!/bin/bash
# Builds RPets and wraps it in an RPets.app bundle that can be dragged into
# /Applications. Run: ./Scripts/build-app.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product RPets

BIN=".build/$CONFIG/RPets"
RESOURCE_BUNDLE=".build/$CONFIG/RPets_RPets.bundle"
APP=".build/RPets.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/RPets"

# Bundle.module resolves resources relative to Bundle.main.bundleURL (the .app
# directory itself), so the SwiftPM resource bundle must sit at the app's top
# level rather than under Contents/Resources.
cp -R "$RESOURCE_BUNDLE" "$APP/RPets_RPets.bundle"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>RPets</string>
    <key>CFBundleDisplayName</key>        <string>RPets</string>
    <key>CFBundleIdentifier</key>         <string>com.rpets.app</string>
    <key>CFBundleExecutable</key>         <string>RPets</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>NSPrincipalClass</key>           <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>LSUIElement</key>                <true/>
</dict>
</plist>
PLIST

echo "Built $APP"
echo "Move it to /Applications, e.g.: cp -R $APP /Applications/"
