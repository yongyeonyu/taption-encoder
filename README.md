# Taption Encoder

Taption Encoder is a free iOS video encoder app intended to make phone-based conversion simple. The first milestone is AV1 to H.265, the next milestone is broad input to H.265, and the long-term goal is universal codec-to-codec conversion through hardware, software, or mixed codec paths, old-device compatibility where practical, background encoding where the OS allows it, and multi-video assembly into one output with lightweight editing.

The first release starts by extracting Taption's AV1 to H.265 conversion path into a focused standalone app. Later releases expand toward "almost any video in, H.265 out", then "any supported codec to any supported codec", plus simple multi-camera merge workflows. The final codec model is symmetric all-to-all routing: for example, `H.264 -> AV1` and `AV1 -> H.264` are both first-class planned routes.

Product path: **AV1 to H.265 first, All to H.265 next, All to All final.**

## Project

- Xcode project: `TaptionEncoder.xcodeproj`
- Scheme: `TaptionEncoder`
- Bundle identifier: `com.taption.encoder`
- Display name: `Taption Encoder`
- Initial platform: iPhone and iPad portrait only
- Minimum OS: iOS/iPadOS 18.0
- iPad UX: use the same portrait-first flow and centered mobile-width layout as iPhone

## Source Core To Port

The current Taption AV1 to H.265 conversion owner path starts from:

- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Release/Media/AV1HEVCTranscodingService.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+AV1Transcoding.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+MediaOpen.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Beta/Export/BurnedSubtitleVideoEncodingPolicy.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Release/Media/VideoPlaybackCodecRegistration.swift`

Next implementation pass should isolate the media conversion core before importing broader editor or subtitle-export code.

## Planning

- App architecture, product plan, UI design, and roadmap: [`docs/APP_ARCHITECTURE.md`](docs/APP_ARCHITECTURE.md)
- Detailed execution plan from launch to completed product: [`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md)
- Phase-by-phase implementation guide for app development: [`docs/DETAILED_DEVELOPMENT_PLAN.md`](docs/DETAILED_DEVELOPMENT_PLAN.md)
- Codec/container/audio support research: [`docs/CODEC_SUPPORT_RESEARCH.md`](docs/CODEC_SUPPORT_RESEARCH.md)
- Apple device-family hardware codec matrix: [`docs/APPLE_DEVICE_CODEC_MATRIX.md`](docs/APPLE_DEVICE_CODEC_MATRIX.md)
- Generated fixture policy and script: [`docs/VIDEO_CODEC_FIXTURES.md`](docs/VIDEO_CODEC_FIXTURES.md)
- Audio fixture policy and script: [`docs/AUDIO_CODEC_FIXTURES.md`](docs/AUDIO_CODEC_FIXTURES.md)
- Device codec route simulation: [`docs/DEVICE_CODEC_ROUTE_SIMULATION.md`](docs/DEVICE_CODEC_ROUTE_SIMULATION.md)
- Local H.265 transcode fixture results: [`docs/HEVC_TRANSCODE_TEST_RESULTS.md`](docs/HEVC_TRANSCODE_TEST_RESULTS.md)
- Release action items and launch blockers: [`docs/ACTION_ITEMS.md`](docs/ACTION_ITEMS.md)

## MVP Scope

- Input: AV1 video
- Output: H.265 video in an `.mp4` container
- Default output: preserve source-like resolution, frame rate, orientation, color characteristics, audio timing, and visual quality whenever technically possible
- Device orientation: iPhone and iPad portrait only
- Shared UX: iPad uses the same main-screen flow and control density as iPhone
- Codec path: the app automatically uses hardware where supported and falls back to software when needed; the UI only displays the actual path.
- Sources: File, folder, and Photos
- Photos output: save as a new Photos asset
- Flow: select a video, inspect and show video info, start encoding only after the user taps Start, allow cancellation during encoding, then save after rewarded ad completion
- Folder flow: select a folder, inspect the first supported video, then encode supported files in that folder sequentially after Start
- Rewarded save failure: keep the completed temporary output and let the user retry later without re-encoding
- Progress: show progress bar, percentage, elapsed time, and estimated time remaining when enough progress samples are available
- Background status: on iOS/iPadOS 26 or later, let users opt into background encoding; on iOS/iPadOS 18-25, tell users to keep the app open for reliable encoding
- Save path: create a sibling output named with `_taption` appended to the original filename
- Safety: warn before output when available storage is insufficient
- Ads: non-personalized AdMob banners at the top and bottom of the main screen, App Open ad on app start/foreground, interstitial before a user-started encoding session, rewarded ad before final save, and interstitial at natural session-end points; Debug builds use Google test ad unit IDs

