# Sample Runtime Status - 2026-07-06

## Scope

- Purpose: verify the current app-side runtime status for local ignored samples that were acquired during the 2026-07-06 codec sample passes.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Runtime: local Debug XCTest on an iPhone 17 Pro iOS 26.5 simulator.
- Output policy remains unchanged: Taption Encoder still outputs H.265 / HEVC video only, and implemented output containers remain MP4/MOV only.
- This is simulator XCTest runtime evidence only. It is not host FFmpeg proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.

## Sample Inputs

The samples remain ignored under:

```text
/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/
```

| Sample | Source shape | App-side status |
| --- | --- | --- |
| `amr_nb_h263_video.3gp` | H.263 video plus AMR-NB audio | Video route is current, but AMR-NB to AAC remains command-plan-only because the FFmpeg-family backend is not bundled. A temporary attempt to treat AMR as current VLC audio decode failed with `AudioCodecInitialize failed` and `Cannot Encode Media`, so AMR was not promoted to current-build executable audio. |
| `rpza_1701-D.mov` | QuickTime RPZA video | Software VLC decode produced 8 frames, but source-preserving output verification failed because duration was expected at 2.667s and the output inspected at 0.760s. |
| `vc1_advanced_profile_2.vc1` | Raw VC-1 Advanced Profile elementary stream | Current route selection reaches the software VLC path, but runtime decode produced no frames before timeout, even after adding raw VC-1 avformat demux hints. |
| `y41p_from_internet_image.avi` | Y41P video plus PCM audio | Current route selection reaches the software VLC path, but libVLC reports the Y41P codec is not supported and no video frames are produced. |

## XCTest Command

```sh
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=A57EE4F1-DE7A-4745-859F-96DC18B110F1" \
  -derivedDataPath /tmp/taption_encoder_dd_vc1_runtime \
  -resultBundlePath /tmp/taption_sample_state_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAACForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealAMRNBH263SampleDocumentsCurrentAudioExecutionBlock \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealVC1RawSampleDocumentsCurrentSwiftVLCNoFrameBlock \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealQuickTimeRPZASampleDocumentsCurrentDurationVerificationBlock \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealY41PSampleDocumentsCurrentSwiftVLCUnsupportedBlock
rm -f /tmp/taption_run_local_real_sample_tests
```

The simulator `A57EE4F1-DE7A-4745-859F-96DC18B110F1` was a temporary device named `TaptionEncoder-Sample-State-iPhone-17-Pro` and was deleted after the run.

## Result

- `CodecRoutePlannerTests`: 5 selected tests passed, 0 failed.
- Result bundle was written to `/tmp/taption_sample_state_result.xcresult` during the run, then removed during local cleanup to recover disk space.
- The first attempts against the pre-existing `iPhone 17 Pro` and `Codex-iPhone-17-Pro` simulator names failed before tests launched because their CoreSimulator data folders were already missing. Those simulator-device failures are separate from codec runtime behavior.

## Follow-Up

- Fix raw VC-1 runtime decode before reporting VC-1 sample execution as passing app-side proof.
- Fix QuickTime RPZA partial-duration decode or adjust source-preserving handling only if a route-specific reason is proven.
- Do not advertise Y41P as sample-executable through current libVLC until a backend with Y41P decode support is bundled.
- AMR-NB audio execution needs an App Store-safe decode/resample/AAC path; route planning alone is not enough.
