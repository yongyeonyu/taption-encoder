# Taption Encoder Completed Action Items

Status date: 2026-07-07

This file stores completed checklist items moved out of `ACTION_ITEMS.md` so the active action list only shows remaining work.

- Completed checklist item count: 245
- Active remaining checklist item count: 103
- Source file: `docs/planning/ACTION_ITEMS.md`

## Release 01.00.02 Closeout

- [x] Move development documents into typed `docs/` folders and keep only `AGENTS.md` at the project root as the routing document.
- [x] Archive old release notes, historical reports, completed Taption Encoder handoffs, and rejected Taption-main handoffs under `docs/archive/`.
- [x] Update Jamini communication scripts and handoff index to use Taption Encoder paths.
- [x] Set Apple marketing version/build to `1.0.2 (28)`.
- [x] Run current release validation for `01.00.02`.
- [x] Commit and push the `01.00.02` release changes to `main`.
- [x] Archive/export/upload `01.00.02` build `28` to TestFlight/App Store Connect.
- [x] Record `01.00.02` upload proof separately from App Review, public availability, real-device install, and runtime logs.

## Release 01.01.00 Preparation

- [x] Set Apple marketing version/build to `1.1.0 (29)`.
- [x] Run focused validation for the latest queue/source-preserving/privacy/multi-file encoding-mode changes.
- [x] Run current core validation for `01.01.00`.
- [x] Create local release archive under `build/TestFlight-01.01.00-29/`.
- [x] Upload `01.01.00` build `29` to App Store Connect/TestFlight preparation.
- [x] Create App Store Connect version `1.1.0` and fill English/Korean What's New text.
- [x] Record `01.01.00` preparation proof separately from App Review submission, public availability, real-device install, and runtime logs.

## Encoding Performance And Battery Options

- [x] Add Battery Options encoding optimization selector with Battery Saver, Balanced, and Max Performance modes.
- [x] Apply Battery Saver output caps for automatic source output and lower bitrate, while preserving explicit user resolution choices.
- [x] Apply Max Performance scheduling, bitrate multiplier, resource sampling, and HEVC writer settings for the highest-performance local path.
- [x] Add bundled-codec simulator benchmark script and record the 2026-07-04 full-sample performance-mode run separately from release upload proof.

## Release 01.00.01 Closeout

- [x] Set Apple marketing version/build to `1.0.1 (19)`.
- [x] Commit release build preparation as `f5af6b3`.
- [x] Push the release commit to `main` / `origin/main`.
- [x] Run `Scripts/run_core_codec_truth_checks.sh`.
- [x] Run full app-scheme XCTest with parallel testing disabled: 209 tests, 0 failures.
- [x] Run `Scripts/verify_codec_fixture_evidence.sh`.
- [x] Archive and export/upload `build/TestFlight-01.00.01-19/TaptionEncoder.xcarchive`.
- [x] Confirm App Store Connect/TestFlight upload success and package processing.
- [x] Install/check the release build on paired iPhone and iPad devices.
- [x] Release `01.00.01`.

## Confirmed Product Policies

- [x] Product path is AV1 to H.265 first, broad inputs to H.265 next, H.265-only video output final.
- [x] Final codec direction is an asymmetric input-to-H.265 mesh: every supported input codec is treated as a source candidate for H.265 output only.
- [x] MVP default output container is `.mp4` with H.265 video, with `.mov` available as a selectable H.265/AAC output.
- [x] Default quality prioritizes source-like visual quality over smallest file size.
- [x] iOS/iPadOS 26 or later can offer user-selectable background encoding.
- [x] Minimum OS is iOS/iPadOS 18.0 for the current SwiftVLC software fallback binary.
- [x] Main screen uses `Reset` instead of `Exit`.
- [x] iOS/iPadOS 18-25 should show guidance to keep the app open for reliable encoding.
- [x] Notification permission and local notifications are not part of the MVP.
- [x] Photos source output saves as a new Photos asset.
- [x] Initial ad policy is non-personalized ads.
- [x] Rewarded ad load failure keeps the completed temporary output and lets the user retry later without re-encoding.
- [x] Encoder project save format starts as native `.fcpxml`.
- [x] A future `.fcpxmld` project bundle should support thumbnails, proxies, and richer metadata.
- [x] Future managed `.fcpxmld` projects may copy original media when the user chooses that mode.
- [x] Merge normalization should show user-selectable options when frame rate, color, audio, or canvas values differ meaningfully.
- [x] Merge normalization can auto-pick the closest recommended value when detected values are effectively equivalent.
- [x] Broad input support may increase app binary size if App Store and licensing constraints are satisfied.
- [x] Software codec stack may evaluate FFmpeg-family technology and should pull broad support as far as App Store, licensing, and binary-size limits allow.
- [x] FCPXML DTD/version should use the latest stable official version available at implementation time.
- [x] MVP advanced output "format" means H.265 container choice only, such as `.mp4` and `.mov`.
- [x] Long-term advanced output includes selectable H.265 containers and encode settings, not alternate video output codecs.
- [x] H.265 is the permanent video output codec.
- [x] Help, Device Info, and saved codec reports separate current-build executable inputs, hardware-gated inputs, and roadmap-only H.265 input coverage.
- [x] Production AdMob IDs, privacy policy, support URL, and `app-ads.txt` will be added to the existing account/site setup.

