#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/Samples/CodecFixtures/generated"}"
DURATION="${TAPTION_FIXTURE_DURATION:-3}"
SIZE="${TAPTION_FIXTURE_SIZE:-640x360}"
FPS="${TAPTION_FIXTURE_FPS:-30}"

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
    -show_entries stream=index,codec_type,codec_name,width,height,pix_fmt,r_frame_rate,avg_frame_rate,duration,bit_rate \
    -show_entries format=filename,format_name,duration,size,bit_rate \
    -of json \
    "$file" > "$file.ffprobe.json"
}

append_manifest() {
  local name="$1"
  local file="$2"
  local video_encoder="$3"
  local audio_encoder="$4"
  local path
  path="$(python3 - "$OUT_DIR" "$file" <<'PY'
import os
import sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
)"
  printf "%s\t%s\t%s\t%s\n" "$name" "$path" "$video_encoder" "$audio_encoder" >> "$MANIFEST"
}

append_generation_result() {
  local name="$1"
  local file="$2"
  local video_encoder="$3"
  local audio_encoder="$4"
  local status="$5"
  local message="$6"
  local path=""
  if [[ -n "$file" ]]; then
    path="$(python3 - "$OUT_DIR" "$file" <<'PY'
import os
import sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
)"
  fi
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$name" "$path" "$video_encoder" "$audio_encoder" "$status" "$message" >> "$GENERATION_RESULTS"
}

generate_av_fixture() {
  local name="$1"
  local extension="$2"
  local video_encoder="$3"
  local audio_encoder="$4"
  shift 4

  local output="$OUT_DIR/$name.$extension"
  local log="$LOG_DIR/$name.log"
  : > "$log"

  if ! has_encoder "$video_encoder"; then
    echo "skip: $name missing video encoder $video_encoder"
    append_generation_result "$name" "$output" "$video_encoder" "$audio_encoder" "SKIP" "missing video encoder $video_encoder"
    return 0
  fi
  if [[ "$audio_encoder" != "none" ]] && ! has_encoder "$audio_encoder"; then
    echo "skip: $name missing audio encoder $audio_encoder"
    append_generation_result "$name" "$output" "$video_encoder" "$audio_encoder" "SKIP" "missing audio encoder $audio_encoder"
    return 0
  fi

  echo "generate: $output"

  local args=(
    -hide_banner
    -loglevel error
    -y
    -f lavfi -i "testsrc2=size=$SIZE:rate=$FPS"
    -f lavfi -i "sine=frequency=880:sample_rate=48000"
    -t "$DURATION"
    -map 0:v:0
  )

  if [[ "$audio_encoder" != "none" ]]; then
    args+=(-map 1:a:0)
  fi

  args+=("$@" "$output")
  if ! ffmpeg "${args[@]}" > "$log" 2>&1; then
    append_generation_result "$name" "$output" "$video_encoder" "$audio_encoder" "FAIL" "ffmpeg generation failed; see logs/$name.log"
    return 0
  fi
  if ! write_probe "$output" >> "$log" 2>&1; then
    append_generation_result "$name" "$output" "$video_encoder" "$audio_encoder" "FAIL" "ffprobe failed; see logs/$name.log"
    return 0
  fi
  append_manifest "$name" "$output" "$video_encoder" "$audio_encoder"
  append_generation_result "$name" "$output" "$video_encoder" "$audio_encoder" "PASS" "ok"
}

