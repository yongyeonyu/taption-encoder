# Taption Encoder

Taption Encoder is a free iOS video encoder app intended to make phone-based conversion simple. The current release train is `01.01.00`, mapped to Apple marketing version `1.1.0` and build `30`. The product direction remains practical all-input-to-H.265 conversion through hardware, software, or mixed codec paths, old-device compatibility where practical, background encoding where the OS allows it, and multi-video assembly into one H.265 output with lightweight editing.

Release `01.01.00` keeps the focused standalone H.265 / HEVC encoder scope and carries forward preview playback, bundled samples, project documentation, queue editing, source-preserving validation, privacy/ad, and multi-file encoding-mode prompt stabilization. Later releases expand toward "almost any video in, H.265 out" plus simple multi-camera merge workflows. Output video codec is a product constraint: H.265 / HEVC is the only supported video output codec. Routes such as `H.264 -> AV1` or `AV1 -> H.264` are not product routes.

Product path: **AV1 to H.265 first, broad inputs to H.265 next, H.265-only output final.**

## Project

- Xcode project: `TaptionEncoder.xcodeproj`
- Scheme: `TaptionEncoder`
- Bundle identifier: `com.taption.encoder`
- Display name: `Taption Encoder`
- Initial platform: iPhone and iPad portrait only
- Minimum OS: iOS/iPadOS 18.0
- iPad UX: use the same portrait-first flow and centered mobile-width layout as iPhone

## Release Status

- Current release label: `01.01.00`
- Apple version/build: `1.1.0 (30)`
- Latest release preparation date: 2026-07-06
- App Store Connect/TestFlight upload: export/upload succeeded for `build/TestFlight-01.01.00-30/TaptionEncoder.xcarchive`; App Store Connect reported `Uploaded package is processing` and `Upload succeeded`. App Review submission, TestFlight availability, processing completion, and public release were not performed or verified.
- App Store Connect version metadata: version `1.1.0` exists in `PREPARE_FOR_SUBMISSION`, release type is `MANUAL`, and English/Korean What's New text has been filled in.
- Device install proof: verify real-device install separately from TestFlight/App Store Connect state.
- Verification proof: current `01.01.00` proof is recorded in `docs/verification/RELEASE_01.01.00.md`.
- Latest local performance proof: Battery Options encoding profiles and the 2026-07-04 bundled-codec simulator benchmark are recorded in `docs/verification/CODEC_BENCHMARK_2026-07-04.md`. This is local Debug simulator evidence, not TestFlight/App Store Connect proof.
- Latest runtime warning implementation: thermal, app-memory, battery, and long-runtime warnings are surfaced in the active encoding resource widget and tracked in `docs/planning/ACTION_ITEMS.md`. This is unit/source-level implementation evidence, not older-real-device threshold proof.
- Latest FFmpeg-family backend engineering review: VC-1 raw/Y41P execution still requires a bundled, license-reviewed, App Store-safe broad backend. The 2026-07-07 review is recorded in `docs/codecs/FFMPEG_FAMILY_BACKEND_REVIEW_2026-07-07.md`. This is engineering review evidence only, not legal approval, App Review approval, app-side execution proof, simulator proof, real-device proof, or TestFlight/App Store Connect proof.
- Latest real-device hardware codec proof: iPhone 14 Pro and iPad Pro 12.9-inch 6th generation `HW_CodecCapabilityProbe` snapshots are recorded in `docs/verification/REAL_DEVICE_CODEC_REPORTS_2026-07-06.md`. This is hardware capability evidence only, not sample encode/playback, TestFlight/App Store Connect, App Review, or manual UI proof.
- Latest real-device runtime sample proof: iPad Pro 12.9-inch 6th generation Debug XCTest encoded bundled `Theora.ogv` to H.265 MP4 with Opus-to-AAC audio on 2026-07-07. Proof is recorded in `docs/verification/REAL_DEVICE_RUNTIME_SAMPLE_PROOF_2026-07-07.md`. This is real-device runtime evidence only, not simulator, host FFmpeg, TestFlight/App Store Connect, App Review, or public-release proof.
- Latest non-AAC audio output route proof: iPad Pro 12.9-inch 6th generation Debug XCTest encoded bundled `Theora.ogv` to H.265 MOV with Opus-to-PCM and Opus-to-ALAC audio on 2026-07-07. Proof is recorded in `docs/verification/NON_AAC_AUDIO_OUTPUT_ROUTE_PROOF_2026-07-07.md`. This is current-build route execution evidence only, not broad FFmpeg-family backend approval, AMR-WB/AMR-WB+ proof, TestFlight/App Store Connect, App Review, or public-release proof.
- Latest host-side sample acquisition proof: Theora, AMR-NB, xHE-AAC, VC-1 raw, AMR-WB+, and ProRes RAW source discovery plus local tool probes are recorded in `docs/verification/CODEC_SAMPLE_ACQUISITION_2026-07-06.md`. This is local host-side evidence only, not app-side execution, simulator benchmark, real-device proof, TestFlight/App Store Connect, App Review, or public release proof.
- Latest AMR-WB sample acquisition and runtime proof: a decodable ETSI TS 126 174-derived AMR-WB `.awb` sample plus H.263/AMR-WB 3GP sample were created locally and host-decoded on 2026-07-07; follow-up focused simulator XCTest now surfaces the host-visible `sawb` AMR-WB audio track through the bundled VLC metadata path and encodes H.263/AMR-WB 3GP to H.265 MP4 with AAC 48 kHz mono output. Proof is recorded in `docs/verification/AMR_WB_SAMPLE_ACQUISITION_2026-07-07.md`. This is host decode plus simulator execution evidence only, not real-device proof, TestFlight/App Store Connect, App Review, or public release proof.
- Latest local sample runtime proof: ignored VC-1 raw and Y41P sample block status is recorded in `docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-06.md`; the follow-up QuickTime RPZA, AMR-NB/H.263, and xHE-AAC passing runtime proof plus Y41P and VC-1 planned-route corrections are recorded in `docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-07.md`. These are focused simulator XCTest evidence only, not host FFmpeg proof, real-device proof, TestFlight/App Store Connect, App Review, or public release proof.

