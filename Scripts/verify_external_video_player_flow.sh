#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-booted}"
SAMPLE_VIDEO="${2:-"$ROOT_DIR/TaptionEncoder/TestVideos/H.264 AVC.mp4"}"
BUNDLE_ID="com.taption.encoder"
APP_PATH="${TAPTION_ENCODER_APP_PATH:-}"
VERIFY_DIR="$ROOT_DIR/build/verification"
MODE="${TAPTION_EXTERNAL_PLAYER_VERIFY_MODE:-warm}"

if [[ "$MODE" != "warm" && "$MODE" != "cold" ]]; then
  echo "error: TAPTION_EXTERNAL_PLAYER_VERIFY_MODE must be 'warm' or 'cold'." >&2
  exit 1
fi

LOG_COPY="$VERIFY_DIR/external-video-player-flow-$MODE.log"
SCREENSHOT="$VERIFY_DIR/external-video-player-flow-$MODE.png"

if [[ ! -f "$SAMPLE_VIDEO" ]]; then
  echo "error: sample video not found: $SAMPLE_VIDEO" >&2
  exit 1
fi

if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$(ls -d "$HOME/Library/Developer/Xcode/DerivedData"/TaptionEncoder-*/Build/Products/Debug-iphonesimulator/Taption\ Encoder.app 2>/dev/null | tail -n 1 || true)"
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "error: built simulator app not found. Build TaptionEncoder for an iOS simulator first, or set TAPTION_ENCODER_APP_PATH." >&2
  exit 1
fi

mkdir -p "$VERIFY_DIR"

sample_url="$(python3 - "$SAMPLE_VIDEO" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve().as_uri())
PY
)"

xcrun simctl install "$DEVICE" "$APP_PATH"

container="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
if [[ -n "$container" ]]; then
  rm -f "$container/Documents/TaptionEncoderLogs/taption-encoder.log"
fi
rm -f "$LOG_COPY" "$SCREENSHOT"

if [[ "$MODE" == "warm" ]]; then
  SIMCTL_CHILD_TAPTION_AUTO_MINIMIZE_PREVIEW=1 \
    xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" >/dev/null
  sleep 1
else
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

xcrun simctl openurl "$DEVICE" "$sample_url"

deadline=$((SECONDS + 12))
while [[ $SECONDS -lt $deadline ]]; do
  container="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" && -f "$container/Documents/TaptionEncoderLogs/taption-encoder.log" ]]; then
    cp "$container/Documents/TaptionEncoderLogs/taption-encoder.log" "$LOG_COPY"
    required_patterns=(
      "External video URL opened"
      "source=scene"
      "External player file routed into preview flow"
      "Security scoped access started"
      "Queue preview opened"
      "Queue preview video output ready"
      "Full-screen ads suppressed during video playback"
    )
    if [[ "$MODE" == "warm" ]]; then
      required_patterns+=(
        "Queue preview minimized to floating player"
        "Queue mini player video output ready"
      )
    fi

    all_patterns_present=1
    for pattern in "${required_patterns[@]}"; do
      if ! grep -q "$pattern" "$LOG_COPY"; then
        all_patterns_present=0
        break
      fi
    done

    if [[ "$all_patterns_present" == "1" ]]; then
      xcrun simctl io "$DEVICE" screenshot "$SCREENSHOT" >/dev/null
      echo "external video player flow verified ($MODE)"
      echo "log: $LOG_COPY"
      echo "screenshot: $SCREENSHOT"
      exit 0
    fi
  fi
  sleep 1
done

if [[ -n "$container" && -f "$container/Documents/TaptionEncoderLogs/taption-encoder.log" ]]; then
  cp "$container/Documents/TaptionEncoderLogs/taption-encoder.log" "$LOG_COPY"
fi

echo "error: external video player flow did not reach expected $MODE playback state in time" >&2
echo "log: $LOG_COPY" >&2
tail -n 80 "$LOG_COPY" >&2 || true
exit 1
