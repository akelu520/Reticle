#!/usr/bin/env bash
# Builds Reticle.app (Release) and packages it into build/Reticle-<version>.dmg.
# SIGN_IDENTITY defaults to ad-hoc ("-"); set it to a Developer ID to sign for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Reticle.xcodeproj -scheme Reticle -configuration Release \
  -derivedDataPath build/dd build | tail -1

APP=build/dd/Build/Products/Release/Reticle.app
IDENTITY="${SIGN_IDENTITY:--}"
# Ad-hoc: pin the designated requirement to the bundle id, otherwise it is the cdhash and
# macOS forgets the screen-recording permission on every update. Developer ID needs no override.
APP_REQ=() WORKER_REQ=()
if [ "$IDENTITY" = "-" ]; then
  APP_REQ=(-r Signing/Reticle.requirements)
  WORKER_REQ=(-r Signing/ReticleWorker.requirements)
fi
# Inside-out: the worker first, then the app (no --deep, it would reset the requirement).
codesign --force --sign "$IDENTITY" --identifier io.github.akelu520.reticle.worker ${WORKER_REQ[@]+"${WORKER_REQ[@]}"} "$APP/Contents/MacOS/ReticleWorker"
codesign --force --sign "$IDENTITY" ${APP_REQ[@]+"${APP_REQ[@]}"} "$APP"
codesign --verify --deep --strict "$APP"
codesign -dr - "$APP" 2>&1 | grep designated

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="build/Reticle-$VERSION.dmg"
hdiutil create -volname Reticle -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "$DMG"