generate_dv_fixture() {
  local video_encoder="dvvideo"
  local output="$OUT_DIR/dv_ntsc_dv.dv"
  local log="$LOG_DIR/dv_ntsc_dv.log"
  : > "$log"

  if ! has_encoder "$video_encoder"; then
    echo "skip: dv_ntsc_dv missing video encoder $video_encoder"
    append_generation_result "dv_ntsc_dv" "$output" "$video_encoder" "pcm_s16le" "SKIP" "missing video encoder $video_encoder"
    return 0
  fi

  echo "generate: $output"
  if ! ffmpeg \
    -hide_banner \
    -loglevel error \
    -y \
    -f lavfi -i "testsrc2=size=720x480:rate=30000/1001" \
    -f lavfi -i "sine=frequency=880:sample_rate=48000" \
    -t "$DURATION" \
    -map 0:v:0 \
    -map 1:a:0 \
    -c:v dvvideo \
    -pix_fmt yuv411p \
    -c:a pcm_s16le \
    -ar 48000 \
    -ac 2 \
    -f dv \
    "$output" > "$log" 2>&1; then
    append_generation_result "dv_ntsc_dv" "$output" "$video_encoder" "pcm_s16le" "FAIL" "ffmpeg generation failed; see logs/dv_ntsc_dv.log"
    return 0
  fi
  if ! write_probe "$output" >> "$log" 2>&1; then
    append_generation_result "dv_ntsc_dv" "$output" "$video_encoder" "pcm_s16le" "FAIL" "ffprobe failed; see logs/dv_ntsc_dv.log"
    return 0
  fi
  append_manifest "dv_ntsc_dv" "$output" "$video_encoder" "pcm_s16le"
  append_generation_result "dv_ntsc_dv" "$output" "$video_encoder" "pcm_s16le" "PASS" "ok"
}

require_tool ffmpeg
require_tool ffprobe
require_tool python3

MANIFEST="$OUT_DIR/fixtures.tsv"
GENERATION_RESULTS="$OUT_DIR/video_fixture_generation.tsv"
{
  printf "name\tfile\tvideo_encoder\taudio_encoder\n"
} > "$MANIFEST"
{
  printf "name\tfile\tvideo_encoder\taudio_encoder\tstatus\tmessage\n"
} > "$GENERATION_RESULTS"

generate_av_fixture \
  "av1_mp4_svt_opus" "mp4" "libsvtav1" "libopus" \
  -c:v libsvtav1 -preset 12 -crf 35 -pix_fmt yuv420p \
  -c:a libopus -b:a 96k -movflags +faststart

generate_av_fixture \
  "av1_webm_svt_opus" "webm" "libsvtav1" "libopus" \
  -c:v libsvtav1 -preset 12 -crf 35 -pix_fmt yuv420p \
  -c:a libopus -b:a 96k

generate_av_fixture \
  "av1_mkv_svt_opus" "mkv" "libsvtav1" "libopus" \
  -c:v libsvtav1 -preset 12 -crf 35 -pix_fmt yuv420p \
  -c:a libopus -b:a 96k

generate_av_fixture \
  "h264_mp4_x264_aac" "mp4" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -movflags +faststart

generate_av_fixture \
  "h264_mp4_videotoolbox_aac" "mp4" "h264_videotoolbox" "aac" \
  -c:v h264_videotoolbox -b:v 1800k -pix_fmt yuv420p \
  -c:a aac -b:a 128k -movflags +faststart

generate_av_fixture \
  "h264_mov_x264_pcm" "mov" "libx264" "pcm_s16le" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "h264_m4v_x264_aac" "m4v" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -movflags +faststart

generate_av_fixture \
  "h264_mkv_x264_flac" "mkv" "libx264" "flac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a flac -ar 48000 -ac 2

generate_av_fixture \
  "h264_mkv_x264_vorbis" "mkv" "libx264" "vorbis" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a vorbis -strict -2 -q:a 4 -ac 2

generate_av_fixture \
  "h264_mp4_x264_ac3" "mp4" "libx264" "ac3" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a ac3 -b:a 192k -movflags +faststart

generate_av_fixture \
  "h264_mp4_x264_eac3" "mp4" "libx264" "eac3" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a eac3 -b:a 192k -movflags +faststart

generate_av_fixture \
  "h264_ts_x264_aac" "ts" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -f mpegts

generate_av_fixture \
  "h264_tp_x264_aac" "tp" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -f mpegts

generate_av_fixture \
  "h264_trp_x264_aac" "trp" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -f mpegts

