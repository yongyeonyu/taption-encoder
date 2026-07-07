# VC-1 Raw And Y41P Backend Decision - 2026-07-07

## Scope

- Purpose: decide the bundled backend shape for VC-1 raw and Y41P promotion, then verify the app-side runner boundary with focused tests.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Product constraints remain unchanged: Taption Encoder outputs H.265 / HEVC video only, and writable output containers remain MP4/MOV only.

This is backend-decision, host sanity-probe, and app-side runner-contract proof. It is not legal approval, not App Review approval, not a bundled FFmpeg iOS library proof, not real decoder execution proof, not real-device proof, not TestFlight/App Store Connect proof, and not public-release proof.

## Sources Checked

- FFmpeg legal and license checklist: https://www.ffmpeg.org/legal.html
- FFmpeg documentation: https://www.ffmpeg.org/general.html
- GNU LGPL 2.1 text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- FFmpegKit repository: https://github.com/arthenica/ffmpeg-kit
- FFmpegKit license page: https://github.com/arthenica/ffmpeg-kit/wiki/License

## Decision

Selected backend shape:

```text
Source-built LGPL FFmpeg-family decode bridge
```

Selected runner shape:

```text
Bundle-contained in-process library bridge; no downloaded binary, side-loaded plugin, or external executable.
```

Selected output path:

```text
Decode VC-1 raw and Y41P with the bundled FFmpeg-family bridge, then feed Taption Encoder's existing H.265 / HEVC MP4/MOV writer.
```

Reasons:

- FFmpeg's LGPL checklist requires a reviewed non-GPL/nonfree configuration, exact source availability, build instructions, notices, and EULA/reverse-engineering compatibility.
- Apple requires the app to be self-contained and not download/install/execute code that changes app functionality.
- FFmpegKit is retired as a historical package, and its license page states GPL builds make the bundle GPL. Prebuilt binary provenance is weaker than a reproducible source-built bridge.
- The current SwiftVLC/libVLC bundle remains useful for existing routes, but VC-1 raw produced no frames and Y41P was unsupported in the prior current-build proof. It is not the selected promotion path for these two samples.
- Keeping FFmpeg-family work decode-focused lets Taption Encoder preserve the existing H.265-only MP4/MOV writer policy and avoid adding broad writable containers.

Rejected paths:

- Downloaded ffmpeg binary or codec plugin.
- Random community prebuilt FFmpeg/FFmpegKit binary packages.
- Non-H.265 output routes or AVI/WebM/MKV output enablement.

## Code Decision Surface

Added `TaptionFFmpegFamilyBackendDecisionCatalog.currentVC1Y41PDecision` in:

```text
TaptionEncoder/Core/Codecs/SW_SoftwareCodecBackendRegistry.swift
```

The catalog records:

- selected candidate id: `source-built-lgpl-ffmpeg-decode-bridge`
- rejected candidate id: `prebuilt-or-archived-ffmpegkit`
- rejected candidate id: `downloaded-ffmpeg-binary-or-plugin`
- deferred candidate id: `swiftvlc-current-bundle`
- proof boundary: decision/runner contract only, not legal/App Review/real decoder approval.

## Host Sanity Probe

Local ignored samples:

```text
Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/vc1_advanced_profile_2.vc1
Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/y41p_from_internet_image.avi
```

Host `ffprobe` summary:

| Sample | Probe result |
| --- | --- |
| `vc1_advanced_profile_2.vc1` | raw VC-1, Advanced profile, 720x480, `yuv420p`, 700,252 bytes |
| `y41p_from_internet_image.avi` | AVI, Y41P video, 160x120, 25 fps, 1.000s, PCM s16le mono |

Host short-transcode sanity check:

```sh
ffmpeg -f vc1 -i vc1_advanced_profile_2.vc1 -frames:v 20 -c:v libx265 -tag:v hvc1 -an vc1_probe.mp4
ffmpeg -i y41p_from_internet_image.avi -frames:v 20 -c:v libx265 -tag:v hvc1 -an y41p_probe.mp4
```

Result:

| Sample | Exit | Output probe |
| --- | ---: | --- |
| VC-1 raw | 0 | H.265 MP4, 720x480, 20 frames, 0.667s |
| Y41P | 0 | H.265 MP4, 160x120, 20 frames, 0.800s |

This host probe is not app-side proof and does not approve `libx265` for shipping. It only confirms the selected FFmpeg-family backend shape has a realistic decode path for the two samples.

## App-Side Runner Contract Proof

Added focused XCTest:

```text
TaptionEncoderTests/CodecRoutePlannerTests/testVC1RawAndY41PPreparedPlansRunThroughInjectedBroadBackendRunnerWhenReady
```

What it proves:

- VC-1 raw and Y41P prepare planned H.265 routes with `videoCommandPlan`.
- When all backend readiness gates are satisfied in the injected test report, `AVFoundationHEVCEncoderService` sends the prepared plan through `SW_FFmpegCommandExecutor`.
- The injected runner receives the expected source URL, output URL, `ffmpegFamily` backend, `-map 0:v:0`, `-an`, `-c:v`, H.265 encoder argument, and MP4/MOV output path.
- The app service reports `.ffmpegFamily` / `.software` after the injected runner writes the expected output file.

What it does not prove:

- It does not decode VC-1 raw or Y41P with a real bundled FFmpeg iOS library.
- It does not close legal, App Store, binary-size, notice, or old-device gates.
- It does not promote VC-1 raw or Y41P to current executable status.

## Remaining Gates

- Build or vendor the selected source-built LGPL FFmpeg-family decode bridge.
- Finalize configure line, enabled component map, source archive, local diff, notices, and EULA language.
- Replace fake/injected runner proof with real app-side simulator execution for VC-1 raw and Y41P.
- Verify H.265 MP4/MOV output duration, dimensions, frame decode, and visual sample decodability.
- Collect real-device and older-device thermal/battery/memory/runtime proof separately.
