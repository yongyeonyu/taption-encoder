# Apple Device Codec Matrix

Date: 2026-06-16

## Purpose

Taption Encoder must automatically prefer hardware codecs when an iPhone or iPad supports them, then fall back to software when the device cannot decode or encode a route in hardware.

This document tracks the Apple device-family simulation matrix and the first runtime model-identifier seed table used by `HW_AppleDeviceCodecProfiles.swift`. It is still reconciled against real-device reports over time. Runtime probing remains the authority inside the app because VideoToolbox support varies by exact model, OS version, resolution, profile, bit depth, and active hardware-resource pressure.

## Runtime Authority

The app-side truth source is:

- Hardware decode: `VTIsHardwareDecodeSupported(_:)`
- Hardware encode: `VTCopySupportedPropertyDictionaryForEncoder(...)` with `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder`
- Route decision: `CodecRoutePlanner`
- Device Info report: `HW_CodecCapabilityProbe`
- Saved probe snapshots: `HW_DeviceCodecReportStore`

The static Apple profiles are only simulation inputs so tests can cover old-device, modern-device, AV1, ProRes, and mixed HW/SW behavior before every physical device is available.

The Device Info sheet can save a JSON snapshot containing the current device probe report, static matrix reconciliation, reusable route simulation summary, and universal codec completion audit. The default app path is Application Support under `TaptionEncoder/DeviceCodecReports`. Those runtime snapshots are collection evidence, not source files; anonymized or selected copies can later be moved into an ignored generated report folder for matrix reconciliation.

The reconciliation summary compares the runtime model identifier against `HW_AppleDeviceCodecModelMatrix`, then lists expected HW decode/encode codecs, probed HW decode/encode codecs, missing expected codecs, and unexpected codecs. Runtime probing remains the authority when it differs from static assumptions.

The archive analyzer can summarize multiple saved snapshots into known models, unknown model identifiers, static-matrix matches, and divergent reports. That lets real-device captures from several iPhone and iPad generations drive targeted matrix updates instead of treating every codec route failure as an isolated bug.

## Sources Used

- Apple Developer: `VTIsHardwareDecodeSupported(_:)`
  <https://developer.apple.com/documentation/videotoolbox/vtishardwaredecodesupported(_:)>
- Apple Developer: `VTCopySupportedPropertyDictionaryForEncoder`
  <https://developer.apple.com/documentation/videotoolbox/vtcopysupportedpropertydictionaryforencoder(width:height:codectype:encoderspecification:encoderidout:supportedpropertiesout:)>
- Apple iPadOS 18 compatibility list
  <https://support.apple.com/en-us/104986>
- Apple iPhone models compatible with iOS 26
  <https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/ios>
- Apple iPad models compatible with iPadOS 26
  <https://support.apple.com/guide/ipad/ipad-models-compatible-with-ipados-26-ipad213a25b2/ipados>
- iPad 7th generation technical specifications
  <https://support.apple.com/en-us/111911>
- iPad 8th generation technical specifications
  <https://support.apple.com/en-us/118451>
- iPhone 15 Pro technical specifications
  <https://support.apple.com/en-us/111829>
- iPhone 16 technical specifications
  <https://support.apple.com/en-us/121029>
- iPhone 16 Pro technical specifications
  <https://support.apple.com/en-us/121031>
- iPhone 17 technical specifications
  <https://support.apple.com/en-us/125089>
- iPhone 17 Pro technical specifications
  <https://support.apple.com/en-us/125090>
- iPhone 17 Pro Max technical specifications
  <https://support.apple.com/en-us/125091>
- iPhone Air technical specifications
  <https://support.apple.com/en-us/125092>
- iPhone 17e technical specifications
  <https://support.apple.com/en-us/126470>
- iPad Air M2 technical specifications
  <https://support.apple.com/en-us/119893>
- iPad Pro M4 technical specifications
  <https://support.apple.com/en-us/119892>
- Current iPad Pro media-engine specifications
  <https://www.apple.com/ipad-pro/specs/>
- Current iPad Air media-engine specifications
  <https://www.apple.com/ipad-air/specs/>

## Simulation Profiles

The current profile catalog lives in:

```text
TaptionEncoder/Core/Codecs/HW_AppleDeviceCodecProfiles.swift
```

The current model-identifier seed table also lives in that file as `HW_AppleDeviceCodecModelMatrix`. It maps current iOS/iPadOS 18+ iPhone and iPad runtime identifiers such as `iPhone16,1`, `iPhone17,3`, `iPhone18,1`, `iPad7,11`, and `iPad16,3` onto the family profiles below. These model rows are simulation inputs, not a replacement for saved real-device probe snapshots.

