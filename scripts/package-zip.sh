#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")

for ARCH in arm64 x86_64; do
    APP="$ROOT/.build/package-$ARCH/Traffic Lights Plus.app"
    ZIP="$ROOT/build/Traffic-Lights-Plus-$VERSION-$ARCH.zip"

    mkdir -p "$ROOT/build"
    rm -f "$ZIP"
    TARGET_ARCH="$ARCH" APP_OUTPUT="$APP" "$ROOT/scripts/build-app.sh"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

    echo "$ZIP"
done
