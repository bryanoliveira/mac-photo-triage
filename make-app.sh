#!/bin/bash
set -euo pipefail

APP_NAME="PhotoTriage"
BUNDLE_ID="com.phototype.phototriage"
VERSION="1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"

RELEASE_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "=========================================="
echo "Building $APP_NAME"
echo "=========================================="

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: macOS required."
    exit 1
fi

swift build -c release

echo ""
echo "=========================================="
echo "Assembling $APP_BUNDLE"
echo "=========================================="

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Binary
cp "$RELEASE_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Resource bundles produced by SPM (e.g. GRDB_GRDB.bundle)
for bundle in "$RELEASE_DIR"/*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$RESOURCES_DIR/"
done

# Info.plist — required for macOS to treat this as a launchable app
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper lets it run without a developer account
echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "=========================================="
echo "Done: $APP_BUNDLE"
echo "=========================================="
echo ""
echo "  Open now:          open $APP_BUNDLE"
echo "  Install globally:  cp -R $APP_BUNDLE /Applications/"
echo ""
