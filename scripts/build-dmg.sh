#!/usr/bin/env bash
# Builds Reticle.app (Release) and packages it into build/Reticle-<version>.dmg.
# SIGN_IDENTITY defaults to ad-hoc ("-"); set it to a Developer ID to sign for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Reticle.xcodeproj -scheme Reticle -configuration Release \
  -derivedDataPath build/dd build | tail -1

APP=build/dd/Build/Products/Release/Reticle.app
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="build/Reticle-$VERSION.dmg"
hdiutil create -volname Reticle -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "$DMG"
