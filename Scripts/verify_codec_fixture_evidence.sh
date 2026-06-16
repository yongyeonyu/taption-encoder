#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_MANIFEST="${1:-"$ROOT_DIR/Samples/CodecFixtures/generated/fixtures.tsv"}"
TRANSCODE_RESULTS="${2:-"$ROOT_DIR/Samples/CodecFixtures/transcode_reports/smoke_latest/transcode_results.tsv"}"
REQUIRED_MODES=("SW_HEVC" "HW_HEVC")

if [[ ! -f "$FIXTURE_MANIFEST" ]]; then
  echo "error: fixture manifest not found: $FIXTURE_MANIFEST" >&2
  exit 1
fi

if [[ ! -f "$TRANSCODE_RESULTS" ]]; then
  echo "error: transcode results not found: $TRANSCODE_RESULTS" >&2
  exit 1
fi

awk -F '\t' -v required_modes="${REQUIRED_MODES[*]}" '
BEGIN {
  mode_count = split(required_modes, modes, " ")
}

FNR == NR && FNR == 1 {
  next
}

FNR == NR {
  if ($1 == "") {
    next
  }
  fixture[$1] = $0
  fixture_count++
  next
}

FNR == 1 {
  for (i = 1; i <= NF; i++) {
    result_col[$i] = i
  }
  required_cols = "name mode status output_video_codec source_audio_streams output_audio_streams audio_status message"
  split(required_cols, cols, " ")
  for (i in cols) {
    if (!(cols[i] in result_col)) {
      failures[++failure_count] = "missing results column " cols[i]
    }
  }
  next
}

{
  name = $result_col["name"]
  mode = $result_col["mode"]
  if (name == "" || mode == "") {
    next
  }
  result_fixture[name] = 1
  key = name SUBSEP mode
  result_seen[key] = 1
  result_status[key] = $result_col["status"]
  result_codec[key] = $result_col["output_video_codec"]
  result_source_audio[key] = $result_col["source_audio_streams"]
  result_output_audio[key] = $result_col["output_audio_streams"]
  result_audio_status[key] = $result_col["audio_status"]
  result_message[key] = $result_col["message"]
}

END {
  if (fixture_count == 0) {
    failures[++failure_count] = "fixture manifest has no rows"
  }

  for (name in result_fixture) {
    if (!(name in fixture)) {
      fixture[name] = "result-only"
      fixture_count++
    }
  }

  for (name in fixture) {
    for (i = 1; i <= mode_count; i++) {
      mode = modes[i]
      key = name SUBSEP mode
      if (!(key in result_seen)) {
        failures[++failure_count] = name " " mode " missing result"
        continue
      }
      if (result_status[key] != "PASS") {
        failures[++failure_count] = name " " mode " status " result_status[key] " message=" result_message[key]
      }
      if (result_codec[key] != "hevc") {
        failures[++failure_count] = name " " mode " output codec " result_codec[key] " is not hevc"
      }
      if (result_source_audio[key] + 0 > 0) {
        if (result_output_audio[key] + 0 <= 0) {
          failures[++failure_count] = name " " mode " lost audio output stream"
        }
        if (result_audio_status[key] != "SIGNAL_PASS") {
          failures[++failure_count] = name " " mode " audio status " result_audio_status[key]
        }
      }
      passed_results++
    }
  }

  if (failure_count > 0) {
    print "fixture evidence verification failed:" > "/dev/stderr"
    for (i = 1; i <= failure_count; i++) {
      print "- " failures[i] > "/dev/stderr"
    }
    exit 1
  }

  print "fixture evidence verified"
  print "fixtures: " fixture_count
  print "required modes per fixture: " mode_count
  print "verified transcodes: " passed_results
}
' "$FIXTURE_MANIFEST" "$TRANSCODE_RESULTS"
