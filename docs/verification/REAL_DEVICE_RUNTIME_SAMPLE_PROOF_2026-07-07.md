# Real-Device Runtime Sample Proof - 2026-07-07

## Scope

- Purpose: collect a real-device runtime sample encode proof separately from simulator, host-tool, hardware-capability, TestFlight, App Store Connect, App Review, and public-release evidence.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Device: iPad Pro 12.9-inch (6th generation), runtime model `iPad14,6`, iPadOS 26.5.
- App build under test: Debug XCTest host app reporting Taption Encoder `1.1.0 (30)`.
- Output policy remains unchanged: Taption Encoder outputs H.265 / HEVC video only, and implemented output containers remain MP4/MOV only.

This is real-device Debug XCTest runtime evidence for focused bundled samples. It is not simulator proof, not host FFmpeg proof, not a full benchmark, not TestFlight/App Store Connect proof, not App Review proof, and not public-release proof.

## Implementation

- `CodecRoutePlannerTests.bundledTestVideosURL()` now resolves bundled sample videos from the host app bundle before falling back to the test bundle or source-tree path. This keeps physical-device XCTest from passing Mac source paths to the app runtime.
- Added `testRealDeviceBundledTheoraOpusSampleEncodesHEVCWithAACAudio` as a focused physical-device test. The test skips on simulator builds and exercises only the bundled `Theora.ogv` sample.
- Added `testRealDeviceBundledAMRWBH263SampleEncodesHEVCWithAACAudio` as a focused physical-device test. The test skips on simulator builds and exercises only the bundled `AMR-WB H.263.3gp` sample.
- Added follow-up bundled AMR-WB non-AAC output tests for PCM/MOV and ALAC/MOV. Those tests are not physical-device-only, but the real-device command below executed them on the paired iPad and keeps their proof separate from simulator regression evidence.
- Added follow-up bundled Flash Video/MP3 non-AAC output tests for PCM/MOV and ALAC/MOV. These tests use the Apple-native MP3 audio transcode route while the video path remains the bundled software VLC decoder route.
- Added follow-up bundled QuickTime Video/AAC non-AAC output tests for PCM/MOV and ALAC/MOV. These tests use the Apple-native AAC audio transcode route while the video path remains the bundled software VLC decoder route.
- Added follow-up bundled H.264/AC3 non-AAC output tests for PCM/MOV and ALAC/MOV. These tests use the bundled software VLC audio decode route on the requested software path.

## Sample

| Sample | Source shape | Runtime expectation |
| --- | --- | --- |
| `Theora.ogv` | Theora video plus Opus audio, 320x240, 30 fps, 48 kHz stereo audio | Software VLC decode to H.265 MP4 with AAC stereo audio at 48 kHz. |
| `AMR-WB H.263.3gp` | H.263 video plus AMR-WB (`sawb`) audio, 176x144, 15 fps, 16 kHz mono audio, 5.000s bundled duration | Software VLC decode to H.265 MP4 with AAC mono audio at 48 kHz. |
| `AMR-WB H.263.3gp` | H.263 video plus AMR-WB (`sawb`) audio, 176x144, 15 fps, 16 kHz mono audio, 5.000s bundled duration | Software VLC decode to H.265 MOV with PCM mono audio at 48 kHz and H.265 MOV with ALAC mono audio at 48 kHz. |
| `Flash Video.flv` | Flash Video plus MP3 audio, 160x120, 10 fps, 44.1 kHz stereo audio, 5.000s bundled duration | Software VLC video decode to H.265 MOV with Apple-native MP3-to-PCM stereo audio at 44.1 kHz and H.265 MOV with Apple-native MP3-to-ALAC stereo audio at 44.1 kHz. |
| `QuickTime Video.mov` | QuickTime Video / RPZA plus AAC audio, 160x120, 5 fps, 48 kHz stereo audio, 5.000s bundled duration | Software VLC video decode to H.265 MOV with Apple-native AAC-to-PCM stereo audio at 48 kHz and H.265 MOV with Apple-native AAC-to-ALAC stereo audio at 48 kHz. |
| `H.264 AC3.mp4` | H.264 video plus AC3 / Dolby Digital audio, 320x180, 24 fps, 44.1 kHz stereo audio, 5.000s bundled duration | Software VLC video/audio decode to H.265 MOV with AC3-to-PCM stereo audio at 44.1 kHz and H.265 MOV with AC3-to-ALAC stereo audio at 44.1 kHz. |

## Theora Command

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008112-000964980E45401E' \
  -derivedDataPath /tmp/taption_encoder_real_device_runtime_dd \
  -resultBundlePath /tmp/taption_encoder_theora_opus_ipad_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testRealDeviceBundledTheoraOpusSampleEncodesHEVCWithAACAudio
