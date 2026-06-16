# Taption Encoder Release Action Items

Status date: 2026-06-16

## Current State

- Product path is AV1 to H.265 first, broad inputs to H.265 next, universal codec-to-codec conversion final.
- Project shell exists.
- App is configured for iPhone and iPad.
- Minimum OS is iOS/iPadOS 18.0 for the current SwiftVLC software fallback binary.
- Orientation is portrait only.
- README and architecture documents exist.
- Detailed development plan exists in `docs/DEVELOPMENT_PLAN.md`.
- Detailed phase-by-phase implementation guide exists in `docs/DETAILED_DEVELOPMENT_PLAN.md`.
- Phase 0 foundation is implemented: app environment, feature flags, Home feature shell, protocol boundaries, and Xcode project grouping exist.
- Phase 1 UX/state machine is implemented: File, folder, and Photos sources can drive inspecting, storage checking, encoding progress, cancellation, rewarded-save waiting, pending-save recovery, and completed states.
- Phase 2 first real encoder slice is partially implemented: File, folder, and selected Photos import now use AVFoundation media inspection, AV1-only validation, video-info review before Start, AVFoundation H.265 export, automatic software AV1 decode fallback, real export/fallback progress, codec-path reporting, security-scoped file/folder access, broad folder extension discovery, folder sequential processing, Photos output save, storage checks, cancellation cleanup, and `_taption.mp4` final save after the rewarded-save gate.
- Development is planned as 9 execution phases, with version 1.0 launching after Phase 3 and final product completion after Phase 8.
- Main screen is componentized with top/bottom banners, File, Folder, Photos, Reset, output codec/container selector, automatic codec-path info, video-info review, folder queue summary, output summary, status, progress, ETA, Start, Cancel, pending-save, and save completion surfaces.
- Main screen now has a top-left menu with Help, Open Source Notices, and Device Info sheets.
- AdMob app and production ad units are created and integrated for top/bottom banner, rewarded save, app-open, start interstitial, and session-end interstitial placements; Debug builds use Google's iOS test ad unit IDs.
- App Store release assets and metadata are not ready.
- The project is in Git and pushed to `https://github.com/yongyeonyu/taption-encoder`.

## P0 Decisions Needed

- [ ] Confirm whether final save must always require a rewarded ad, even if App Review asks for a fallback.
- [ ] Confirm merge MVP scope: trim, cut, split, shorten, reorder, and canvas position only.

## Confirmed Product Policies

- [x] Product path is AV1 to H.265 first, broad inputs to H.265 next, universal codec-to-codec conversion final.
- [x] Final codec direction is a symmetric all-to-all mesh: every supported universal input codec is also treated as a possible universal output codec unless deliberately excluded.
- [x] MVP output container is `.mp4` with H.265 video.
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
- [x] Long-term advanced output includes selectable output codecs for all-to-all conversion.
- [x] H.265 remains the recommended default output, not a permanent architecture ceiling.
- [x] Production AdMob IDs, privacy policy, support URL, and `app-ads.txt` will be added to the existing account/site setup.

## P0 Release Blockers

- [x] Apply iOS/iPadOS 18.0 deployment target for the current SwiftVLC software fallback binary.
- [x] Build Phase 0 main UI: top/bottom banner areas, title, File, Folder, Photos, Reset, automatic codec-path info, H.265 output summary, status/progress/cancel area.
- [x] Create app module structure from `docs/APP_ARCHITECTURE.md`.
- [x] Create `AppEnvironment` and protocol shells for encoder, media inspection, storage, ads, background, and project files.
- [x] Implement AV1 media inspection by codec metadata.
- [x] Port or rewrite the narrow AV1 to H.265 conversion core.
- [ ] Implement end-to-end source-preserving execution for resolution, frame rate, orientation, color metadata, HDR/SDR mode, audio timing, and visual quality across every HW/SW path.
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
- [ ] Persist completed temporary outputs when rewarded save cannot finish.
- [ ] Restore pending save jobs on app launch so the user can retry saving without re-encoding.
- [x] Implement File source import with security-scoped access.
- [x] Implement Folder source import with security-scoped access.
- [x] Implement sequential folder encoding for supported video files.
- [x] Implement Photos source import and new Photos asset save.
- [x] Implement storage checks before encoding and before final save.
- [ ] Implement Live Activity progress for active encoding.
- [ ] Implement user-selectable iOS 26+ continued background processing for user-started encoding.
- [ ] Implement iOS/iPadOS 18-25 keep-the-app-open guidance for reliable encoding.
- [ ] Implement user-facing error states in English.

