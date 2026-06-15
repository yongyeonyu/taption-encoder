# Taption Encoder Release Action Items

Status date: 2026-06-15

## Current State

- Product path is AV1 to H.265 first, All to H.265 final.
- Project shell exists.
- App is configured for iPhone and iPad.
- Minimum OS is iOS/iPadOS 15.0.
- Orientation is portrait only.
- README and architecture documents exist.
- Detailed development plan exists in `docs/DEVELOPMENT_PLAN.md`.
- Detailed phase-by-phase implementation guide exists in `docs/DETAILED_DEVELOPMENT_PLAN.md`.
- Phase 0 foundation is implemented: app environment, feature flags, Home feature shell, protocol boundaries, and Xcode project grouping exist.
- Phase 1 fake UX/state machine is implemented: Files and Photos can drive fake inspecting, storage checking, encoding progress, cancellation, rewarded-save waiting, pending-save recovery, and completed states.
- Phase 2 first real encoder slice is partially implemented: Files import now uses AVFoundation media inspection, AV1-only validation, AVFoundation H.265 export, real export progress, hardware-first encoder reporting with software fallback policy, security-scoped file access, storage checks, cancellation cleanup, and `_taption.mp4` final save after the rewarded-save gate.
- Development is planned as 9 execution phases, with version 1.0 launching after Phase 3 and final product completion after Phase 8.
- Main screen is componentized with banner, title, Files, Photos, Reset, Automatic/Hardware/Software mode, H.265 output summary, status, progress, ETA, cancel, pending-save, and save completion surfaces.
- AdMob is not integrated.
- App Store release assets and metadata are not ready.
- The project is in Git and pushed to `https://github.com/yongyeonyu/taption-encoder`.

## P0 Decisions Needed

- [ ] Confirm whether final save must always require a rewarded ad, even if App Review asks for a fallback.
- [ ] Confirm merge MVP scope: trim, cut, split, shorten, reorder, and canvas position only.

## Confirmed Product Policies

- [x] Product path is AV1 to H.265 first, All to H.265 final.
- [x] MVP output container is `.mp4` with H.265 video.
- [x] Default quality prioritizes source-like visual quality over smallest file size.
- [x] iOS/iPadOS 26 or later can offer user-selectable background encoding.
- [x] Minimum OS is iOS/iPadOS 15.0 for old-device software encoding support.
- [x] Main screen uses `Reset` instead of `Exit`.
- [x] iOS/iPadOS 15-25 should show guidance to keep the app open for reliable encoding.
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
- [x] Advanced output "format" means H.265 container choice only, such as `.mp4` and `.mov`, not future non-H.265 output codecs.
- [x] Production AdMob IDs, privacy policy, support URL, and `app-ads.txt` will be added to the existing account/site setup.

## P0 Release Blockers

- [x] Apply iOS/iPadOS 15.0 deployment target for old-device software encoding support.
- [x] Build Phase 0 main UI: banner area, title, Files, Photos, Reset, encoder mode, H.265 output summary, status/progress/cancel area.
- [x] Create app module structure from `docs/APP_ARCHITECTURE.md`.
- [x] Create `AppEnvironment` and protocol shells for encoder, media inspection, storage, ads, background, and project files.
- [x] Implement AV1 media inspection by codec metadata.
- [x] Port or rewrite the narrow AV1 to H.265 conversion core.
- [ ] Implement source-preserving defaults for resolution, frame rate, orientation, color metadata, HDR/SDR mode, audio timing, and visual quality.
- [x] Implement hardware-first encoder path through AVFoundation/VideoToolbox reporting.
- [x] Implement software encoder path or a clear software fallback policy.
- [x] Implement codec capability detection that can report hardware, software, or mixed codec path.
- [x] Implement progress reporting.
- [x] Implement elapsed time and estimated time remaining.
- [x] Implement cancellation that safely cleans temporary output.
- [x] Implement output naming policy with `_taption`.
- [x] Implement temporary output first, then final save after reward.
- [ ] Persist completed temporary outputs when rewarded save cannot finish.
- [ ] Restore pending save jobs on app launch so the user can retry saving without re-encoding.
- [x] Implement Files source import with security-scoped access.
- [ ] Implement Photos source import and new Photos asset save.
- [x] Implement storage checks before encoding and before final save.
- [ ] Implement Live Activity progress for active encoding.
- [ ] Implement user-selectable iOS 26+ continued background processing for user-started encoding.
- [ ] Implement iOS/iPadOS 15-25 keep-the-app-open guidance for reliable encoding.
- [ ] Implement user-facing error states in English.

