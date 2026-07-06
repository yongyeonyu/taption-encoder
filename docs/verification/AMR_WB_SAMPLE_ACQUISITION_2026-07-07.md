# AMR-WB Sample Acquisition And Runtime Proof - 2026-07-07

## Scope

- Purpose: acquire a decodable AMR-WB sample candidate after the prior AMR-WB+ sample stayed negative, then separate host decode proof, simulator runtime proof, bundled-resource proof, and real-device runtime proof.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Local sample folder: `/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-07/`.
- Evidence folder: `docs/verification/amr_wb_sample_acquisition_2026-07-07/`.
- Output policy remains unchanged: Taption Encoder still outputs H.265 / HEVC video only, and implemented output containers remain MP4/MOV only.
- This is local sample acquisition, host decode, focused simulator app-side execution, bundled sample-resource, focused real-device app-side execution, and focused non-AAC output-route evidence. It is not TestFlight/App Store Connect proof, App Review proof, or public release proof.

`Samples/Downloaded/` is intentionally ignored by git, so the original generated sample files stay local. A copy of the H.263/AMR-WB 3GP sample is now checked in under `TaptionEncoder/TestVideos/AMR-WB H.263.3gp` only for bundled sample and physical-device XCTest proof. The checked-in TSV files preserve the source URL, source hash, generated sample hashes, bundled sample hash, host probe results, the initial app-side block, the follow-up simulator execution proof, and the real-device execution proof.

## Source

The successful source was the ETSI TS 126 174 V19.0.0 companion archive:

```text
https://www.etsi.org/deliver/etsi_ts/126100_126199/126174/19.00.00_60/ts_126174v190000p0.zip
```

The ETSI/3GPP document states that the AMR-WB digital test sequence files are provided as ZIP archives accompanying the document. The downloaded companion ZIP contained `readme.txt`, `S.zip`, and `T.zip`.

The selected encoded sequence was:

```text
T.zip -> T/T_1265/T02_1265.cod
```

`T02_1265.cod` is a 12.65 kbit/s AMR-WB serial test-vector file. The local conversion packed the first 150 20 ms frames into the AMR-WB storage format with the `#!AMR-WB` header, then muxed the resulting audio with a small synthetic H.263 wrapper video into a 3GP sample. The checked-in bundled copy stream-loops that sample to 5 seconds so it follows the bundled sample policy. The wrapper is used only to make the official AMR-WB audio vector available to the video-source runtime path; H.263 video coverage already has separate public-sample proof.

## Created Local Samples

| Target | Local sample | Size | SHA-256 | Result |
| --- | --- | ---: | --- | --- |
| AMR-WB audio | `sample_audio/amr_wb_t02_1265.awb` | 4,959 bytes | `050ddecc011ce2566b9012a7ff79c19dd153c4738b2ba3713cfb605a2fd26c98` | Host FFprobe identifies `amr_wb` / `sawb`, 16 kHz mono, 3.093750s. |
| AMR-WB video container | `sample_videos/amr_wb_h263_video.3gp` | 148,699 bytes | `af9398db3c70b2bc32d8ade87f11fee79b6b2a7344b58cb96d7ea901791c0fc1` | Host FFprobe identifies H.263 video plus `amr_wb` / `sawb` audio, 16 kHz mono, 3.000000s. |
| Bundled AMR-WB proof sample | `TaptionEncoder/TestVideos/AMR-WB H.263.3gp` | 258,024 bytes | `f31b08cc128645b1b2572eb0c2101ef66ec64753d7cc76da79c8fe69a3a7d6be` | Checked-in 5-second physical-device XCTest sample. Source policy recorded in `TaptionEncoder/TestVideos/SAMPLE_SOURCES.txt`. |

## Host Decode Probe

Host FFmpeg 8.1.1 decoded both the `.awb` file and the 3GP audio stream without corruption errors.

| Sample | FFprobe | Decode signal |
| --- | --- | --- |
| `amr_wb_t02_1265.awb` | `amr_wb`, `sawb`, 16 kHz mono, 12.8 kb/s, 3.093750s | Peak level 6.694738 dB, RMS level -17.168818 dB |
| `amr_wb_h263_video.3gp` | H.263 video plus `amr_wb`, `sawb`, 16 kHz mono, 13.2 kb/s, 3.000000s | Peak level 6.694738 dB, RMS level -17.168818 dB |

## Initial Focused App-Side Simulator Block

The initial opt-in XCTest documented the prior app-side block:

```sh
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=BCFE1251-F1C1-4637-A0F9-F47813B1DA81" \
  -derivedDataPath /tmp/taption_encoder_amrwb_dd \
  -resultBundlePath /tmp/taption_encoder_amrwb_block_result_rerun.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealAMRWBH263SampleDocumentsCurrentAppAudioInspectionBlock
rm -f /tmp/taption_run_local_real_sample_tests
```