## P0 Release Blockers And Post-Release Follow-Ups

- [x] Apply iOS/iPadOS 18.0 deployment target for the current SwiftVLC software fallback binary.
- [x] Build Phase 0 main UI: top/bottom banner areas, title, File, Folder, Photos, Reset, automatic codec-path info, H.265 output summary, status/progress/cancel area.
- [x] Create app module structure from `docs/architecture/APP_ARCHITECTURE.md`.
- [x] Create `AppEnvironment` and protocol shells for encoder, media inspection, storage, ads, background, and project files.
- [x] Implement AV1 media inspection by codec metadata.
- [x] Port or rewrite the narrow AV1 to H.265 conversion core.
- [x] Implement end-to-end source-preserving execution for resolution, frame rate, orientation, color metadata, HDR/SDR mode, audio timing, and visual quality across every HW/SW path.
- [x] Implement hardware-first encoder path through AVFoundation/VideoToolbox reporting.
- [x] Implement software encoder path or a clear software fallback policy.
- [x] Implement codec capability detection that can report hardware, software, or mixed codec path.
- [x] Implement progress reporting.
- [x] Implement elapsed time and estimated time remaining.
- [x] Show video info after file inspection and before encoding starts.
- [x] Require Start before encoding, then switch the action button to Cancel during encoding.
- [x] Implement cancellation that safely cleans temporary output.
- [x] Implement output naming policy with `_taption`.
- [x] Implement temporary output first, then final save after reward.
- [x] Persist completed temporary outputs when rewarded save cannot finish.
- [x] Restore pending save jobs on app launch so the user can retry saving without re-encoding.
- [x] Implement File source import with security-scoped access.
- [x] Implement Folder source import with security-scoped access.
- [x] Add folder-picker file passthrough and queue-list full-screen preview: Folder accepts either one folder or one supported video file; file selection uses the existing File import flow; tapping an enabled queue item opens a full-screen SwiftVLC/libVLC preview using current-build implemented codec routes, preserves source resolution, avoids temporary H.265 preview files, and stops playback on Close/reset/source change/encoding start.
- [x] Add commercial-player style queue preview navigation and explicit playback audio activation: preview activates an iOS playback audio session, unmutes/sets player volume/role before SwiftVLC playback, displays the source audio status, and lets multi-file queues move to previous/next videos from full-screen controls or edge swipes without returning Home.
- [x] Implement sequential folder encoding for supported video files.
- [x] Implement Photos source import and new Photos asset save.
- [x] Implement storage checks before encoding and before final save.
- [x] Implement Live Activity progress for active encoding.
- [x] Implement user-selectable iOS 26+ continued background processing for user-started encoding.
- [x] Implement iOS/iPadOS 18-25 keep-the-app-open guidance for reliable encoding.
- [x] Implement user-facing error states in English.

## P1 Final Product Architecture