## P1 Final Product Architecture

- [x] Add core `HW_` and `SW_` codec catalog/probe files for future portable Taption integration.
- [x] Add function-style codec transcode API contract using `TaptionCodecTranscodeRequest`, options, progress, and output.
- [x] Add `TaptionSourcePreservingOutputPolicyResolver` so generic encoding plans fill empty advanced options from the inspected source track before dispatching HW/SW codec algorithms.
- [x] Add source-preserving SW command-plan arguments for scale, frame rate, bitrate, 10-bit pixel format, color primaries, transfer function, color matrix, and rotation metadata.
- [x] Connect the current AV1 software fallback path to the function-style codec request API.
- [x] Add tests that require implemented routes to expose both HW and SW algorithm descriptors.
- [x] Route live AV1-to-H.265 execution through a codec registry/dispatcher so HW and SW algorithms can be added without hardcoding service branches.
- [x] Split the reusable Apple-native H.265 hardware algorithm into `HW_AppleHEVCCodecAlgorithm.swift`, leaving `HW_AV1HEVCCodecAlgorithm.swift` as the AV1-specific wrapper for future Taption migration.
- [x] Add broad SW backend capability registry for future all-to-all video/audio decode, encode, and container read/write coverage.
- [x] Add `TaptionSoftwareCodecBackendReadinessReport` so the broad bundled SW backend cannot be treated as executable until license review, App Store policy review, binary-size budget, iOS packaging, open-source notice generation, fixture regression proof, audio-signal proof, and old-device performance proof are closed.
- [x] Add planned `SW_UniversalCodecTranscodeAlgorithm` descriptors for every non-implemented universal route, with an explicit not-bundled execution error until the broad software backend ships.
- [x] Add `SW_FFmpegCodecCommandPlanner` so function-style video/audio codec requests can produce explicit FFmpeg-family command plans before the broad backend is bundled.
- [x] Add Xcode tests that every plannable FFmpeg-family video/audio output codec can generate command plans from every planned source codec, while unsupported output codecs fail explicitly.
- [x] Add shared video-container extension inference and command-plan tests for every declared readable input container and writable output container.
- [x] Add representative legacy/raw import alias inference and command-plan tests for DivX, TP/TRP/TOD, MOD, OGM, DVR-MS, AV1 elementary, H.263, MPEG elementary, and VC-1 files.
- [x] Add codec/container/audio research matrix for Apple-native, software, generated fixture, and real-world sample targets.
- [x] Add generated fixture script coverage for expanded video and audio codec families.
- [x] Expand generated video fixture coverage across every declared readable container, including M4V, MPEG-TS, MXF, FLV, 3G2, ASF, and raw elementary streams.
- [x] Expand generated video fixture coverage for representative container/raw aliases including DivX, TP/TRP/TOD, MOD, OGM, DVR-MS, AV1 OBU, H.263, M1V, and M2V.
- [x] Add repeatable SW/HW H.265 transcode fixture gate with objective audio signal verification.
- [x] Re-run the expanded 45-fixture video smoke set through both SW_HEVC and HW_HEVC, with 90/90 H.265 conversion attempts passing and 80 audio-signal checks passing.
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
- [x] Attach planned video FFmpeg-family command plans to single-asset encoding plans when the selected all-to-all output route has a software encoder.
- [x] Add single-asset FFmpeg-family A/V command planning so video all-to-all routes can carry audio copy/transcode decisions and source-preserving audio arguments.
- [x] Add gated FFmpeg-family command executor boundary with fake-runner tests so broad SW codec execution cannot run until all readiness gates close.
- [x] Connect prepared video command plans to the app encoder service through `SW_FFmpegVideoCodecTranscodeExecutor` so a ready broad SW backend can execute planned all-to-all routes through the same function-style codec request contract.
- [x] Add app-core fixture execution jobs that convert generated video/audio fixture rows into gated FFmpeg-family executor inputs.
- [x] Run generated AAC/MP4 audio fixture execution jobs through `SW_FFmpegAudioCodecTranscodeExecutor` from function-style audio requests when broad SW backend gates are satisfied.
- [x] Add app-scheme tests that match app-core fixture execution jobs against the latest SW/HW H.265 output and audio-signal evidence rows.
- [x] Add app-scheme tests that build generated video/audio fixture command plans to every currently plannable all-to-all output codec.
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
- [x] Add universal codec completion audit reporting so all-to-all planning, required bidirectional examples, command-plan gaps, and runtime gaps are visible as one core gate.
- [ ] Implement the bundled software codec backend for broad input decode and fallback H.265 encode.
- [x] Expand codec routing model from broad input to H.265 into all-to-all routes, including H.264 to AV1 and AV1 to H.264.
- [x] Add unit-test and route-simulator guards that every planned source/output codec pair is covered by the universal route matrix, including reverse routes for every supported pair.
- [x] Add a unit-test guard that universal source and output codec catalogs stay symmetric for the all-to-all product contract.
- [x] Add `TaptionCodecMeshCoverageReport` so app-core tests can audit video/audio all-to-all route counts, missing reverse routes, executable route counts, command-planner gaps, and broad software backend license-review status from one source.
- [x] Add unit-test and route-simulator guards that every implemented or planned route prefers HW decode/encode backends per codec side when the simulated device profile supports them.
- [x] Add app-side codec route planner that prioritizes HW, falls back to SW/mixed paths, and reports the planned path per imported file.
- [x] Register first Apple-native H.265 HW routes for H.264, H.265, and ProRes input, while keeping software fallback as planned work on devices without the required hardware path.
- [x] Add codec route simulation script and profile report for HW/SW priority checks.
- [x] Add app-scheme Xcode tests that parse route matrix TSV evidence for profile coverage, route coverage, and HW decode/encode preference.
- [x] Add Xcode unit test target for codec route planner HW/SW priority checks.
- [x] Add Apple device-family HW codec profiles for A10/A12/A13/A14/A15/A16/A17 Pro/A18/M-series simulation.
- [x] Add Apple device-family tests that verify `AV1 -> H.265` selects `SW`, `HW/SW`, or `HW` by profile.
- [ ] Complete license review for any bundled software codec stack.
- [ ] Evaluate FFmpeg-family software codec options for App Store, licensing, binary-size, and performance constraints.
- [x] Add runtime hardware codec probe foundation for the future Device Info menu.
- [x] Add top-left menu with Help, Open Source Notices, and Device Info.
- [x] Split Open Source Notices into shipped components, local development tooling, and broad codec backend candidate status so planning-only codec stacks are not presented as shipped app binaries.
- [x] Move Open Source Notices data into `TaptionOpenSourceNoticeCatalog` so shipped components, development tooling, and planning-only broad codec candidates share one core source with tests.
- [x] Add Open Source Notice readiness checks so bundled codec backends cannot pass release notices without final license text resource paths.
- [x] Bundle current shipped Open Source Notice license text resources and add app-scheme tests that fail when required notice files are missing or empty.
- [x] Show runtime HW decode/encode codec support in Device Info.
- [x] Show Apple-native audio decode/encode and MP4/MOV copy compatibility in Device Info.
- [x] Add capability-profile simulation for HW-first route selection.
- [x] Add all-to-all output codec/container selector UI that shows planned routes while current execution remains limited to H.265 output: AV1 via HW/SW fallback, plus H.264/H.265/ProRes on hardware-capable profiles.
- [x] Add core output readiness catalog so UI and route planning share the same `Now`, `Plan Ready`, `Planned`, and `Blocked` output status.
- [x] Include output selector readiness counts and item details in Device Info and saved device codec snapshots.
- [x] Name the final route contract `All-to-All Universal Codec Mesh` and expose representative `H.264 -> AV1`, `AV1 -> H.264`, and same-codec re-encode routes from core.
- [x] Surface video route readiness details in file-card codec path text and Device Info mesh readiness summaries.
- [x] Show audio Copy/HW/SW/Unsupported route details in loaded file cards alongside the video codec path.
- [x] Show all-to-all video card route states as HW/SW, SW Plan Ready, or SW Blocked so planned universal routes are not confused with runnable launch routes.
- [x] Add tests that selected output policy is preserved by the generic single-asset encoding plan.
- [x] Add Device Info save action and `HW_DeviceCodecReportStore` so real-device codec probe reports can be captured as JSON snapshots.
- [x] Include the universal codec completion audit in Device Info and saved device codec snapshots.
- [x] Add seeded Apple model-identifier codec matrix and expand route simulation evidence from family profiles to runtime model profiles.
- [x] Add static-matrix reconciliation to saved device codec reports so real-device probe snapshots expose missing and unexpected HW codec assumptions.
- [x] Add device codec report archive summarizer so multiple real-device probe snapshots can be audited for unknown and divergent HW codec assumptions.
- [x] Refresh the static Apple model matrix for current iPhone 17, iPhone Air, and iPhone 17e rows and expose a model coverage report.
- [ ] Replace Apple device-family profiles with a complete per-model identifier matrix.
- [ ] Capture real-device hardware codec reports across representative iPhone/iPad generations.
- [ ] Add thermal, battery, memory, and estimated runtime warnings for older devices.
- [x] Add mixed decode/encode path reporting.
- [x] Add broad input model/inspection mapping for H.264, H.265, AV1, VP9, VP8, MPEG-1/2/4, H.263, ProRes, DV, and legacy QuickTime families.
- [x] Add broad container inspection for MP4, MOV, M4V, WebM, MKV, AVI/DivX, TS/MTS/M2TS/TP/TRP/TOD, MPEG-PS/VOB/MOD, MXF, LRF, DV, Ogg/Ogv/OGM, FLV/F4V, 3GP/3G2, ASF/WMV/DVR-MS, and raw elementary streams.
- [x] Migrate the SW/HW H.265 media fixture transcode gate into app-side fixture evidence tests.
- [x] Migrate objective sound signal verification into app-side fixture evidence tests, not only host-side scripts.
- [ ] Implement app-side audio transcode execution for every planned audio route, not only route selection.
- [ ] Collect or generate xHE-AAC, AMR-NB, and AMR-WB samples through App Store-safe paths.
- [ ] Add fallback behavior for unsupported inputs with clear English copy.

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

