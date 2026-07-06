# Non-AAC Audio Output Route Proof - 2026-07-07

## Scope

- Repository: `/Users/u_mo_c/Documents/taption_encoder`
- Feature surface: current-build bundled software audio decode feeding Apple `AVAssetWriter` with non-AAC audio output.
- Output contract: video output remains H.265 / HEVC only; writable output containers remain MP4/MOV only.
- Proof surface: focused simulator XCTest plus real-device Debug XCTest on a paired iPad. Simulator and real-device results are recorded separately below. This is not host FFmpeg proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

## Implemented Routes

- Source sample: bundled `TaptionEncoder/TestVideos/Theora.ogv`
- Source media: Theora video plus Opus audio
- Output: H.265 / HEVC video in MOV with Linear PCM audio
- Executed audio route: `Opus to PCM`
- Output: H.265 / HEVC video in MOV with Apple Lossless / ALAC audio
- Executed audio route: `Opus to Apple Lossless`
- Source sample: bundled `TaptionEncoder/TestVideos/AMR-WB H.263.3gp`
- Source media: H.263 video plus AMR-WB (`sawb`) audio, surfaced as the app AMR-family route
- Output: H.265 / HEVC video in MOV with Linear PCM audio
- Executed audio route: `AMR to PCM`
- Output: H.265 / HEVC video in MOV with Apple Lossless / ALAC audio
- Executed audio route: `AMR to Apple Lossless`
- Source sample: bundled `TaptionEncoder/TestVideos/Flash Video.flv`
- Source media: Flash Video plus MP3 audio
- Output: H.265 / HEVC video in MOV with Linear PCM audio
- Executed audio route: `MP3 to PCM`
- Output: H.265 / HEVC video in MOV with Apple Lossless / ALAC audio
- Executed audio route: `MP3 to Apple Lossless`
- Source sample: bundled `TaptionEncoder/TestVideos/QuickTime Video.mov`
- Source media: QuickTime Video / RPZA plus AAC audio
- Output: H.265 / HEVC video in MOV with Linear PCM audio
- Executed audio route: `AAC to PCM`
- Output: H.265 / HEVC video in MOV with Apple Lossless / ALAC audio
- Executed audio route: `AAC to Apple Lossless`
- Source sample: bundled `TaptionEncoder/TestVideos/H.264 AC3.mp4`
- Source media: H.264 video plus AC3 / Dolby Digital audio
- Output: H.265 / HEVC video in MOV with Linear PCM audio
- Executed audio route: `Dolby Digital to PCM`
- Output: H.265 / HEVC video in MOV with Apple Lossless / ALAC audio
- Executed audio route: `Dolby Digital to Apple Lossless`
- Source sample: bundled `TaptionEncoder/TestVideos/H.264 EAC3.mp4`
- Source media: H.264 video plus E-AC-3 / Dolby Digital Plus audio
- Output: H.265 / HEVC video in MOV with Linear PCM audio
- Executed audio route: `Dolby Digital Plus to PCM`
- Output: H.265 / HEVC video in MOV with Apple Lossless / ALAC audio
- Executed audio route: `Dolby Digital Plus to Apple Lossless`
- Execution backend: bundled software VLC video decode feeding the Apple-native output writer. Opus, AMR-family, AC3, and EAC3 audio use bundled software VLC audio decode for the proved software-video path; MP3 and AAC use the current Apple-native audio transcode route while the video path still runs through the software writer.

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
- `TaptionSourcePreservingAudioOptionsResolver` now normalizes low-rate AMR-family sources to 48 kHz for AAC, PCM, and ALAC writer outputs so source-preserving verification matches the Apple writer path.
- `CodecRoutePlannerTests` now verifies AMR-to-PCM and AMR-to-ALAC current-build readiness, plus bundled `AMR-WB H.263.3gp` execution to H.265 MOV with PCM and ALAC audio.
- `CodecRoutePlannerTests` also verifies bundled `Flash Video.flv` execution to H.265 MOV with MP3-to-PCM and MP3-to-ALAC output through the Apple-native audio transcode route while the video route stays on the bundled software VLC decoder.
- `CodecRoutePlannerTests` now also verifies bundled `QuickTime Video.mov` execution to H.265 MOV with AAC-to-PCM and AAC-to-ALAC output through the Apple-native audio transcode route while the video route stays on the bundled software VLC decoder.
- `SW_AudioCodecSupportCatalog` and `AudioCodecRoutePlanner` now allow AC3/EAC3-to-PCM and AC3/EAC3-to-ALAC MOV output through the current bundled VLC audio decode path when the software video writer path is selected.
- `CodecRoutePlannerTests` now verifies bundled `H.264 AC3.mp4` and `H.264 EAC3.mp4` execution to H.265 MOV with Dolby-to-PCM and Dolby-to-ALAC output on the requested software path.

