#!/bin/zsh
set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 <zip> <arm64|x86_64> <version> <build>" >&2
    exit 64
fi

ZIP="$1"
ARCH="$2"
EXPECTED_VERSION="$3"
EXPECTED_BUILD="$4"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

case "$ARCH" in
    arm64)
        EXPECTED_FEED="https://liu223344.github.io/traffic-light-plus/appcast-arm64.xml"
        ;;
    x86_64)
        EXPECTED_FEED="https://liu223344.github.io/traffic-light-plus/appcast-x86_64.xml"
        ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 64
        ;;
esac

ditto -x -k "$ZIP" "$TMP"
APP=$(find "$TMP" -maxdepth 2 -type d -name '*.app' -print -quit)
if [[ -z "$APP" ]]; then
    echo "No application bundle found in $ZIP" >&2
    exit 1
fi

INFO="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/TrafficLightsPlus"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"

[[ "$(plutil -extract CFBundleShortVersionString raw "$INFO")" == "$EXPECTED_VERSION" ]]
[[ "$(plutil -extract CFBundleVersion raw "$INFO")" == "$EXPECTED_BUILD" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw "$INFO")" == "13.0" ]]
[[ "$(plutil -extract SUFeedURL raw "$INFO")" == "$EXPECTED_FEED" ]]
[[ -n "$(plutil -extract SUPublicEDKey raw "$INFO")" ]]
[[ -d "$FRAMEWORK" ]]

lipo "$BINARY" -verify_arch "$ARCH"
lipo "$FRAMEWORK/Versions/B/Sparkle" -verify_arch "$ARCH"
otool -L "$BINARY" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle'
otool -l "$BINARY" | grep -q '@executable_path/../Frameworks'
codesign --verify --deep --strict "$APP"

echo "Validated $ZIP ($ARCH, $EXPECTED_VERSION build $EXPECTED_BUILD)"
