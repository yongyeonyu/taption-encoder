#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_VIDEO_DIR="${1:-"$ROOT_DIR/TaptionEncoder/TestVideos"}"
EXPECTED_VIDEO_COUNT=57
MIN_SECONDS=4.85
MAX_SECONDS=5.15
SIZE_LIMIT_BYTES=1000000
SIZE_EXCEPTIONS=("DV.dv" "DVCPro.mov" "DVCPro HD.mov")

if [[ ! -d "$TEST_VIDEO_DIR" ]]; then
  echo "error: bundled test video directory not found: $TEST_VIDEO_DIR" >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "error: ffprobe is required for bundled test video verification" >&2
  exit 1
fi

python3 - "$TEST_VIDEO_DIR" "$EXPECTED_VIDEO_COUNT" "$MIN_SECONDS" "$MAX_SECONDS" "$SIZE_LIMIT_BYTES" "${SIZE_EXCEPTIONS[@]}" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

test_video_dir = Path(sys.argv[1])
expected_count = int(sys.argv[2])
min_seconds = float(sys.argv[3])
max_seconds = float(sys.argv[4])
size_limit = int(sys.argv[5])
size_exceptions = set(sys.argv[6:])
audio_exceptions = {"H.261.h261", "RoQ Video.roq"}

failures = []
large_exceptions = []
verified_rows = []

video_files = sorted(
    path for path in test_video_dir.iterdir()
    if path.is_file() and path.name != "SAMPLE_SOURCES.txt" and not path.name.startswith(".")
)

if len(video_files) != expected_count:
    failures.append(f"expected {expected_count} video samples, found {len(video_files)}")

def parse_rate(rate):
    if not rate or rate == "0/0":
        return None
    if "/" in rate:
        numerator, denominator = rate.split("/", 1)
        try:
            numerator_value = float(numerator)
            denominator_value = float(denominator)
        except ValueError:
            return None
        if denominator_value == 0:
            return None
        return numerator_value / denominator_value
    try:
        return float(rate)
    except ValueError:
        return None

def parse_duration(value):
    if value is None or value == "N/A":
        return None
    try:
        duration = float(value)
    except (TypeError, ValueError):
        return None
    return duration if duration > 0 else None

for path in video_files:
    probe = subprocess.run(
        [
            "ffprobe",
            "-v", "error",
            "-count_frames",
            "-show_entries", "format=duration,size,format_name",
            "-show_entries", "stream=index,codec_type,codec_name,codec_tag_string,width,height,avg_frame_rate,r_frame_rate,duration,nb_frames,nb_read_frames",
            "-of", "json",
            str(path),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    if probe.returncode != 0 or not probe.stdout.strip():
        failures.append(f"{path.name}: ffprobe failed: {(probe.stderr or probe.stdout).strip()}")
        continue

    data = json.loads(probe.stdout)
    streams = data.get("streams", [])
    video_stream = next(
        (stream for stream in streams if stream.get("codec_type") == "video" and stream.get("codec_name") != "unknown"),
        None,
    )
    if video_stream is None:
        failures.append(f"{path.name}: no readable video stream")
        continue

    audio_stream = next(
        (stream for stream in streams if stream.get("codec_type") == "audio" and stream.get("codec_name") != "unknown"),
        None,
    )
    if audio_stream is None and path.name not in audio_exceptions:
        failures.append(f"{path.name}: no readable audio stream")

    format_info = data.get("format", {})
    duration = parse_duration(format_info.get("duration")) or parse_duration(video_stream.get("duration"))
    fps = parse_rate(video_stream.get("avg_frame_rate")) or parse_rate(video_stream.get("r_frame_rate"))
    frame_value = video_stream.get("nb_read_frames") or video_stream.get("nb_frames")
    try:
        frame_count = int(frame_value) if frame_value and frame_value != "N/A" else None
    except ValueError:
        frame_count = None
    inferred_duration = (frame_count / fps) if duration is None and fps and frame_count else None
    effective_duration = duration if duration is not None else inferred_duration

    if effective_duration is None or not (min_seconds <= effective_duration <= max_seconds):
        failures.append(
            f"{path.name}: duration {duration} inferred {inferred_duration} is outside {min_seconds}-{max_seconds}s"
        )

    size = path.stat().st_size
    if size > size_limit:
        if path.name in size_exceptions:
            large_exceptions.append(f"{path.name}={size}")
        else:
            failures.append(f"{path.name}: size {size} exceeds {size_limit} bytes")

    verified_rows.append((
        path.name,
        video_stream.get("codec_name", "unknown"),
        audio_stream.get("codec_name", "none") if audio_stream else "none",
        duration,
        inferred_duration,
        size
    ))

if failures:
    print("bundled test video verification failed:", file=sys.stderr)
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    sys.exit(1)

print("bundled test videos verified")
print(f"video samples: {len(video_files)}")
print(f"target duration: {min_seconds}-{max_seconds}s")
if large_exceptions:
    print("size exceptions: " + ", ".join(large_exceptions))
else:
    print("size exceptions: none")
print("audio exceptions: " + ", ".join(sorted(audio_exceptions)))
print("verified rows:")
for name, codec, audio_codec, duration, inferred_duration, size in verified_rows:
    duration_text = f"{duration:.3f}s" if duration is not None else f"inferred {inferred_duration:.3f}s"
    print(f"- {name}: {codec}, audio={audio_codec}, {duration_text}, {size} bytes")
PY
