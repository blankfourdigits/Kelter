#!/bin/bash
# Builds Kelter in release mode and wraps it in build/Kelter.app.
# Usage: ./scripts/make-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="0.1.0"
APP="build/Kelter.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Kelter" "$APP/Contents/MacOS/Kelter"
cp -R Resources/. "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Kelter</string>
    <key>CFBundleDisplayName</key>
    <string>Kelter</string>
    <key>CFBundleIdentifier</key>
    <string>app.kelter.Kelter</string>
    <key>CFBundleExecutable</key>
    <string>Kelter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run on this Mac.
codesign --force --sign - "$APP"

echo "Fertig: $APP"
echo "Starten mit: open $APP"
