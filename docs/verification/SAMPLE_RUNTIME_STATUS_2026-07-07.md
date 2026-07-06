# Sample Runtime Status - 2026-07-07

## Scope

- Purpose: verify the next local ignored codec samples after the 2026-07-06 runtime-gap pass, then correct the Y41P and VC-1 route statuses after the current libVLC backend proved unsupported or unable to produce frames.
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
- USAC/xHE-AAC audio descriptions are now recognized as xHE-AAC during Apple-native media inspection.
- xHE-AAC-to-AAC source-preserving expectations follow the Apple-native AAC writer's observed 44.1 kHz output rate for this route.
- Y41P remains detectable as a source codec, but it is no longer advertised as current-build executable through SwiftVLC. The route now stays planned with an FFmpeg-family decode backend until a bundled, license-reviewed backend can actually decode the sample.
- VC-1 raw elementary streams remain detectable as source media, but they are no longer advertised as current-build executable through SwiftVLC after the local raw sample reached the route and produced no decoded frames. The route now stays planned with an FFmpeg-family or equivalent decode backend until a bundled, license-reviewed backend can actually decode the sample.

## Sample Input

The tested samples remain ignored under:

```text
/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/rpza_1701-D.mov
/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/amr_nb_h263_video.3gp
/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/xhe_aac_hevc_video.mp4
/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/y41p_from_internet_image.avi
/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/vc1_advanced_profile_2.vc1
```

| Sample | Source shape | App-side status |
| --- | --- | --- |
| `rpza_1701-D.mov` | QuickTime RPZA video, 160x120, 28 frames, 2.667s source duration | Passed focused simulator XCTest. Output is H.265 MP4, 160x120, 28 software frames, 2.660s inspected output duration. |
| `amr_nb_h263_video.3gp` | H.263 video plus AMR-NB audio, 176x144, 10 frames, 1.000s source duration | Passed focused simulator XCTest after AMR-NB was decoded through bundled VLC and resampled to 48 kHz AAC. Output is H.265 MP4 with 1 AAC mono audio track. |
| `xhe_aac_hevc_video.mp4` | H.265/HEVC video plus xHE-AAC/USAC audio, 160x120, 15 fps, 1.000s source duration | Passed focused simulator XCTest after USAC was inspected as xHE-AAC and Apple-native export produced H.265 MP4 with 1 AAC stereo audio track at 44.1 kHz. |
| `y41p_from_internet_image.avi` | Y41P video plus PCM audio, 160x120, 1.000s source duration | Passed focused route-correction XCTest as a planned route, not an executable encode route. Inspection still detects Y41P, launch readiness no longer lists it as available now, and the route remains planned for an FFmpeg-family decode backend. |
| `vc1_advanced_profile_2.vc1` | Raw VC-1 Advanced Profile elementary stream, 720x480 | Passed focused route-correction XCTest as a planned route, not an executable encode route. Inspection still detects VC-1, launch readiness no longer lists it as available now, and the route remains planned for an FFmpeg-family or equivalent decode backend. |

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
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testSourcePreservingAudioOptionsResolverRaisesAMRNBSampleRateForAACWriter \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealAMRNBH263SampleEncodesHEVCWithAACAudio
rm -f /tmp/taption_run_local_real_sample_tests
```

The simulator `D6CFCB2E-E61E-4772-B536-607891E4A210` was a temporary device named `TaptionEncoder-AMR-Proof-iPhone-17-Pro`.

Y41P route-correction coverage:

```sh
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=80E525BD-4A80-4E79-AABC-5E4684BF707C" \
  -derivedDataPath /tmp/taption_encoder_y41p_route_dd \
  -resultBundlePath /tmp/taption_encoder_y41p_route_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testNextTenPreservationCodecsToHEVCUseSoftwareWhenNoHardwareIsAvailable \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLiveTranscodingRegistryExposesImplementedAlgorithms \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledAvailableNowSamplesInspectToExpectedLaunchCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLaunchSupportCatalogMatchesCurrentLaunchContract \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testSoftwareBackendRegistryCoversUniversalVideoDecodeAndEncodeTargets \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealY41PSampleDocumentsPlannedFFmpegBackendAfterVLCUnsupportedBlock
rm -f /tmp/taption_run_local_real_sample_tests
```

The simulator `80E525BD-4A80-4E79-AABC-5E4684BF707C` was a temporary device named `TaptionEncoder-Y41P-Route-Proof-iPhone-17-Pro`.

VC-1/Y41P/AMR follow-up route and runtime coverage:

```sh
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=D46A2F29-A09B-4A67-8E6B-A99150F074B0" \
  -derivedDataPath /tmp/taption_encoder_vc1_impl_dd \
  -resultBundlePath /tmp/taption_encoder_codec_followup_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testNextTenPreservationCodecsToHEVCUseSoftwareWhenNoHardwareIsAvailable \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLiveTranscodingRegistryExposesImplementedAlgorithms \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLaunchSupportCatalogMatchesCurrentLaunchContract \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testSoftwareBackendRegistryCoversUniversalVideoDecodeAndEncodeTargets \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealVC1RawSampleDocumentsPlannedFFmpegBackendAfterVLCNoFrameBlock \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealY41PSampleDocumentsPlannedFFmpegBackendAfterVLCUnsupportedBlock \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testSourcePreservingAudioOptionsResolverRaisesAMRNBSampleRateForAACWriter \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealAMRNBH263SampleEncodesHEVCWithAACAudio