## Source Core To Port

The current Taption AV1 to H.265 conversion owner path starts from:

- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Release/Media/AV1HEVCTranscodingService.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+AV1Transcoding.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+MediaOpen.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Beta/Export/BurnedSubtitleVideoEncodingPolicy.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Release/Media/VideoPlaybackCodecRegistration.swift`

Next implementation pass should isolate the media conversion core before importing broader editor or subtitle-export code.

## Planning

- App architecture, product plan, UI design, and roadmap: [`docs/architecture/APP_ARCHITECTURE.md`](../architecture/APP_ARCHITECTURE.md)
- External video-editor architecture references: [`docs/architecture/VIDEO_EDITOR_REFERENCE_REVIEW_2026-07-07.md`](../architecture/VIDEO_EDITOR_REFERENCE_REVIEW_2026-07-07.md)
- Detailed execution plan from launch to completed product: [`docs/planning/DEVELOPMENT_PLAN.md`](../planning/DEVELOPMENT_PLAN.md)
- Phase-by-phase implementation guide for app development: [`docs/planning/DETAILED_DEVELOPMENT_PLAN.md`](../planning/DETAILED_DEVELOPMENT_PLAN.md)
- Codec/container/audio support research: [`docs/codecs/CODEC_SUPPORT_RESEARCH.md`](../codecs/CODEC_SUPPORT_RESEARCH.md)
- Apple device-family hardware codec matrix: [`docs/codecs/APPLE_DEVICE_CODEC_MATRIX.md`](../codecs/APPLE_DEVICE_CODEC_MATRIX.md)
- Generated fixture policy and script: [`docs/codecs/VIDEO_CODEC_FIXTURES.md`](../codecs/VIDEO_CODEC_FIXTURES.md)
- Audio fixture policy and script: [`docs/codecs/AUDIO_CODEC_FIXTURES.md`](../codecs/AUDIO_CODEC_FIXTURES.md)
- Device codec route simulation: [`docs/codecs/DEVICE_CODEC_ROUTE_SIMULATION.md`](../codecs/DEVICE_CODEC_ROUTE_SIMULATION.md)
- FFmpeg-family broad backend review: [`docs/codecs/FFMPEG_FAMILY_BACKEND_REVIEW_2026-07-07.md`](../codecs/FFMPEG_FAMILY_BACKEND_REVIEW_2026-07-07.md)
- Local H.265 transcode fixture results: [`docs/verification/HEVC_TRANSCODE_TEST_RESULTS.md`](../verification/HEVC_TRANSCODE_TEST_RESULTS.md)
- Local bundled-codec simulator benchmark: [`docs/verification/CODEC_BENCHMARK_2026-07-04.md`](../verification/CODEC_BENCHMARK_2026-07-04.md)
- Real-device hardware codec reports: [`docs/verification/REAL_DEVICE_CODEC_REPORTS_2026-07-06.md`](../verification/REAL_DEVICE_CODEC_REPORTS_2026-07-06.md)
- Real-device runtime sample proof: [`docs/verification/REAL_DEVICE_RUNTIME_SAMPLE_PROOF_2026-07-07.md`](../verification/REAL_DEVICE_RUNTIME_SAMPLE_PROOF_2026-07-07.md)
- Non-AAC audio output route proof: [`docs/verification/NON_AAC_AUDIO_OUTPUT_ROUTE_PROOF_2026-07-07.md`](../verification/NON_AAC_AUDIO_OUTPUT_ROUTE_PROOF_2026-07-07.md)
- Host-side codec sample acquisition: [`docs/verification/CODEC_SAMPLE_ACQUISITION_2026-07-06.md`](../verification/CODEC_SAMPLE_ACQUISITION_2026-07-06.md)
- Internet-supported missing sample refresh: [`docs/verification/INTERNET_SUPPORTED_SAMPLE_REFRESH_2026-07-06.md`](../verification/INTERNET_SUPPORTED_SAMPLE_REFRESH_2026-07-06.md)
- AMR-WB sample acquisition: [`docs/verification/AMR_WB_SAMPLE_ACQUISITION_2026-07-07.md`](../verification/AMR_WB_SAMPLE_ACQUISITION_2026-07-07.md)
- Local sample runtime status: [`docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-06.md`](../verification/SAMPLE_RUNTIME_STATUS_2026-07-06.md), [`docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-07.md`](../verification/SAMPLE_RUNTIME_STATUS_2026-07-07.md)
- Remaining release action items and launch blockers: [`docs/planning/ACTION_ITEMS.md`](../planning/ACTION_ITEMS.md)
- Completed release action items: [`docs/planning/COMPLETED_ACTION_ITEMS.md`](../planning/COMPLETED_ACTION_ITEMS.md)
- Release closeout for `01.00.01`: [`docs/archive/releases/RELEASE_01.00.01.md`](../archive/releases/RELEASE_01.00.01.md)
- Current release proof for `01.01.00`: [`docs/verification/RELEASE_01.01.00.md`](../verification/RELEASE_01.01.00.md)

## Release 01.00.01 Scope

- Input: AV1, VP9, VP8, MPEG-1, MPEG-2, MPEG-4 Visual, H.263, H.261, Flash Video, Microsoft MPEG-4 V2/V3, Motion JPEG, JPEG 2000, JPEG-LS, Lossless JPEG, Apple Animation, Cinepak, Sorenson Video, Sorenson Video 3, QuickTime Video, Theora, Windows Media Video, Microsoft Video 1, ASUS V1/V2, Flash Screen Video, Flash Screen Video 2, ZMBV, CLJR, and FFV1 through the current software fallback path; H.264, H.265, and ProRes through Apple-native hardware routes when the device supports them
- Output: H.265 video with `.mp4` as the default container and `.mov` as a selectable output container
- Default output: preserve source-like resolution, frame rate, orientation, color characteristics, audio timing, and visual quality whenever technically possible
- Device orientation: iPhone and iPad portrait only
- Shared UX: iPad uses the same main-screen flow and control density as iPhone
- Codec path: the app automatically uses hardware where supported and falls back to software when needed; the UI only displays the actual path.
- Sources: File, folder, and Photos
- Photos output: save as a new Photos asset
- Flow: select a video, inspect and show video info, start encoding only after the user taps Start, allow cancellation during encoding, then save without a rewarded ad when one Star was consumed; if no Star is available, encode first and require a rewarded ad before final save
- Folder flow: select a folder, inspect the first supported video, then encode supported files in that folder sequentially after Start
- Rewarded save failure: keep the completed temporary output and let the user retry later without re-encoding
- Progress: show progress bar, percentage, elapsed time, and estimated time remaining when enough progress samples are available
- Background status: on iOS/iPadOS 26 or later, let users opt into background encoding; on iOS/iPadOS 18-25, tell users to keep the app open for reliable encoding
- Save path: create a sibling output named with `_taption` appended to the original filename
- Safety: warn before output when available storage is insufficient
- Ads: non-personalized AdMob banners at the top and bottom of the main screen, App Open ad on app start/foreground, interstitial before a user-started encoding session, rewarded ad for zero-Star final save, and interstitial at natural session-end points; Debug builds use Google test ad unit IDs

## Implementation Status

- Release `01.00.01` / `1.0.1 (19)` is the current shipped baseline as of 2026-06-27.
- Phase 0 foundation is implemented as of 2026-06-15.
- The app now has `AppEnvironment`, `FeatureFlags`, `AppConfiguration`, the `Features/Home` screen shell, protocol boundaries, and real AVFoundation services for the first AV1-to-H.265 path.
- Phase 1 UX/state machine is implemented as of 2026-06-15.
- File entry now runs a real `importing -> inspecting -> storage checking -> encoding -> star or rewarded save -> completed` flow for implemented H.265 routes, with AVFoundation progress, software AV1 decode fallback, percentage, elapsed time, estimated remaining time, cancellation, reset, and pending-save recovery surfaces.
- Folder entry supports direct folder selection, scans common video file extensions, and sequentially processes videos whose selected H.265 route is executable on the current device.
- Photos entry uses the system Photos picker, copies the selected video into app-owned temporary storage, and saves the completed H.265 output as a new Photos asset after either Star consumption or the zero-Star rewarded-save gate.
- Files output saves to the same folder as the source file after either Star consumption or the zero-Star rewarded-save gate, using `_taption` before the selected `.mp4` or `.mov` extension. AdMob app/ad units are connected through GoogleMobileAds 13.5.0, with production IDs reserved for Release builds; the current build now preserves audio on the bundled Vorbis-to-AAC software path that backs the real WebM sample test, while consent UI, app-ads.txt, broader software fallback audio coverage, and broad software codec support remain later-phase implementation work.
- `TaptionEncoderTests` is attached to the shared scheme and verifies codec route planning, including HW-first, HW/SW mixed, SW fallback, H.265 output readiness, input coverage, and per-side HW backend preference for every simulated profile.
- The app-scheme tests also parse `Samples/CodecFixtures/transcode_reports/smoke_latest/transcode_results.tsv` and `Samples/CodecFixtures/transcode_reports/audio_smoke_latest/transcode_results.tsv`, requiring every fixture row to prove SW/HW H.265 output with preserved audio signal.
- The same evidence layer parses `Samples/CodecFixtures/generated_smoke/fixtures.tsv` and compares it to `SW_CodecSupportCatalog.fixtureTargets`, so the broad generated video fixture catalog stays synchronized with the software codec roadmap.
- The fixture evidence tests also build source-preserving H.265/MP4 app-core command plans from every generated video fixture row, including audio-to-AAC decisions and no-audio elementary streams.
- The same fixture evidence layer parses `Samples/CodecFixtures/audio_generated_smoke/audio_fixture_generation.tsv`, so generated audio codec coverage and current pending codecs such as xHE-AAC, AMR-NB, and AMR-WB stay visible in app-scheme tests.
- The audio fixture evidence tests now build app-core AAC/MP4 route plans and FFmpeg-family software fallback command plans from every generated audio fixture row, preserving sample rate, channel count, and source bitrate options.
- Fixture evidence tests now also convert generated video/audio fixture rows into app-core FFmpeg-family execution jobs and match those jobs against the latest SW/HW H.265 evidence rows. These jobs remain blocked by the broad software backend gates in the current build, but they run through the injected command executor when a fully satisfied readiness report is supplied.
- Planned video and audio codec routes now have gated FFmpeg-family execution wrappers, so future bundled broad-backend conversion can share the same readiness-gated runner path from function-style codec requests.
- Route matrix evidence from `Samples/CodecFixtures/transcode_reports/route_matrix_latest/codec_route_matrix.tsv` is also parsed by the app-scheme tests, proving profile coverage, universal route coverage, and HW decode/encode preference in the generated simulation report.
- Audio route planning now covers default source-audio-to-AAC decisions for MP4/MOV H.265 output, including copy/native/SW route states and fixture coverage status.
- The live H.265 execution paths now run through `TaptionCodecTranscodingRegistry`, so AV1, VP9, VP8, MPEG-1, MPEG-2, MPEG-4 Visual, H.263, H.261, Flash Video, Microsoft MPEG-4 V2/V3, Motion JPEG, JPEG 2000, JPEG-LS, Lossless JPEG, Apple Animation, Cinepak, Sorenson Video, Sorenson Video 3, QuickTime Video, Theora, Windows Media Video, Microsoft Video 1, ASUS V1/V2, Flash Screen Video, Flash Screen Video 2, ZMBV, CLJR, and FFV1 software routes plus hardware-capable routes are registered as replaceable implementations instead of being hardcoded in the encoder service.
- Apple-native H.265 hardware routes are now registered for `H.264 -> H.265`, `H.265 -> H.265`, `HEVC with Alpha -> H.265`, `Dolby Vision HEVC -> H.265`, and `ProRes -> H.265` when the simulated or runtime device profile can hardware-decode the source and hardware-encode H.265. Devices without that full HW path keep those routes visible as planned software-fallback work instead of pretending they can run.
- Broad software codec planning now has `SW_SoftwareCodecBackendRegistry`, which models software video/audio decode, H.265 video encode, audio encode, and container read/write coverage for future broad-input execution. `SW_UniversalCodecTranscodeAlgorithm` may still expose older broad route scaffolding internally while returning a clear not-bundled error until the broad backend and license review are complete.
- Single-asset encoding plans now carry a planned FFmpeg-family video command plan for H.265 output routes when the broad software backend can plan the input, mirroring the existing audio command-plan attachment.
- The app encoder service now dispatches prepared planned routes through the gated function-style FFmpeg-family video executor: when the broad SW backend is marked executable and a runner is injected, planned input-to-H.265 routes can run from the same `TaptionCodecTranscodeRequest` contract used by core codec algorithms.
- Generated AAC/MP4 audio fixture jobs now rebuild `TaptionAudioCodecTranscodeRequest` values and pass through `SW_FFmpegAudioCodecTranscodeExecutor` with a fake runner once broad SW backend gates are satisfied, giving audio the same function-style execution boundary as video.
- Core route planning now uses the `All Inputs to H.265 Codec Mesh` contract: practical video inputs can be admitted broadly, while video output remains H.265 only.
- `TaptionUniversalCodecCompletionAuditor` reports launch-route execution, planning locks, command-plan readiness, and runtime gaps. Its output must be interpreted against the H.265-only product contract, not as a requirement to ship non-H.265 output routes.
- Device Info now shows that completion audit state and saved device codec JSON snapshots include it alongside the runtime HW probe, static Apple model reconciliation, and route simulation summary.
- Audio conversion now has the same function-style contract shape through `AudioCodecAlgorithm.swift` and `SW_UniversalAudioCodecTranscodeAlgorithm.swift`. The planned software audio catalog covers every universal audio source/output pair and returns a clear not-bundled error until the broad backend ships.
- `CodecOutputCatalog` now centralizes output readiness as `Now`, `Plan Ready`, `Planned`, or `Blocked`, so the Home output selectors, file cards, Device Info, and saved device codec reports use the same core status model. Planned output routes are visible in file cards as states such as `Path SW Plan Ready` or `Path SW Blocked`; current-build video execution remains limited to H.265 output in MP4 or MOV, with AV1 covered by HW/SW fallback and H.264/H.265/ProRes covered only on hardware-capable profiles.
- `TaptionAudioCodecOutputCatalog` mirrors that output readiness model for audio codec/container pairs. Device Info now shows audio output readiness and saved device codec JSON snapshots include the audio output catalog beside the video output catalog.
- The Home output selector must keep video output fixed to H.265 while exposing audio codec and container readiness. Current execution is gated to launch-safe `H.265 + AAC / MP4`, `H.265 + AAC / MOV`, and the sample-proven bundled software `H.265 + PCM / MOV` and `H.265 + ALAC / MOV` output paths.
- `TaptionUniversalCodecCompletionAuditor` includes video and audio output-selector coverage, so saved device codec reports prove both H.265 route planning and Home selector readiness from one snapshot.
- Help, Device Info, and saved device codec reports now separate current-build inputs into `Now`, hardware-gated, and roadmap-only states, so planned H.265 input coverage is not presented as executable in the installed build.
- The future merge/edit project core now has native `.fcpxml` read/write through `FCPXMLProjectDocumentStore`. The generated FCPXML keeps normal `resources`, `project`, `sequence`, `spine`, and `asset-clip` structure while embedding the full Taption Encoder project model as metadata so early video segments, slices, touch-widget anchors, and normalization choices can round-trip before the editor UI ships. `FCPXMLValidator` now rejects generated/project files that are missing the required Taption metadata or core timeline structure.

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

Output video codec remains H.265 only. Future releases should expand input coverage and output controls around H.265, without adding alternate video output codecs or tying the app to Taption editor, subtitle, or editor-export UI dependencies.

### Final Product Goal

- Product path: AV1 to H.265 first, broad inputs to H.265 next, H.265-only output final.
- Convert almost any practical user video input into H.265 / HEVC.
- Treat every supported input as a candidate source for H.265 output only.
- Keep source and output codec catalogs intentionally asymmetric: input coverage expands broadly, output video codec remains H.265 only.
- Treat H.265 as the product's permanent video output codec, not merely a default.
- Use hardware codecs when available and software codecs when hardware is unavailable or unsupported.
- Evaluate FFmpeg-family software codec options and use the broadest codec support that is safe for App Store review, licensing, binary size, and performance.
- Support older devices where performance and OS APIs allow it.
- Let users choose background encoding on iOS/iPadOS 26 or later; on earlier versions, guide users to keep the app open for reliable encoding.
- Merge multiple videos into one H.265 output, even when the source containers/codecs/cameras differ.
- Preserve the source look by default.
- Add advanced controls over output container, size, frame rate, bitrate, quality, and color mapping after the simple flow is stable.
- Advanced output format means H.265 container and encode-setting choices, such as `.mp4` and `.mov`; it must not become full output codec selection.
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
- H.263 / H.261
- Motion JPEG, JPEG 2000, JPEG-LS, Lossless JPEG
- QuickTime Animation, Cinepak, Sorenson Video, RPZA, DV/DVCPro
- Flash Video, Flash Screen Video, Microsoft MPEG-4 V2/V3, Microsoft Video 1
- ASUS V1/V2, ZMBV, CLJR, FFV1, Snow, RealVideo
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
