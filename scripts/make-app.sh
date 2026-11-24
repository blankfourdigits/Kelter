#!/bin/bash
# Builds Kelter in release mode and wraps it in build/Kelter.app.
# Usage: ./scripts/make-app.sh
#        KELTER_VERSION=0.2.1 ./scripts/make-app.sh   (the release workflow)
# Without KELTER_VERSION, the version comes from the newest v* tag.
set -euo pipefail

cd "$(dirname "$0")/.."

LAST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
VERSION="${KELTER_VERSION:-${LAST_TAG#v}}"
VERSION="${VERSION:-0.0.0}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Ungültige Version: $VERSION (erwartet z. B. 0.1.0)" >&2
    exit 1
fi
APP="build/Kelter.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/de.lproj"
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
    <key>CFBundleDevelopmentRegion</key>
    <string>de</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>de</string>
        <string>en</string>
    </array>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

# Ad-hoc signature over the whole bundle. Not notarized: on other Macs the
# first start has to be allowed once in System Settings.
codesign --force --sign - "$APP"

# macOS remembers app icons by path; register the new build so the Dock and
# the app switcher show the current icon instead of a cached blank one.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true

echo "Fertig: $APP"
echo "Starten mit: open $APP"
