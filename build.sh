#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NotesSnap"
APP_DIR="${APP_NAME}.app"
DIST_DIR="dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"

rm -rf "$APP_DIR" "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$DIST_DIR"

cp Info.plist "$APP_DIR/Contents/Info.plist"

# Universal binary (arm64 + x86_64) so friends on Intel Macs can run it too.
swiftc -O -target arm64-apple-macos12.0   -o "/tmp/${APP_NAME}.arm64"  main.swift -framework Cocoa -framework AVFoundation
swiftc -O -target x86_64-apple-macos12.0 -o "/tmp/${APP_NAME}.x86_64" main.swift -framework Cocoa -framework AVFoundation
lipo -create -output "$APP_DIR/Contents/MacOS/$APP_NAME" "/tmp/${APP_NAME}.arm64" "/tmp/${APP_NAME}.x86_64"
rm -f "/tmp/${APP_NAME}.arm64" "/tmp/${APP_NAME}.x86_64"

# Ad-hoc sign so macOS honours the Info.plist camera usage string.
codesign --force --deep --sign - "$APP_DIR" >/dev/null

# Zip (preserves bundle structure + xattrs)
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.zip"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

# DMG (nicer install UX: drag-to-Applications)
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
STAGE_DIR="$(mktemp -d)"
cp -R "$APP_DIR" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format ULFO "$DMG_PATH" >/dev/null
rm -rf "$STAGE_DIR"

echo ""
echo "Built:"
echo "  $(pwd)/$APP_DIR"
echo "  $(pwd)/$ZIP_PATH"
echo "  $(pwd)/$DMG_PATH"
