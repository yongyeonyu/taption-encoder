# Device Codec Route Simulation

Date: 2026-06-16

## Purpose

This document describes the current route-selection simulation for Taption Encoder.

The final product must run on many iPhone and iPad generations. The app should always prefer hardware codecs when available, then fall back to software or mixed paths. Because real Apple devices differ by chip, OS version, resolution, bit depth, profile, thermal state, and active encoder availability, the app uses runtime probing on device and capability-profile simulation in development.

Apple device-family simulation profiles, model-identifier seed profiles, and reusable route simulation summaries are defined in `HW_AppleDeviceCodecProfiles.swift` and documented in `docs/APPLE_DEVICE_CODEC_MATRIX.md`.

## Script

Run:

```sh
Scripts/simulate_codec_route_planner.sh
```

Optional output folder:

```sh
Scripts/simulate_codec_route_planner.sh Samples/CodecFixtures/transcode_reports/route_matrix_latest
```

The script compiles the Swift route-planner core directly and writes:

```text
Samples/CodecFixtures/transcode_reports/<run>/codec_route_matrix.tsv
```

The output report is generated data and is ignored by git.

## Xcode Unit Tests

The project also includes `TaptionEncoderTests`, attached to the shared `TaptionEncoder` scheme. The tests call the same `CodecRoutePlanner` core through `@testable import Taption_Encoder`.

Run:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Current tests cover:

- `AV1 -> H.265` selects `SW` when no hardware exists.
- `AV1 -> H.265` selects `HW/SW` when only H.265 hardware encode exists.
- `AV1 -> H.265` selects `HW` when AV1 hardware decode and H.265 hardware encode both exist.
- Non-H.265 output routes such as `H.264 -> AV1` and `AV1 -> H.264` are outside product scope.
- The source-to-H.265 route matrix covers planned input expansion.
- The latest route matrix TSV evidence covers every simulation profile and every planned route, and keeps hardware decode/encode preference when available.
- Apple device-family profiles select the expected `SW`, `HW/SW`, or `HW` path for `AV1 -> H.265`.
- Apple runtime model identifiers such as `iPhone16,1`, `iPhone17,3`, `iPad7,11`, and `iPad16,3` map to the expected family profile and route path.
- Implemented routes only report current-build execution when the selected simulation profile has the required HW/SW path. Hardware-only implemented routes fall back to planned software-fallback state on devices without the required hardware path.

## What It Verifies

The script verifies:

- `AV1 -> H.265` is implemented and encodable.
- Apple-native `H.264 -> H.265`, `H.265 -> H.265`, `HEVC with Alpha -> H.265`, `Dolby Vision HEVC -> H.265`, and `ProRes -> H.265` hardware routes are implemented only for profiles that can hardware-decode the source and hardware-encode H.265.
- Automatic route selection chooses `HW` when source hardware decode and output hardware encode are both present.
- Automatic route selection chooses `HW/SW` when source decode needs software but output hardware encode exists.
- Automatic route selection chooses `SW` when hardware encode is unavailable.
- Every implemented or planned route uses a hardware decode backend when the simulated device profile can hardware-decode the source codec.
- Every implemented or planned route uses a hardware encode backend when the simulated device profile can hardware-encode the output codec.
- Non-H.265 output routes such as `H.264 -> AV1` and `AV1 -> H.264` are not roadmap requirements.
- Every supported input source codec should be evaluated against H.265 output readiness.
- The full internal route matrix is emitted for every simulation profile.
- The Device Info menu can show the same app-core simulation summary instead of relying on separate script-only logic.
- Saved Device Info reports include static matrix reconciliation so real-device probe snapshots can correct profile assumptions over time.
- Saved Device Info reports also include codec completion audit data so physical-device evidence records both HW capability and the current H.265 output execution gap state.
- Saved report archives can be summarized into known, unknown, consistent, and divergent device groups before updating static HW codec assumptions.

## Current Simulation Profiles

These are the base generic and Apple family capability profiles. The simulator also expands these through the seeded `HW_AppleDeviceCodecModelMatrix` runtime identifier table.

