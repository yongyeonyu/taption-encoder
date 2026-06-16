#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

struct CoreTruthCheckFailure: Error {
    var failures: [String]
}

func require(_ condition: @autoclosure () -> Bool, _ message: String, failures: inout [String]) {
    if !condition() {
        failures.append(message)
    }
}

func makeFixtureAsset() -> TaptionVideoAsset {
    TaptionVideoAsset(
        displayName: "Fixture.mov",
        location: TaptionVideoAssetLocation(
            kind: .temporary,
            url: URL(fileURLWithPath: "/tmp/Fixture.mov")
        ),
        container: .mov,
        duration: 12,
        videoTrack: TaptionVideoTrackInfo(
            codec: .h264,
            naturalSize: TaptionPixelSize(width: 3840, height: 2160),
            displaySize: TaptionPixelSize(width: 3840, height: 2160),
            nominalFrameRate: TaptionRationalFrameRate(numerator: 30000, denominator: 1001),
            estimatedBitrate: 42_000_000,
            color: TaptionColorDescription(
                primaries: .bt709,
                transfer: .sRGB,
                matrix: .bt709,
                bitDepth: 10,
                isHDR: false
            ),
            rotationDegrees: 90
        ),
        audioTracks: [
            TaptionAudioTrackInfo(
                codec: .aac,
                channelCount: 2,
                sampleRate: 48_000,
                estimatedBitrate: 192_000
            )
        ]
    )
}

var failures: [String] = []

let modelCoverage = HW_AppleDeviceCodecModelMatrix.coverageReport()
require(modelCoverage.isPassing, "Apple device model coverage report is failing.", failures: &failures)
require(modelCoverage.modelCount > 0, "Apple device model matrix is empty.", failures: &failures)
require(modelCoverage.av1HardwareDecodeModelCount > 0, "No AV1 hardware decode Apple models were reported.", failures: &failures)

let completionAudit = TaptionUniversalCodecCompletionAuditor.makeReport()
require(completionAudit.universalPlanningIsLocked, "Universal codec planning is not locked.", failures: &failures)
require(completionAudit.outputSelectionCoverageIsPassing, "Output selection coverage is not passing.", failures: &failures)
require(completionAudit.videoRouteCount == TaptionCodecRegistry.universalRoutePairCount, "Video route count drifted from the universal route pair count.", failures: &failures)
require(
    completionAudit.audioRouteCount == TaptionAudioCodecRoutePlanner.universalAudioCodecs.count * TaptionAudioCodecRoutePlanner.universalAudioCodecs.count,
    "Audio route count drifted from the universal route pair count.",
    failures: &failures
)

let videoReadiness = TaptionCodecOutputCatalog.makeReadinessReport()
require(videoReadiness.outputSelectionCount > 0, "Video output readiness catalog is empty.", failures: &failures)
require(videoReadiness.implementedOutputSelectionCount > 0, "Video output readiness catalog has no runnable selections.", failures: &failures)

let audioReadiness = TaptionAudioCodecOutputCatalog.makeReadinessReport()
require(audioReadiness.outputSelectionCount > 0, "Audio output readiness catalog is empty.", failures: &failures)
require(audioReadiness.implementedOutputSelectionCount > 0, "Audio output readiness catalog has no runnable selections.", failures: &failures)

let fixtureAsset = makeFixtureAsset()
let resolvedPolicy = TaptionSourcePreservingOutputPolicyResolver.resolvedPolicy(
    for: fixtureAsset,
    requestedPolicy: TaptionVideoOutputPolicy(
        videoCodec: .hevc,
        audioCodec: .aac,
        container: .mp4,
        qualityPolicy: .preserveSourceVisuals,
        advancedOptions: .preserveSource
    )
)

require(resolvedPolicy.advancedOptions.resizeTo == fixtureAsset.videoTrack?.displaySize, "Source-preserving video size was not filled from the source track.", failures: &failures)
require(resolvedPolicy.advancedOptions.frameRate == fixtureAsset.videoTrack?.nominalFrameRate, "Source-preserving frame rate was not filled from the source track.", failures: &failures)
require(resolvedPolicy.advancedOptions.targetBitrate == fixtureAsset.videoTrack?.estimatedBitrate, "Source-preserving bitrate was not filled from the source track.", failures: &failures)
require(resolvedPolicy.advancedOptions.color == fixtureAsset.videoTrack?.color, "Source-preserving color metadata was not filled from the source track.", failures: &failures)
require(resolvedPolicy.advancedOptions.rotationDegrees == fixtureAsset.videoTrack?.rotationDegrees, "Source-preserving rotation was not filled from the source track.", failures: &failures)