## P1 Final Product Architecture

- [ ] Add software codec abstraction for broad input decode and fallback H.265 encode.
- [ ] Complete license review for any bundled software codec stack.
- [ ] Evaluate FFmpeg-family software codec options for App Store, licensing, binary-size, and performance constraints.
- [ ] Add legacy-device capability matrix.
- [ ] Add thermal, battery, memory, and estimated runtime warnings for older devices.
- [ ] Add mixed decode/encode path reporting.
- [ ] Add broad input inspection for H.264, H.265, VP9, VP8, MPEG-2, ProRes, and unknown codecs.
- [ ] Add broad container inspection for MP4, MOV, M4V, WebM, MKV, AVI, TS/MTS/M2TS, and MXF.
- [ ] Add fallback behavior for unsupported inputs with clear English copy.

## Phase 1 UX State Machine

- [x] Add enum-based Home screen states for idle, importing, inspecting, storage checking, encoding, cancelling, waiting for reward, pending save, saving, completed, failed, and cancelled.
- [x] Add fake Files flow from file import to encoding progress.
- [x] Add fake Photos flow placeholder.
- [x] Add Hardware / Software encoder mode picker.
- [x] Add H.265 / MP4 output summary.
- [x] Add progress percentage, elapsed time, and estimated remaining time.
- [x] Add fake cancellation flow.
- [x] Add rewarded-save waiting surface.
- [x] Add pending-save recovery surface backed by `FakePendingSaveStore`.
- [x] Add shared UI components for source actions, progress, status, output summary, encoder mode, and pending save.

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

- [ ] Add Google Mobile Ads SDK.
- [ ] Add Google User Messaging Platform SDK if serving regions that require consent.
- [ ] Add `GADApplicationIdentifier` to generated Info.plist settings.
- [ ] Add required SKAdNetwork identifiers.
- [ ] Add app-open ad provider.
- [ ] Add anchored adaptive banner provider.
- [ ] Add native ad provider for idle/completed states.
- [ ] Add interstitial provider for natural pauses.
- [ ] Add rewarded ad gate for `Watch Ad to Save`.
- [ ] Use Google test ad units in Debug builds.
- [ ] Prevent production ad unit IDs in Debug builds.
- [ ] Add privacy options entry point when required.
- [ ] Add inappropriate-ad reporting path if required by App Review.
- [ ] Add App Store privacy nutrition label answers for ads, analytics, diagnostics, and any tracking.
- [ ] Keep initial ad requests non-personalized.
- [ ] Add ATT purpose string only if personalized ads or cross-app tracking are introduced later.
- [ ] Add consent flow before requesting ads where required for non-personalized or regional consent.
- [ ] Add remote-configurable ad placement switches and frequency caps.

## Recommended Ad Placement Plan

- [ ] App open ad on cold launch or foreground return when no encoding is active.
- [ ] Persistent top anchored adaptive banner on main and job status screens.
- [ ] Native ad in idle state below output summary.
- [ ] Native ad in completed state below saved output confirmation.
- [ ] Interstitial after completed save before returning to idle.
- [ ] Interstitial after cancelled/failed job acknowledgement, with frequency cap.
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
- [ ] Add unit tests for source-preserving output policy.
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
- [ ] Verify iOS/iPadOS 15-25 fallback messaging.
- [ ] Verify software codec fallback on an older supported device.
- [ ] Verify mixed codec path with a non-native input sample.
- [ ] Verify merge output from at least two cameras/formats.
- [ ] Verify FCPXML project files can be reopened by Taption Encoder.
- [ ] Verify generated FCPXML validates against the selected FCPXML DTD/version.
- [ ] Verify user-selected normalization with differing frame rate, color, and audio samples.
- [ ] Verify automatic close-enough normalization with near-identical source values.
- [ ] Verify AdMob test ads on device before production IDs.

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