generate_av_fixture \
  "h264_tod_x264_aac" "tod" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -f mpegts

generate_av_fixture \
  "h264_m2ts_x264_aac" "m2ts" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -f mpegts

generate_av_fixture \
  "dji_style_lrf_h264_aac" "lrf" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 24 -pix_fmt yuv420p \
  -c:a aac -b:a 96k -f mp4 -movflags +faststart

generate_av_fixture \
  "hevc_mp4_x265_aac" "mp4" "libx265" "aac" \
  -c:v libx265 -preset ultrafast -x265-params log-level=error -crf 28 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -movflags +faststart

generate_av_fixture \
  "hevc_mp4_videotoolbox_aac" "mp4" "hevc_videotoolbox" "aac" \
  -c:v hevc_videotoolbox -b:v 1600k -pix_fmt yuv420p \
  -c:a aac -b:a 128k -movflags +faststart

generate_av_fixture \
  "hevc_mov_x265_alac" "mov" "libx265" "alac" \
  -c:v libx265 -preset ultrafast -x265-params log-level=error -crf 28 -pix_fmt yuv420p \
  -c:a alac -ar 48000 -ac 2

generate_av_fixture \
  "h264_qt_x264_pcm" "qt" "libx264" "pcm_s16le" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a pcm_s16le -ar 48000 -ac 2 -f mov

generate_av_fixture \
  "vp9_webm_vpx_opus" "webm" "libvpx-vp9" "libopus" \
  -c:v libvpx-vp9 -deadline good -cpu-used 4 -b:v 0 -crf 36 -pix_fmt yuv420p \
  -c:a libopus -b:a 96k

generate_av_fixture \
  "vp8_webm_vpx_opus" "webm" "libvpx" "libopus" \
  -c:v libvpx -deadline good -cpu-used 4 -b:v 1000k -pix_fmt yuv420p \
  -c:a libopus -b:a 96k

generate_av_fixture \
  "prores_mov_ks_pcm" "mov" "prores_ks" "pcm_s16le" \
  -c:v prores_ks -profile:v 1 -pix_fmt yuv422p10le \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "prores_mov_ks_alac" "mov" "prores_ks" "alac" \
  -c:v prores_ks -profile:v 1 -pix_fmt yuv422p10le \
  -c:a alac -ar 48000 -ac 2

generate_av_fixture \
  "ffv1_mkv_flac" "mkv" "ffv1" "flac" \
  -c:v ffv1 -level 3 -pix_fmt yuv420p \
  -c:a flac -ar 48000 -ac 2

generate_av_fixture \
  "huffyuv_avi_pcm" "avi" "huffyuv" "pcm_s16le" \
  -c:v huffyuv -pix_fmt yuv422p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "ffvhuff_avi_pcm" "avi" "ffvhuff" "pcm_s16le" \
  -c:v ffvhuff -pix_fmt yuv420p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "utvideo_avi_pcm" "avi" "utvideo" "pcm_s16le" \
  -c:v utvideo -pix_fmt yuv420p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "magicyuv_avi_pcm" "avi" "magicyuv" "pcm_s16le" \
  -c:v magicyuv -pix_fmt yuv420p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "cineform_mov_pcm" "mov" "cfhd" "pcm_s16le" \
  -vf scale=1280:720 -c:v cfhd -pix_fmt yuv422p10le \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "dnxhr_mov_pcm" "mov" "dnxhd" "pcm_s16le" \
  -vf scale=1280:720 -r 24000/1001 -c:v dnxhd -profile:v dnxhr_lb -pix_fmt yuv422p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "png_mov_pcm" "mov" "png" "pcm_s16le" \
  -c:v png -pix_fmt rgb24 \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "r10k_mov_pcm" "mov" "r10k" "pcm_s16le" \
  -c:v r10k -pix_fmt gbrp10le \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "v210_mov_pcm" "mov" "v210" "pcm_s16le" \
  -c:v v210 -pix_fmt yuv422p10le \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "msrle_mov_pcm" "mov" "msrle" "pcm_s16le" \
  -c:v msrle -pix_fmt rgb24 \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "smc_mov_pcm" "mov" "smc" "pcm_s16le" \
  -c:v smc -pix_fmt rgb24 \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "v308_mov_pcm" "mov" "v308" "pcm_s16le" \
  -c:v v308 -pix_fmt yuv444p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "v408_mov_pcm" "mov" "v408" "pcm_s16le" \
  -c:v v408 -pix_fmt yuva444p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "yuv4_mov_pcm" "mov" "yuv4" "pcm_s16le" \
  -c:v yuv4 -pix_fmt yuv420p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "mpeg1_mpg_mp2" "mpg" "mpeg1video" "mp2" \
  -vf scale=352:288 -r 25 -c:v mpeg1video -b:v 1400k -pix_fmt yuv420p \
  -c:a mp2 -b:a 128k

