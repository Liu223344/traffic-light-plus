#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")

for ARCH in arm64 x86_64; do
    APP="$ROOT/.build/package-$ARCH/Traffic Lights Plus.app"
    STAGE="$ROOT/.build/dmg-root-$ARCH"
    DMG="$ROOT/build/Traffic-Lights-Plus-$VERSION-$ARCH.dmg"

    mkdir -p "$ROOT/build"
    rm -f "$DMG"
    TARGET_ARCH="$ARCH" APP_OUTPUT="$APP" "$ROOT/scripts/build-app.sh"

    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    ditto "$APP" "$STAGE/Traffic Lights Plus.app"
    ln -s /Applications "$STAGE/Applications"

    hdiutil create \
        -volname "Traffic Lights+ ($ARCH)" \
        -srcfolder "$STAGE" \
        -format UDZO \
        -ov \
        "$DMG"

    echo "$DMG"
done
