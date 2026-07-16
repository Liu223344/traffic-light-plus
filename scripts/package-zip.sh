#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Traffic Lights Plus.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")
ZIP="$ROOT/build/Traffic-Lights-Plus-$VERSION.zip"

"$ROOT/scripts/build-app.sh"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "$ZIP"
