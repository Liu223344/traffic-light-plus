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
SPARKLE_FRAMEWORK="$SCRATCH/$TARGET_ARCH-apple-macosx/release/Sparkle.framework"
AD_HOC_ENTITLEMENTS="$ROOT/Resources/TrafficLightsPlus.ad-hoc.entitlements"

case "$TARGET_ARCH" in
    arm64)
        FEED_URL="https://liu223344.github.io/traffic-light-plus/appcast-arm64.xml"
        ;;
    x86_64)
        FEED_URL="https://liu223344.github.io/traffic-light-plus/appcast-x86_64.xml"
        ;;
esac

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
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Missing Sparkle framework: $SPARKLE_FRAMEWORK" >&2
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$ROOT/Resources"
swift "$ROOT/scripts/generate-icon.swift" "$ICONSET" "$ICON"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$APP_BINARY" "$APP/Contents/MacOS/TrafficLightsPlus"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
plutil -replace SUFeedURL -string "$FEED_URL" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/Sources/TrafficLightsPlus/Resources/zh-Hans.lproj" "$APP/Contents/Resources/"
cp -R "$ROOT/Sources/TrafficLightsPlus/Resources/en.lproj" "$APP/Contents/Resources/"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

while IFS= read -r -d $'\0' executable; do
    architectures=$(lipo -archs "$executable" 2>/dev/null || true)
    [[ -z "$architectures" ]] && continue
    if [[ "$architectures" == *" "* ]]; then
        lipo "$executable" -thin "$TARGET_ARCH" -output "$executable.thin"
        mv "$executable.thin" "$executable"
    fi
    lipo "$executable" -verify_arch "$TARGET_ARCH"
done < <(find "$APP/Contents/Frameworks/Sparkle.framework" -type f -print0)

if ! otool -l "$APP/Contents/MacOS/TrafficLightsPlus" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/TrafficLightsPlus"
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --deep --options runtime --timestamp=none \
        --preserve-metadata=identifier,entitlements,flags,runtime \
        --sign - "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp=none \
        --entitlements "$AD_HOC_ENTITLEMENTS" --sign - \
        --requirements '=designated => identifier "app.trafficlightsplus.mac"' \
        "$APP"
else
    codesign --force --deep --options runtime --timestamp \
        --preserve-metadata=identifier,entitlements,flags,runtime \
        --sign "$SIGNING_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi

otool -L "$APP/Contents/MacOS/TrafficLightsPlus" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle'
otool -l "$APP/Contents/MacOS/TrafficLightsPlus" | grep -q '@executable_path/../Frameworks'
lipo "$APP/Contents/MacOS/TrafficLightsPlus" -verify_arch "$TARGET_ARCH"
lipo "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" -verify_arch "$TARGET_ARCH"
[[ "$(plutil -extract SUFeedURL raw "$APP/Contents/Info.plist")" == "$FEED_URL" ]]
codesign --verify --deep --strict "$APP"

echo "$APP"
