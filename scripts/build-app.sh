#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
APP="${APP_OUTPUT:-$ROOT/build/Traffic Lights Plus.app}"
ICONSET="$ROOT/.build/AppIcon.iconset"
ICON="$ROOT/Resources/AppIcon.icns"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

case "$TARGET_ARCH" in
    arm64|x86_64) ;;
    *)
        echo "Unsupported TARGET_ARCH: $TARGET_ARCH (expected arm64 or x86_64)" >&2
        exit 1
        ;;
esac

TRIPLE="$TARGET_ARCH-apple-macosx13.0"
SCRATCH="$ROOT/.build/$TARGET_ARCH"
APP_BINARY="$SCRATCH/$TARGET_ARCH-apple-macosx/release/TrafficLightsPlus"
RESOURCE_BUNDLE="$SCRATCH/$TARGET_ARCH-apple-macosx/release/TrafficLightsPlus_TrafficLightsPlus.bundle"

cd "$ROOT"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/ModuleCache"
swift build -c release \
    --triple "$TRIPLE" \
    --scratch-path "$SCRATCH" \
    --disable-sandbox \
    --cache-path "$ROOT/.build/SwiftPMCache"

lipo "$APP_BINARY" -verify_arch "$TARGET_ARCH"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "Missing localization resource bundle: $RESOURCE_BUNDLE" >&2
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$ROOT/Resources"
swift "$ROOT/scripts/generate-icon.swift" "$ICONSET" "$ICON"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$APP_BINARY" "$APP/Contents/MacOS/TrafficLightsPlus"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/Sources/TrafficLightsPlus/Resources/zh-Hans.lproj" "$APP/Contents/Resources/"
cp -R "$ROOT/Sources/TrafficLightsPlus/Resources/en.lproj" "$APP/Contents/Resources/"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --deep --options runtime --timestamp=none --sign - \
        --requirements '=designated => identifier "app.trafficlightsplus.mac"' \
        "$APP"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi

echo "$APP"
