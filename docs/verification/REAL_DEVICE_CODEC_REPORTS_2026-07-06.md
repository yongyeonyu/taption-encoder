# Real-Device Codec Reports

Date: 2026-07-06

## Scope

This pass captures `HW_CodecCapabilityProbe` JSON reports from paired physical devices. It is real-device hardware capability evidence only. It is not TestFlight/App Store Connect proof, App Review proof, manual UI proof, or a real sample encode/playback proof.

Output policy remains unchanged: Taption Encoder keeps H.265 / HEVC as the only video output codec and MP4/MOV as the implemented output containers.

## Command

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=<device-id>' \
  -parallel-testing-enabled NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testCaptureRuntimeDeviceCodecReportWhenRequested \
  -resultBundlePath build/DeviceCodecReports/<device>.xcresult
```

## Captured Devices

| Device | Runtime model | OS | JSON proof | Result |
| --- | --- | --- | --- | --- |
| iPhone 14 Pro | `iPhone15,2` | iOS 26.5 | `docs/verification/device_codec_reports/hw-codec-report-iPhone15-2-2026-07-06.json` | Passed |
| iPad Pro 12.9-inch (6th generation) | `iPad14,6` | iPadOS 26.5 | `docs/verification/device_codec_reports/hw-codec-report-iPad14-6-2026-07-06.json` | Passed |

Both focused real-device XCTest runs passed with 1 selected test, 0 failures.

## Runtime Probe Summary

| Runtime model | Matched static profile | Missing expected decode | Unexpected decode | Missing expected encode | Unexpected encode |
| --- | --- | --- | --- | --- | --- |
| `iPhone15,2` | `apple_iphone_pro_a15_a16_prores` | none | `jpeg`, `motionJPEG`, `proResRaw` | none | `h263`, `hevcWithAlpha`, `jpeg`, `motionJPEG` |
| `iPad14,6` | `apple_ipad_pro_m1_m2_prores` | none | `jpeg`, `motionJPEG` | none | `h263`, `hevcWithAlpha`, `jpeg`, `motionJPEG` |

The current static matrix underestimates some runtime VideoToolbox capabilities on both devices. Runtime probing remains the installed-device authority; the static profiles should be updated conservatively only after more device captures confirm the same pattern.

## Route-Audit Counts

Both captured snapshots report:

- Video capability rows: 63
- Audio capability rows: 28
- Current-build runnable video routes: 56
- Pending runtime video routes: 7
- Video output selections: 2 (`H.265 + MP4`, `H.265 + MOV`)
- Audio route count: 784
- Broad software backend bundled: false
- Broad software backend executable: false
- Broad software backend requires license review: true

## Notes

- The focused test launches the Debug app on device and captures the report through `HW_DeviceCodecReportStore.makeSnapshot()`.
- The test log showed the existing AdMob consent configuration warning. That warning did not fail the codec report capture and is not codec proof.
- This pass does not prove that every reported hardware codec route is user-facing or executable in the current app. The app still gates current execution to H.265 output and the implemented MP4/MOV containers.

## Follow-Up

- Collect older iPhone/iPad class reports, especially A10/A12/A13/A14 and AV1-capable A17/M-series devices.
- Decide whether to update static profiles for JPEG/Motion JPEG decode/encode, HEVC-with-alpha encode, H.263 encode, and iPhone ProRes RAW decode after additional reports.
- Run real sample encode/playback proof separately from this hardware capability capture.