## Implementation Status

- Phase 0 foundation is implemented as of 2026-06-15.
- The app now has `AppEnvironment`, `FeatureFlags`, `AppConfiguration`, the `Features/Home` screen shell, protocol boundaries, and real AVFoundation services for the first AV1-to-H.265 path.
- Phase 1 UX/state machine is implemented as of 2026-06-15.
- File entry now runs a real `importing -> inspecting -> storage checking -> encoding -> rewarded save -> completed` flow for implemented H.265 routes, with AVFoundation progress, software AV1 decode fallback, percentage, elapsed time, estimated remaining time, cancellation, reset, and pending-save recovery surfaces.
- Folder entry supports direct folder selection, scans common video file extensions, and sequentially processes videos whose selected H.265 route is executable on the current device.
- Photos entry uses the system Photos picker, copies the selected video into app-owned temporary storage, and saves the completed H.265 output as a new Photos asset after the rewarded-save gate.
- Files output saves after the rewarded-save gate to the same folder as the source file, using `_taption` before the `.mp4` extension. AdMob app/ad units are connected through GoogleMobileAds 13.5.0, with production IDs reserved for Release builds; audio preservation in the software fallback path, consent UI, app-ads.txt, and broad software codec support remain later-phase implementation work.
- `TaptionEncoderTests` is attached to the shared scheme and verifies codec route planning, including HW-first, HW/SW mixed, SW fallback, planned all-to-all routes, complete source/output matrix coverage, reverse route coverage for every supported pair, and per-side HW backend preference for every simulated profile.
- The app-scheme tests also parse `Samples/CodecFixtures/transcode_reports/smoke_latest/transcode_results.tsv` and `Samples/CodecFixtures/transcode_reports/audio_smoke_latest/transcode_results.tsv`, requiring every fixture row to prove SW/HW H.265 output with preserved audio signal.
- The same evidence layer parses `Samples/CodecFixtures/generated_smoke/fixtures.tsv` and compares it to `SW_CodecSupportCatalog.fixtureTargets`, so the broad generated video fixture catalog stays synchronized with the software codec roadmap.
- The fixture evidence tests also build source-preserving H.265/MP4 app-core command plans from every generated video fixture row, including audio-to-AAC decisions and no-audio elementary streams.
- The same fixture evidence layer parses `Samples/CodecFixtures/audio_generated_smoke/audio_fixture_generation.tsv`, so generated audio codec coverage and current pending codecs such as xHE-AAC, AMR-NB, and AMR-WB stay visible in app-scheme tests.
- The audio fixture evidence tests now build app-core AAC/MP4 route plans and FFmpeg-family software fallback command plans from every generated audio fixture row, preserving sample rate, channel count, and source bitrate options.
- Fixture evidence tests now also convert generated video/audio fixture rows into app-core FFmpeg-family execution jobs and match those jobs against the latest SW/HW H.265 evidence rows. These jobs remain blocked by the broad software backend gates in the current build, but they run through the injected command executor when a fully satisfied readiness report is supplied.
- Planned video and audio codec routes now have gated FFmpeg-family execution wrappers, so future bundled broad-backend conversion can share the same readiness-gated runner path from function-style codec requests.
- Route matrix evidence from `Samples/CodecFixtures/transcode_reports/route_matrix_latest/codec_route_matrix.tsv` is also parsed by the app-scheme tests, proving profile coverage, universal route coverage, and HW decode/encode preference in the generated simulation report.
- Audio route planning now covers default source-audio-to-AAC decisions for MP4/H.265 output, including copy/native/SW route states and fixture coverage status.
- The live AV1-to-H.265 execution path now runs through `TaptionCodecTranscodingRegistry`, so HW/SW codec algorithms are registered as replaceable route implementations instead of being hardcoded in the encoder service.
- Apple-native H.265 hardware routes are now registered for `H.264 -> H.265`, `H.265 -> H.265`, and `ProRes -> H.265` when the simulated or runtime device profile can hardware-decode the source and hardware-encode H.265. Devices without that full HW path keep those routes visible as planned software-fallback work instead of pretending they can run.
- Broad software codec planning now has `SW_SoftwareCodecBackendRegistry`, which models software video/audio decode, software video/audio encode, and container read/write coverage for the future all-to-all backend. `SW_UniversalCodecTranscodeAlgorithm` adds planned software descriptors for every non-implemented universal route while still returning a clear not-bundled error until the broad backend and license review are complete.
- Single-asset encoding plans now carry a planned FFmpeg-family video command plan when the selected all-to-all output route has a software encoder, mirroring the existing audio command-plan attachment.
- The app encoder service now dispatches prepared planned routes through the gated function-style FFmpeg-family video executor: when the broad SW backend is marked executable and a runner is injected, planned all-to-all routes can run from the same `TaptionCodecTranscodeRequest` contract used by core codec algorithms.
- Generated AAC/MP4 audio fixture jobs now rebuild `TaptionAudioCodecTranscodeRequest` values and pass through `SW_FFmpegAudioCodecTranscodeExecutor` with a fake runner once broad SW backend gates are satisfied, giving audio the same function-style execution boundary as video.
- The final codec contract is now named `All-to-All Universal Codec Mesh` in core code. `TaptionCodecRegistry` exposes the full source-codec x output-codec route set, including examples such as `H.264 -> AV1`, `AV1 -> H.264`, and same-codec re-encode routes for future resize, frame-rate, bitrate, quality, and color workflows.
- `TaptionUniversalCodecCompletionAuditor` now reports whether the universal mesh is only launch-route executable, planning-locked, command-plan ready, or fully executable. It explicitly keeps `H.264 -> AV1`, `AV1 -> H.264`, and same-codec re-encode routes as required bidirectional contract checks.
- Device Info now shows that completion audit state and saved device codec JSON snapshots include it alongside the runtime HW probe, static Apple model reconciliation, and route simulation summary.
- Audio conversion now has the same function-style contract shape through `AudioCodecAlgorithm.swift` and `SW_UniversalAudioCodecTranscodeAlgorithm.swift`. The planned software audio catalog covers every universal audio source/output pair and returns a clear not-bundled error until the broad backend ships.
- `CodecOutputCatalog` now centralizes output readiness as `Now`, `Plan Ready`, `Planned`, or `Blocked`, so the Home output selectors, file cards, Device Info, and saved device codec reports use the same core status model. Planned output routes are visible in file cards as states such as `Path SW Plan Ready` or `Path SW Blocked`; current-build video execution remains limited to H.265 output, with AV1 covered by HW/SW fallback and H.264/H.265/ProRes covered only on hardware-capable profiles.
- `TaptionAudioCodecOutputCatalog` mirrors that output readiness model for audio codec/container pairs. Device Info now shows audio output readiness and saved device codec JSON snapshots include the audio output catalog beside the video output catalog.
- The Home output selector now exposes video codec, audio codec, and container as separate route axes. Current execution is still gated to the launch-safe `H.265 + AAC / MP4` route while planned all-to-all combinations remain visible as readiness states.
- `TaptionUniversalCodecCompletionAuditor` now includes video and audio output-selector coverage in the all-to-all completion audit, so saved device codec reports prove both route-mesh planning and Home selector readiness from one snapshot.