- [x] Add core `HW_` and `SW_` codec catalog/probe files for future portable Taption integration.
- [x] Add function-style codec transcode API contract using `TaptionCodecTranscodeRequest`, options, progress, and output.
- [x] Add `TaptionSourcePreservingOutputPolicyResolver` so generic encoding plans fill empty advanced options from the inspected source track before dispatching HW/SW codec algorithms.
- [x] Add source-preserving SW command-plan arguments for scale, frame rate, bitrate, 10-bit pixel format, color primaries, transfer function, color matrix, and rotation metadata.
- [x] Connect the current AV1 software fallback path to the function-style codec request API.
- [x] Add tests that require implemented routes to expose both HW and SW algorithm descriptors.
- [x] Route live AV1-to-H.265 execution through a codec registry/dispatcher so HW and SW algorithms can be added without hardcoding service branches.
- [x] Split the reusable Apple-native H.265 hardware algorithm into `HW_AppleHEVCCodecAlgorithm.swift`, leaving `HW_AV1HEVCCodecAlgorithm.swift` as the AV1-specific wrapper for future Taption migration.
- [x] Add broad SW backend capability registry for future input decode, H.265 encode, audio encode, and container read/write coverage.
- [x] Add `TaptionSoftwareCodecBackendReadinessReport` so the broad bundled SW backend cannot be treated as executable until license review, App Store policy review, binary-size budget, iOS packaging, open-source notice generation, fixture regression proof, audio-signal proof, and old-device performance proof are closed.
- [x] Add planned `SW_UniversalCodecTranscodeAlgorithm` descriptors for every non-implemented universal route, with an explicit not-bundled execution error until the broad software backend ships.
- [x] Add `SW_FFmpegCodecCommandPlanner` so function-style video/audio codec requests can produce explicit FFmpeg-family command plans before the broad backend is bundled.
- [x] Add Xcode tests that every plannable FFmpeg-family H.265 video/audio output can generate command plans from planned source codecs, while unsupported outputs fail explicitly.
- [x] Add shared video-container extension inference and command-plan tests for every declared readable input container and writable output container.
- [x] Add representative legacy/raw import alias inference and command-plan tests for DivX, TP/TRP/TOD, MOD, OGM, DVR-MS, NUT, RoQ, RealMedia, AV1 elementary, H.263, MPEG elementary, and VC-1 files.
- [x] Add codec/container/audio research matrix for Apple-native, software, generated fixture, and real-world sample targets.
- [x] Add generated fixture script coverage for expanded video and audio codec families.
- [x] Expand generated video fixture coverage across every declared readable container, including M4V, MPEG-TS, MXF, FLV, 3G2, ASF, and raw elementary streams.
- [x] Expand generated video fixture coverage for representative container/raw aliases including DivX, M2TS/TP/TRP/TOD, DAT/MOD/VOB, QT, F4V, OGM, DVR-MS, NUT, RoQ, RealMedia, AV1 OBU, H.263, rawvideo Y4M, M1V, and M2V.
- [x] Add repeatable SW/HW H.265 transcode fixture gate with objective audio signal verification.
- [x] Re-run the expanded 90-fixture video smoke set through both SW_HEVC and HW_HEVC, with 180/180 H.265 conversion attempts passing and 166 audio-signal checks passing.
- [x] Add fixture evidence verifier that requires every generated sample to pass both SW_HEVC and HW_HEVC with H.265 output and preserved audio signal.
- [x] Add app-scheme Xcode tests that parse the generated video fixture manifest and compare it against `SW_CodecSupportCatalog.fixtureTargets`.
- [x] Add app-scheme Xcode tests that parse the fixture transcode evidence TSV and fail when SW/HW H.265 output or audio signal proof is missing.
- [x] Add app-scheme Xcode tests that build source-preserving H.265/MP4 command plans from every generated video fixture manifest row.
- [x] Add audio-focused fixture generation and SW/HW H.265 transcode gate with objective audio signal verification.
- [x] Add app-scheme Xcode tests that parse audio fixture generation evidence, proving generated codecs and tracking pending xHE-AAC, AMR-NB, and AMR-WB attempts.
- [x] Add app-scheme Xcode tests that build AAC/MP4 app-core audio route plans and FFmpeg-family software fallback command plans from every generated audio fixture row.
- [x] Add app-core audio route planner for copy, native transcode, software decode to AAC, and planned audio routes.
- [x] Add tests that every planned source audio codec routes to default AAC output for MP4/H.265.
- [x] Add function-style audio codec request/output contract and planned `SW_UniversalAudioCodecTranscodeAlgorithm` descriptors for every universal audio source/output pair.
- [x] Add source-preserving audio option resolution for sample rate, channel count, and source bitrate, then emit `-ar`, `-ac`, and `-b:a` in software audio command plans.
- [x] Populate inspected audio sample rate and channel count from AVFoundation format descriptions so source-preserving audio options use real file metadata.
- [x] Attach first-track audio route, source-preserving audio options, readiness state, and FFmpeg-family command-plan evidence to single-asset encoding plans.
- [x] Add gated FFmpeg-family video command execution wrapper with fake-runner tests so planned video routes can execute directly from function-style codec requests after broad-backend gates close.
- [x] Add gated FFmpeg-family audio command execution wrapper with fake-runner tests so planned audio routes can use the same future broad-backend execution boundary as video.
- [x] Attach planned video FFmpeg-family command plans to single-asset encoding plans when the selected H.265 output route has a software encoder.
- [x] Add single-asset FFmpeg-family A/V command planning so input-to-H.265 routes can carry audio copy/transcode decisions and source-preserving audio arguments.
- [x] Add gated FFmpeg-family command executor boundary with fake-runner tests so broad SW codec execution cannot run until all readiness gates close.
- [x] Connect prepared video command plans to the app encoder service through `SW_FFmpegVideoCodecTranscodeExecutor` so a ready broad SW backend can execute planned input-to-H.265 routes through the same function-style codec request contract.
- [x] Build and vendor the selected source-built LGPL FFmpeg-family decode bridge for focused VC-1 raw/Y41P execution proof, including configure/component-map/source/notice documentation and iOS simulator H.265 MP4/MOV output verification through the real bundled bridge.
- [x] Add app-core fixture execution jobs that convert generated video/audio fixture rows into gated FFmpeg-family executor inputs.
- [x] Run generated AAC/MP4 audio fixture execution jobs through `SW_FFmpegAudioCodecTranscodeExecutor` from function-style audio requests when broad SW backend gates are satisfied.
- [x] Add app-scheme tests that match app-core fixture execution jobs against the latest SW/HW H.265 output and audio-signal evidence rows.
- [x] Add app-scheme tests that build generated video/audio fixture command plans to currently plannable H.265 output paths.
- [x] Add video fixture catalog coverage reporting so every universal source codec is tracked as generated, conditional, real-world-sample-required, or planned.
- [x] Enforce video fixture generation evidence so implemented targets pass generation and optional VC-1/Theora attempts keep concrete blocking reasons.
- [x] Add video container fixture coverage reporting so every declared non-unknown container and extension alias is tracked by the sample plan.
- [x] Align iOS file picker UTTypes, folder scanning, and `Info.plist` imported video extensions with the core container alias list, including legacy and raw stream aliases.
- [x] Add audio fixture catalog coverage reporting so every universal audio codec is tracked as generated or explicitly pending.
- [x] Enforce pending audio fixture evidence rows so xHE-AAC, AMR-NB, and AMR-WB keep concrete generator attempts and blocking reasons until generated samples are available.
- [x] Add Apple `afconvert` alternate generation attempts for pending xHE-AAC, AMR-NB, and AMR-WB audio fixtures so evidence records both FFmpeg and system-encoder blockers.
- [x] Add app-core video execution readiness reporting that separates current-build implemented routes, FFmpeg-family command-plan routes, and missing software video encoder gaps.
- [x] Add app-core audio execution readiness reporting that separates current-build native/copy routes, FFmpeg-family command-plan routes, and missing software audio encoder gaps.
- [x] Add `HW_AudioCodecAlgorithmCatalog` and `TaptionAudioCodecDescriptorRegistry` so audio routes expose preferred HW/SW descriptors before full audio execution lands.
- [x] Add codec completion audit reporting so H.265 route planning, command-plan gaps, and runtime gaps are visible as one core gate.
- [x] Expand codec routing model around broad input to H.265 routes.
- [x] Add unit-test and route-simulator guards that every supported input codec can be evaluated against H.265 output readiness.
- [x] Add a unit-test guard that source and output codec catalogs remain intentionally asymmetric for the H.265-only product contract.
- [x] Add `TaptionCodecMeshCoverageReport` so app-core tests can audit H.265 route counts, executable route counts, command-planner gaps, and broad software backend license-review status from one source.
- [x] Add unit-test and route-simulator guards that every implemented or planned route prefers HW decode/encode backends per codec side when the simulated device profile supports them.
- [x] Add app-side codec route planner that prioritizes HW, falls back to SW/mixed paths, and reports the planned path per imported file.
- [x] Register first Apple-native H.265 HW routes for H.264, H.265, and ProRes input, while keeping software fallback as planned work on devices without the required hardware path.
- [x] Add codec route simulation script and profile report for HW/SW priority checks.
- [x] Add app-scheme Xcode tests that parse route matrix TSV evidence for profile coverage, route coverage, and HW decode/encode preference.
- [x] Add Xcode unit test target for codec route planner HW/SW priority checks.
- [x] Add Apple device-family HW codec profiles for A10/A12/A13/A14/A15/A16/A17 Pro/A18/M-series simulation.
- [x] Add Apple device-family tests that verify `AV1 -> H.265` selects `SW`, `HW/SW`, or `HW` by profile.
- [x] Add runtime hardware codec probe foundation for the future Device Info menu.
- [x] Add top-left menu with Help, Open Source Notices, and Device Info.
- [x] Split Open Source Notices into shipped components, local development tooling, and broad codec backend candidate status so planning-only codec stacks are not presented as shipped app binaries.
- [x] Move Open Source Notices data into `TaptionOpenSourceNoticeCatalog` so shipped components, development tooling, and planning-only broad codec candidates share one core source with tests.
- [x] Add Open Source Notice readiness checks so bundled codec backends cannot pass release notices without final license text resource paths.
- [x] Bundle current shipped Open Source Notice license text resources and add app-scheme tests that fail when required notice files are missing or empty.
- [x] Show runtime HW decode/encode codec support in Device Info.
- [x] Show Apple-native audio decode/encode and MP4/MOV copy compatibility in Device Info.
- [x] Add capability-profile simulation for HW-first route selection.
- [x] Add H.265 output container selector UI that shows planned H.265 routes while current execution remains limited to H.265 output: AV1 via HW/SW fallback, plus H.264/H.265/ProRes on hardware-capable profiles.
- [x] Add core output readiness catalog so UI and route planning share the same `Now`, `Plan Ready`, `Planned`, and `Blocked` output status.
- [x] Include output selector readiness counts and item details in Device Info and saved device codec snapshots.
- [x] Name the final product contract as broad input to H.265 output; non-H.265 routes such as `H.264 -> AV1`, `AV1 -> H.264`, and same-codec non-H.265 re-encode are outside scope.
- [x] Surface video route readiness details in file-card codec path text and Device Info mesh readiness summaries.
- [x] Show audio Copy/HW/SW/Unsupported route details in loaded file cards alongside the video codec path.
- [x] Show video card route states as HW/SW, SW Plan Ready, or SW Blocked so planned H.265 routes are not confused with runnable launch routes.
- [x] Add tests that selected output policy is preserved by the generic single-asset encoding plan.
- [x] Add Device Info save action and `HW_DeviceCodecReportStore` so real-device codec probe reports can be captured as JSON snapshots.
- [x] Include the universal codec completion audit in Device Info and saved device codec snapshots.
- [x] Add seeded Apple model-identifier codec matrix and expand route simulation evidence from family profiles to runtime model profiles.
- [x] Add static-matrix reconciliation to saved device codec reports so real-device probe snapshots expose missing and unexpected HW codec assumptions.
- [x] Add device codec report archive summarizer so multiple real-device probe snapshots can be audited for unknown and divergent HW codec assumptions.
- [x] Refresh the static Apple model matrix for current iPhone 17, iPhone Air, and iPhone 17e rows and expose a model coverage report.
- [x] Capture real-device hardware codec reports from paired iPhone 14 Pro and iPad Pro 12.9-inch 6th generation, with JSON proof recorded under `docs/verification/device_codec_reports/`.
- [x] Add mixed decode/encode path reporting.
- [x] Add broad input model/inspection mapping for H.264, H.265, AV1, VP9, VP8, MPEG-1/2/4, H.263, ProRes, DV, and legacy QuickTime families.
- [x] Add broad container inspection for MP4, MOV, M4V, WebM, MKV, AVI/DivX, TS/MTS/M2TS/TP/TRP/TOD, MPEG-PS/VOB/MOD, MXF, LRF, DV, Ogg/Ogv/OGM, FLV/F4V, NUT, RealMedia, RoQ, 3GP/3G2, ASF/WMV/DVR-MS, and raw elementary streams.
- [x] Migrate the SW/HW H.265 media fixture transcode gate into app-side fixture evidence tests.
- [x] Migrate objective sound signal verification into app-side fixture evidence tests, not only host-side scripts.