| Profile ID | Representative class | HW decode model | HW encode model | AV1 route expectation |
| --- | --- | --- | --- | --- |
| `apple_ipados18_legacy_a10_h264` | iPad 7th generation / A10 | H.264 only | H.264 only | `AV1 -> H.265` uses `SW` |
| `apple_ios18_a12_h264_hevc` | iPhone XS/XR, A12/A12X/A12Z iPads including iPad 8th generation | H.264, H.265/HEVC family | H.264, H.265/HEVC | `HW/SW` |
| `apple_a13_a14_h264_hevc` | iPhone 11/12, A13/A14 iPads from iPad 9th/10th generation and iPad Air 4th generation | H.264, H.265/HEVC family | H.264, H.265/HEVC | `HW/SW` |
| `apple_a15_a16_h264_hevc` | iPhone 13/14/base 15, A15/A16 iPads | H.264, H.265/HEVC family | H.264, H.265/HEVC | `HW/SW` |
| `apple_iphone_pro_a15_a16_prores` | iPhone 13 Pro / 14 Pro | H.264, H.265/HEVC, ProRes | H.264, H.265/HEVC, ProRes | `HW/SW` |
| `apple_ipad_pro_m1_m2_prores` | M1/M2 iPad Pro | H.264, H.265/HEVC, ProRes, ProRes RAW | H.264, H.265/HEVC, ProRes | `HW/SW` |
| `apple_ipad_air_m1_m2_h264_hevc` | M1/M2 iPad Air | H.264, H.265/HEVC family | H.264, H.265/HEVC | `HW/SW` |
| `apple_a17pro_av1_decode` | iPhone 15 Pro, iPad mini A17 Pro | H.264, H.265/HEVC, AV1, ProRes-class | H.264, H.265/HEVC, ProRes-class | `HW` |
| `apple_a18_av1_decode` | iPhone 16 / 16 Plus / 16e | H.264, H.265/HEVC, AV1 | H.264, H.265/HEVC | `HW` |
| `apple_a18pro_av1_decode_prores` | iPhone 16 Pro family | H.264, H.265/HEVC, AV1, ProRes | H.264, H.265/HEVC, ProRes | `HW` |
| `apple_a19_av1_decode` | iPhone 17 / 17e | H.264, H.265/HEVC, AV1 | H.264, H.265/HEVC | `HW` |
| `apple_a19pro_av1_decode` | iPhone Air | H.264, H.265/HEVC, AV1 | H.264, H.265/HEVC | `HW` |
| `apple_a19pro_av1_decode_prores_raw` | iPhone 17 Pro family | H.264, H.265/HEVC, AV1, ProRes, ProRes RAW | H.264, H.265/HEVC, ProRes | `HW` |
| `apple_ipad_m3_m4_av1_prores` | M3 iPad Air, M4 iPad Pro | H.264, H.265/HEVC, AV1, ProRes, ProRes RAW | H.264, H.265/HEVC, ProRes | `HW` |

Meaning of `AV1 -> H.265` expectation:

- `SW`: neither AV1 hardware decode nor H.265 hardware encode is assumed available.
- `HW/SW`: AV1 decode falls back to software, then H.265 encode uses hardware.
- `HW`: AV1 hardware decode and H.265 hardware encode are both assumed available.

## Current Local Simulation

Command:

```sh
Scripts/simulate_codec_route_planner.sh Samples/CodecFixtures/transcode_reports/route_matrix_latest
```

Current output:

- Base generic + Apple family profiles: 19.
- Static model identifier rows: 93.
- Total simulation profiles after adding model identifiers: 112.
- Source codecs: 63.
- Output codecs: 1 (`hevc`).
- Routes per profile: 63.
- Total route rows: 7,056.
- Output file rows including header: 7,057.

Static model coverage report:

- iPhone model rows: 35.
- iPad model rows: 58.
- AV1 hardware decode model rows: 22.
- H.265/HEVC hardware encode model rows: 91.
- H.264-only fallback rows: 2.
- ProRes hardware encode model rows: 32.
- Profile/chip-family mismatches: 0.

The simulator fails if:

- Any planned source-to-H.265 pair is missing.
- Any implemented route reports `Planned` or `Unsupported`.
- Any implemented route with both HW decode and HW encode support fails to prefer `HW`.

## Remaining Work

- Continue reconciling the seeded per-model identifier table against official specs and physical-device reports.
- Collect saved `HW_DeviceCodecReportStore` snapshots from representative real iPhones and iPads.
- Store anonymized copies of selected probe snapshots in a generated report folder ignored by git.
- Add resolution/bit-depth/profile-specific probes, especially 4K, HDR, Main10, ProRes, and AV1.
- Reconcile profile assumptions with actual VideoToolbox results when they differ from broad Apple marketing/spec wording.
