#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Traffic Lights Plus.app"
ZIP="$ROOT/build/Traffic-Lights-Plus-1.0.0.zip"

"$ROOT/scripts/build-app.sh"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "$ZIP"