## Phase 1 UX State Machine

- [x] Add enum-based Home screen states for idle, importing, inspecting, storage checking, encoding, cancelling, waiting for reward, pending save, saving, completed, failed, and cancelled.
- [x] Add fake Files flow from file import to encoding progress.
- [x] Add real Folder flow from folder import to sequential encoding progress.
- [x] Add real Photos picker flow.
- [x] Add automatic codec-path info display; HW/SW is not a user-selectable mode.
- [x] Add output codec/container selector and output summary.
- [x] Add progress percentage, elapsed time, and estimated remaining time.
- [x] Add fake cancellation flow.
- [x] Add rewarded-save waiting surface.
- [x] Add pending-save recovery surface backed by `FakePendingSaveStore`.
- [x] Add shared UI components for source actions, progress, status, output summary, codec-path info, and pending save.

## P1 Merge And Lightweight Editing

- [x] Add `EncoderProject` domain model for future merge/edit timelines.
- [x] Add FCPXML-based project document strategy.
- [x] Add FCPXML serializer and parser behind project protocols.
- [x] Add structural FCPXML validation for generated project files.

## P2 Advanced Controls

- [x] Add output container selector around H.265 video.

## P0 AdMob And Privacy

- [x] Add Google Mobile Ads SDK.
- [x] Add Google User Messaging Platform SDK if serving regions that require consent.
- [x] Add `GADApplicationIdentifier` to Info.plist.
- [x] Add required SKAdNetwork identifiers.
- [x] Add app-open ad provider.
- [x] Add top banner provider.
- [x] Add bottom banner provider.
- [x] Add native ad provider for idle/completed states.
- [x] Add interstitial provider for natural pauses.
- [x] Add interstitial provider before user-started encoding sessions.
- [x] Add rewarded ad gate for `Watch Ad to Save`.
- [x] Use Google test ad units in Debug builds.
- [x] Prevent production ad unit IDs in Debug builds.
- [x] Add privacy options entry point when required.
- [x] Add inappropriate-ad reporting path if required by App Review.
- [x] Add App Store privacy nutrition label answers for ads, analytics, diagnostics, and any tracking.
- [x] Keep initial ad requests non-personalized.
- [x] Add consent flow before requesting ads where required for non-personalized or regional consent.
- [x] Add remote-configurable ad placement switches and frequency caps.

