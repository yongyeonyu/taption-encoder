# VC-1 Raw And Y41P Bundled FFmpeg Decode Bridge Proof - 2026-07-07

## Scope

- Purpose: replace the earlier fake-runner contract proof with a real bundled iOS simulator decode runner proof for VC-1 raw and Y41P.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Output video policy remains H.265 / HEVC only.
- Writable output containers remain MP4 and MOV only.

This is source-build, vendored-binary, open-source-notice draft, and focused iOS simulator execution proof. It is not formal legal approval, not App Review approval, not TestFlight/App Store Connect proof, not public-release proof, not full broad-backend promotion, and not iPhone/older-device thermal/battery/memory/runtime proof.

## Vendored Bridge

Added a source-built LGPL FFmpeg-family in-process decode bridge:

```text
Vendor/FFmpegLGPLDecodeBridge/Sources/TaptionFFmpegDecodeBridge.c
Vendor/FFmpegLGPLDecodeBridge/Sources/TaptionFFmpegDecodeBridge.h
Vendor/FFmpegLGPLDecodeBridge/Sources/module.modulemap
Vendor/FFmpegLGPLDecodeBridge/TaptionFFmpegDecodeBridge.xcframework
```

The bridge decodes source frames through FFmpeg libraries into BGRA and feeds Taption Encoder's existing AVAssetWriter H.265 writer path. No FFmpeg command-line executable is bundled or invoked.

Build script:

```text
Scripts/build_ffmpeg_lgpl_decode_bridge.sh
```

Build artifact size:

| Artifact | Size |
| --- | ---: |
| `TaptionFFmpegDecodeBridge.xcframework` | 8.6 MB |
| `ios-arm64/libTaptionFFmpegDecodeBridge.a` | 4.3 MB |
| `ios-arm64-simulator/libTaptionFFmpegDecodeBridge.a` | 4.3 MB |

## Source And Configure Surface

Pinned source:

```text
FFmpeg version: 8.1.1
Source URL: https://ffmpeg.org/releases/ffmpeg-8.1.1.tar.xz
SHA-256: b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3
Minimum iOS: 17.0
```

Configure flags:

```text
--disable-everything
--disable-programs
--disable-doc
--disable-debug
--disable-network
--disable-autodetect
--disable-asm
--disable-avdevice
--disable-avfilter
--disable-swresample
--disable-shared
--enable-pic
--enable-static
--enable-avcodec
--enable-avformat
--enable-avutil
--enable-swscale
--enable-protocol=file
--enable-demuxer=vc1,avi
--enable-parser=vc1
--enable-decoder=vc1,vc1image,y41p,rawvideo,pcm_s16le
```

Enabled component map:

| Category | Enabled components |
| --- | --- |
| Libraries | `avformat`, `avcodec`, `avutil`, `swscale` |
| Demuxers | `vc1`, `avi` |
| Decoders | `vc1`, `vc1image`, `y41p`, `rawvideo`, `pcm_s16le` |
| Parser | `vc1` |
| Protocol | `file` |
| Programs | none |
| External libraries | none |
| GPL/nonfree flags | none |

The generated build record is stored at:

```text
Vendor/FFmpegLGPLDecodeBridge/FFMPEG_LGPL_DECODE_BRIDGE_BUILD.txt
```

## Notice, Source Availability, And EULA

Engineering notice draft:

```text
TaptionEncoder/OpenSourceNotices/FFmpeg-LGPL-Decode-Bridge.txt
```

The app notice catalog now includes the bridge as a shipped component so notice-resource tests check it with the other bundled SDK notices.

Current engineering status:

- Source availability is pinned to the official FFmpeg source URL and SHA-256 above.
- Local bridge source is stored under `Vendor/FFmpegLGPLDecodeBridge/Sources`.
- The bridge disables GPL and nonfree configure paths.
- The bridge does not bundle a command-line executable or runtime-downloaded plugin.
- Final counsel approval is still required before release promotion.
- Final EULA review must preserve any LGPL-required reverse-engineering or relinking rights needed for debugging modified LGPL components.

## Test Fixtures

Bundled test-only fixtures:

| Fixture | Size | SHA-256 | Probe |
| --- | ---: | --- | --- |
| `TaptionEncoderTests/Fixtures/VC-1 Raw.vc1` | 700,252 bytes | `2484afca1a8e63237e07a9a4960b704dd1199eb808eb10ffa5f44d673d69ff40` | raw VC-1, 720x480, `yuv420p` |
| `TaptionEncoderTests/Fixtures/Y41P.avi` | 819,846 bytes | `580b6312bd4c8659881670d54eebb4f5b749d9349b83f126652578804b3fa7ec` | AVI Y41P, 160x120, 25 fps, PCM s16le mono |

## Simulator Execution Proof

Focused XCTest:

```text
TaptionEncoderTests/CodecRoutePlannerTests/testBundledFFmpegDecodeBridgeEncodesVC1RawAndY41PToHEVCMP4MOVInSimulator
```

Command:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,id=A5C810F9-20A8-46B7-B4BF-8AF3399D00C1' \
  -derivedDataPath /tmp/taption_encoder_ffmpeg_bridge_dd \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledFFmpegDecodeBridgeEncodesVC1RawAndY41PToHEVCMP4MOVInSimulator
```

Result:

```text
** TEST SUCCEEDED **
Executed 1 test, with 0 failures.
xcresult: /tmp/taption_encoder_ffmpeg_bridge_dd/Logs/Test/Test-TaptionEncoder-2026.07.07_11-44-33-+0900.xcresult
```

The test exercises the vendored `TaptionFFmpegDecodeBridge` runner in process and verifies:

| Source | Output | Verified output |
| --- | --- | --- |
| VC-1 raw elementary stream | H.265 MP4 | HEVC video, 720x480, no audio, approximately 20/30 seconds |
| Y41P AVI | H.265 MOV | HEVC video, 160x120, no audio, approximately 20/25 seconds |

The planned route still enters the executor through an injected ready report for this focused proof. The global FFmpeg-family broad backend readiness gates remain open for release promotion.

## Generic iOS Build Proof

Command:

```sh
xcodebuild \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/taption_encoder_ffmpeg_bridge_iosbuild_dd \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Result:

```text
** BUILD SUCCEEDED **
```

This confirms the app target links the `ios-arm64` bridge slice in a generic iOS Debug build. It is not a real-device install, launch, runtime encode, TestFlight, App Store Connect, or release archive proof.

## Device Proof Status

Device availability checked in this pass:

```text
iPad Pro 12.9-inch 6th generation (iPad14,6): available (paired)
iPhone 14 Pro (iPhone15,2): unavailable
```

No iPhone proof and no older-device thermal/battery/memory/runtime proof were collected in this pass. Those remain separate follow-up gates.

## Remaining Gates

- Formal counsel approval for LGPL static-linking, source availability, relinking/reverse-engineering/EULA language, enabled component compatibility, and HEVC distribution.
- App Review submission/approval and final release packaging/export review after the local engineering preflight in `docs/verification/FFMPEG_BRIDGE_LEGAL_RELEASE_PREFLIGHT_2026-07-07.md`.
- App Store distribution export/IPA size was measured separately in `docs/verification/FFMPEG_BRIDGE_LEGAL_RELEASE_PREFLIGHT_2026-07-07.md`; upload, processing, App Review, and public release remain separate.
- Real-device bridge execution proof.
- iPhone and older-device thermal/battery/memory/runtime threshold proof.
- AMR-WB+ remains separate because this VC-1/Y41P decode bridge does not prove `sawp` AMR-WB+ decode.
