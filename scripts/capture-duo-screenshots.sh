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
#   scripts/capture-duo-screenshots.sh --pose outer          # fully headless
#   scripts/capture-duo-screenshots.sh --pose inner          # needs one manual unfold
#   scripts/capture-duo-screenshots.sh --pose both
#
# The pose cannot be set from simctl: there is no fold subcommand, and neither the simctl binary
# nor CoreSimulator exports any fold/pose symbol. The device boots folded, so **the outer pose is
# the boot pose and needs no interaction** — `--pose outer` runs headless. The inner pose needs
# one unfold in the Simulator window (Device > Fold / Unfold) followed by Return.
#
# Timing matters. The capture waits `--delay` seconds (default 6) after launch. Longer is worse,
# not better: around 15-20 s the first-launch "Allow folder access" sheet appears and the AdMob
# banner resolves into a real test ad with a "Test mode" label, both of which ruin the frame.

set -uo pipefail

PROJECT="TaptionEncoder.xcodeproj"
SCHEME="TaptionEncoder"
BUNDLE_ID="com.taption.encoder"
DERIVED="${TAPTION_DERIVED_DATA:-/tmp/taption-duo-capture}"
OUT_DIR="${TAPTION_SHOT_DIR:-design/appstore/duo}"

POSE="both"
DELAY=6
while [ $# -gt 0 ]; do
  case "$1" in
    --pose) POSE="${2:-}"; shift 2 ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --delay) DELAY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# Match on the device *type*, not on the display name. A device the developer renamed
# (BOKKI-duo, say) is still a Duo, and matching by name silently created a second one.
UDID=$(xcrun simctl list devices --json | python3 -c '
import json, sys
want = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device.get("deviceTypeIdentifier") == want and device.get("isAvailable", True):
            print(device["udid"])
            raise SystemExit
' "$DUO_TYPE" 2>/dev/null || true)
if [ -z "$UDID" ]; then
  RUNTIME=$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | sort -rV | head -1)
  echo "==> Creating a Duo on $RUNTIME"
  created=$(xcrun simctl create "BOKKI-duo" "$DUO_TYPE" "$RUNTIME" 2>&1 || true)
  if ! echo "$created" | grep -qE '^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$'; then
    echo "error: could not create a Duo device: $created" >&2
    echo "       A runtime does not support every device type; the iOS 27.1 runtime is the one" >&2
    echo "       that carries the Duo. Available: $(xcrun simctl list runtimes | grep -oE 'iOS [0-9.]+' | tr '\n' ' ')" >&2
    exit 1
  fi
  UDID="$created"
fi
echo "==> Device: $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
# A device whose data container failed to migrate answers `simctl io` intermittently and
# then fails the screenshot outright. Erasing it is cheaper than debugging it.
if xcrun simctl bootstatus "$UDID" -b 2>&1 | grep -q "Data Migration Failed"; then
  echo "==> Device data migration failed; erasing it and booting again"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl erase "$UDID" >/dev/null 2>&1 || true
  xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
fi
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

# The Duo exposes both panels at once, and `simctl io screenshot` without --display picks
# whichever it likes — the same device answered "LCD" on one boot and "LCD-1" on the next. Pick
# the display whose native size matches the pose instead of trusting the default.
display_for_size() {
  local want_w="$1" want_h="$2"
  xcrun simctl io "$UDID" enumerate 2>/dev/null | awk -v w="$want_w" -v h="$want_h" '
    /UUID:/ { uuid = $2 }
    /Default width:/ { cw = $3 }
    /Default height:/ { ch = $3; if (cw == w && ch == h) { print uuid; exit } }
  '
}

shoot() {
  local file="$1" display="$2"
  # simctl writes as its own process and is refused write access to the checkout when the
  # caller is sandboxed ("NSCocoaErrorDomain 513 … You don't have permission"), so the shot
  # lands in the temp directory first and is moved into place by the shell.
  local tmp
  tmp="$(mktemp -t duo-shot).png"
  local ok=0
  if [ -n "$display" ]; then
    xcrun simctl io "$UDID" screenshot --type=png --mask=black --display="$display" "$tmp" \
      >/dev/null 2>&1 && ok=1
  else
    xcrun simctl io "$UDID" screenshot --type=png --mask=black "$tmp" >/dev/null 2>&1 && ok=1
  fi
  if [ "$ok" = "1" ]; then
    mkdir -p "$(dirname "$file")"
    if mv -f "$tmp" "$file"; then
      return 0
    fi
  fi
  rm -f "$tmp"
  return 1
}

capture() {
  local pose="$1"
  read -r want_w want_h <<<"$(expected_size "$pose")"
  local file="$OUT_DIR/duo-$pose-${want_w}x${want_h}.png"

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
  sleep "$DELAY"   # first frame, banner, ad slot

  # The device boots folded, so the outer pose is already on screen and the capture
  # stays headless. Only the unfolded pose needs a hand on the Simulator window.
  if [ "$pose" = "inner" ]; then
    echo
    echo "==> Unfold the device in the Simulator window (Device > Unfold),"
    echo "    wait for the screen to settle, then press Return."
    read -r _
    sleep 1
  fi

  local display
  display=$(display_for_size "$want_w" "$want_h")
  if [ -n "$display" ]; then
    echo "==> Display for the $pose pose: $display"
  else
    echo "==> No display reports ${want_w}x${want_h}; using the default one"
  fi

  # --mask=black is what makes the file uploadable: the default policy writes the
  # panel's rounded corners as premultiplied alpha, and App Store Connect rejects a
  # PNG with an alpha channel. Rendering the mask black keeps the image opaque and
  # lossless — no JPEG round trip needed.
  #
  # The display UUID is re-read on every attempt: it is not stable across a boot, and a
  # cold boot (especially the first one after an erase) registers the display late, so a
  # UUID captured once can be stale by the time the shot is taken.
  local attempt=0
  while :; do
    display=$(display_for_size "$want_w" "$want_h")
    if shoot "$file" "$display"; then
      break
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 8 ]; then
      echo "error: screenshot failed after $attempt attempts" >&2
      echo "       Booted devices: $(xcrun simctl list devices booted | grep -c Booted)" >&2
      return 1
    fi
    sleep 4
  done

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