## Simulator Regression Proof - H.264 AC3 PCM/ALAC

Command:

```sh
rm -rf /tmp/taption_encoder_ac3_nonaac_sim_dd /tmp/taption_encoder_ac3_nonaac_sim_result.xcresult && xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,id=A5C810F9-20A8-46B7-B4BF-8AF3399D00C1' \
  -derivedDataPath /tmp/taption_encoder_ac3_nonaac_sim_dd \
  -resultBundlePath /tmp/taption_encoder_ac3_nonaac_sim_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledH264AC3SampleEncodesHEVCMOVWithPCMAudioOnSoftwarePath \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledH264AC3SampleEncodesHEVCMOVWithALACAudioOnSoftwarePath
```

Result:

- Passed: 3.
- Failed: 0.
- Skipped: 0.
- Simulator: iPhone 17 Pro, iOS 26.5, build `23F77`.
- Simulator ID: `A5C810F9-20A8-46B7-B4BF-8AF3399D00C1`.
- Result bundle: `/tmp/taption_encoder_ac3_nonaac_sim_result.xcresult`.

Key runtime evidence from the passing test log:

- `audioRoute=Dolby Digital to PCM`
- `audioRoute=Dolby Digital to Apple Lossless`
- `audioPath=SW`
- `output=H.265 / HEVC / MOV`
- `route=H.264 / AVC to H.265 / HEVC`
- `Software H.264 transcode pipeline completed`
- `frames=120`
- `audioSampleBuffers=144`
- `audioSamples=221184`
- Source-preserving output verification passed with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=44100`
  - `actualAudioChannels=2`
  - `actualDuration=5.016`
  - `actualFrameRate=24000/1000`
  - `actualResolution=320x180`

Test assertions also verified:

- source container: MP4
- source video codec: H.264 / AVC
- source audio codec: AC3 / Dolby Digital
- source audio sample rate: 44.1 kHz
- source audio channel count: 2
- output container: MOV
- output video codec: H.265 / HEVC
- output audio codecs: PCM and ALAC
- output audio sample rate: 44.1 kHz
- output audio channel count: 2

This is focused simulator regression evidence only. It is not real-device proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

## Simulator Regression Proof - H.264 EAC3 PCM/ALAC

Command:

```sh
rm -rf /tmp/taption_encoder_eac3_nonaac_sim_dd /tmp/taption_encoder_eac3_nonaac_sim_result.xcresult && xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,id=A5C810F9-20A8-46B7-B4BF-8AF3399D00C1' \
  -derivedDataPath /tmp/taption_encoder_eac3_nonaac_sim_dd \
  -resultBundlePath /tmp/taption_encoder_eac3_nonaac_sim_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledH264EAC3SampleEncodesHEVCMOVWithPCMAudioOnSoftwarePath \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledH264EAC3SampleEncodesHEVCMOVWithALACAudioOnSoftwarePath
```

Result:

- Passed: 3.
- Failed: 0.
- Skipped: 0.
- Test duration: 16.376 seconds.
- Simulator ID: `A5C810F9-20A8-46B7-B4BF-8AF3399D00C1`.
- Result bundle: `/tmp/taption_encoder_eac3_nonaac_sim_result.xcresult`.

Key runtime evidence from the passing test log:

- `audioRoute=Dolby Digital Plus to PCM`
- `audioPath=SW`
- `backend=softwareVLCDecoder`
- `output=H.265 / HEVC / MOV`
- `route=H.264 / AVC to H.265 / HEVC`
- `Software H.264 transcode pipeline completed`
- `frames=120`
- `audioSampleBuffers=144`
- `audioSamples=221184`
- Source-preserving output verification passed with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=44100`
  - `actualAudioChannels=2`
  - `actualDuration=5.016`
  - `actualFrameRate=24000/1000`
  - `actualResolution=320x180`

Test assertions also verified:

- source container: MP4
- source video codec: H.264 / AVC
- source audio codec: E-AC-3 / Dolby Digital Plus
- source audio sample rate: 44.1 kHz
- source audio channel count: 2
- output container: MOV
- output video codec: H.265 / HEVC
- output audio codecs: PCM and ALAC
- output audio sample rate: 44.1 kHz
- output audio channel count: 2

This is focused simulator regression evidence only. It is not real-device proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

## Device XCTest Proof - H.264 AC3 PCM/ALAC

