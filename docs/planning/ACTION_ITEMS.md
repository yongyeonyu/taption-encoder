# Taption Encoder Release Action Items

Status date: 2026-07-07

## Current State

- Product path is AV1 to H.265 first, broad inputs to H.265 next, H.265-only video output final.
- Active action item count as of 2026-07-07: 104 remaining. Completed checklist items live in [COMPLETED_ACTION_ITEMS.md](COMPLETED_ACTION_ITEMS.md).
- Latest `01.01.00` TestFlight build-up pass: 1) set Apple version/build to `1.1.0 (30)`, 2) run plist/build-setting/core/focused validation, 3) create a local release archive, 4) upload to App Store Connect/TestFlight preparation, 5) keep App Review submission, TestFlight availability, processing completion, and public release as separate follow-up states.
- Latest preview/sample verification on 2026-06-29: `Scripts/verify_bundled_test_videos.sh` passed for 55 bundled videos normalized to 5 seconds; `Scripts/run_core_codec_truth_checks.sh` passed; focused iPhone simulator XCTest passed for bundled sample matching, source notice policy, codec inspection, software-only readiness, queue thumbnails, File/Folder thumbnail source routing, preview video output, preview close/reset/source-change/encoding-start behavior, and representative bundled H.265/MP4 transcodes.
- Latest iPhone preview log review on 2026-06-29 copied `Documents/TaptionEncoderLogs/taption-encoder.log` from the paired iPhone 14 Pro. It showed the preview audio session now activates, and identified several VLC preview no-video-output codecs (`Lossless JPEG`, `Microsoft RLE`, `R10K`, `R210`, `Snow`) that should remain encodable but not open a black preview surface in this build.
- Current bundled `TestVideos` audio policy: samples with readable source audio preserve source audio through codec/container-appropriate re-encoding; raw `H.261.h261` and `RoQ Video.roq` remain documented no-audio exceptions.
- Active player UX work: File/Folder/external video open should auto-enter full-screen preview when the current build can render the route; full-screen preview keeps controls visible during next/previous navigation, uses fixed one-line `current / duration` timing, supports previous/next queue controls, and suppresses app-open ads for external video-player launches.
- Files integration follow-up: `test video` seeding now verifies the expected bundled samples after wiping `Documents/test video`; Files app visibility is covered by `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, `UISupportsDocumentBrowser`, legacy-video `Owner` document ownership, standard-video `Owner` handler registration, and bundled sample thumbnails embedded in both the app and thumbnail extension.
- Current validation for the player/sample/background pass: `plutil -lint TaptionEncoder/Info.plist TaptionEncoderThumbnailExtension/Info.plist TaptionEncoderLiveActivityExtension/Info.plist` passed; `Scripts/verify_bundled_test_videos.sh` passed with 55 videos and the two documented audio exceptions; `Scripts/run_core_codec_truth_checks.sh` passed; external player registration and warm/cold external video player flow verification passed on the iPhone 17 Pro simulator; full app-scheme XCTest passed with parallel testing disabled.
- Latest P0 guidance/error-state validation on 2026-07-03: focused `CodecRoutePlannerTests` presenter tests passed on the iPhone 17 Pro simulator, covering iOS/iPadOS 18-25 keep-open guidance, iOS/iPadOS 26 Lock Screen/Dynamic Island copy, and English user-facing error formatting before raw diagnostics.
- Latest P0 AdMob/privacy validation on 2026-07-03: focused `CodecRoutePlannerTests` passed on the iPhone 17 Pro simulator, covering UMP/privacy options wiring, native ad provider and idle/completed slots, non-personalized ad requests, runtime ad placement switches, frequency caps, and full-screen ad suppression during protected flows.
- Latest P0 source-preserving execution validation on 2026-07-03: focused `CodecRoutePlannerTests` passed on the Codex iPhone 17 Pro simulator with parallel testing disabled, covering execution-plan source preservation requirements for resolution, frame rate, bitrate, color/HDR metadata, orientation, duration, and audio presence/sample shape; post-encode output verification for resolution, frame rate, color/HDR metadata, orientation, duration, audio shape, and AVFoundation visual-sample decodability/comparison; pre-encoder audit failure when known source-preserving fields are missing; and encoder-service failure when completed output verification fails. `Scripts/run_core_codec_truth_checks.sh` passed after the verification layer was added. A real bundled representative encode probe now passes H.261, Theora/Opus, JPEG-LS, QuickTime Video/AAC, and Flash Video/MP3 to H.265/MP4 with audio-bearing samples producing AAC output tracks, Theora preserving 320x240 instead of the prior 2x2 fallback, and source-preserving output verification passing.
- Latest P0 App Store privacy label pass on 2026-07-03: `docs/app_store/PRIVACY_NUTRITION_LABEL_ANSWERS.md` records the current App Store Connect answer set for ads, analytics, diagnostics, and tracking using Apple guidance, Google Mobile Ads disclosure guidance, UMP guidance, and the build `28` framework privacy manifests.
- Latest local performance/battery pass on 2026-07-04: Battery Options now include Battery Saver, Balanced, and Max Performance encoding profiles; Max Performance raises bitrate and task/resource-monitoring aggressiveness, Battery Saver caps automatic source output to 1080p/30fps and lowers bitrate. `Scripts/benchmark_bundled_codecs_simulator.sh` exercised all 56 bundled samples on the iPhone 17 Pro simulator in performance mode; 37 encoded successfully, 17 failed, 1 was route-blocked, and 1 timed out. Proof is recorded in `docs/verification/CODEC_BENCHMARK_2026-07-04.md`. This is local Debug simulator proof and not TestFlight/App Store Connect proof.
- Latest real-device hardware codec report pass on 2026-07-06: focused XCTest captured `HW_CodecCapabilityProbe` JSON from paired iPhone 14 Pro (`iPhone15,2`, iOS 26.5) and iPad Pro 12.9-inch 6th generation (`iPad14,6`, iPadOS 26.5). Proof is recorded in `docs/verification/REAL_DEVICE_CODEC_REPORTS_2026-07-06.md` and the JSON snapshots under `docs/verification/device_codec_reports/`. This is hardware capability evidence only, not real sample encode/playback, TestFlight/App Store Connect, App Review, or manual UI proof.
- Latest local codec sample acquisition on 2026-07-06: host-side probes acquired Theora, AMR-NB, AMR-WB+, xHE-AAC, and VC-1 raw samples, then verified H.265 MP4/MOV output for Theora, AMR-NB, and VC-1 raw through local FFmpeg. Fraunhofer xHE-AAC was decoded and converted to AAC through Apple `afconvert`; AMR-WB+ and ProRes RAW remain blocked. Proof is recorded in `docs/verification/CODEC_SAMPLE_ACQUISITION_2026-07-06.md`. This is local host-side evidence only, not app-side execution, simulator benchmark, real-device proof, TestFlight/App Store Connect, App Review, or public release proof.
- Latest internet-supported missing sample refresh on 2026-07-06: skipped bundled `TaptionEncoder/TestVideos` codecs and created local ignored samples under `Samples/Downloaded/internet_supported_missing_2026-07-06/` for HEVC-with-alpha candidates, VC-1 raw, QuickTime RPZA, AMR-NB video, xHE-AAC video, Y41P video, and an AMR-WB+ negative sample. Proof is recorded in `docs/verification/INTERNET_SUPPORTED_SAMPLE_REFRESH_2026-07-06.md`. This is local sample/probe evidence only, not app-side execution, simulator benchmark, real-device proof, TestFlight/App Store Connect, App Review, or public release proof.
- Latest VC-1 route correction on 2026-07-07: after the local raw VC-1 sample reached SwiftVLC but produced no frames, VC-1 was removed from current SwiftVLC executable/launch-available-now status and left as a planned FFmpeg-family/equivalent decode route. This is route-catalog evidence only, not app-side sample execution proof.
- Latest local sample runtime status on 2026-07-06: focused opt-in simulator XCTest passed while documenting current app-side blocks for local ignored samples. AMR-NB/H.263 stayed command-plan-only for AMR-to-AAC audio at that point, QuickTime RPZA reached software decode but failed source-preserving duration verification, VC-1 raw reached software VLC but produced no frames, and Y41P reached software VLC but libVLC reported the codec as unsupported. Proof is recorded in `docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-06.md`. This is simulator XCTest runtime evidence only, not host FFmpeg proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.
- Latest QuickTime RPZA sample-backed runtime pass on 2026-07-07: software VLC decode now keeps legacy held frames through the source duration for QuickTime Video/RPZA, and focused opt-in simulator XCTest encoded `rpza_1701-D.mov` to H.265 MP4 with source-preserving output verification passing at 2.660s output duration against 2.667s source duration. Proof is recorded in `docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-07.md`. This is simulator XCTest runtime evidence only, not host FFmpeg proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.
- Latest AMR-NB/H.263 sample-backed runtime pass on 2026-07-07: bundled VLC audio decode now feeds the AAC writer after resampling AMR-NB to 48 kHz, and focused opt-in simulator XCTest encoded `amr_nb_h263_video.3gp` to H.265 MP4 with 1 AAC mono output track. Proof is recorded in `docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-07.md`. This is simulator XCTest runtime evidence only, not host FFmpeg proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.
- Latest Y41P route correction on 2026-07-07: after libVLC reported Y41P unsupported, Y41P was removed from current SwiftVLC executable/launch-available-now status and left as a planned FFmpeg-family decode route. Focused opt-in simulator XCTest confirmed sample inspection and planned-route status. Proof is recorded in `docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-07.md`. This is simulator XCTest route-catalog evidence only, not app-side sample execution, host FFmpeg proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.
- Latest xHE-AAC sample-backed runtime pass on 2026-07-07: Apple-native inspection now recognizes USAC/xHE-AAC sample descriptions, xHE-AAC-to-AAC output expectations follow the native 44.1 kHz AAC writer rate, and focused opt-in simulator XCTest encoded `xhe_aac_hevc_video.mp4` to H.265 MP4 with 1 AAC stereo output track. Proof is recorded in `docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-07.md`. This is simulator XCTest runtime evidence only, not host FFmpeg proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.
- Latest external editor reference review on 2026-07-07: OpenCut, capcut-cli, pyCapCut, pyJianYingDraft, capcut-mate, capsrt, capcut-export, SmartCut/capcut-ai-editor, and the CapCut/JianYing draft schema cheat sheet were reviewed as architecture references for future merge/lightweight-editing work. Proof is recorded in `docs/architecture/VIDEO_EDITOR_REFERENCE_REVIEW_2026-07-07.md`. This is architecture/reference evidence only, not code import, dependency approval, codec execution proof, simulator proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.
- Latest handoff anchor: commit `72d5df0` (`Add encoding optimization profiles`) contains the Battery Options profile implementation, Max Performance/Battery Saver encode-policy changes, benchmark script, benchmark proof, and release-preparation docs. Keep this separate from any later TestFlight/App Store upload claim.
- Release `01.01.00` is the active release train and maps to Apple marketing version `1.1.0`, build `30`.
- Release `01.00.02` remains the previous uploaded release train; `01.01.00` build `30` App Store Connect upload has succeeded and the uploaded package is processing. The App Store Connect `1.1.0` version page exists in `PREPARE_FOR_SUBMISSION` with `MANUAL` release type and localized English/Korean What's New text. App Review submission, TestFlight availability, processing completion, and public availability remain owner-decided follow-up states and are not part of release preparation unless explicitly requested.
- Release commit is `f5af6b3` (`Prepare Taption Encoder 1.0.1 build 19`).
- Project shell exists.
- App is configured for iPhone and iPad.
- Minimum OS is iOS/iPadOS 18.0 for the current SwiftVLC software fallback binary.
- Orientation is portrait only.
- README and architecture documents exist.
- Detailed development plan exists in `docs/planning/DEVELOPMENT_PLAN.md`.
- Detailed phase-by-phase implementation guide exists in `docs/planning/DETAILED_DEVELOPMENT_PLAN.md`.
- Phase 0 foundation is implemented: app environment, feature flags, Home feature shell, protocol boundaries, and Xcode project grouping exist.
- Phase 1 UX/state machine is implemented: File, folder, and Photos sources can drive inspecting, storage checking, encoding progress, cancellation, rewarded-save waiting, pending-save recovery, and completed states.
- Phase 2 first real encoder slice is implemented for the release baseline: File, folder, and selected Photos import now use AVFoundation media inspection, route validation, video-info review before Start, H.265 export, software fallback for current executable software routes, real export/fallback progress, codec-path reporting, security-scoped file/folder access, broad folder extension discovery, folder sequential processing, Photos output save, storage checks, cancellation cleanup, and `_taption` final save after Star consumption or a zero-Star rewarded-save gate.
- Development is planned as 9 execution phases; release `01.00.01` / `1.0.1 (19)` is the shipped Phase 3 baseline, and final product completion remains targeted after Phase 8.
- Main screen is componentized with top/bottom banners, File, Folder, Photos, Reset, output codec/container selector, automatic codec-path info, video-info review, folder queue summary, output summary, status, progress, ETA, Start, Cancel, pending-save, and save completion surfaces.
- Main screen now has a top-left menu with Help, Open Source Notices, and Device Info sheets.
- AdMob app and production ad units are created and integrated for top/bottom banner, rewarded save, app-open, start interstitial, and session-end interstitial placements; Debug builds use Google's iOS test ad unit IDs.
- App Store release assets, app icon, preview/marketing copy, support URL, release metadata, and H.265-only output policy copy were prepared for release `01.00.01`.
- App Store Connect/TestFlight export upload succeeded for `1.0.1 (19)` and the uploaded package entered processing.
- Paired iPhone 14 Pro and iPad Pro 12.9-inch (6th generation) install checks both reported `com.taption.encoder` version `1.0.1`, build `19`.
- Latest release preparation proof for `01.01.00`: Apple version/build are set to `1.1.0 (30)`; plist lint passed; focused multi-file/folder XCTest passed; `Scripts/run_core_codec_truth_checks.sh` passed; local archive creation and archive Info.plist inspection passed at `build/TestFlight-01.01.00-30/TaptionEncoder.xcarchive`; App Store Connect/TestFlight upload succeeded and the uploaded package is processing. App Store Connect version `1.1.0` was created earlier in `PREPARE_FOR_SUBMISSION` with `MANUAL` release type and localized English/Korean What's New text. App Review submission, TestFlight availability, processing completion, public release, real-device install, and runtime logs were not performed for build `30` and remain separate proof surfaces. The upload completed with non-fatal third-party framework dSYM warnings for GoogleMobileAds and UserMessagingPlatform. The previous uploaded `01.00.02` build `28` proof remains separate.
- The project is in Git and pushed to `https://github.com/yongyeonyu/taption-encoder`.