- [ ] Add multi-file selection flow.
- [ ] Add `EncoderProject` domain model for future merge/edit timelines.
- [ ] Add FCPXML-based project document strategy.
- [ ] Add FCPXML serializer and parser behind project protocols.
- [ ] Add FCPXML DTD validation for generated project files.
- [ ] Add project save/open flow.
- [ ] Add future `.fcpxmld` bundle plan for thumbnails, proxies, and richer metadata.
- [ ] Add managed `.fcpxmld` project mode plan that can copy original media when the user chooses it.
- [ ] Add merge compatibility inspection.
- [ ] Add output canvas resolver.
- [ ] Add merge normalization menu for output canvas/resolution, frame rate, color handling, audio layout, and orientation handling.
- [ ] Add close-enough auto-selection rules for similar frame rates, similar color metadata, and compatible audio layouts.
- [ ] Add `VideoSegment` and `VideoSegmentTimeline` models that replace Taption subtitle segments with video segments.
- [ ] Add Taption-inspired touch widget interaction model for video segment editing.
- [ ] Add trim start/end editing.
- [ ] Add cut-range editing.
- [ ] Add slice/split operation that creates two video segments from one source asset.
- [ ] Add shorten clip behavior through out-point changes.
- [ ] Add clip reorder UI.
- [ ] Add clip canvas position/fit/fill/center controls.
- [ ] Keep preview cursor, touch hit testing, and committed edit calculations aligned through shared edit operations.
- [ ] Add normalization plan for differing codecs, containers, frame rates, color metadata, orientation, and audio layouts.
- [ ] Add merge encoding pipeline to one H.265 output.
- [ ] Reuse progress, ETA, cancellation, storage check, background status, and rewarded-save gates for merge jobs.

