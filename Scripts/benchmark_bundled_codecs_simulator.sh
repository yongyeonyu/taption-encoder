#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="com.taption.encoder"
DEVICE="booted"
PROFILE="balanced"
MODE="both"
LIMIT=0
TIMEOUT_SECONDS=180
BUILD_APP=1
VERIFY_DIR="$ROOT_DIR/build/benchmark-reports"
REPORT="$VERIFY_DIR/bundled-codec-simulator-benchmark.tsv"
LOG_COPY="$VERIFY_DIR/latest-probe.log"

usage() {
  cat <<'USAGE'
Usage: benchmark_bundled_codecs_simulator.sh [options]

Options:
  --device DEVICE       Simulator UDID or "booted" (default: booted)
  --profile PROFILE    batterySaver, balanced, or performance (default: balanced)
  --mode MODE          playback, encoding, or both (default: both)
  --limit N            Limit sample count for smoke runs (default: all)
  --timeout N          Per-sample encode timeout seconds (default: 180)
  --skip-build         Reuse the latest Debug simulator app
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE="${2:?missing --device value}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:?missing --profile value}"
      shift 2
      ;;
    --mode)
      MODE="${2:?missing --mode value}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:?missing --limit value}"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="${2:?missing --timeout value}"
      shift 2
      ;;
    --skip-build)
      BUILD_APP=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$PROFILE" in
  batterySaver|balanced|performance|maxPerformance|max|fastest) ;;
  *)
    echo "error: unsupported profile: $PROFILE" >&2
    exit 2
    ;;
esac

case "$MODE" in
  playback|encoding|both) ;;
  *)
    echo "error: unsupported mode: $MODE" >&2
    exit 2
    ;;
esac

mkdir -p "$VERIFY_DIR"
rm -f "$REPORT" "$LOG_COPY"

"$ROOT_DIR/Scripts/verify_bundled_test_videos.sh" "$ROOT_DIR/TaptionEncoder/TestVideos" >/dev/null

if [[ "$DEVICE" == "booted" ]]; then
  if ! xcrun simctl getenv booted SIMULATOR_DEVICE_NAME >/dev/null 2>&1; then
    echo "error: no booted simulator. Boot a simulator or pass --device UDID." >&2
    exit 1
  fi
fi

if [[ "$BUILD_APP" == "1" ]]; then
  xcodebuild \
    -project "$ROOT_DIR/TaptionEncoder.xcodeproj" \
    -scheme TaptionEncoder \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$DEVICE" \
    build >/dev/null
fi

APP_PATH="${TAPTION_ENCODER_APP_PATH:-}"
if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData"/TaptionEncoder-*/Build/Products/Debug-iphonesimulator/Taption\ Encoder.app 2>/dev/null | head -1 || true)"
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "error: built simulator app not found. Build first or set TAPTION_ENCODER_APP_PATH." >&2
  exit 1
fi

xcrun simctl install "$DEVICE" "$APP_PATH"

clear_benchmark_state() {
  local container
  container="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" ]]; then
    rm -f "$container/Library/Application Support/TaptionEncoder/pending-saves.json"
    rm -rf "$container/Library/Application Support/TaptionEncoder/PendingEncodedVideos"
    rm -rf "$container/tmp/TaptionEncoder"
  fi
}

copy_log() {
  local container
  container="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" && -f "$container/Documents/TaptionEncoderLogs/taption-encoder.log" ]]; then
    cp "$container/Documents/TaptionEncoderLogs/taption-encoder.log" "$LOG_COPY"
    return 0
  fi
  return 1
}

clear_app_log() {
  local container
  container="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" ]]; then
    rm -f "$container/Documents/TaptionEncoderLogs/taption-encoder.log"
  fi
}

field_value() {
  local line="$1"
  local key="$2"
  sed -n "s/.* $key=\\([^ ]*\\).*/\\1/p" <<<"$line"
}

wait_for_pattern() {
  local pattern="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while [[ $SECONDS -lt $deadline ]]; do
    if copy_log && grep -q "$pattern" "$LOG_COPY"; then
      return 0
    fi
    sleep 1
  done
  copy_log || true
  return 1
}