## Release 01.01.00 Preparation

- [ ] Owner decision pending: select build/submit/release in App Store Connect.

## P0 Decisions Needed

- [ ] Confirm whether App Review requires a non-ad fallback for the Star or zero-Star rewarded-save flow.
- [ ] Confirm merge MVP scope: trim, cut, split, shorten, reorder, and canvas position only.

## P1 Final Product Architecture

- [ ] Implement the bundled software codec backend for broad input decode and fallback H.265 encode, including the planned FFmpeg-family/equivalent backend needed before VC-1 raw and Y41P can become sample-executable.
- [ ] Complete license review for any bundled software codec stack.
- [ ] Evaluate FFmpeg-family software codec options for App Store, licensing, binary-size, and performance constraints.
- [ ] Replace Apple device-family profiles with a complete per-model identifier matrix.
- [ ] Add thermal, battery, memory, and estimated runtime warnings for older devices.
- [ ] Implement app-side audio transcode execution for remaining planned audio routes, including AMR-WB/AMR-WB+ and non-AAC output-route coverage.
- [ ] Finish audio sample and execution coverage after the 2026-07-06 host-side pass: xHE-AAC now has focused simulator app-side execution proof through the Fraunhofer-derived local sample; AMR-WB+ has a negative sample; pure AMR-WB still needs a decodable App Store-safe sample and execution path.
- [ ] Download or acquire the deferred missing sample candidates after storage and use review: Dolby Vision HEVC, ProRes RAW, JPEG XL frame-sequence material, a decodable pure AMR-WB or AMR-WB+ sample, and a confirmed HEVC-with-alpha sample if Apple-side inspection rejects the current candidates.
- [ ] Add fallback behavior for unsupported inputs with clear English copy.