## P2 Advanced Controls

- [ ] Add output container selector around H.265 video.
- [ ] Add output size/resolution controls.
- [ ] Add frame-rate controls.
- [ ] Add bitrate controls.
- [ ] Add quality controls.
- [ ] Add color-map/tone-map controls.
- [ ] Add HDR/SDR conversion options.
- [ ] Add advanced setting presets while keeping the default source-preserving path simple.

## P0 AdMob And Privacy

- [x] Add Google Mobile Ads SDK.
- [ ] Add Google User Messaging Platform SDK if serving regions that require consent.
- [x] Add `GADApplicationIdentifier` to Info.plist.
- [x] Add required SKAdNetwork identifiers.
- [x] Add app-open ad provider.
- [x] Add top banner provider.
- [x] Add bottom banner provider.
- [ ] Add native ad provider for idle/completed states.
- [x] Add interstitial provider for natural pauses.
- [x] Add interstitial provider before user-started encoding sessions.
- [x] Add rewarded ad gate for `Watch Ad to Save`.
- [x] Use Google test ad units in Debug builds.
- [x] Prevent production ad unit IDs in Debug builds.
- [ ] Add privacy options entry point when required.
- [ ] Add inappropriate-ad reporting path if required by App Review.
- [ ] Add App Store privacy nutrition label answers for ads, analytics, diagnostics, and any tracking.
- [x] Keep initial ad requests non-personalized.
- [ ] Add ATT purpose string only if personalized ads or cross-app tracking are introduced later.
- [ ] Add consent flow before requesting ads where required for non-personalized or regional consent.
- [ ] Add remote-configurable ad placement switches and frequency caps.

