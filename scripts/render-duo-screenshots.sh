#!/usr/bin/env bash
#
# Render the iPhone Duo App Store screenshots at the exact required pixel sizes.
#
# This is the fallback for machines without Xcode 27.1. It hosts the real HomeView at the Duo point
# sizes on any booted simulator and rasterises it, so the layout is genuine — but the image has no
# status bar, no device chrome, and no ads. Treat it as a layout reference, not a device capture.
#
# Use scripts/capture-duo-screenshots.sh instead once a Duo simulator exists.

set -uo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${TAPTION_SHOT_DIR:-design/appstore/duo}"
MARKER=/tmp/taption-render-duo
RAW=/tmp/taption-duo-shots

UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1 || true)
if [ -z "$UDID" ]; then
  echo "error: no booted simulator. Boot one first." >&2
  exit 1
fi

touch "$MARKER"
rm -rf "$RAW"

xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "id=$UDID" \
  -derivedDataPath /tmp/taption-verify \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' \
  -only-testing:TaptionEncoderTests/DuoAppStoreScreenshotTests \
  -parallel-testing-enabled NO > /tmp/taption-duo-render.log 2>&1
STATUS=$?

if [ $STATUS -ne 0 ] || ! grep -q "testRenderDuoScreenshotsWhenRequested.*passed" /tmp/taption-duo-render.log; then
  echo "error: render failed. See /tmp/taption-duo-render.log" >&2
  grep -E "error:|failed" /tmp/taption-duo-render.log | head -10 >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cp "$RAW"/*.png "$OUT_DIR"/
for f in "$OUT_DIR"/*.png; do
  printf "%s  %sx%s\n" "$f" \
    "$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')" \
    "$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')"
done
