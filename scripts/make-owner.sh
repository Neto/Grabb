#!/bin/zsh
# Owner build: Grabb that never asks for a license key, for the developer's own Macs.
# Writes ~/Desktop/Grabb-<version>-owner.zip. Never publish this file.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate -q
xcodebuild -project Grabb.xcodeproj -scheme Grabb -configuration Release -derivedDataPath build/owner \
  'OTHER_SWIFT_FLAGS=$(inherited) -DOWNER' build -quiet
APP=build/owner/Build/Products/Release/Grabb.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ditto -c -k --keepParent "$APP" "$HOME/Desktop/Grabb-$VERSION-owner.zip"
echo "Owner build: $HOME/Desktop/Grabb-$VERSION-owner.zip"