## Recommended Ad Placement Plan

- [ ] App open ad on cold launch or foreground return when no encoding is active.
- [x] Persistent top and bottom banner placements on the main screen.
- [ ] Native ad in idle state below output summary.
- [ ] Native ad in completed state below saved output confirmation.
- [x] Interstitial before a user-started encoding session.
- [x] Interstitial after completed save before returning to idle.
- [x] Interstitial after cancelled/failed job acknowledgement.
- [ ] Add frequency caps for start and session-end interstitials.
- [ ] Rewarded ad before final save for every completed encoding job.
- [ ] No full-screen ad during active encoding, picker presentation, or cancellation.
- [ ] No banner/native ad directly adjacent to primary buttons.

## P1 Reliability

- [ ] Add unit tests for output naming.
- [ ] Add unit tests for storage estimation and insufficient-space blocking.
- [ ] Add unit tests for home screen state transitions.
- [ ] Add unit tests for rewarded-save gating.
- [ ] Add unit tests for pending temporary output restoration after rewarded ad failure.
- [ ] Add unit tests for ad placement eligibility and frequency caps.
- [x] Add unit tests for source-preserving output policy.
- [ ] Add unit tests for ETA smoothing.
- [ ] Add unit tests for background capability selection.
- [ ] Add unit tests for codec capability selection.
- [ ] Add unit tests for merge compatibility inspection.
- [ ] Add unit tests for output canvas resolution.
- [ ] Add unit tests for trim/cut/reorder/position validation.
- [ ] Add unit tests for video segment split/slice operations.
- [ ] Add unit tests for touch widget edit ownership.
- [ ] Add unit tests for FCPXML project save/open round trips.
- [ ] Add unit tests for FCPXML validation against the selected DTD/version.
- [ ] Add unit tests for merge normalization option generation.
- [ ] Add unit tests for close-enough automatic normalization choices.
- [ ] Add fake encoder for simulator UI tests.
- [ ] Add fake ad providers for simulator UI tests.
- [ ] Add fake Live Activity provider for simulator tests.
- [ ] Verify iPhone portrait layout in simulator.
- [ ] Verify iPad portrait layout in simulator.
- [ ] Verify Files picker flow.
- [ ] Verify Photos picker flow.
- [ ] Verify progress and cancellation flow.
- [ ] Verify ETA display flow.
- [ ] Verify rewarded-save retry/cancel flow.
- [ ] Verify pending save restoration after relaunch.
- [ ] Verify fake multi-file merge UI.
- [ ] Verify fake lightweight edit UI.
- [ ] Verify fake FCPXML project save/open UI.
- [ ] Verify fake merge normalization selection UI.