run_playback_probe() {
  local sample="$1"
  local probe_id="$2"
  clear_benchmark_state
  clear_app_log
  SIMCTL_CHILD_TAPTION_PREVIEW_SAMPLE_NAME="$sample" \
    SIMCTL_CHILD_TAPTION_AUTO_START_PIP=1 \
    SIMCTL_CHILD_TAPTION_PIP_PROBE_ID="$probe_id" \
    xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" >/dev/null

  if wait_for_pattern "Debug auto PiP requested .*probeID=$probe_id"; then
    local line
    line="$(grep "Debug auto PiP requested .*probeID=$probe_id" "$LOG_COPY" | tail -1)"
    if grep -q "possible=true" <<<"$line"; then
      echo "playback_possible"
    else
      echo "playback_unavailable"
    fi
  else
    echo "playback_timeout"
  fi
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

run_encoding_probe() {
  local sample="$1"
  local probe_id="$2"
  local started=$SECONDS
  clear_benchmark_state
  clear_app_log
  SIMCTL_CHILD_TAPTION_PREVIEW_SAMPLE_NAME="$sample" \
    SIMCTL_CHILD_TAPTION_AUTO_START_ENCODING=1 \
    SIMCTL_CHILD_TAPTION_CODEC_PROBE_PROFILE="$PROFILE" \
    SIMCTL_CHILD_TAPTION_CODEC_PROBE_ID="$probe_id" \
    SIMCTL_CHILD_TAPTION_DEBUG_BENCHMARK_ALLOW_FREE_ENCODING=1 \
    xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" >/dev/null

  local status="encoding_timeout"
  local mode_value=""
  local backend_value=""
  local bytes_value=""
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while [[ $SECONDS -lt $deadline ]]; do
    if copy_log; then
      if grep -q "Codec benchmark probe completed .*probeID=$probe_id" "$LOG_COPY"; then
        local line
        line="$(grep "Codec benchmark probe completed .*probeID=$probe_id" "$LOG_COPY" | tail -1)"
        status="encoding_completed"
        mode_value="$(field_value "$line" "mode")"
        backend_value="$(field_value "$line" "backend")"
        bytes_value="$(field_value "$line" "temporaryBytes")"
        break
      fi
      if grep -q "Prepare encoding blocked due to unsupported route/output" "$LOG_COPY"; then
        status="encoding_blocked"
        break
      fi
      if grep -Eq "Encoding task failed|Codec transcode failed|decoder produced no frames" "$LOG_COPY"; then
        status="encoding_failed"
        break
      fi
    fi
    sleep 1
  done
  copy_log || true

  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  local elapsed=$((SECONDS - started))
  printf "%s\t%s\t%s\t%s\t%s\n" "$status" "$elapsed" "$mode_value" "$backend_value" "$bytes_value"
}

printf "sample\tplayback_status\tencoding_status\telapsed_seconds\tmode\tbackend\toutput_bytes\tprofile\n" >"$REPORT"

SAMPLES=()
while IFS= read -r -d '' sample_path; do
  SAMPLES+=("$(basename "$sample_path")")
done < <(find "$ROOT_DIR/TaptionEncoder/TestVideos" -maxdepth 1 -type f \
  ! -name 'SAMPLE_SOURCES.txt' \
  ! -name '.*' \
  -print0 | sort -z)

count=0
for sample in "${SAMPLES[@]}"; do
  if [[ "$LIMIT" != "0" && "$count" -ge "$LIMIT" ]]; then
    break
  fi
  count=$((count + 1))
  echo "[$count/${#SAMPLES[@]}] $sample"

  playback_status="not_run"
  encoding_status="not_run"
  elapsed_seconds=""
  mode_value=""
  backend_value=""
  bytes_value=""

  if [[ "$MODE" == "playback" || "$MODE" == "both" ]]; then
    playback_status="$(run_playback_probe "$sample" "playback-$count-$(date +%s)-$RANDOM")"
  fi

  if [[ "$MODE" == "encoding" || "$MODE" == "both" ]]; then
    IFS=$'\t' read -r encoding_status elapsed_seconds mode_value backend_value bytes_value < <(
      run_encoding_probe "$sample" "encoding-$count-$(date +%s)-$RANDOM"
    )
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$sample" \
    "$playback_status" \
    "$encoding_status" \
    "$elapsed_seconds" \
    "$mode_value" \
    "$backend_value" \
    "$bytes_value" \
    "$PROFILE" >>"$REPORT"
done

echo "benchmark report: $REPORT"