## Verification

Run the app-scheme unit tests:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Run a Release build:

```sh
xcodebuild \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  build
```

Verify generated codec fixture evidence after running the fixture transcode smoke gate:

```sh
Scripts/verify_codec_fixture_evidence.sh
```

## Encoder Roadmap

Output remains H.265 first. Future releases should expand input coverage, then output codec coverage, without tying the app to Taption editor, subtitle, or editor-export UI dependencies.

### Final Product Goal

- Product path: AV1 to H.265 first, All to H.265 next, All to All final.
- Convert almost any practical user video input into H.265 first, then into any supported output codec.
- Treat every supported source/output pair as a route, including reverse pairs such as `H.264 -> AV1` and `AV1 -> H.264`.
- Keep the final codec catalog symmetric: if a codec is accepted as a universal input, it is also considered as a universal output unless intentionally removed from the product contract.
- Treat H.265 as the recommended default and launch output, not a permanent architecture limit.
- Use hardware codecs when available and software codecs when hardware is unavailable or unsupported.
- Evaluate FFmpeg-family software codec options and use the broadest codec support that is safe for App Store review, licensing, binary size, and performance.
- Support older devices where performance and OS APIs allow it.
- Let users choose background encoding on iOS/iPadOS 26 or later; on earlier versions, guide users to keep the app open for reliable encoding.
- Merge multiple videos into one H.265 output, even when the source containers/codecs/cameras differ.
- Preserve the source look by default.
- Add advanced controls over output codec, output container, size, frame rate, bitrate, quality, and color mapping after the simple flow is stable.
- Advanced output format starts as H.265 container choice, such as `.mp4` and `.mov`, then becomes full output codec/container selection.
- Add lightweight edit tools for trim, cut, shorten, reorder, and clip positioning before merge/export.

