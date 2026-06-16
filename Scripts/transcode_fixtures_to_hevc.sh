#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="${1:-"$ROOT_DIR/Samples/CodecFixtures/generated"}"
OUT_DIR="${2:-"$ROOT_DIR/Samples/CodecFixtures/transcode_reports/$(date +%Y%m%d_%H%M%S)"}"
MANIFEST="$FIXTURE_DIR/fixtures.tsv"
RESULTS="$OUT_DIR/transcode_results.tsv"
LOG_DIR="$OUT_DIR/logs"
OUTPUT_DIR="$OUT_DIR/outputs"
STRICT="${TAPTION_TRANSCODE_STRICT:-0}"
SW_CRF="${TAPTION_SW_HEVC_CRF:-24}"
HW_DEFAULT_BITRATE="${TAPTION_HW_HEVC_DEFAULT_BITRATE:-2500000}"
HW_MIN_BITRATE="${TAPTION_HW_HEVC_MIN_BITRATE:-800000}"
HW_MAX_BITRATE="${TAPTION_HW_HEVC_MAX_BITRATE:-12000000}"
AUDIO_SIGNAL_THRESHOLD_DB="${TAPTION_AUDIO_SIGNAL_THRESHOLD_DB:--60}"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: $1 is required" >&2
    exit 1
  fi
}

has_encoder() {
  ffmpeg -hide_banner -encoders 2>/dev/null | awk '{print $2}' | grep -qx "$1"
}

stream_count() {
  local file="$1"
  local stream_type="$2"
  ffprobe \
    -v error \
    -select_streams "$stream_type" \
    -show_entries stream=index \
    -of csv=p=0 \
    "$file" | sed '/^$/d' | wc -l | tr -d ' '
}

video_codec() {
  local file="$1"
  ffprobe \
    -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name \
    -of default=nokey=1:noprint_wrappers=1 \
    "$file" | head -n 1
}

video_bitrate() {
  local file="$1"
  local bitrate
  bitrate="$(
    ffprobe \
      -v error \
      -select_streams v:0 \
      -show_entries stream=bit_rate \
      -of default=nokey=1:noprint_wrappers=1 \
      "$file" | head -n 1
  )"
  if [[ "$bitrate" =~ ^[0-9]+$ ]] && (( bitrate > 0 )); then
    echo "$bitrate"
  else
    echo "$HW_DEFAULT_BITRATE"
  fi
}

audio_peak_db() {
  local file="$1"
  if [[ "$(stream_count "$file" "a")" == "0" ]]; then
    echo "NO_AUDIO"
    return 0
  fi

  local output
  output="$(
    ffmpeg \
      -hide_banner \
      -nostats \
      -v info \
      -i "$file" \
      -map 0:a:0 \
      -af volumedetect \
      -f null - 2>&1 >/dev/null || true
  )"

  local peak
  peak="$(
    printf "%s\n" "$output" |
      awk -F 'max_volume: ' '/max_volume:/ { gsub(/ dB/, "", $2); print $2; found=1 } END { if (!found) exit 1 }' |
      tail -n 1
  )"

  if [[ -z "${peak:-}" ]]; then
    echo "UNKNOWN"
  else
    echo "$peak"
  fi
}

audio_signal_passes() {
  local peak="$1"
  case "$peak" in
    ""|"NO_AUDIO"|"UNKNOWN"|"-inf")
      return 1
      ;;
  esac

  awk -v peak="$peak" -v threshold="$AUDIO_SIGNAL_THRESHOLD_DB" 'BEGIN { exit(peak > threshold ? 0 : 1) }'
}

bounded_hw_bitrate() {
  local bitrate="$1"
  if (( bitrate < HW_MIN_BITRATE )); then
    echo "$HW_MIN_BITRATE"
  elif (( bitrate > HW_MAX_BITRATE )); then
    echo "$HW_MAX_BITRATE"
  else
    echo "$bitrate"
  fi
}

write_probe() {
  local file="$1"
  ffprobe \
    -v error \
    -show_entries stream=index,codec_type,codec_name,width,height,pix_fmt,r_frame_rate,avg_frame_rate,duration,bit_rate,sample_rate,channels \
    -show_entries format=filename,format_name,duration,size,bit_rate \
    -of json \
    "$file" > "$file.ffprobe.json"
}

append_result() {
  local name="$1"
  local mode="$2"
  local status="$3"
  local source_file="$4"
  local output_file="$5"
  local output_video_codec="$6"
  local source_audio_count="$7"
  local output_audio_count="$8"
  local audio_status="$9"
  local source_audio_peak_db="${10}"
  local output_audio_peak_db="${11}"
  local elapsed_seconds="${12}"
  local message="${13}"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$name" \
    "$mode" \
    "$status" \
    "$source_file" \
    "$output_file" \
    "$output_video_codec" \
    "$source_audio_count" \
    "$output_audio_count" \
    "$audio_status" \
    "$source_audio_peak_db" \
    "$output_audio_peak_db" \
    "$elapsed_seconds" \
    "$message" >> "$RESULTS"
}