Command:

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

Result:

- Result: passed.
- Selected tests: 2.
- Failures: 0.
- Test duration: 16.262 seconds.
- Device: iPad Pro 12.9-inch 6th generation.
- Device ID: `00008112-000964980E45401E`.
- OS: iOS/iPadOS 26.5.
- Result bundle: `/tmp/taption_encoder_ac3_realdevice_result.xcresult`.

Runtime log evidence:

- `Codec transcode started` reported `audioPath=SW`, `audioRoute=Dolby Digital to Apple Lossless`, `output=H.265 / HEVC / MOV`, `route=H.264 / AVC to H.265 / HEVC`, `preserveResolution=320x180`, and `preserveFrameRate=24000/1000`.
- `Codec transcode started` also reported `audioRoute=Dolby Digital to PCM` for the PCM/MOV route.
- `Software H.264 transcode pipeline completed` reported `frames=120` and `audioSampleBuffers=144` for both routes.
- `Performance trace finished` reported `audioSamples=221184`, `frames=120`, and `phase=completed`.
- `Source-preserving output verification passed` reported `actualAudioTracks=1`, `actualAudioSampleRate=44100`, `actualAudioChannels=2`, `actualDuration=5.016`, `actualFrameRate=24000/1000`, and `actualResolution=320x180`.
- `Codec transcode completed` reported `backend=softwareVLCDecoder` and `mode=software`.

This is focused real-device Debug XCTest route-execution evidence. It is not simulator proof, host FFmpeg proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

## Device XCTest Proof - H.264 EAC3 PCM/ALAC

Command:

```sh
rm -rf /tmp/taption_encoder_eac3_ipad_dd /tmp/taption_encoder_eac3_ipad_result.xcresult && xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008112-000964980E45401E' \
  -derivedDataPath /tmp/taption_encoder_eac3_ipad_dd \
  -resultBundlePath /tmp/taption_encoder_eac3_ipad_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledH264EAC3SampleEncodesHEVCMOVWithPCMAudioOnSoftwarePath \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledH264EAC3SampleEncodesHEVCMOVWithALACAudioOnSoftwarePath
```

Result:

- Result: passed.
- Selected tests: 2.
- Failures: 0.
- Test duration: 15.942 seconds.
- Device: iPad Pro 12.9-inch 6th generation.
- Device ID: `00008112-000964980E45401E`.
- OS: iOS/iPadOS 26.5.
- Result bundle: `/tmp/taption_encoder_eac3_ipad_result.xcresult`.

Runtime log evidence:

- `Codec transcode started` reported `audioRoute=Dolby Digital Plus to PCM`, `audioPath=SW`, `output=H.265 / HEVC / MOV`, `route=H.264 / AVC to H.265 / HEVC`, `preserveResolution=320x180`, and `preserveFrameRate=24000/1000`.
- `Codec transcode started` also reported `audioRoute=Dolby Digital Plus to Apple Lossless` for the ALAC/MOV route.
- `Software H.264 transcode pipeline completed` reported `frames=120` and `audioSampleBuffers=144` for both routes.
- `Performance trace finished` reported `audioSamples=221184`, `frames=120`, and `phase=completed`.
- `Source-preserving output verification passed` reported `actualAudioTracks=1`, `actualAudioSampleRate=44100`, `actualAudioChannels=2`, `actualDuration=5.016`, `actualFrameRate=24000/1000`, and `actualResolution=320x180`.
- `Codec transcode completed` reported `backend=softwareVLCDecoder` and `mode=software`.

This is focused real-device Debug XCTest route-execution evidence. It is not simulator proof, host FFmpeg proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

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

## Simulator Regression Proof - AMR-WB PCM/ALAC

Command:

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

Result:

- Passed: 4.
- Failed: 0.
- Skipped: 0.
- Simulator: iPhone 17 Pro, iOS 26.5, build `23F77`.
- Simulator ID: `A5C810F9-20A8-46B7-B4BF-8AF3399D00C1`.
- Result bundle: `/tmp/taption_encoder_amrwb_nonaac_sim_result.xcresult`.

This is simulator regression evidence only. It is not real-device proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

The assertions verified:

- AMR-to-PCM and AMR-to-ALAC route selection use bundled software VLC decode and Apple-native output writing.
- The AMR-family source-preserving writer options raise the source 16 kHz mono track to 48 kHz mono for AAC, PCM, and ALAC writer outputs.
- Bundled `AMR-WB H.263.3gp` encodes to H.265 MOV with PCM audio at 48 kHz mono.
- Bundled `AMR-WB H.263.3gp` encodes to H.265 MOV with ALAC audio at 48 kHz mono.

