# Preview Playback Blocklist Proof - 2026-07-07

## Scope

- Purpose: keep encodable legacy samples out of the full-screen preview path when the current SwiftVLC preview surface is known to show black video or otherwise misleading playback.
- Product policy: output video remains H.265 / HEVC only, and writable output containers remain MP4/MOV only.
- Proof surface: focused Debug XCTest on an iPhone 17 Pro iOS 26.5 simulator.
- This is simulator unit/UI-routing evidence only. It is not real-device playback proof, real-device encode proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

## User-Reported Playback Issues

- `R210.avi`: reported as not playing in preview.
- `Snow.avi`: reported as audio-only with a black preview surface.
- `RoQ Video.roq`: reported as the playback bar jumping directly to the end.

The existing 2026-06-29 iPhone preview log review had already identified several SwiftVLC preview no-video-output codecs: `Lossless JPEG`, `Microsoft RLE`, `R10K`, `R210`, and `Snow`. This pass makes that policy executable in the queue preview gate.

## Implementation Result

- `Lossless JPEG`, `Microsoft RLE`, `R10K`, `R210`, and `Snow` remain encodable through the existing route catalog, but `HomeViewModel.isPreviewableInCurrentBuild(asset:)` now returns `false` for those codecs.
- Queue cards for those codecs can still remain enabled for encoding and details, but they no longer open a black full-screen preview.
- RoQ is not blocklisted as a video preview codec in this pass. Instead, the preview timeline now treats missing or zero duration as an unusable timeline, keeps the slider at `0`, disables scrubbing, and ignores skip/seek gestures until a usable duration exists.

Host probe note for RoQ:

```text
ffprobe TaptionEncoder/TestVideos/RoQ Video.roq
format_name=roq
duration=<missing>
video codec=roq
```

That missing duration explains why player-reported normalized position can be misleading for RoQ even when the route remains previewable.

## Focused Simulator XCTest

Command:

```sh
rm -rf /tmp/taption_encoder_preview_block_dd /tmp/taption_encoder_preview_block.xcresult && xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,id=A5C810F9-20A8-46B7-B4BF-8AF3399D00C1' \
  -derivedDataPath /tmp/taption_encoder_preview_block_dd \
  -resultBundlePath /tmp/taption_encoder_preview_block.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testQueuePreviewPlaybackMathFormatsAndClampsControls \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testKnownBlackPreviewCodecStaysEncodableWithoutOpeningPreview \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testKnownBlackPreviewCodecsStayEncodableButNotPreviewableInQueue \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testRenderableLegacyAndProResPreviewCodecsStayPlayableInQueue \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLaunchSupportCatalogMatchesCurrentLaunchContract
```

Result:

```text
Test Suite 'Selected tests' passed.
Executed 5 tests, with 0 failures (0 unexpected).
Result bundle: /tmp/taption_encoder_preview_block.xcresult
```

Storage cleanup:

```text
/tmp/taption_encoder_preview_block_dd removed after the pass.
/tmp/taption_encoder_preview_block.xcresult retained, 252K.
```

## Follow-Up

- Collect real-device manual/video proof for R210, Snow, and RoQ preview behavior after installing the next build.
- If RoQ still feels misleading on device, promote RoQ from timeline-only mitigation to the preview blocklist while preserving H.265 encode support.
- Revisit the blocklist if a different bundled, license-reviewed preview backend can produce reliable video output for these codecs.