## Recommended Ad Placement Plan

- [x] App open ad on cold launch or foreground return when no encoding is active.
- [x] Persistent top and bottom banner placements on the main screen.
- [x] Native ad in idle state below output summary.
- [x] Native ad in completed state below saved output confirmation.
- [x] Interstitial before a user-started encoding session.
- [x] Interstitial after completed save before returning to idle.
- [x] Interstitial after cancelled/failed job acknowledgement.
- [x] Add frequency caps for start and session-end interstitials.
- [x] Use one Star for ad-free final save, otherwise require a rewarded ad before final save.
- [x] No full-screen ad during active encoding, picker presentation, or cancellation.
- [x] No banner/native ad directly adjacent to primary buttons.

## P1 Reliability

- [x] Add unit tests for rewarded-save gating.
- [x] Add unit tests for source-preserving output policy.
- [x] Add unit tests for FCPXML project save/open round trips.
- [x] Add unit tests for structural FCPXML validation.

## P1 App Store Release Prep

- [x] Archive release build.
- [x] TestFlight upload.
- [x] Upload TestFlight build 00.01.00 (7); App Store Connect accepted the package and started processing.
- [x] Upload TestFlight build 00.01.01 (8); App Store Connect accepted the package and started processing.
- [x] Upload TestFlight build 00.01.01 (9); App Store Connect accepted the package and started processing.
- [x] Upload TestFlight build 00.01.01 (10); App Store Connect accepted the package and started processing.
- [x] Upload TestFlight build 00.01.01 (11); App Store Connect accepted the package and started processing.
- [x] Upload TestFlight build 00.01.01 (12); App Store Connect accepted the package and started processing.
- [x] Upload TestFlight build 00.01.01 (13); App Store Connect accepted the package and started processing.
- [x] Upload TestFlight build 00.01.01 (14); App Store Connect accepted the package and started processing.
- [x] Release iPhone ad ID smoke for 01.00.00 (15); Release log showed production publisher `ca-app-pub-9754025737691277` and zero Google demo IDs after launch.
- [x] Upload TestFlight build 01.00.00 (15); App Store Connect accepted the package and started processing.
- [x] Create internal TestFlight group and attach build 00.01.00 (5).
- [x] Add account owner/admin as internal tester for build 00.01.00 (5).