Result: passed, 1 selected test, 0 failures.

The simulator was a temporary iPhone 17 Pro iOS 26.5 device named `TaptionEncoder-AMRWB-Proof-iPhone-17-Pro` with UDID `BCFE1251-F1C1-4637-A0F9-F47813B1DA81`.

The test confirms:

- The app can prepare the 3GP as a video source and inspect the H.263 video track.
- Host FFmpeg sees the `sawb` AMR-WB audio track, but the initial app inspection path did not surface that audio track as `TaptionAudioTrackInfo`.
- The prepared app plan has no `audioPlan`, so AMR-WB is not promoted to current-build AAC execution.
- No H.265/AAC output is claimed for AMR-WB in this pass.

## Follow-Up App-Side Simulator Execution Proof

The follow-up implementation made `AVFoundationMediaInspector` fall back to the bundled VLC metadata path when a 3GP/3GPP2 asset has no AVFoundation audio tracks. This keeps the fallback narrow to legacy telephony containers while letting the existing `sawb` parser and bundled VLC audio callback path surface AMR-WB as the app's `.amr` family route.

Command:

```sh
SIM_ID=$(xcrun simctl create TaptionEncoder-AMRWB-$(date +%s) \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath /tmp/taption_encoder_amrwb_exec_dd \
  -resultBundlePath /tmp/taption_encoder_amrwb_exec_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealAMRWBH263SampleEncodesHEVCWithAACAudio
rm -f /tmp/taption_run_local_real_sample_tests
```

Result:

- Passed: 1
- Failed: 0
- Skipped: 0
- Simulator: iPhone 17 Pro, iOS 26.5, build `23F77`
- Simulator ID: `AC54C59E-BB85-4DDC-8810-BBFFB6835DA7`
- Result bundle: `/tmp/taption_encoder_amrwb_exec_result.xcresult`

Key runtime evidence from the passing test log:

- `audioRoute=AMR to AAC`
- `audioPath=SW`
- `output=H.265 / HEVC / MP4`
- `Codec algorithm selected backend=softwareVLCDecoder mode=software`
- `Performance trace mark audioTracks=1`
- `Software H.263 transcode pipeline completed`
- `frames=45`
- `audioSampleBuffers=150`
- `audioSamples=143966`
- Source-preserving output verification passed with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=48000`
  - `actualAudioChannels=1`
  - `actualDuration=3.000`
  - `actualFrameRate=15000/1000`
  - `actualResolution=176x144`

Test assertions also verified:

- source container: 3GP
- source video codec: H.263
- source audio codec: AMR family, representing the host-visible `sawb` AMR-WB track
- source audio sample rate: 16 kHz
- source audio channel count: 1
- output container: MP4
- output video codec: H.265 / HEVC
- output audio codec: AAC
- output audio sample rate: 48 kHz
- output audio channel count: 1

Related regression check:

```sh
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=AC54C59E-BB85-4DDC-8810-BBFFB6835DA7" \
  -derivedDataPath /tmp/taption_encoder_amrwb_exec_dd \
  -resultBundlePath /tmp/taption_encoder_amrnb_regression_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealAMRNBH263SampleEncodesHEVCWithAACAudio
rm -f /tmp/taption_run_local_real_sample_tests
```

Result: passed, 1 selected test, 0 failures. Result bundle: `/tmp/taption_encoder_amrnb_regression_result.xcresult`.

## Bundled Resource Regression Proof

The AMR-WB 3GP sample was promoted into the bundled `TestVideos` folder as `AMR-WB H.263.3gp` and paired with a 320x180 thumbnail resource:

```text
TaptionEncoder/TestVideos/AMR-WB H.263.3gp
TaptionEncoder/SampleThumbnails/sample-thumbnail-amr_wb_h_263_3gp.png
```

The bundled sample is a 5-second stream-looped derivative of the local generated 3GP sample. Its SHA-256 is:

```text
f31b08cc128645b1b2572eb0c2101ef66ec64753d7cc76da79c8fe69a3a7d6be
```

Command:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=638F2CB7-6CC6-49FE-8C63-CCE3DB1A3A61" \
  -derivedDataPath /tmp/taption_encoder_amrwb_bundle_dd \
  -resultBundlePath /tmp/taption_encoder_amrwb_bundle_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledTestVideosMatchCurrentLaunchVideoSupport \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledSampleSourceNoticeRejectsGeneratedOnlyFixtures \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledSampleThumbnailResourcesCoverSeededVideos \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledAvailableNowSamplesInspectToExpectedLaunchCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledAvailableNowSamplesAreReadyOnSoftwareOnlyProfile
```

Result:

- Passed: 5.
- Failed: 0.
- Skipped: 0.
- Simulator: iPhone 17 Pro, iOS 26.5, build `23F77`.
- Simulator ID: `638F2CB7-6CC6-49FE-8C63-CCE3DB1A3A61`.
- Result bundle: `/tmp/taption_encoder_amrwb_bundle_result.xcresult`.
- App log showed `Test video samples seeded copied=58`, which is 57 video samples plus `SAMPLE_SOURCES.txt`.