generate_av_fixture \
  "mpeg1_dat_mp2" "dat" "mpeg1video" "mp2" \
  -vf scale=352:288 -r 25 -c:v mpeg1video -b:v 1150k -pix_fmt yuv420p \
  -c:a mp2 -b:a 224k -f vcd

generate_av_fixture \
  "mpeg2_mpg_mp2" "mpg" "mpeg2video" "mp2" \
  -vf scale=352:288 -r 25 -c:v mpeg2video -b:v 1800k -pix_fmt yuv420p \
  -c:a mp2 -b:a 128k

generate_av_fixture \
  "mpeg2_mod_mp2" "mod" "mpeg2video" "mp2" \
  -vf scale=352:288 -r 25 -c:v mpeg2video -b:v 1800k -pix_fmt yuv420p \
  -c:a mp2 -b:a 128k -f vob

generate_av_fixture \
  "mpeg2_vob_mp2" "vob" "mpeg2video" "mp2" \
  -vf scale=352:288 -r 25 -c:v mpeg2video -b:v 1800k -pix_fmt yuv420p \
  -c:a mp2 -b:a 128k -f vob

generate_av_fixture \
  "mpeg2_mxf_pcm" "mxf" "mpeg2video" "pcm_s16le" \
  -vf scale=720:480 -r 30000/1001 -c:v mpeg2video -b:v 5000k -pix_fmt yuv422p \
  -c:a pcm_s16le -ar 48000 -ac 2 -f mxf

generate_av_fixture \
  "mpeg4_avi_mp3" "avi" "mpeg4" "libmp3lame" \
  -c:v mpeg4 -q:v 5 -pix_fmt yuv420p \
  -c:a libmp3lame -b:a 128k

generate_av_fixture \
  "mpeg4_divx_mp3" "divx" "mpeg4" "libmp3lame" \
  -c:v mpeg4 -q:v 5 -pix_fmt yuv420p \
  -c:a libmp3lame -b:a 128k -f avi

generate_av_fixture \
  "h264_flv_x264_aac" "flv" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -f flv

generate_av_fixture \
  "h264_f4v_x264_aac" "f4v" "libx264" "aac" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -f flv

generate_av_fixture \
  "h263_3gp_aac" "3gp" "h263" "aac" \
  -vf scale=352:288 -c:v h263 -b:v 600k -pix_fmt yuv420p \
  -c:a aac -b:a 96k

generate_av_fixture \
  "h263_3g2_aac" "3g2" "h263" "aac" \
  -vf scale=352:288 -c:v h263 -b:v 600k -pix_fmt yuv420p \
  -c:a aac -b:a 96k

generate_av_fixture \
  "mjpeg_avi_pcm" "avi" "mjpeg" "pcm_s16le" \
  -c:v mjpeg -q:v 5 -pix_fmt yuvj420p \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "qtrle_mov_pcm" "mov" "qtrle" "pcm_s16le" \
  -c:v qtrle -pix_fmt argb \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "cinepak_mov_pcm" "mov" "cinepak" "pcm_s16le" \
  -vf scale=160:92 -c:v cinepak -q:v 6 \
  -c:a pcm_s16le -ar 48000 -ac 2