## P1 Merge And Lightweight Editing

- [ ] Add multi-file selection flow.
- [ ] Add project save/open flow using first-party typed project operations, validation, and backup-before-mutation rules from the external editor reference review.
- [ ] Add future `.fcpxmld` bundle plan for thumbnails, proxies, and richer metadata.
- [ ] Add managed `.fcpxmld` project mode plan that can copy original media when the user chooses it.
- [ ] Add merge compatibility inspection.
- [ ] Add output canvas resolver.
- [ ] Add merge normalization menu for output canvas/resolution, frame rate, color handling, audio layout, and orientation handling.
- [ ] Add close-enough auto-selection rules for similar frame rates, similar color metadata, and compatible audio layouts.
- [ ] Add `VideoSegment` and `VideoSegmentTimeline` models that replace Taption subtitle segments with video segments.
- [ ] Add Taption-inspired touch widget interaction model for video segment editing, keeping OpenCut-style shared core boundaries in mind without importing external editor code.
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

- [ ] Add output size/resolution controls.
- [ ] Add frame-rate controls.
- [ ] Add bitrate controls.
- [ ] Add quality controls.
- [ ] Add color-map/tone-map controls.
- [ ] Add HDR/SDR conversion options.
- [ ] Add advanced setting presets while keeping the default source-preserving path simple.