## P1 Device Proof

- [ ] Collect real AV1 sample files.
- [ ] Verify AV1 detection on device.
- [ ] Verify hardware encoder output on device.
- [ ] Verify software encoder behavior on device or document simulator-only limits.
- [ ] Verify output playback as H.265.
- [ ] Verify source-like preservation of resolution, orientation, frame rate, SDR/HDR mode, and color metadata.
- [ ] Verify `_taption` filename for Files outputs.
- [ ] Verify new Photos asset save.
- [ ] Verify storage warning behavior.
- [ ] Verify Live Activity/system progress during active encoding.
- [ ] Verify user-selectable background continuation on iOS/iPadOS 26+ real device.
- [ ] Verify iOS/iPadOS 18-25 fallback messaging.
- [ ] Verify software codec fallback on an older supported device.
- [ ] Verify mixed codec path with a non-native input sample.
- [ ] Verify merge output from at least two cameras/formats.
- [ ] Verify FCPXML project files can be reopened by Taption Encoder.
- [ ] Verify generated FCPXML validates against the selected FCPXML DTD/version.
- [ ] Verify user-selected normalization with differing frame rate, color, and audio samples.
- [ ] Verify automatic close-enough normalization with near-identical source values.
- [ ] Verify AdMob load on device after new production ad units become available.

## P1 App Store Release Prep

- [ ] Create final app icon.
- [ ] Create launch screen if the default generated launch screen is not sufficient.
- [ ] Prepare App Store screenshots for iPhone and iPad portrait.
- [ ] Prepare app description emphasizing free ad-supported AV1 to H.265 conversion.
- [ ] Prepare review notes explaining ad-supported save flow.
- [ ] Publish privacy policy.
- [ ] Publish support URL.
- [ ] Publish `app-ads.txt`.
- [ ] Confirm age rating.
- [ ] Confirm export compliance / encryption answers.
- [ ] Confirm category: Video.
- [ ] Archive release build.
- [ ] TestFlight upload.
- [ ] TestFlight smoke test.
- [ ] Submit for App Review.

## Policy Risks To Watch

- Rewarded ad before final save is the core monetization strategy, but it needs clear disclosure and opt-in text.
- Aggressive interstitial timing can create invalid clicks or review rejection if users are surprised during active work.
- Banners near primary controls can create accidental taps.
- Personalized ads require correct consent, ATT handling, and App Store privacy answers.
- Non-personalized ads still require regional consent handling where applicable.
- Long-running background encoding is only reliable where supported by the OS background task APIs; older OS versions need honest fallback UX.
- H.265 transcoding can preserve the source look, but it is not bit-for-bit lossless.
- Broad software codec support can create licensing, binary size, performance, and App Store review risk.
- Merge/edit features can grow into a full editor if scope is not kept clip-based and lightweight.
- FCPXML compatibility can drift if app-specific metadata is written directly into the interchange document without a clear namespace or sidecar policy.
- App Review may ask how users report inappropriate ads.
- If Photos/file access purpose strings are vague, review can reject or delay.