let resolvedAudioOptions = TaptionSourcePreservingAudioOptionsResolver.resolvedOptions(
    for: fixtureAsset.audioTracks.first,
    requestedOptions: .preservingSource(outputCodec: .aac, outputContainer: .mp4)
)
require(resolvedAudioOptions.sampleRate == fixtureAsset.audioTracks.first?.sampleRate, "Source-preserving audio sample rate was not filled from the source track.", failures: &failures)
require(resolvedAudioOptions.channelCount == fixtureAsset.audioTracks.first?.channelCount, "Source-preserving audio channel count was not filled from the source track.", failures: &failures)
require(resolvedAudioOptions.targetBitrate == fixtureAsset.audioTracks.first?.estimatedBitrate, "Source-preserving audio bitrate was not filled from the source track.", failures: &failures)

let hardwareSelection = TaptionCodecRoutePlanner.selectRoute(
    for: fixtureAsset,
    outputCodec: .hevc,
    requestedMode: .automatic,
    hardwareSupport: .h264HEVCHardware
)
require(hardwareSelection.executionKind == .hardware, "H.264 to H.265 should prefer hardware on H.264/HEVC-capable hardware.", failures: &failures)

let av1FixtureAsset = TaptionVideoAsset(
    displayName: "Fixture.webm",
    location: TaptionVideoAssetLocation(kind: .temporary, url: URL(fileURLWithPath: "/tmp/Fixture.webm")),
    container: .webm,
    duration: 8,
    videoTrack: TaptionVideoTrackInfo(
        codec: .av1,
        naturalSize: TaptionPixelSize(width: 1920, height: 1080),
        displaySize: TaptionPixelSize(width: 1920, height: 1080),
        nominalFrameRate: TaptionRationalFrameRate(numerator: 30),
        estimatedBitrate: 8_000_000
    )
)

let softwareSelection = TaptionCodecRoutePlanner.selectRoute(
    for: av1FixtureAsset,
    outputCodec: .hevc,
    requestedMode: .automatic,
    hardwareSupport: .softwareOnly
)
require(softwareSelection.executionKind == .software, "AV1 to H.265 should fall back to software when no hardware is available.", failures: &failures)

if !failures.isEmpty {
    throw CoreTruthCheckFailure(failures: failures)
}

print("core truth checks passed")
print("planned video route pairs: \(TaptionCodecRegistry.universalRoutePairCount)")
print("apple device models: \(modelCoverage.modelCount)")
print("video output selections: \(videoReadiness.outputSelectionCount)")
print("audio output selections: \(audioReadiness.outputSelectionCount)")
SWIFT

xcrun swiftc \
  "$ROOT_DIR/TaptionEncoder/Core/VideoCore/TaptionVideoCoreModels.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/VideoCore/TaptionVideoEncodingPlan.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/CodecAlgorithm.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/CodecOutputCatalog.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_CodecSupportCatalog.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_UniversalCodecTranscodeAlgorithm.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/AudioCodecAlgorithm.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/HW_AudioCodecCapabilityCatalog.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/SW_AudioCodecSupportCatalog.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/SW_UniversalAudioCodecTranscodeAlgorithm.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/Audio/AudioCodecRoutePlanner.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_SoftwareCodecBackendRegistry.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_FFmpegCodecCommandPlanner.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/CodecFixtureEvidence.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/SW_FFmpegCommandExecutor.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/HW_CodecCapabilityProbe.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/HW_AppleDeviceCodecProfiles.swift" \
  "$ROOT_DIR/TaptionEncoder/Core/Codecs/CodecRoutePlanner.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/core_codec_truth_checks"

if ! "$TMP_DIR/core_codec_truth_checks"; then
  echo "error: core codec truth checks failed" >&2
  exit 1
fi