This is simulator bundled-resource regression proof only. It is not real-device runtime proof or TestFlight/App Store Connect proof.

## Real-Device App-Side Runtime Proof

Command:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008112-000964980E45401E' \
  -derivedDataPath /tmp/taption_encoder_real_device_amrwb_dd \
  -resultBundlePath /tmp/taption_encoder_real_device_amrwb_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testRealDeviceBundledAMRWBH263SampleEncodesHEVCWithAACAudio
```

Result:

- Passed: 1.
- Failed: 0.
- Skipped: 0.
- Test duration: 8.285 seconds.
- Device: iPad Pro 12.9-inch (6th generation), runtime model `iPad14,6`, iPadOS 26.5, build `23F77`.
- Result bundle: `/tmp/taption_encoder_real_device_amrwb_result.xcresult`.

Key runtime evidence from the passing test log:

- `Codec transcode started` reported `audioRoute=AMR to AAC`, `audioPath=SW`, `output=H.265 / HEVC / MP4`, `route=H.263 to H.265 / HEVC`, `preserveResolution=176x144`, and `preserveFrameRate=15000/1000`.
- `Software H.263 transcode pipeline completed` reported `frames=75` and `audioSampleBuffers=250`.
- `Performance trace finished` reported `audioSamples=239589`, `frames=75`, and `phase=completed`.
- `Source-preserving output verification passed` reported `actualAudioTracks=1`, `actualAudioSampleRate=48000`, `actualAudioChannels=1`, `actualDuration=5.000`, `actualFrameRate=15000/1000`, and `actualResolution=176x144`.
- `Codec transcode completed` reported `backend=softwareVLCDecoder` and `mode=software`.

Test assertions also verified:

- source container: 3GP
- source video codec: H.263
- source audio codec: AMR family, representing the host-visible `sawb` AMR-WB track
- source audio sample rate: 16 kHz
- source audio channel count: 1
- output container: MP4
- output video codec: H.265 / HEVC
- output audio codec: AAC
- output audio sample rate: 48 kHz
- output audio channel count: 1

## Follow-Up Non-AAC Output Route Proof

AMR-WB was also exercised through the current non-AAC MOV output routes after the AAC/MP4 proof. This is recorded separately from the original sample acquisition and AAC runtime proof because it validates output audio route breadth rather than sample availability.

Simulator command:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,id=A5C810F9-20A8-46B7-B4BF-8AF3399D00C1' \
  -derivedDataPath /tmp/taption_encoder_amrwb_nonaac_sim_dd \
  -resultBundlePath /tmp/taption_encoder_amrwb_nonaac_sim_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testSourcePreservingAudioOptionsResolverRaisesAMRSampleRateForCurrentAppleWriters \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledAMRWBH263SampleEncodesHEVCMOVWithPCMAudio \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledAMRWBH263SampleEncodesHEVCMOVWithALACAudio
```

Simulator result:

- Passed: 4.
- Failed: 0.
- Skipped: 0.
- Result bundle: `/tmp/taption_encoder_amrwb_nonaac_sim_result.xcresult`.

Real-device command:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008112-000964980E45401E' \
  -derivedDataPath /tmp/taption_encoder_amrwb_nonaac_ipad_dd \
  -resultBundlePath /tmp/taption_encoder_amrwb_nonaac_ipad_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledAMRWBH263SampleEncodesHEVCMOVWithPCMAudio \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledAMRWBH263SampleEncodesHEVCMOVWithALACAudio
```

Real-device result:

- Passed: 2.
- Failed: 0.
- Skipped: 0.
- Device: iPad Pro 12.9-inch (6th generation), runtime model `iPad14,6`, iPadOS 26.5, build `23F77`.
- Result bundle: `/tmp/taption_encoder_amrwb_nonaac_ipad_result.xcresult`.

The follow-up proof verified bundled `AMR-WB H.263.3gp` to H.265 MOV with PCM 48 kHz mono output and H.265 MOV with ALAC 48 kHz mono output through bundled software VLC decode feeding the Apple-native writer.

## Outcome

- Decodable AMR-WB sample acquisition is no longer blocked at the host/sample level.
- AMR-WB app-side execution now has focused simulator proof through the current bundled VLC decode path feeding AAC output in MP4.
- AMR-WB now has a bundled sample and focused real-device iPad Debug XCTest proof for H.263/AMR-WB 3GP to H.265 MP4 with AAC 48 kHz mono output, plus H.265 MOV with PCM and ALAC 48 kHz mono output.
- The previous AMR-WB+ sample remains a negative sample.
- AMR-WB+ still needs a decodable positive sample or a clear unsupported decision from the selected broad backend.