### Input Codec Roadmap

- AV1
- H.264 / AVC
- H.265 / HEVC
- Dolby Vision HEVC
- Apple ProRes / ProRes RAW
- VP9
- VP8
- MPEG-1 Video
- MPEG-2 Video
- MPEG-4 Part 2
- H.263
- Motion JPEG
- QuickTime Animation, Cinepak, Sorenson Video, DV/DVCPro
- Windows Media / VC-1 where software support and licensing allow it
- Other practical user video codecs supported by the selected software codec backend
- App binary size may increase if broad input support requires bundled software codec components.

### Input Container Roadmap

- MP4 (`.mp4`)
- QuickTime Movie (`.mov`)
- M4V (`.m4v`)
- WebM (`.webm`)
- Matroska (`.mkv`)
- AVI (`.avi`)
- MPEG transport streams (`.ts`, `.mts`, `.m2ts`)
- MXF (`.mxf`)
- DJI low-resolution proxy (`.lrf`)
- MPEG program streams and VOB (`.mpg`, `.mpeg`, `.vob`)
- DV (`.dv`)
- Ogg/Ogv (`.ogg`, `.ogv`)
- FLV/F4V (`.flv`, `.f4v`)
- NUT (`.nut`)
- RealMedia (`.rm`, `.rmvb`)
- RoQ (`.roq`)
- 3GP/3G2 (`.3gp`, `.3g2`)
- ASF/WMV (`.asf`, `.wmv`)
- Raw elementary and diagnostic streams (`.h264`, `.h265`, `.hevc`, `.ivf`, `.obu`, `.y4m`, `.av1`, `.h263`, `.m1v`, `.m2v`, `.vc1`)

### Future Encoding Options

These options should be represented in the architecture before they are exposed in the UI:

- Output format presets, with H.265 as the first fixed output
- Resolution changes
- Frame-rate changes
- Quality presets
- Bitrate controls
- Color mapping controls
- Multi-file merge into a single output video
- Lightweight editing before merge/export
- Batch conversion

### Merge And Edit Roadmap

- Merge multiple videos into one H.265 output.
- Allow sources from different cameras, codecs, and containers.
- Use a common output canvas when resolutions match or after user-selected normalization.
- Use `.fcpxml` as the native project save format from the first project feature.
- Add a future `.fcpxmld` project bundle for thumbnails, proxies, and richer metadata when the single-document workflow is stable.
- Allow future managed `.fcpxmld` projects to copy original media when the user chooses that mode.
- Reuse Taption's interaction ideas as Encoder-specific video editing concepts:
  - touch widget controls
  - slice/split interactions
  - segment-based editing, with video segments replacing subtitle segments
- Add lightweight editing before merge/export:
  - trim
  - cut
  - split
  - shorten
  - reorder
  - clip position on the output canvas
- When frame rate, color, or audio settings differ, show selectable normalization options based on the detected source values.
- If values are effectively equivalent, auto-pick the closest recommended value and show it in the merge summary.