generate_av_fixture \
  "wmv2_asf_wmav2" "wmv" "wmv2" "wmav2" \
  -c:v wmv2 -b:v 1200k \
  -c:a wmav2 -b:a 128k

generate_av_fixture \
  "wmv2_asf_wmav2_container" "asf" "wmv2" "wmav2" \
  -c:v wmv2 -b:v 1200k \
  -c:a wmav2 -b:a 128k -f asf

generate_av_fixture \
  "wmv2_dvrms_wmav2" "dvr-ms" "wmv2" "wmav2" \
  -c:v wmv2 -b:v 1200k \
  -c:a wmav2 -b:a 128k -f asf

generate_av_fixture \
  "h264_raw_elementary" "h264" "libx264" "none" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -an -f h264

generate_av_fixture \
  "av1_obu_elementary" "av1" "libsvtav1" "none" \
  -c:v libsvtav1 -preset 12 -crf 35 -pix_fmt yuv420p \
  -an -f obu

generate_av_fixture \
  "h263_raw_elementary" "h263" "h263" "none" \
  -vf scale=352:288 -c:v h263 -b:v 600k -pix_fmt yuv420p \
  -an -f h263

generate_av_fixture \
  "mpeg1_raw_m1v" "m1v" "mpeg1video" "none" \
  -vf scale=352:288 -r 25 -c:v mpeg1video -b:v 1400k -pix_fmt yuv420p \
  -an -f mpeg1video

generate_av_fixture \
  "mpeg2_raw_m2v" "m2v" "mpeg2video" "none" \
  -vf scale=352:288 -r 25 -c:v mpeg2video -b:v 1800k -pix_fmt yuv420p \
  -an -f mpeg2video

generate_av_fixture \
  "vp8_ogm_vorbis" "ogm" "libvpx" "vorbis" \
  -c:v libvpx -deadline good -cpu-used 4 -b:v 1000k -pix_fmt yuv420p \
  -c:a vorbis -strict -2 -ac 2 -f ogg

generate_av_fixture \
  "realvideo_rm_rv20_ac3" "rm" "rv20" "ac3" \
  -vf scale=320:240 -r 15 -c:v rv20 -b:v 600k \
  -c:a ac3 -b:a 96k -f rm

generate_av_fixture \
  "roq_video_game" "roq" "roqvideo" "none" \
  -vf scale=320:240 -r 15 -c:v roqvideo \
  -an -f roq

generate_av_fixture \
  "rawvideo_yuv_elementary" "y4m" "rawvideo" "none" \
  -c:v rawvideo -pix_fmt yuv420p \
  -an -f yuv4mpegpipe

generate_av_fixture \
  "h264_nut_x264_pcm" "nut" "libx264" "pcm_s16le" \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  -c:a pcm_s16le -ar 48000 -ac 2 -f nut

append_generation_result \
  "vc1_raw_elementary" \
  "$OUT_DIR/vc1_raw_elementary.vc1" \
  "vc1" \
  "none" \
  "SKIP" \
  "local FFmpeg can mux VC-1 but has no VC-1 encoder; use a real-world VC-1 elementary sample"

if has_encoder libtheora && has_encoder libvorbis; then
  generate_av_fixture \
    "theora_ogv_vorbis" "ogv" "libtheora" "libvorbis" \
    -c:v libtheora -q:v 6 -pix_fmt yuv420p \
    -c:a libvorbis -q:a 4
else
  echo "skip: theora_ogv_vorbis missing libtheora or libvorbis"
  append_generation_result \
    "theora_ogv_vorbis" \
    "$OUT_DIR/theora_ogv_vorbis.ogv" \
    "libtheora" \
    "libvorbis" \
    "SKIP" \
    "missing libtheora or libvorbis"
fi

generate_dv_fixture

echo "done: $OUT_DIR"
echo "manifest: $MANIFEST"
echo "generation: $GENERATION_RESULTS"
