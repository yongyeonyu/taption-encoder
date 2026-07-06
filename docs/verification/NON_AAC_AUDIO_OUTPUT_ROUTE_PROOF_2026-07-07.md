# Non-AAC Audio Output Route Proof - 2026-07-07

## Scope

- Repository: `/Users/u_mo_c/Documents/taption_encoder`
- Feature surface: current-build bundled software audio decode feeding Apple `AVAssetWriter` with non-AAC audio output.
- Output contract: video output remains H.265 / HEVC only; writable output containers remain MP4/MOV only.
- Proof surface: real-device Debug XCTest on a paired iPad. This is not simulator proof, host FFmpeg proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

## Implemented Routes

- Source sample: bundled `TaptionEncoder/TestVideos/Theora.ogv`
- Source media: Theora video plus Opus audio
- Output: H.265 / HEVC video in MOV with Linear PCM audio
- Executed audio route: `Opus to PCM`
- Output: H.265 / HEVC video in MOV with Apple Lossless / ALAC audio
- Executed audio route: `Opus to Apple Lossless`
- Execution backend: bundled software VLC decode feeding the Apple-native output writer

## Code Changes Covered

- `SW_AudioCodecSupportCatalog` now treats current-build bundled VLC audio decode as available for:
  - AAC output in MP4/MOV
  - PCM output in MOV
  - ALAC output in MOV
- `SW_AV1NativeAudioEncodingConfiguration` now builds codec-aware writer settings:
  - AAC uses `kAudioFormatMPEG4AAC`
  - PCM uses `kAudioFormatLinearPCM` with 16-bit packed interleaved samples
  - ALAC uses `kAudioFormatAppleLossless` with a 16-bit encoder depth hint
- `TaptionAudioCodecOutputCatalog` now marks `PCM / MOV` and `ALAC / MOV` as implemented.

## Device XCTest Proof - PCM

Command:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008112-000964980E45401E' \
  -derivedDataPath /tmp/taption_encoder_pcm_mov_dd \
  -resultBundlePath /tmp/taption_encoder_pcm_mov_result.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testOutputSelectionOnlyMarksCurrentImplementedOutputAsRunnable \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testAudioOutputReadinessCatalogReportSummarizesSelectorMatrix \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledTheoraOpusSampleEncodesHEVCMOVWithPCMAudio
```

Result:

- Passed: 4
- Failed: 0
- Skipped: 0
- Device: iPad Pro 12.9-inch 6th generation
- Device ID: `00008112-000964980E45401E`
- OS: iOS/iPadOS 26.5, build `23F77`
- Result bundle: `/tmp/taption_encoder_pcm_mov_result.xcresult`

Key runtime evidence from the passing test log:

- `audioRoute=Opus to PCM`
- `audioPath=SW`
- `output=H.265 / HEVC / MOV`
- `Software Theora transcode pipeline completed`
- `frames=150`
- `audioSampleBuffers=201`
- `audioSamples=192312`
- Source-preserving output verification passed with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=48000`
  - `actualAudioChannels=2`
  - `actualDuration=5.000`
  - `actualResolution=320x240`

Test assertions also verified:

- output container: MOV
- output video codec: H.265 / HEVC
- output audio codec: PCM
- output audio sample rate: 48 kHz
- output audio channel count: 2

## Device XCTest Proof - ALAC

Command:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008112-000964980E45401E' \
  -derivedDataPath /tmp/taption_encoder_alac_mov_dd \
  -resultBundlePath /tmp/taption_encoder_alac_mov_result.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testOutputSelectionOnlyMarksCurrentImplementedOutputAsRunnable \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testAudioOutputReadinessCatalogReportSummarizesSelectorMatrix \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledTheoraOpusSampleEncodesHEVCMOVWithALACAudio
```

Result:

- Passed: 4
- Failed: 0
- Skipped: 0
- Device: iPad Pro 12.9-inch 6th generation
- Device ID: `00008112-000964980E45401E`
- OS: iOS/iPadOS 26.5
- Result bundle: `/tmp/taption_encoder_alac_mov_result.xcresult`

Key runtime evidence from the passing test log:

- `audioRoute=Opus to Apple Lossless`
- `audioPath=SW`
- `output=H.265 / HEVC / MOV`
- `Codec algorithm selected backend=softwareVLCDecoder mode=software`
- `Software Theora transcode pipeline completed`
- `frames=150`
- `audioSampleBuffers=201`
- `audioSamples=192312`
- Source-preserving output verification passed with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=48000`
  - `actualAudioChannels=2`
  - `actualDuration=5.000`
  - `actualResolution=320x240`

Test assertions also verified:

- output container: MOV
- output video codec: H.265 / HEVC
- output audio codec: ALAC
- output audio sample rate: 48 kHz
- output audio channel count: 2

## Core Truth Check

Command:

```sh
Scripts/run_core_codec_truth_checks.sh
```

Result:

- `core truth checks passed`
- planned video route pairs: 63
- apple device models: 93
- video output selections: 2
- audio output selections: 56

## Remaining Audio Work

- AMR-WB app-side execution remains blocked by current inspection not surfacing the host-visible `sawb` audio track.
- AMR-WB+ still needs a decodable positive sample.
- Broader non-AAC output routes beyond current `PCM / MOV` and `ALAC / MOV` still need implementation and proof.
- FFmpeg-family or equivalent broad backend execution remains gated on bundled backend integration and license/App Store review.