## Device XCTest Proof - AMR-WB PCM/ALAC

Command:

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

Result:

- Passed: 2.
- Failed: 0.
- Skipped: 0.
- Device: iPad Pro 12.9-inch 6th generation, runtime model `iPad14,6`.
- Device ID: `00008112-000964980E45401E`.
- OS: iOS/iPadOS 26.5, build `23F77`.
- Result bundle: `/tmp/taption_encoder_amrwb_nonaac_ipad_result.xcresult`.

Key runtime evidence from the passing test log:

- `audioRoute=AMR to PCM`
- `audioRoute=AMR to Apple Lossless`
- `audioPath=SW`
- `output=H.265 / HEVC / MOV`
- `route=H.263 to H.265 / HEVC`
- `Software H.263 transcode pipeline completed`
- `frames=75`
- `audioSampleBuffers=250`
- `Source-preserving output verification passed` with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=48000`
  - `actualAudioChannels=1`
  - `actualDuration=5.000`
  - `actualFrameRate=15000/1000`
  - `actualResolution=176x144`

Test assertions also verified:

- source container: 3GP
- source video codec: H.263
- source audio codec: AMR family, representing the host-visible `sawb` AMR-WB track
- source audio sample rate: 16 kHz
- source audio channel count: 1
- output container: MOV
- output video codec: H.265 / HEVC
- output audio codecs: PCM and ALAC
- output audio sample rate: 48 kHz
- output audio channel count: 1

## Simulator Regression Proof - Flash Video MP3 PCM/ALAC

Command:

```sh
rm -rf /tmp/taption_encoder_mp3_nonaac_sim_dd && xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,id=A5C810F9-20A8-46B7-B4BF-8AF3399D00C1' \
  -derivedDataPath /tmp/taption_encoder_mp3_nonaac_sim_dd \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledFlashVideoMP3SampleEncodesHEVCMOVWithPCMAudio \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledFlashVideoMP3SampleEncodesHEVCMOVWithALACAudio
```

Result:

- Passed: 3.
- Failed: 0.
- Skipped: 0.
- Simulator: iPhone 17 Pro, iOS 26.5, build `23F77`.
- Simulator ID: `A5C810F9-20A8-46B7-B4BF-8AF3399D00C1`.
- Temporary result path during the run: `/tmp/taption_encoder_mp3_nonaac_sim_dd/Logs/Test/Test-TaptionEncoder-2026.07.07_03-56-41-+0900.xcresult`.

Key runtime evidence from the passing test log:

- `audioRoute=MP3 to PCM`
- `audioRoute=MP3 to Apple Lossless`
- `audioPath=HW`
- `output=H.265 / HEVC / MOV`
- `route=Flash Video to H.265 / HEVC`
- `Software Flash Video transcode pipeline completed`
- `frames=50`
- Source-preserving output verification passed with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=44100`
  - `actualAudioChannels=2`
  - `actualDuration=5.000`
  - `actualFrameRate=10000/1000`
  - `actualResolution=160x120`

This is simulator regression evidence only. It is not real-device proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

## Device XCTest Proof - Flash Video MP3 PCM/ALAC

Command:

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

Result:

- Passed: 2.
- Failed: 0.
- Skipped: 0.
- Device: iPad Pro 12.9-inch 6th generation, runtime model `iPad14,6`.
- Device ID: `00008112-000964980E45401E`.
- OS: iOS/iPadOS 26.5, build `23F77`.
- Temporary result path during the run: `/tmp/taption_encoder_mp3_nonaac_ipad_dd/Logs/Test/Test-TaptionEncoder-2026.07.07_03-57-51-+0900.xcresult`.

Key runtime evidence from the passing test log:

- `audioRoute=MP3 to PCM`
- `audioRoute=MP3 to Apple Lossless`
- `audioPath=HW`
- `output=H.265 / HEVC / MOV`
- `route=Flash Video to H.265 / HEVC`
- `Software Flash Video transcode pipeline completed`
- `frames=50`
- `audioSampleBuffers=135` on the PCM route
- `audioSampleBuffers=139` on the ALAC route
- Source-preserving output verification passed with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=44100`
  - `actualAudioChannels=2`
  - `actualDuration=5.000`
  - `actualFrameRate=10000/1000`
  - `actualResolution=160x120`

Test assertions also verified:

- source container: FLV
- source video codec: Flash Video
- source audio codec: MP3
- source audio sample rate: 44.1 kHz
- source audio channel count: 2
- output container: MOV
- output video codec: H.265 / HEVC
- output audio codecs: PCM and ALAC
- output audio sample rate: 44.1 kHz
- output audio channel count: 2

## Simulator Regression Proof - QuickTime AAC PCM/ALAC

Command:

```sh
rm -rf /tmp/taption_encoder_aac_nonaac_sim_dd && xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,id=A5C810F9-20A8-46B7-B4BF-8AF3399D00C1' \
  -derivedDataPath /tmp/taption_encoder_aac_nonaac_sim_dd \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledQuickTimeVideoAACSampleEncodesHEVCMOVWithPCMAudio \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testBundledQuickTimeVideoAACSampleEncodesHEVCMOVWithALACAudio