## P0 AdMob And Privacy

- [ ] Add ATT purpose string only if personalized ads or cross-app tracking are introduced later.

## P1 Reliability

- [ ] Add unit tests for output naming.
- [ ] Add unit tests for storage estimation and insufficient-space blocking.
- [ ] Add unit tests for home screen state transitions.
- [ ] Add unit tests for pending temporary output restoration after rewarded ad failure.
- [ ] Add unit tests for ad placement eligibility and frequency caps.
- [ ] Add unit tests for ETA smoothing.
- [ ] Add unit tests for background capability selection.
- [ ] Add unit tests for codec capability selection.
- [ ] Add unit tests for merge compatibility inspection.
- [ ] Add unit tests for output canvas resolution.
- [ ] Add unit tests for trim/cut/reorder/position validation.
- [ ] Add unit tests for video segment split/slice operations.
- [ ] Add unit tests for touch widget edit ownership.
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
- [ ] Verify generated FCPXML imports cleanly into Final Cut Pro.
- [ ] Verify user-selected normalization with differing frame rate, color, and audio samples.
- [ ] Verify automatic close-enough normalization with near-identical source values.
- [ ] Verify AdMob load on device after new production ad units become available.

## P1 App Store Release Prep

- [ ] Create final app icon.
- [ ] Create launch screen if the default generated launch screen is not sufficient.
- [ ] Prepare App Store screenshots for iPhone and iPad portrait.
- [ ] Prepare app description emphasizing free ad-supported H.265 conversion, starting with AV1 plus Apple-native HW routes.
- [ ] Prepare review notes explaining ad-supported save flow.
- [ ] Publish privacy policy.
- [ ] Publish support URL.
- [ ] Publish `app-ads.txt`.
- [ ] Confirm age rating.
- [ ] Confirm export compliance / encryption answers.
- [ ] Confirm category: Video.
- [ ] Attach build 01.00.00 (15) to the internal TestFlight group after App Store Connect processing completes.
- [ ] TestFlight smoke test.
- [ ] Submit for App Review.

## Policy Risks To Watch

- Star consumption is the ad-free save path; zero-Star jobs use rewarded ad before final save and still need clear disclosure and opt-in text.
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
