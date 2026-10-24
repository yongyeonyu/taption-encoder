#!/usr/bin/env bash
#
# Capture the iPhone Duo App Store screenshots from a real Duo simulator.
#
# Requires Xcode 27.1 or later: Xcode 27.0 ships no Duo device type, and the iOS 27.0 runtime has
# no geometry for the panel, so there is nothing to boot. Check with:
#
#   xcrun simctl list devicetypes | grep -i duo
#
# Output sizes are fixed by Apple's screenshot specification:
#
#   outer (folded)    1398 x 2034
#   inner (unfolded)  2007 x 2853
#
# Usage:
#   scripts/capture-duo-screenshots.sh --pose outer
#   scripts/capture-duo-screenshots.sh --pose inner
#   scripts/capture-duo-screenshots.sh --pose both
#
# The pose cannot be set from simctl. The script builds and launches the app, then asks you to fold
# or unfold the device in the Simulator window (Device > Fold / Unfold) and press Return.

set -uo pipefail

PROJECT="TaptionEncoder.xcodeproj"
SCHEME="TaptionEncoder"
BUNDLE_ID="com.taption.encoder"
DERIVED="${TAPTION_DERIVED_DATA:-/tmp/taption-duo-capture}"
OUT_DIR="${TAPTION_SHOT_DIR:-design/appstore/duo}"

POSE="both"
while [ $# -gt 0 ]; do
  case "$1" in
    --pose) POSE="${2:-}"; shift 2 ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$POSE" in
  outer|inner|both) ;;
  *) echo "error: --pose must be outer, inner or both" >&2; exit 2 ;;
esac

expected_size() {
  case "$1" in
    outer) echo "1398 2034" ;;
    inner) echo "2007 2853" ;;
  esac
}

# --- 1. Is a Duo device type available? ---------------------------------------------------------

DUO_TYPE=$(xcrun simctl list devicetypes | grep -i "iPhone Duo (" | head -1 \
  | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9.-]+' || true)

if [ -z "$DUO_TYPE" ]; then
  cat >&2 <<'MSG'
error: no iPhone Duo simulator device type on this machine.

  Installed Xcode:  $(xcodebuild -version | head -1)
  Device types:     $(xcrun simctl list devicetypes | wc -l | tr -d ' ')

Xcode 27.0 does not ship the Duo device type; 27.1 is the first release that does. Install 27.1,
then run this script again:

  xcode-select -s /Applications/Xcode_27.1.app
  xcrun simctl list devicetypes | grep -i duo

Until then, scripts/render-duo-screenshots.sh produces the same pixel sizes from the real views
on any simulator. Those are renders, not device captures — do not upload them without checking.
MSG
  exit 1
fi

echo "==> Duo device type: $DUO_TYPE"

# --- 2. Reuse or create the device --------------------------------------------------------------

UDID=$(xcrun simctl list devices | grep -i "iPhone Duo (" | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1 || true)
if [ -z "$UDID" ]; then
  RUNTIME=$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | tail -1)
  echo "==> Creating iPhone Duo on $RUNTIME"
  UDID=$(xcrun simctl create "BOKKI-duo" "$DUO_TYPE" "$RUNTIME")
fi
echo "==> Device: $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
open -a "$(xcode-select -p)/Applications/DeviceHub.app" --args -CurrentDeviceUDID "$UDID" 2>/dev/null || true

# --- 3. Build and install ----------------------------------------------------------------------

echo "==> Building"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' > /tmp/taption-duo-build.log 2>&1
if [ $? -ne 0 ]; then
  echo "error: build failed. See /tmp/taption-duo-build.log" >&2
  tail -20 /tmp/taption-duo-build.log >&2
  exit 1
fi

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Taption Encoder.app"
[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }

xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT_DIR"

# --- 4. Capture ---------------------------------------------------------------------------------

capture() {
  local pose="$1"
  read -r want_w want_h <<<"$(expected_size "$pose")"
  local file="$OUT_DIR/duo-$pose-${want_w}x${want_h}.png"

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
  sleep 4   # first frame, banner, ad slot

  echo
  echo "==> Set the device to the $pose pose in the Simulator window"
  echo "    (Device > Fold / Unfold), wait for the screen to settle, then press Return."
  read -r _
  sleep 1

  xcrun simctl io "$UDID" screenshot "$file" >/dev/null 2>&1 || {
    echo "error: screenshot failed" >&2; return 1; }

  local got_w got_h
  got_w=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
  got_h=$(sips -g pixelHeight "$file" | awk '/pixelHeight/{print $2}')

  if [ "$got_w" != "$want_w" ] || [ "$got_h" != "$want_h" ]; then
    echo "error: $file is ${got_w}x${got_h}, expected ${want_w}x${want_h}" >&2
    echo "       The pose is probably wrong, or this runtime scales differently." >&2
    return 1
  fi
  echo "==> $file  ${got_w}x${got_h}"
}

STATUS=0
if [ "$POSE" = "outer" ] || [ "$POSE" = "both" ]; then
  capture outer || STATUS=1
fi
if [ "$POSE" = "inner" ] || [ "$POSE" = "both" ]; then
  capture inner || STATUS=1
fi

echo
if [ $STATUS -eq 0 ]; then
  echo "==> Done. Upload with:"
  echo "    python3 scripts/upload-appstore-screenshots.py --dir $OUT_DIR"
else
  echo "==> Finished with errors." >&2
fi
exit $STATUS