| Profile | Meaning |
| --- | --- |
| `software_only` | No hardware decode or encode available. |
| `h264_only_hw` | H.264 hardware decode and encode only. |
| `h264_hevc_hw` | H.264 and H.265 hardware decode and encode. |
| `h264_hevc_prores_hw` | H.264, H.265, selected HEVC variants, and ProRes-style hardware paths. |
| `av1_decode_hevc_encode_hw` | Modern profile with AV1 hardware decode and H.265 hardware encode. |
| `apple_ipados18_legacy_a10_h264` | Oldest iPadOS 18 H.264-only fallback class. |
| `apple_ios18_a12_h264_hevc` | A12/A12X/A12Z HEVC class without AV1 hardware. |
| `apple_a13_a14_h264_hevc` | A13/A14 HEVC class without AV1 hardware. |
| `apple_a15_a16_h264_hevc` | A15/A16 HEVC class without AV1 hardware. |
| `apple_iphone_pro_a15_a16_prores` | iPhone Pro A15/A16 class with ProRes paths but no AV1 hardware. |
| `apple_ipad_pro_m1_m2_prores` | M1/M2 iPad Pro class with ProRes paths but no AV1 hardware. |
| `apple_ipad_air_m1_m2_h264_hevc` | M1/M2 iPad Air H.264/H.265 class. |
| `apple_a17pro_av1_decode` | A17 Pro class with AV1 hardware decode. |
| `apple_a18_av1_decode` | A18 class with AV1 hardware decode. |
| `apple_a18pro_av1_decode_prores` | A18 Pro class with AV1 decode and ProRes paths. |
| `apple_a19_av1_decode` | A19 class with AV1 hardware decode. |
| `apple_a19pro_av1_decode` | iPhone Air A19 Pro class with AV1 hardware decode. |
| `apple_a19pro_av1_decode_prores_raw` | iPhone 17 Pro family class with AV1 decode plus ProRes/ProRes RAW media paths. |
| `apple_ipad_m3_m4_av1_prores` | M3/M4 iPad class with AV1 decode and ProRes paths. |

## Latest Local Check

Command:

```sh
Scripts/simulate_codec_route_planner.sh Samples/CodecFixtures/transcode_reports/route_matrix_latest
```

Result:

- Generated `codec_route_matrix.tsv`.
- Base generic + Apple family profiles: 19.
- Total simulation profiles after adding model identifiers: 112.
- Source codecs: 63.
- Output codecs: 1 (`hevc`).
- Routes per profile: 63.
- Total route rows: 7,056.
- Output file rows including header: 7,057.
- Current-build encodable rows: 1,250.
- Current-build path split: 496 `HW`, 719 `HW/SW`, 35 `SW`, and 5,806 `Planned`.
- Universal source-to-H.265 route coverage: 63/63 pairs per profile, no unsupported route-map gaps.
- Planned input-to-H.265 routes still prefer hardware decode and H.265 hardware encode backends when a simulation profile exposes that capability.
- `AV1 -> H.265` selected:
  - `SW` for `software_only`.
  - `SW` for `h264_only_hw`.
  - `SW` for `apple_ipados18_legacy_a10_h264`.
  - `HW/SW` for `h264_hevc_hw`.
  - `HW/SW` for `h264_hevc_prores_hw`.
  - `HW/SW` for Apple HEVC-only classes without AV1 hardware decode.
  - `HW` for `av1_decode_hevc_encode_hw`.
  - `HW` for Apple AV1-decode classes.
- Apple-native H.265 hardware route coverage:
  - `H.264 -> H.265`: 107/112 profiles encodable now.
  - `H.265 -> H.265`: 107/112 profiles encodable now.
  - `HEVC with Alpha -> H.265`: 106/112 profiles encodable now.
  - `Dolby Vision HEVC -> H.265`: 106/112 profiles encodable now.
  - `ProRes -> H.265`: 40/112 profiles encodable now.
- Software H.265 route coverage:
  - `AV1 -> H.265`: 112/112 profiles encodable now.
  - `VP9 -> H.265`: 112/112 profiles encodable now.
  - `VP8 -> H.265`: 112/112 profiles encodable now.
  - `MPEG-2 -> H.265`: 112/112 profiles encodable now.
  - `MPEG-4 Visual -> H.265`: 112/112 profiles encodable now.
  - Path split for VP9, VP8, MPEG-2, and MPEG-4 Visual: 107 `HW/SW` and 5 `SW`.
  - Path split for AV1: 30 `HW`, 77 `HW/SW`, and 5 `SW`.
- ProRes RAW remains sample-gated:
  - `ProRes RAW -> H.265`: 0/112 profiles encodable now.
  - 25 profiles expose a hardware decode + hardware encode path, but stay `Planned` until real-world sample proof and runtime verification are captured.
  - 87 profiles remain sample-gated before any software or hardware fallback is enabled.

## Remaining Work

- Continue reconciling the seeded per-model Apple device identifier matrix against real-device reports.
- Capture real-device `HW_CodecCapabilityProbe` reports from representative iPhone and iPad generations.
- Capture real-world ProRes RAW samples before enabling `ProRes RAW -> H.265` execution.
- Add software fallbacks for the new Apple-native H.265 hardware routes and continue expanding executable routes beyond H.265 output.
- Keep the current output codec/container selectors connected to route readiness while planned outputs stay disabled until bundled implementations exist.
