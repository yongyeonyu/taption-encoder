#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/Samples/CodecFixtures/transcode_reports/route_matrix_$(date +%Y%m%d_%H%M%S)"}"
RESULTS="$OUT_DIR/codec_route_matrix.tsv"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

let rows = HW_CodecRouteSimulator.rows()

print(HW_CodecRouteSimulator.tsvHeader.joined(separator: "\t"))
for row in rows {
    print(row.tsvFields.joined(separator: "\t"))
}

let failures = HW_CodecRouteSimulator.validationFailures(rows: rows)

if !failures.isEmpty {
    FileHandle.standardError.write(("Route simulation failed:\n" + failures.joined(separator: "\n") + "\n").data(using: .utf8)!)
    exit(1)
}
SWIFT

mkdir -p "$OUT_DIR"

xcrun swiftc \
  "$ROOT_DIR/TaptionEncoder/Core/VideoCore/TaptionVideoCoreModels.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/VideoCore/TaptionVideoEncodingPlan.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/CodecAlgorithm.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_CodecSupportCatalog.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_UniversalCodecTranscodeAlgorithm.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/AudioCodecAlgorithm.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/HW_AudioCodecCapabilityCatalog.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/SW_AudioCodecSupportCatalog.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/SW_UniversalAudioCodecTranscodeAlgorithm.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/AudioCodecRoutePlanner.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_SoftwareCodecBackendRegistry.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_FFmpegCodecCommandPlanner.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_FFmpegCommandExecutor.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/HW_CodecCapabilityProbe.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/HW_AppleDeviceCodecProfiles.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/CodecRoutePlanner.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/codec_route_simulator"

"$TMP_DIR/codec_route_simulator" > "$RESULTS"

echo "wrote $RESULTS"