transcode_one() {
  local name="$1"
  local relative_file="$2"
  local mode="$3"
  local source="$FIXTURE_DIR/$relative_file"
  local output="$OUTPUT_DIR/${name}_${mode}.mp4"
  local log_file="$LOG_DIR/${name}_${mode}.log"
  local encoder
  local start
  local end
  local elapsed
  local bitrate

  case "$mode" in
    SW_HEVC)
      encoder="libx265"
      if ! has_encoder "$encoder"; then
        append_result "$name" "$mode" "SKIP" "$relative_file" "" "" "" "" "" "" "" "0" "missing encoder $encoder"
        return 0
      fi
      ;;
    HW_HEVC)
      encoder="hevc_videotoolbox"
      if ! has_encoder "$encoder"; then
        append_result "$name" "$mode" "SKIP" "$relative_file" "" "" "" "" "" "" "" "0" "missing encoder $encoder"
        return 0
      fi
      ;;
    *)
      append_result "$name" "$mode" "FAIL" "$relative_file" "" "" "" "" "" "" "" "0" "unknown mode $mode"
      return 0
      ;;
  esac

  if [[ ! -f "$source" ]]; then
    append_result "$name" "$mode" "FAIL" "$relative_file" "" "" "" "" "" "" "" "0" "missing source file"
    return 0
  fi

  local source_audio_count
  local source_audio_peak
  source_audio_count="$(stream_count "$source" "a")"
  source_audio_peak="$(audio_peak_db "$source")"
  start="$(date +%s)"
  rm -f "$output" "$output.ffprobe.json" "$log_file"

  set +e
  if [[ "$mode" == "SW_HEVC" ]]; then
    ffmpeg \
      -hide_banner \
      -loglevel error \
      -y \
      -i "$source" \
      -map 0:v:0 \
      -map 0:a? \
      -c:v libx265 \
      -preset ultrafast \
      -crf "$SW_CRF" \
      -pix_fmt yuv420p \
      -tag:v hvc1 \
      -c:a aac \
      -b:a 160k \
      -movflags +faststart \
      "$output" >"$log_file" 2>&1
  else
    bitrate="$(bounded_hw_bitrate "$(video_bitrate "$source")")"
    ffmpeg \
      -hide_banner \
      -loglevel error \
      -y \
      -i "$source" \
      -map 0:v:0 \
      -map 0:a? \
      -c:v hevc_videotoolbox \
      -b:v "$bitrate" \
      -pix_fmt yuv420p \
      -tag:v hvc1 \
      -c:a aac \
      -b:a 160k \
      -movflags +faststart \
      "$output" >"$log_file" 2>&1
  fi
  local ffmpeg_status=$?
  set -e

  end="$(date +%s)"
  elapsed="$((end - start))"

  if (( ffmpeg_status != 0 )) || [[ ! -s "$output" ]]; then
    local message
    message="$(tail -n 1 "$log_file" 2>/dev/null | tr '\t' ' ' || true)"
    append_result "$name" "$mode" "FAIL" "$relative_file" "$output" "" "$source_audio_count" "" "FAIL" "$source_audio_peak" "" "$elapsed" "${message:-ffmpeg failed}"
    return 0
  fi

  write_probe "$output"
  local output_codec
  local output_audio_count
  local output_audio_peak
  local audio_status
  output_codec="$(video_codec "$output")"
  output_audio_count="$(stream_count "$output" "a")"
  output_audio_peak="$(audio_peak_db "$output")"
  if [[ "$source_audio_count" == "0" ]]; then
    audio_status="NO_SOURCE_AUDIO"
  elif ! audio_signal_passes "$source_audio_peak"; then
    audio_status="SOURCE_SIGNAL_FAIL"
  elif (( output_audio_count > 0 )) && audio_signal_passes "$output_audio_peak"; then
    audio_status="SIGNAL_PASS"
  elif (( output_audio_count > 0 )); then
    audio_status="OUTPUT_SIGNAL_FAIL"
  else
    audio_status="OUTPUT_AUDIO_MISSING"
  fi

  if [[ "$output_codec" == "hevc" && ( "$audio_status" == "SIGNAL_PASS" || "$audio_status" == "NO_SOURCE_AUDIO" ) ]]; then
    append_result "$name" "$mode" "PASS" "$relative_file" "$output" "$output_codec" "$source_audio_count" "$output_audio_count" "$audio_status" "$source_audio_peak" "$output_audio_peak" "$elapsed" "ok"
  else
    append_result "$name" "$mode" "FAIL" "$relative_file" "$output" "$output_codec" "$source_audio_count" "$output_audio_count" "$audio_status" "$source_audio_peak" "$output_audio_peak" "$elapsed" "output verification failed"
  fi
}

require_tool ffmpeg
require_tool ffprobe

if [[ ! -f "$MANIFEST" ]]; then
  echo "error: manifest not found: $MANIFEST" >&2
  exit 1
fi

mkdir -p "$LOG_DIR" "$OUTPUT_DIR"
printf "name\tmode\tstatus\tsource_file\toutput_file\toutput_video_codec\tsource_audio_streams\toutput_audio_streams\taudio_status\tsource_audio_peak_db\toutput_audio_peak_db\telapsed_seconds\tmessage\n" > "$RESULTS"

tail -n +2 "$MANIFEST" | while IFS=$'\t' read -r name file _video_encoder _audio_encoder; do
  [[ -z "${name:-}" ]] && continue
  echo "transcode: $name SW_HEVC"
  transcode_one "$name" "$file" "SW_HEVC"
  echo "transcode: $name HW_HEVC"
  transcode_one "$name" "$file" "HW_HEVC"
done

fail_count="$(awk -F '\t' 'NR > 1 && $3 == "FAIL" { count++ } END { print count + 0 }' "$RESULTS")"
pass_count="$(awk -F '\t' 'NR > 1 && $3 == "PASS" { count++ } END { print count + 0 }' "$RESULTS")"
skip_count="$(awk -F '\t' 'NR > 1 && $3 == "SKIP" { count++ } END { print count + 0 }' "$RESULTS")"

echo "done: $OUT_DIR"
echo "results: $RESULTS"
echo "pass: $pass_count"
echo "skip: $skip_count"
echo "fail: $fail_count"

if [[ "$STRICT" == "1" ]] && (( fail_count > 0 )); then
  exit 1
fi
