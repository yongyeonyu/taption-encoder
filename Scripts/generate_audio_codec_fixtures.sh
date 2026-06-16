#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/Samples/CodecFixtures/audio_generated"}"
DURATION="${TAPTION_AUDIO_FIXTURE_DURATION:-2}"
SIZE="${TAPTION_AUDIO_FIXTURE_SIZE:-320x180}"
FPS="${TAPTION_AUDIO_FIXTURE_FPS:-15}"
MANIFEST="$OUT_DIR/fixtures.tsv"
GENERATION_RESULTS="$OUT_DIR/audio_fixture_generation.tsv"
LOG_DIR="$OUT_DIR/logs"

mkdir -p "$OUT_DIR" "$LOG_DIR"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: $1 is required" >&2
    exit 1
  fi
}

has_encoder() {
  ffmpeg -hide_banner -encoders 2>/dev/null | awk '{print $2}' | grep -qx "$1"
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

relative_to_output_dir() {
  python3 - "$OUT_DIR" "$1" <<'PY'
import os
import sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
}

append_manifest() {
  local name="$1"
  local file="$2"
  local video_encoder="$3"
  local audio_encoder="$4"
  local path
  path="$(relative_to_output_dir "$file")"
  printf "%s\t%s\t%s\t%s\n" "$name" "$path" "$video_encoder" "$audio_encoder" >> "$MANIFEST"
}

append_generation_result() {
  local name="$1"
  local file="$2"
  local target_audio_codec="$3"
  local audio_encoder="$4"
  local status="$5"
  local message="$6"
  local path=""
  if [[ -n "$file" && -f "$file" ]]; then
    path="$(relative_to_output_dir "$file")"
  fi
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$name" \
    "$path" \
    "$target_audio_codec" \
    "$audio_encoder" \
    "$status" \
    "$message" >> "$GENERATION_RESULTS"
}

generate_audio_fixture() {
  local name="$1"
  local extension="$2"
  local target_audio_codec="$3"
  local video_encoder="$4"
  local audio_encoder="$5"
  local sample_rate="$6"
  local channels="$7"
  shift 7

  local output="$OUT_DIR/$name.$extension"
  local log_file="$LOG_DIR/$name.log"

  if ! has_encoder "$video_encoder"; then
    echo "skip: $name missing video encoder $video_encoder"
    append_generation_result "$name" "" "$target_audio_codec" "$audio_encoder" "SKIP" "missing video encoder $video_encoder"
    return 0
  fi
  if ! has_encoder "$audio_encoder"; then
    echo "skip: $name missing audio encoder $audio_encoder"
    append_generation_result "$name" "" "$target_audio_codec" "$audio_encoder" "SKIP" "missing audio encoder $audio_encoder"
    return 0
  fi

  echo "generate: $output"
  rm -f "$output" "$output.ffprobe.json" "$log_file"

  set +e
  ffmpeg \
    -hide_banner \
    -loglevel error \
    -y \
    -f lavfi -i "testsrc2=size=$SIZE:rate=$FPS" \
    -f lavfi -i "sine=frequency=880:sample_rate=$sample_rate" \
    -t "$DURATION" \
    -map 0:v:0 \
    -map 1:a:0 \
    "$@" \
    "$output" >"$log_file" 2>&1
  local ffmpeg_status=$?
  set -e

  if (( ffmpeg_status != 0 )) || [[ ! -s "$output" ]]; then
    local message
    message="$(tail -n 1 "$log_file" 2>/dev/null | tr '\t' ' ' || true)"
    echo "fail: $name ${message:-ffmpeg failed}"
    append_generation_result "$name" "" "$target_audio_codec" "$audio_encoder" "FAIL" "${message:-ffmpeg failed}"
    rm -f "$output"
    return 0
  fi

  write_probe "$output"
  append_manifest "$name" "$output" "$video_encoder" "$audio_encoder"
  append_generation_result "$name" "$output" "$target_audio_codec" "$audio_encoder" "PASS" "ok"
}

generate_audio_fixture_with_afconvert_attempt() {
  local name="$1"
  local extension="$2"
  local target_audio_codec="$3"
  local video_encoder="$4"
  local audio_encoder="$5"
  local sample_rate="$6"
  local channels="$7"
  local afconvert_file_format="$8"
  local afconvert_data_format="$9"
  local afconvert_bitrate="${10}"
  shift 10

  if has_encoder "$audio_encoder"; then
    generate_audio_fixture \
      "$name" \
      "$extension" \
      "$target_audio_codec" \
      "$video_encoder" \
      "$audio_encoder" \
      "$sample_rate" \
      "$channels" \
      "$@"
    return 0
  fi

  local source_pcm="$LOG_DIR/${name}_afconvert_source.wav"
  local alternate_audio="$OUT_DIR/${name}_afconvert_audio.$extension"
  local log_file="$LOG_DIR/$name.log"
  local fallback_message="missing audio encoder $audio_encoder"

  rm -f "$source_pcm" "$alternate_audio" "$log_file"

  if command -v afconvert >/dev/null 2>&1; then
    ffmpeg \
      -hide_banner \
      -loglevel error \
      -y \
      -f lavfi -i "sine=frequency=880:sample_rate=$sample_rate" \
      -t "$DURATION" \
      -ac "$channels" \
      -c:a pcm_s16le \
      "$source_pcm" >>"$log_file" 2>&1 || true

    set +e
    afconvert \
      "$source_pcm" \
      "$alternate_audio" \
      -f "$afconvert_file_format" \
      -d "$afconvert_data_format" \
      -b "$afconvert_bitrate" \
      -c "$channels" >>"$log_file" 2>&1
    local afconvert_status=$?
    set -e

    if (( afconvert_status == 0 )) && [[ -s "$alternate_audio" ]]; then
      append_generation_result \
        "$name" \
        "$alternate_audio" \
        "$target_audio_codec" \
        "$audio_encoder" \
        "PASS" \
        "afconvert alternate generated audio; promote this codec from pending and add video mux coverage"
      echo "generate: $alternate_audio via afconvert alternate"
      return 0
    fi

    local afconvert_error
    afconvert_error="$(tail -n 1 "$log_file" 2>/dev/null | tr '\t' ' ' || true)"
    fallback_message="$fallback_message; afconvert alternate failed: ${afconvert_error:-unknown error}"
  else
    fallback_message="$fallback_message; afconvert alternate unavailable"
  fi

  echo "skip: $name $fallback_message"
  append_generation_result \
    "$name" \
    "" \
    "$target_audio_codec" \
    "$audio_encoder" \
    "SKIP" \
    "$fallback_message"
}

require_tool ffmpeg
require_tool ffprobe
require_tool python3

printf "name\tfile\tvideo_encoder\taudio_encoder\n" > "$MANIFEST"
printf "name\tfile\ttarget_audio_codec\taudio_encoder\tstatus\tmessage\n" > "$GENERATION_RESULTS"

generate_audio_fixture \
  "audio_aac_mp4" "mp4" "aac" "libx264" "aac" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ar 48000 -ac 2 -movflags +faststart

generate_audio_fixture_with_afconvert_attempt \
  "audio_xhe_aac_unavailable" "mp4" "xheAAC" "libx264" "xhe_aac" "48000" "2" \
  "mp4f" "usac" "48000" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a xhe_aac -b:a 128k -ar 48000 -ac 2 -movflags +faststart

generate_audio_fixture \
  "audio_pcm_s16le_mov" "mov" "pcm" "libx264" "pcm_s16le" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_audio_fixture \
  "audio_pcm_s24le_mov" "mov" "pcm" "libx264" "pcm_s24le" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a pcm_s24le -ar 48000 -ac 2

generate_audio_fixture \
  "audio_pcm_f32le_mov" "mov" "pcm" "libx264" "pcm_f32le" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a pcm_f32le -ar 48000 -ac 2

generate_audio_fixture \
  "audio_alaw_avi" "avi" "aLaw" "mpeg4" "pcm_alaw" "8000" "1" \
  -c:v mpeg4 -q:v 5 -pix_fmt yuv420p \
  -c:a pcm_alaw -ar 8000 -ac 1

generate_audio_fixture \
  "audio_mulaw_avi" "avi" "muLaw" "mpeg4" "pcm_mulaw" "8000" "1" \
  -c:v mpeg4 -q:v 5 -pix_fmt yuv420p \
  -c:a pcm_mulaw -ar 8000 -ac 1

generate_audio_fixture \
  "audio_alac_mov" "mov" "alac" "libx264" "alac" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a alac -ar 48000 -ac 2

generate_audio_fixture \
  "audio_opus_webm" "webm" "opus" "libvpx-vp9" "libopus" "48000" "2" \
  -c:v libvpx-vp9 -deadline good -cpu-used 4 -b:v 0 -crf 36 -pix_fmt yuv420p \
  -c:a libopus -b:a 96k -ar 48000 -ac 2

generate_audio_fixture \
  "audio_opus_mkv" "mkv" "opus" "libx264" "libopus" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a libopus -b:a 96k -ar 48000 -ac 2

generate_audio_fixture \
  "audio_mp3_avi" "avi" "mp3" "mpeg4" "libmp3lame" "48000" "2" \
  -c:v mpeg4 -q:v 5 -pix_fmt yuv420p \
  -c:a libmp3lame -b:a 128k -ar 48000 -ac 2

generate_audio_fixture \
  "audio_mp2_mpg" "mpg" "mp2" "mpeg2video" "mp2" "48000" "2" \
  -vf scale=352:288 -r 25 -c:v mpeg2video -b:v 1600k -pix_fmt yuv420p \
  -c:a mp2 -b:a 128k -ar 48000 -ac 2

generate_audio_fixture \
  "audio_ac3_mp4" "mp4" "ac3" "libx264" "ac3" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a ac3 -b:a 192k -ar 48000 -ac 2 -movflags +faststart

generate_audio_fixture \
  "audio_eac3_mp4" "mp4" "eac3" "libx264" "eac3" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a eac3 -b:a 192k -ar 48000 -ac 2 -movflags +faststart

generate_audio_fixture \
  "audio_dts_mkv" "mkv" "dts" "libx264" "dca" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -strict -2 -c:a dca -b:a 768k -ar 48000 -ac 2

generate_audio_fixture \
  "audio_truehd_mkv" "mkv" "trueHD" "libx264" "truehd" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -strict -2 -c:a truehd -ar 48000 -ac 2

generate_audio_fixture \
  "audio_flac_mkv" "mkv" "flac" "libx264" "flac" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a flac -ar 48000 -ac 2

generate_audio_fixture \
  "audio_vorbis_mkv" "mkv" "vorbis" "libx264" "vorbis" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -strict -2 -c:a vorbis -q:a 4 -ar 48000 -ac 2

generate_audio_fixture_with_afconvert_attempt \
  "audio_amr_nb_3gp" "3gp" "amr" "h263" "libopencore_amrnb" "8000" "1" \
  "3gpp" "samr" "12200" \
  -vf scale=352:288 -c:v h263 -b:v 500k -pix_fmt yuv420p \
  -c:a libopencore_amrnb -ar 8000 -ac 1

generate_audio_fixture_with_afconvert_attempt \
  "audio_amr_wb_3gp" "3gp" "amr" "h263" "libvo_amrwbenc" "16000" "1" \
  "3gpp" "sawb" "23850" \
  -vf scale=352:288 -c:v h263 -b:v 500k -pix_fmt yuv420p \
  -c:a libvo_amrwbenc -ar 16000 -ac 1

generate_audio_fixture \
  "audio_ilbc_mov" "mov" "ilbc" "libx264" "ilbc_at" "8000" "1" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a ilbc_at -ar 8000 -ac 1

generate_audio_fixture \
  "audio_g722_mkv" "mkv" "g722" "libx264" "g722" "16000" "1" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a g722 -ar 16000 -ac 1

generate_audio_fixture \
  "audio_g723_mkv" "mkv" "g723" "libx264" "g723_1" "8000" "1" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a g723_1 -b:a 6300 -ar 8000 -ac 1

generate_audio_fixture \
  "audio_g726_mkv" "mkv" "g726" "libx264" "g726" "8000" "1" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a g726 -b:a 32k -ar 8000 -ac 1

generate_audio_fixture \
  "audio_mlp_mkv" "mkv" "mlp" "libx264" "mlp" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -strict -2 -c:a mlp -ar 48000 -ac 2

generate_audio_fixture \
  "audio_tta_mkv" "mkv" "tta" "libx264" "tta" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a tta -ar 48000 -ac 2

generate_audio_fixture \
  "audio_nellymoser_flv" "flv" "nellymoser" "flv" "nellymoser" "8000" "1" \
  -c:v flv -b:v 600k \
  -c:a nellymoser -ar 8000 -ac 1

generate_audio_fixture \
  "audio_real144_mkv" "mkv" "realAudio" "libx264" "real_144" "8000" "1" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a real_144 -ar 8000 -ac 1

generate_audio_fixture \
  "audio_roq_dpcm_roq" "roq" "roqDPCM" "roqvideo" "roq_dpcm" "22050" "1" \
  -vf scale=160:96 -c:v roqvideo -pix_fmt yuvj444p \
  -c:a roq_dpcm -ar 22050 -ac 1

generate_audio_fixture \
  "audio_wavpack_mkv" "mkv" "wavPack" "libx264" "wavpack" "48000" "2" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p \
  -c:a wavpack -ar 48000 -ac 2

generate_audio_fixture \
  "audio_wmav2_wmv" "wmv" "wma" "wmv2" "wmav2" "48000" "2" \
  -c:v wmv2 -b:v 1000k \
  -c:a wmav2 -b:a 128k -ar 48000 -ac 2

generate_audio_fixture \
  "audio_adpcm_ima_wav_avi" "avi" "adpcm" "mpeg4" "adpcm_ima_wav" "22050" "1" \
  -c:v mpeg4 -q:v 5 -pix_fmt yuv420p \
  -c:a adpcm_ima_wav -ar 22050 -ac 1

generate_audio_fixture \
  "audio_adpcm_ms_avi" "avi" "adpcm" "mpeg4" "adpcm_ms" "22050" "1" \
  -c:v mpeg4 -q:v 5 -pix_fmt yuv420p \
  -c:a adpcm_ms -ar 22050 -ac 1

pass_count="$(awk -F '\t' 'NR > 1 && $5 == "PASS" { count++ } END { print count + 0 }' "$GENERATION_RESULTS")"
skip_count="$(awk -F '\t' 'NR > 1 && $5 == "SKIP" { count++ } END { print count + 0 }' "$GENERATION_RESULTS")"
fail_count="$(awk -F '\t' 'NR > 1 && $5 == "FAIL" { count++ } END { print count + 0 }' "$GENERATION_RESULTS")"

echo "done: $OUT_DIR"
echo "manifest: $MANIFEST"
echo "generation: $GENERATION_RESULTS"
echo "pass: $pass_count"
echo "skip: $skip_count"
echo "fail: $fail_count"