```

## Theora Result

- Result: passed.
- Selected tests: 1.
- Failures: 0.
- Test duration: 8.319 seconds.
- Result bundle: `/tmp/taption_encoder_theora_opus_ipad_result.xcresult`.

Runtime log evidence:

- `Codec transcode started` reported `audioPath=SW`, `audioRoute=Opus to AAC`, `output=H.265 / HEVC / MP4`, `route=Theora to H.265 / HEVC`, `preserveResolution=320x240`, and `preserveFrameRate=30/1`.
- `Software Theora transcode pipeline completed` reported `frames=150` and `audioSampleBuffers=201`.
- `Performance trace finished` reported `audioSamples=192312`, `frames=150`, `totalMs=5631.5`, and `phase=completed`.
- `Source-preserving output verification passed` reported `actualAudioTracks=1`, `actualAudioSampleRate=48000`, `actualAudioChannels=2`, `actualDuration=5.000`, `actualFrameRate=30000/1000`, and `actualResolution=320x240`.
- `Codec transcode completed` reported `backend=softwareVLCDecoder` and `mode=software`.

## AMR-WB Command

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

## AMR-WB Result

- Result: passed.
- Selected tests: 1.
- Failures: 0.
- Test duration: 8.285 seconds.
- Result bundle: `/tmp/taption_encoder_real_device_amrwb_result.xcresult`.

Runtime log evidence:

- `Codec transcode started` reported `audioPath=SW`, `audioRoute=AMR to AAC`, `output=H.265 / HEVC / MP4`, `route=H.263 to H.265 / HEVC`, `preserveResolution=176x144`, and `preserveFrameRate=15000/1000`.
- `Software H.263 transcode pipeline completed` reported `frames=75` and `audioSampleBuffers=250`.
- `Performance trace finished` reported `audioSamples=239589`, `frames=75`, and `phase=completed`.
- `Source-preserving output verification passed` reported `actualAudioTracks=1`, `actualAudioSampleRate=48000`, `actualAudioChannels=1`, `actualDuration=5.000`, `actualFrameRate=15000/1000`, and `actualResolution=176x144`.
- `Codec transcode completed` reported `backend=softwareVLCDecoder` and `mode=software`.

## Flash Video MP3 Non-AAC MOV Command

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008112-000964980E45401E' \
  -derivedDataPath /tmp/taption_encoder_mp3_nonaac_ipad_dd \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledFlashVideoMP3SampleEncodesHEVCMOVWithPCMAudio \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledFlashVideoMP3SampleEncodesHEVCMOVWithALACAudio
```

## Flash Video MP3 Non-AAC MOV Result

- Result: passed.
- Selected tests: 2.
- Failures: 0.
- Test duration: 11.537 seconds.
- Temporary result path during the run: `/tmp/taption_encoder_mp3_nonaac_ipad_dd/Logs/Test/Test-TaptionEncoder-2026.07.07_03-57-51-+0900.xcresult`.

Runtime log evidence:

- `Codec transcode started` reported `audioRoute=MP3 to PCM`, `audioPath=HW`, `output=H.265 / HEVC / MOV`, `route=Flash Video to H.265 / HEVC`, `preserveResolution=160x120`, and `preserveFrameRate=10000/1000`.
- `Codec transcode started` also reported `audioRoute=MP3 to Apple Lossless` for the ALAC/MOV route.
- `Software Flash Video transcode pipeline completed` reported `frames=50`, `audioSampleBuffers=135` on the PCM route, and `audioSampleBuffers=139` on the ALAC route.
- `Source-preserving output verification passed` reported `actualAudioTracks=1`, `actualAudioSampleRate=44100`, `actualAudioChannels=2`, `actualDuration=5.000`, `actualFrameRate=10000/1000`, and `actualResolution=160x120`.
- `Codec transcode completed` reported `backend=softwareVLCDecoder` and `mode=software`.

## QuickTime AAC Non-AAC MOV Command

```sh
rm -rf /tmp/taption_encoder_aac_nonaac_ipad_dd && xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008112-000964980E45401E' \
  -derivedDataPath /tmp/taption_encoder_aac_nonaac_ipad_dd \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledQuickTimeVideoAACSampleEncodesHEVCMOVWithPCMAudio \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledQuickTimeVideoAACSampleEncodesHEVCMOVWithALACAudio
```

## QuickTime AAC Non-AAC MOV Result

- Result: passed.
- Selected tests: 2.
- Failures: 0.
- Test duration: 11.059 seconds.
- Temporary result path during the run: `/tmp/taption_encoder_aac_nonaac_ipad_dd/Logs/Test/Test-TaptionEncoder-2026.07.07_04-06-40-+0900.xcresult`.

Runtime log evidence:

- `Codec transcode started` reported `audioRoute=AAC to PCM`, `audioPath=HW`, `output=H.265 / HEVC / MOV`, `route=QuickTime Video to H.265 / HEVC`, `preserveResolution=160x120`, and `preserveFrameRate=5000/1000`.
- `Codec transcode started` also reported `audioRoute=AAC to Apple Lossless` for the ALAC/MOV route.
- `Software QuickTime Video transcode pipeline completed` reported `frames=25` and `audioSampleBuffers=129` for both routes.
- `Performance trace finished` reported `audioSamples=132096`, `frames=25`, and `phase=completed`.
- `Source-preserving output verification passed` reported `actualAudioTracks=1`, `actualAudioSampleRate=48000`, `actualAudioChannels=2`, `actualDuration=5.000`, `actualFrameRate=5000/1000`, and `actualResolution=160x120`.
- `Codec transcode completed` reported `backend=softwareVLCDecoder` and `mode=software`.

## AMR-WB Non-AAC MOV Command

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

## AMR-WB Non-AAC MOV Result

- Result: passed.
- Selected tests: 2.
- Failures: 0.
- Result bundle: `/tmp/taption_encoder_amrwb_nonaac_ipad_result.xcresult`.

Runtime log evidence:

- `Codec transcode started` reported `audioRoute=AMR to PCM`, `audioPath=SW`, `output=H.265 / HEVC / MOV`, `route=H.263 to H.265 / HEVC`, `preserveResolution=176x144`, and `preserveFrameRate=15000/1000`.
- `Codec transcode started` also reported `audioRoute=AMR to Apple Lossless` for the ALAC/MOV route.
- `Software H.263 transcode pipeline completed` reported `frames=75` and `audioSampleBuffers=250` for both routes.
- `Performance trace finished` reported `audioSamples=239589`, `frames=75`, and `phase=completed`.
- `Source-preserving output verification passed` reported `actualAudioTracks=1`, `actualAudioSampleRate=48000`, `actualAudioChannels=1`, `actualDuration=5.000`, `actualFrameRate=15000/1000`, and `actualResolution=176x144`.
- `Codec transcode completed` reported `backend=softwareVLCDecoder` and `mode=software`.

## H.264 AC3 Non-AAC MOV Command

```sh
rm -rf /tmp/taption_encoder_ac3_realdevice_dd /tmp/taption_encoder_ac3_realdevice_result.xcresult && xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008112-000964980E45401E' \
  -derivedDataPath /tmp/taption_encoder_ac3_realdevice_dd \
  -resultBundlePath /tmp/taption_encoder_ac3_realdevice_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledH264AC3SampleEncodesHEVCMOVWithPCMAudioOnSoftwarePath \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledH264AC3SampleEncodesHEVCMOVWithALACAudioOnSoftwarePath
```

## H.264 AC3 Non-AAC MOV Result

- Result: passed.
- Selected tests: 2.
- Failures: 0.
- Test duration: 16.262 seconds.
- Result bundle: `/tmp/taption_encoder_ac3_realdevice_result.xcresult`.

Runtime log evidence:

- `Codec transcode started` reported `audioRoute=Dolby Digital to PCM`, `audioPath=SW`, `output=H.265 / HEVC / MOV`, `route=H.264 / AVC to H.265 / HEVC`, `preserveResolution=320x180`, and `preserveFrameRate=24000/1000`.
- `Codec transcode started` also reported `audioRoute=Dolby Digital to Apple Lossless` for the ALAC/MOV route.
- `Software H.264 transcode pipeline completed` reported `frames=120` and `audioSampleBuffers=144` for both routes.
- `Performance trace finished` reported `audioSamples=221184`, `frames=120`, and `phase=completed`.
- `Source-preserving output verification passed` reported `actualAudioTracks=1`, `actualAudioSampleRate=44100`, `actualAudioChannels=2`, `actualDuration=5.016`, `actualFrameRate=24000/1000`, and `actualResolution=320x180`.
- `Codec transcode completed` reported `backend=softwareVLCDecoder` and `mode=software`.

Non-fatal runtime noise observed:

- Google Mobile Ads / UMP debug and account-configuration warnings.
- SKAdNetwork missing-identifier warning from the Google test ad stack.
- `DVTDevice: Error locating DeviceSupport directory` warning before launch.
- `UIRequiresFullScreen` future-compatibility warning.
- `Option --avcodec-hw no longer exists` warning from the bundled VLC path on the Flash Video/MP3 proof run.
- Source visual sample warnings in output verification. Output visual decodability was still verified; this pass is runtime encode proof, not bit-for-bit perceptual quality proof.

## Discarded Attempts

- An earlier iPad run of the broad representative bundled-sample XCTest failed and is not counted as proof. It tried five samples instead of the intended focused sample and used the Mac source-tree path on device before the bundle-resolution fix.
- An earlier iPhone run reached build/install but was interrupted after Xcode reported the iPhone was locked. It is not counted as proof.

## Follow-Up

- Collect the same focused real-device runtime sample proof on iPhone after the device is unlocked.
- Collect older-device runtime proof for thermal, battery, memory, and ETA warning threshold tuning.
- Keep AMR-WB+, VC-1 raw, and Y41P proof separate; this pass does not promote those routes.
