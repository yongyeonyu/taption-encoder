#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-booted}"
SAMPLE_NAME="${2:-H.264 AVC.mp4}"
BUNDLE_ID="com.taption.encoder"
VERIFY_DIR="$ROOT_DIR/build/verification"
REQUIRE_ACTIVE="${TAPTION_PIP_REQUIRE_ACTIVE:-0}"
PROBE_ID="pip-probe-$(date +%s)-$RANDOM"
LOG_COPY="$VERIFY_DIR/picture-in-picture-probe.log"
SCREENSHOT="$VERIFY_DIR/picture-in-picture-probe.png"

mkdir -p "$VERIFY_DIR"
rm -f "$LOG_COPY" "$SCREENSHOT"

is_simulator=0
if xcrun simctl getenv "$DEVICE" SIMULATOR_DEVICE_NAME >/dev/null 2>&1; then
  is_simulator=1
fi

if [[ "$is_simulator" == "1" ]]; then
  app_path="${TAPTION_ENCODER_APP_PATH:-}"
  if [[ -z "$app_path" ]]; then
    app_path="$(ls -d "$HOME/Library/Developer/Xcode/DerivedData"/TaptionEncoder-*/Build/Products/Debug-iphonesimulator/Taption\ Encoder.app 2>/dev/null | tail -n 1 || true)"
  fi

  if [[ -z "$app_path" || ! -d "$app_path" ]]; then
    echo "error: built simulator app not found. Build TaptionEncoder for an iOS simulator first, or set TAPTION_ENCODER_APP_PATH." >&2
    exit 1
  fi

  xcrun simctl install "$DEVICE" "$app_path"
  container="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" ]]; then
    rm -f "$container/Documents/TaptionEncoderLogs/taption-encoder.log"
  fi

  SIMCTL_CHILD_TAPTION_PREVIEW_SAMPLE_NAME="$SAMPLE_NAME" \
    SIMCTL_CHILD_TAPTION_AUTO_START_PIP=1 \
    SIMCTL_CHILD_TAPTION_PIP_PROBE_ID="$PROBE_ID" \
    xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" >/dev/null
else
  app_path="${TAPTION_ENCODER_APP_PATH:-}"
  if [[ -z "$app_path" ]]; then
    app_path="$(ls -d "$HOME/Library/Developer/Xcode/DerivedData"/TaptionEncoder-*/Build/Products/Debug-iphoneos/Taption\ Encoder.app 2>/dev/null | tail -n 1 || true)"
  fi

  if [[ -z "$app_path" || ! -d "$app_path" ]]; then
    echo "error: built device app not found. Build TaptionEncoder for an iOS device first, or set TAPTION_ENCODER_APP_PATH." >&2
    exit 1
  fi

  xcrun devicectl device install app --device "$DEVICE" "$app_path" --timeout 120 >/dev/null
  xcrun devicectl device process launch \
    --device "$DEVICE" \
    --terminate-existing \
    --environment-variables "{\"TAPTION_PREVIEW_SAMPLE_NAME\":\"$SAMPLE_NAME\",\"TAPTION_AUTO_START_PIP\":\"1\",\"TAPTION_PIP_PROBE_ID\":\"$PROBE_ID\"}" \
    "$BUNDLE_ID" >/dev/null
fi

copy_log() {
  if [[ "$is_simulator" == "1" ]]; then
    local container
    container="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
    if [[ -n "$container" && -f "$container/Documents/TaptionEncoderLogs/taption-encoder.log" ]]; then
      cp "$container/Documents/TaptionEncoderLogs/taption-encoder.log" "$LOG_COPY"
      return 0
    fi
    return 1
  fi

  xcrun devicectl device copy from \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source Documents/TaptionEncoderLogs/taption-encoder.log \
    --destination "$LOG_COPY" \
    --timeout 60 >/dev/null 2>&1
}

deadline=$((SECONDS + 25))
requested_pattern="Debug auto PiP requested .*probeID=$PROBE_ID"
possible_pattern="Debug auto PiP requested .*possible=true .*probeID=$PROBE_ID"
active_pattern="Debug auto PiP state checked .*active=true .*probeID=$PROBE_ID"
while [[ $SECONDS -lt $deadline ]]; do
  if copy_log && grep -q "$requested_pattern" "$LOG_COPY"; then
    if [[ "$REQUIRE_ACTIVE" == "1" ]]; then
      if grep -q "$active_pattern" "$LOG_COPY"; then
        [[ "$is_simulator" == "1" ]] && xcrun simctl io "$DEVICE" screenshot "$SCREENSHOT" >/dev/null || true
        echo "picture-in-picture active verified"
        echo "probe: $PROBE_ID"
        echo "log: $LOG_COPY"
        [[ -f "$SCREENSHOT" ]] && echo "screenshot: $SCREENSHOT"
        exit 0
      fi
    else
      [[ "$is_simulator" == "1" ]] && xcrun simctl io "$DEVICE" screenshot "$SCREENSHOT" >/dev/null || true
      if grep -q "$possible_pattern" "$LOG_COPY"; then
        echo "picture-in-picture probe completed: possible=true"
      else
        echo "picture-in-picture probe completed: possible=false"
      fi
      echo "probe: $PROBE_ID"
      echo "log: $LOG_COPY"
      [[ -f "$SCREENSHOT" ]] && echo "screenshot: $SCREENSHOT"
      exit 0
    fi
  fi
  sleep 1
done

copy_log || true
if [[ "$REQUIRE_ACTIVE" == "1" ]]; then
  echo "error: picture-in-picture did not become active in time" >&2
else
  echo "error: picture-in-picture probe did not reach a requested state in time" >&2
fi
echo "probe: $PROBE_ID" >&2
echo "log: $LOG_COPY" >&2
tail -n 100 "$LOG_COPY" >&2 || true
exit 1