rm -f /tmp/taption_run_local_real_sample_tests
```

The simulator `D46A2F29-A09B-4A67-8E6B-A99150F074B0` was a temporary device named `TaptionEncoder-VC1-Implementation-iPhone-17-Pro`.

xHE-AAC follow-up runtime coverage:

```sh
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=2327959D-2E59-42CA-B1E9-ABBE04A8977E" \
  -derivedDataPath /tmp/taption_encoder_xhe_aac_dd \
  -resultBundlePath /tmp/taption_encoder_audio_regression_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealXHEAACSampleEncodesHEVCWithNativeAACAudio \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealAMRNBH263SampleEncodesHEVCWithAACAudio \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testSourcePreservingAudioOptionsResolverRaisesAMRNBSampleRateForAACWriter \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testSourcePreservingAudioOptionsResolverUsesAppleXHEAACWriterRateForAAC \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testAudioCodecRoutesCoverEveryPlannedSourceToAAC \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testAudioFormatDescriptionParserRecognizesUSACAsXHEAAC
rm -f /tmp/taption_run_local_real_sample_tests
```

The simulator `2327959D-2E59-42CA-B1E9-ABBE04A8977E` was a temporary device named `TaptionEncoder-XHEAAC-Proof-iPhone-17-Pro`.

## Result

- `testQuickTimeVideoSoftwareHEVCConfigurationAllowsLegacyFrameHold`: passed.
- `testLocalRealQuickTimeRPZASampleEncodesWithLegacyFrameHoldDuration`: passed.
- Runtime log showed `Software QuickTime Video transcode pipeline completed` with `frames=28`.
- Source-preserving output verification passed with `expectedDuration=2.667`, `actualDuration=2.660`, `expectedResolution=160x120`, `actualResolution=160x120`, `expectedFrameRate=10500/1000`, and `actualFrameRate=10526/1000`.
- `testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs`: passed with AMR included in the representative current-build VLC audio decode set.
- `testSourcePreservingAudioOptionsResolverRaisesAMRNBSampleRateForAACWriter`: passed.
- `testLocalRealAMRNBH263SampleEncodesHEVCWithAACAudio`: passed.
- Runtime log showed `Software H.263 transcode pipeline completed` with `frames=10`, `audioSampleBuffers=45`, and `audioSamples=45687`.
- Source-preserving output verification passed with `expectedDuration=1.000`, `actualDuration=1.000`, `expectedResolution=176x144`, `actualResolution=176x144`, `expectedAudioSampleRate=48000`, `actualAudioSampleRate=48000`, `expectedAudioChannels=1`, and `actualAudioChannels=1`.
- Y41P route-correction focused XCTest passed 6 selected tests with 0 failures.
- `testLocalRealY41PSampleDocumentsPlannedFFmpegBackendAfterVLCUnsupportedBlock`: passed. It confirmed Y41P sample inspection, planned support, non-executable current-build status, FFmpeg-family planned decode, and no live SwiftVLC algorithm descriptor for the route.
- VC-1/Y41P/AMR follow-up focused XCTest passed 9 selected tests with 0 failures.
- `testLocalRealVC1RawSampleDocumentsPlannedFFmpegBackendAfterVLCNoFrameBlock`: passed. It confirmed VC-1 sample inspection, planned support, non-executable current-build status, FFmpeg-family planned decode, and no live SwiftVLC algorithm descriptor for the route.
- xHE-AAC follow-up focused XCTest passed 7 selected tests with 0 failures.
- `testAudioFormatDescriptionParserRecognizesUSACAsXHEAAC`: passed. It confirmed USAC format descriptions map to the xHE-AAC audio codec model while preserving 48 kHz stereo source metadata.
- `testSourcePreservingAudioOptionsResolverUsesAppleXHEAACWriterRateForAAC`: passed. It confirmed xHE-AAC-to-AAC source-preserving expectations use 44.1 kHz for the Apple-native AAC writer.
- `testLocalRealXHEAACSampleEncodesHEVCWithNativeAACAudio`: passed. It confirmed the local xHE-AAC sample inspects as H.265 video plus xHE-AAC audio, routes audio through native xHE-AAC-to-AAC transcode, produces H.265 MP4 through Apple VideoToolbox, and outputs 1 AAC stereo track at 44.1 kHz.
- Runtime log showed `audioPath=HW`, `audioRoute=xHE-AAC to AAC`, `expectedAudioSampleRate=44100`, and `actualAudioSampleRate=44100`.
- Result bundles were written under `/tmp` during the runs, then removed during cleanup after the passes were recorded here.

## Remaining Sample Runtime Gaps

- VC-1 raw no longer advertises a current SwiftVLC executable path; it still needs a bundled, license-reviewed FFmpeg-family or equivalent backend before sample execution can be promoted.
- Y41P no longer advertises a current SwiftVLC executable path; it still needs a bundled, license-reviewed FFmpeg-family or equivalent backend before sample execution can be promoted.
- AMR-WB now has a decodable host-side sample, focused simulator AAC execution proof, and bundled real-device iPad Debug XCTest proof recorded separately in `docs/verification/AMR_WB_SAMPLE_ACQUISITION_2026-07-07.md`.
