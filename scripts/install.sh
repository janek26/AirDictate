#!/bin/bash
set -euo pipefail

APP_NAME="AirDictate"
REPO="janek26/AirDictate"
INSTALL_DIR="/Applications"

echo "AirDictate Installer"
echo "===================="

# Ensure macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: AirDictate requires macOS."
    exit 1
fi

# Get latest release download URL
echo "Fetching latest release..."
RELEASE_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" \
    | grep "browser_download_url.*\.app\.zip" \
    | cut -d '"' -f 4)

if [[ -z "$RELEASE_URL" ]]; then
    echo "Error: Could not find a release for $REPO"
    echo "Check https://github.com/$REPO/releases"
    exit 1
fi

echo "Downloading $APP_NAME..."
TMP_DIR=$(mktemp -d)
curl -sL "$RELEASE_URL" -o "$TMP_DIR/$APP_NAME.app.zip"

echo "Installing to $INSTALL_DIR..."
# Remove existing if present
rm -rf "$INSTALL_DIR/$APP_NAME.app"
unzip -q "$TMP_DIR/$APP_NAME.app.zip" -d "$INSTALL_DIR"

# Clean up
rm -rf "$TMP_DIR"

echo ""
echo "$APP_NAME installed to $INSTALL_DIR/$APP_NAME.app"
echo "Launch it from Applications or Spotlight."
echo ""
echo "On first launch, AirDictate will guide you through setup."
