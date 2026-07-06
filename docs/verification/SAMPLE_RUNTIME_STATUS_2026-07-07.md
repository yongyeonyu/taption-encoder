# Sample Runtime Status - 2026-07-07

## Scope

- Purpose: verify the next local ignored codec sample after the 2026-07-06 runtime-gap pass.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Runtime: local Debug XCTest on a temporary iPhone 17 Pro iOS 26.5 simulator.
- Output policy remains unchanged: Taption Encoder still outputs H.265 / HEVC video only, and implemented output containers remain MP4/MOV only.
- This is simulator XCTest runtime evidence only. It is not host FFmpeg proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.

## Implementation

- QuickTime Video/RPZA software decode now enables a legacy frame-hold path in `SW_AV1HEVCTranscodeConfiguration`.
- `SW_AV1FrameWriterContext` stores the latest decoded pixel buffer and, for the QuickTime Video/RPZA route only, appends held frames until the expected source-duration frame count is reached.
- The fix keeps ordinary software-decoded routes on the existing one decoded frame to one output frame behavior.
- AMR-NB audio is now promoted to the current-build bundled VLC audio decode path for AAC output in MP4.
- AMR-NB audio is resampled to 48 kHz for the AAC writer, and the source-preserving verification expectation follows the audio plan's resolved output sample rate.

## Sample Input

The tested samples remain ignored under:

```text
/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/rpza_1701-D.mov
/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/amr_nb_h263_video.3gp
```

| Sample | Source shape | App-side status |
| --- | --- | --- |
| `rpza_1701-D.mov` | QuickTime RPZA video, 160x120, 28 frames, 2.667s source duration | Passed focused simulator XCTest. Output is H.265 MP4, 160x120, 28 software frames, 2.660s inspected output duration. |
| `amr_nb_h263_video.3gp` | H.263 video plus AMR-NB audio, 176x144, 10 frames, 1.000s source duration | Passed focused simulator XCTest after AMR-NB was decoded through bundled VLC and resampled to 48 kHz AAC. Output is H.265 MP4 with 1 AAC mono audio track. |

## XCTest Commands

Initial focused coverage:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=4BC65C4C-73B6-459B-9419-E9B1EF161297" \
  -derivedDataPath /tmp/taption_encoder_rpza_dd \
  -resultBundlePath /tmp/taption_encoder_rpza_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testQuickTimeVideoSoftwareHEVCConfigurationAllowsLegacyFrameHold \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealQuickTimeRPZASampleEncodesWithLegacyFrameHoldDuration
```

In that first run, `testQuickTimeVideoSoftwareHEVCConfigurationAllowsLegacyFrameHold` passed and the local real-sample test skipped because the opt-in flag file was not present.

Local ignored sample runtime coverage:

```sh
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=4BC65C4C-73B6-459B-9419-E9B1EF161297" \
  -derivedDataPath /tmp/taption_encoder_rpza_dd \
  -resultBundlePath /tmp/taption_encoder_rpza_actual_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealQuickTimeRPZASampleEncodesWithLegacyFrameHoldDuration
rm -f /tmp/taption_run_local_real_sample_tests
```

The simulator `4BC65C4C-73B6-459B-9419-E9B1EF161297` was a temporary device named `TaptionEncoder-RPZA-Proof-iPhone-17-Pro`.

AMR-NB/H.263 follow-up runtime coverage:

```sh
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=D6CFCB2E-E61E-4772-B536-607891E4A210" \
  -derivedDataPath /tmp/taption_encoder_amr_dd \
  -resultBundlePath /tmp/taption_encoder_amr_result_48k.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAACForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testSourcePreservingAudioOptionsResolverRaisesAMRNBSampleRateForAACWriter \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealAMRNBH263SampleEncodesHEVCWithAACAudio
rm -f /tmp/taption_run_local_real_sample_tests
```

The simulator `D6CFCB2E-E61E-4772-B536-607891E4A210` was a temporary device named `TaptionEncoder-AMR-Proof-iPhone-17-Pro`.

## Result

- `testQuickTimeVideoSoftwareHEVCConfigurationAllowsLegacyFrameHold`: passed.
- `testLocalRealQuickTimeRPZASampleEncodesWithLegacyFrameHoldDuration`: passed.
- Runtime log showed `Software QuickTime Video transcode pipeline completed` with `frames=28`.
- Source-preserving output verification passed with `expectedDuration=2.667`, `actualDuration=2.660`, `expectedResolution=160x120`, `actualResolution=160x120`, `expectedFrameRate=10500/1000`, and `actualFrameRate=10526/1000`.
- `testBundledVLCAudioDecodeFeedsAACForRepresentativeCurrentBuildCodecs`: passed with AMR included in the representative current-build VLC audio decode set.
- `testSourcePreservingAudioOptionsResolverRaisesAMRNBSampleRateForAACWriter`: passed.
- `testLocalRealAMRNBH263SampleEncodesHEVCWithAACAudio`: passed.
- Runtime log showed `Software H.263 transcode pipeline completed` with `frames=10`, `audioSampleBuffers=45`, and `audioSamples=45687`.
- Source-preserving output verification passed with `expectedDuration=1.000`, `actualDuration=1.000`, `expectedResolution=176x144`, `actualResolution=176x144`, `expectedAudioSampleRate=48000`, `actualAudioSampleRate=48000`, `expectedAudioChannels=1`, and `actualAudioChannels=1`.
- Result bundles were written under `/tmp` during the runs, then removed during cleanup after the passes were recorded here.

## Remaining Sample Runtime Gaps

- VC-1 raw still reaches the software VLC path but produces no frames before timeout.
- Y41P still reaches the software VLC path but libVLC reports the codec is unsupported.
- xHE-AAC still needs app-side execution proof.
