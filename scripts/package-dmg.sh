#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Traffic Lights Plus.app"
STAGE="$ROOT/.build/dmg-root"
DMG="$ROOT/build/Traffic-Lights-Plus-1.0.0.dmg"

"$ROOT/scripts/build-app.sh"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Traffic Lights Plus.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "Traffic Lights+" \
    -srcfolder "$STAGE" \
    -format UDZO \
    -ov \
    "$DMG"

echo "$DMG"