```

Result:

- Passed: 2.
- Failed: 0.
- Skipped: 0.
- Simulator: iPhone 17 Pro, iOS 26.5, build `23F77`.
- Simulator ID: `A5C810F9-20A8-46B7-B4BF-8AF3399D00C1`.
- Temporary result path during the run: `/tmp/taption_encoder_aac_nonaac_sim_dd/Logs/Test/Test-TaptionEncoder-2026.07.07_04-05-22-+0900.xcresult`.

Key runtime evidence from the passing test log:

- `audioRoute=AAC to PCM`
- `audioRoute=AAC to Apple Lossless`
- `audioPath=HW`
- `output=H.265 / HEVC / MOV`
- `route=QuickTime Video to H.265 / HEVC`
- `Software QuickTime Video transcode pipeline completed`
- `frames=25`
- `audioSampleBuffers=129`
- Source-preserving output verification passed with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=48000`
  - `actualAudioChannels=2`
  - `actualDuration=5.000`
  - `actualFrameRate=5000/1000`
  - `actualResolution=160x120`

This is simulator regression evidence only. It is not real-device proof, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

## Device XCTest Proof - QuickTime AAC PCM/ALAC

Command:

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

Result:

- Passed: 2.
- Failed: 0.
- Skipped: 0.
- Device: iPad Pro 12.9-inch 6th generation, runtime model `iPad14,6`.
- Device ID: `00008112-000964980E45401E`.
- OS: iOS/iPadOS 26.5, build `23F77`.
- Temporary result path during the run: `/tmp/taption_encoder_aac_nonaac_ipad_dd/Logs/Test/Test-TaptionEncoder-2026.07.07_04-06-40-+0900.xcresult`.

Key runtime evidence from the passing test log:

- `audioRoute=AAC to PCM`
- `audioRoute=AAC to Apple Lossless`
- `audioPath=HW`
- `output=H.265 / HEVC / MOV`
- `route=QuickTime Video to H.265 / HEVC`
- `Software QuickTime Video transcode pipeline completed`
- `frames=25`
- `audioSampleBuffers=129`
- Source-preserving output verification passed with:
  - `actualAudioTracks=1`
  - `actualAudioSampleRate=48000`
  - `actualAudioChannels=2`
  - `actualDuration=5.000`
  - `actualFrameRate=5000/1000`
  - `actualResolution=160x120`

Test assertions also verified:

- source container: MOV
- source video codec: QuickTime Video
- source audio codec: AAC
- source audio sample rate: 48 kHz
- source audio channel count: 2
- output container: MOV
- output video codec: H.265 / HEVC
- output audio codecs: PCM and ALAC
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

- AMR-WB now has focused simulator and bundled real-device iPad Debug XCTest execution proof for AAC/MP4, PCM/MOV, and ALAC/MOV through the H.263/AMR-WB 3GP sample.
- MP3 now has focused simulator and bundled real-device iPad Debug XCTest execution proof for PCM/MOV and ALAC/MOV through the Flash Video/MP3 sample. This is an Apple-native audio route, separate from the bundled software VLC audio-decode proof for Opus and AMR-family samples.
- AAC now has focused simulator and bundled real-device iPad Debug XCTest execution proof for PCM/MOV and ALAC/MOV through the QuickTime Video/AAC sample.
- AC3 now has focused simulator and bundled real-device iPad Debug XCTest execution proof for PCM/MOV and ALAC/MOV through bundled `H.264 AC3.mp4` on the requested software path.
- EAC3 now has focused simulator and bundled real-device iPad Debug XCTest execution proof for PCM/MOV and ALAC/MOV through bundled `H.264 EAC3.mp4` on the requested software path.
- AMR-WB+ still needs a decodable positive sample.
- Broader non-AAC output routes beyond current sample-proven `PCM / MOV` and `ALAC / MOV` still need implementation and proof.
- FFmpeg-family or equivalent broad backend execution remains gated on bundled backend integration and license/App Store review.
