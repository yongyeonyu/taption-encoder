#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-booted}"
SAMPLE_VIDEO="${2:-"$ROOT_DIR/TaptionEncoder/TestVideos/H.264 AVC.mp4"}"
BUNDLE_ID="com.taption.encoder"
APP_PATH="${TAPTION_ENCODER_APP_PATH:-}"
VERIFY_DIR="$ROOT_DIR/build/verification"
LOG_COPY="$VERIFY_DIR/external-video-player-flow.log"
SCREENSHOT="$VERIFY_DIR/external-video-player-flow.png"

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

SIMCTL_CHILD_TAPTION_AUTO_MINIMIZE_PREVIEW=1 \
  xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" >/dev/null
sleep 1
xcrun simctl openurl "$DEVICE" "$sample_url"

deadline=$((SECONDS + 12))
while [[ $SECONDS -lt $deadline ]]; do
  container="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" && -f "$container/Documents/TaptionEncoderLogs/taption-encoder.log" ]]; then
    cp "$container/Documents/TaptionEncoderLogs/taption-encoder.log" "$LOG_COPY"
    if grep -q "External video URL opened" "$LOG_COPY" \
      && grep -q "source=scene" "$LOG_COPY" \
      && grep -q "External player file routed into preview flow" "$LOG_COPY" \
      && grep -q "Security scoped access started" "$LOG_COPY" \
      && grep -q "Queue preview opened" "$LOG_COPY" \
      && grep -q "Queue preview minimized to floating player" "$LOG_COPY" \
      && grep -q "Queue mini player video output ready" "$LOG_COPY" \
      && grep -q "Full-screen ads suppressed during video playback" "$LOG_COPY"; then
      xcrun simctl io "$DEVICE" screenshot "$SCREENSHOT" >/dev/null
      echo "external video player flow verified"
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

echo "error: external video player flow did not reach mini-player playback in time" >&2
echo "log: $LOG_COPY" >&2
tail -n 80 "$LOG_COPY" >&2 || true
exit 1
