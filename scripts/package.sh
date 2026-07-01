#!/bin/bash
set -euo pipefail

APP_NAME="AirDictate"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "Packaging $APP_NAME.app..."

# Clean previous
rm -rf "$APP_DIR"

# Create bundle structure
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy Info.plist
cp Info.plist "$CONTENTS/"

# Copy banner for about
cp banner.svg "$RESOURCES_DIR/"

# Set bundle executable name in Info.plist to match binary
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$CONTENTS/Info.plist" 2>/dev/null || true

# Ad-hoc code sign to give the binary a consistent identity
codesign --force --sign - "$APP_DIR" 2>/dev/null || echo "  (ad-hoc signing skipped)"

# Zip for distribution
cd "$BUILD_DIR"
zip -r "$APP_NAME.app.zip" "$APP_NAME.app"
cd - > /dev/null
