#!/bin/zsh
set -euo pipefail

if [[ $# -lt 6 || $# -gt 7 ]]; then
    echo "Usage: $0 <appcast> <zip> <arch> <version> <build> <download-url> [private-key-file]" >&2
    exit 64
fi

ROOT="${0:A:h:h}"
APPCAST="$1"
ZIP="$2"
EXPECTED_ARCH="$3"
EXPECTED_VERSION="$4"
EXPECTED_BUILD="$5"
EXPECTED_DOWNLOAD_URL="$6"
PRIVATE_KEY_FILE="${7:-}"
SIGN_UPDATE="${SPARKLE_TOOLS_DIR:-$ROOT/.build/artifacts/sparkle/Sparkle/bin}/sign_update"

xml_value() {
    xmllint --xpath "string($1)" "$APPCAST"
}

VERSION=$(xml_value '(//*[local-name()="item"]/*[local-name()="shortVersionString"])[1]')
BUILD=$(xml_value '(//*[local-name()="item"]/*[local-name()="version"])[1]')
MINIMUM_SYSTEM=$(xml_value '(//*[local-name()="item"]/*[local-name()="minimumSystemVersion"])[1]')
HARDWARE=$(xml_value '(//*[local-name()="item"]/*[local-name()="hardwareRequirements"])[1]')
DOWNLOAD_URL=$(xml_value '(//*[local-name()="item"]/*[local-name()="enclosure"])[1]/@url')
LENGTH=$(xml_value '(//*[local-name()="item"]/*[local-name()="enclosure"])[1]/@length')
SIGNATURE=$(xml_value '(//*[local-name()="item"]/*[local-name()="enclosure"])[1]/@*[local-name()="edSignature"]')

[[ "$VERSION" == "$EXPECTED_VERSION" ]]
[[ "$BUILD" == "$EXPECTED_BUILD" ]]
[[ "$MINIMUM_SYSTEM" == "13.0" ]]
case "$EXPECTED_ARCH" in
    arm64) [[ "$HARDWARE" == "arm64" ]] ;;
    x86_64) [[ -z "$HARDWARE" || "$HARDWARE" == "x86_64" ]] ;;
    *) exit 64 ;;
esac
[[ "$DOWNLOAD_URL" == "$EXPECTED_DOWNLOAD_URL" ]]
[[ "$LENGTH" == "$(stat -f %z "$ZIP")" ]]
[[ -n "$SIGNATURE" ]]
[[ -x "$SIGN_UPDATE" ]]

if [[ -n "$PRIVATE_KEY_FILE" ]]; then
    "$SIGN_UPDATE" --ed-key-file "$PRIVATE_KEY_FILE" --verify "$ZIP" "$SIGNATURE" >/dev/null
else
    "$SIGN_UPDATE" --account app.trafficlightsplus.mac --verify "$ZIP" "$SIGNATURE" >/dev/null
fi

echo "Validated $APPCAST ($EXPECTED_ARCH, $EXPECTED_VERSION build $EXPECTED_BUILD)"
