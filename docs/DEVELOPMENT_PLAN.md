# Taption Encoder Development Plan

Status date: 2026-06-15

## Phase Count

Taption Encoder should be developed in 9 execution phases.

- Phase 0 to Phase 3: build and launch the first monetized AV1 to H.265 app.
- Phase 4 to Phase 8: expand from the launched app into a broad input encoder, then into the final universal codec-to-codec encoder with legacy software support, FCPXML projects, merge editing, and advanced controls.

Launch target:

- Version 1.0 ships at the end of Phase 3.
- The completed product direction is reached at the end of Phase 8.

## Product Completion Definition

The app is considered complete when it can:

- Convert AV1 first, then broadly used user video formats into H.265, then support codec-to-codec conversion across the supported matrix.
- Use hardware, software, or mixed codec paths based on file and device capability.
- Support older iPhones and iPads honestly through software encoding, warnings, and capability checks.
- Run background encoding on iOS/iPadOS 26 or later when the user selects it.
- Tell iOS/iPadOS 18-25 users to keep the app open for reliable long encodes.
- Save output automatically with `_taption` naming or Photos equivalent.
- Gate final save through rewarded AdMob ads.
- Preserve completed temporary outputs if rewarded save cannot finish, then restore a pending-save state later without re-encoding.
- Show top and bottom banner ads plus additional non-disruptive non-personalized ad placements.
- Save merge/edit projects as native `.fcpxml`.
- Later support `.fcpxmld` bundles for thumbnails, proxies, richer metadata, and user-selected managed media copies.
- Merge multiple videos into one H.265 output.
- Provide video-segment editing: trim, cut, split, shorten, reorder, and canvas placement.
- Offer advanced output controls for output codec, container, size, frame rate, bitrate, quality, and color handling.

## Phase 0: Foundation Lock

Goal: make the project ready for real implementation without pulling in unrelated Taption editor code.

Status, 2026-06-15: implemented. The source tree, environment object, feature flags, protocol shells, fake services, and Home screen shell compile for iPhone and iPad simulators.

Scope:

- Keep the app separate from `/Users/u_mo_c/Documents/taption`.
- Use iOS/iPadOS 18.0 as the minimum OS for the current SwiftVLC software fallback, with feature gates for newer APIs.
- Keep iPhone and iPad portrait-only.
- Keep iPad using the same centered mobile-width UX as iPhone.
- Establish the source tree from `docs/APP_ARCHITECTURE.md`.
- Add dependency injection through `AppEnvironment`.
- Add protocol boundaries for encoder, media inspection, file access, storage, ads, background, and project files.
- Keep all visible app strings in English.

Key decisions to close:

- Final save rewarded-ad fallback policy if App Review requires one.
- Software codec implementation choice and licensing details.

Deliverables:

- Module folders created.
- `AppEnvironment` created.
- Feature and core protocols compile.
- Test targets can use fake services.
- Action items remain synchronized with this plan.

Exit criteria:

- Clean simulator build.
- No direct import of main Taption editor, subtitle, or export UI dependencies.
- Architecture, action items, and README agree on MVP scope.

## Phase 1: Main UX And State Machine

Goal: replace the placeholder shell with the first usable app surface.

Status, 2026-06-16: implemented for the main UX flow and now connected to real AdMob placements. The Home screen is componentized and can run File, folder, and selected Photos flows through inspecting, storage checking, progress with ETA, cancellation, rewarded-save waiting, pending-save recovery, and completed states. Real file-based, folder-based, and selected Photos AV1 encoding paths are implemented; additional ad/privacy hardening remains later-phase work.

Scope:

- Build the main screen:
  - AdMob top and bottom banner containers
  - `Taption Encoder`
  - `AV1 to H.265`
  - `File`
  - `Folder`
  - `Photos`
  - `Reset`
  - automatic codec-path info display
  - H.265 output summary
  - status, progress, ETA, and cancel area
- Implement `HomeScreenState`.
- Add File picker, Folder picker, and Photos picker entry points behind source protocols.
- Add fake encoding flow for UI testing and real AV1 source flows for device proof.
- Add progress bar, percent, elapsed time, and estimated time remaining placeholders.
- Add cancellation state and failed/completed state shells.
- Keep ads visually separated from primary controls.

Deliverables:

- `HomeView`
- `HomeViewModel`
- `HomeScreenState`
- `EncodingProgressView`
- `EncoderModePicker`
- `OutputSummaryView`
- Fake encoder and fake ad gate for simulator flows

Exit criteria:

- iPhone portrait layout works.
- iPad portrait layout uses the same mobile-width UX.
- File, Folder, and Photos buttons enter the expected source-selection flows.
- Fake encoding can progress, cancel, fail, and complete.
- GoogleMobileAds is integrated; Debug builds use Google test ad unit IDs before extended ad QA.

## Phase 2: AV1 To H.265 Core

Status, 2026-06-16: partially implemented for the first AV1 path. The app now uses AVFoundation media inspection, AV1-only validation, AVFoundation HEVC export, automatic software AV1 decode fallback through SwiftVLC/libVLC, VideoToolbox hardware encoder capability reporting, real export/fallback progress, sequential folder processing for common video file extensions, selected Photos import, Photos output save, cancellation cleanup, storage checks, security-scoped file/folder access, AdMob rewarded save, `_taption.mp4` final copy after the save gate, and bundled Vorbis-to-AAC / MP4 audio preservation for the current real WebM software route. Durable pending-save restoration hardening, broader software fallback audio preservation, consent UI, and broad software codec integration remain open.

Status, 2026-06-16 update: broad codec planning now has a concrete research and fixture base in `docs/CODEC_SUPPORT_RESEARCH.md`, `docs/VIDEO_CODEC_FIXTURES.md`, `docs/AUDIO_CODEC_FIXTURES.md`, `docs/HEVC_TRANSCODE_TEST_RESULTS.md`, `docs/DEVICE_CODEC_ROUTE_SIMULATION.md`, `Scripts/generate_video_codec_fixtures.sh`, `Scripts/generate_audio_codec_fixtures.sh`, `Scripts/transcode_fixtures_to_hevc.sh`, `Scripts/verify_codec_fixture_evidence.sh`, `Scripts/simulate_codec_route_planner.sh`, `HW_CodecCapabilityProbe.swift`, `SW_CodecSupportCatalog.swift`, `SW_SoftwareCodecBackendRegistry.swift`, `CodecRoutePlanner.swift`, `TaptionCodecTranscodingRegistry.swift`, `CodecFixtureEvidence.swift`, and the `TaptionEncoderTests` Xcode test target. The local host-side smoke gate converted 90 synthetic input fixtures through both `SW_HEVC` and `HW_HEVC`, for 180/180 passing H.265 outputs; 166 attempts preserve measured audio signal, and 14 no-source-audio attempts are explicitly recorded. The fixture set now includes representative container/raw aliases and lossless/intermediate codecs such as DivX, M2TS/TP/TRP/TOD, DAT/MOD/VOB, QT, F4V, OGM, DVR-MS, NUT, RoQ, RealMedia, FFV1, HuffYUV/FFVHuff, Ut Video, MagicYUV, GoPro CineForm, DNxHD/DNxHR, PNG video, R10k, V210, Microsoft RLE, QuickTime Graphics, V308, V408, YUV4, AV1 OBU, H.263, rawvideo Y4M, M1V, and M2V; VC-1 remains a real-world or alternate-generator target because the current local FFmpeg build has no VC-1 encoder. The fixture evidence verifier now enforces that every generated fixture has both SW and HW H.265 PASS rows with output audio signal preserved when the source has audio. `CodecFixtureEvidenceTests` now runs the same evidence check inside the app scheme by parsing both the video smoke TSV and audio-focused smoke TSV from Swift; it also parses the generated video smoke manifest and compares it with `SW_CodecSupportCatalog.fixtureTargets`, so the video sample set stays tied to the software codec roadmap. The same tests build source-preserving H.265/MP4 command plans and gated FFmpeg-family execution jobs for every generated video fixture row, match those jobs against the latest SW/HW H.265 and audio-signal evidence rows, and preserve source-derived size, frame rate, bitrate, audio-to-AAC decisions, and no-audio elementary streams. The audio-focused smoke gate generated 30 audio codec fixtures and converted them through both SW/HW H.265 paths for 60/60 passing outputs with measured audio signal present; the app-scheme fixture evidence tests also parse the audio generation TSV, build AAC/MP4 app-core audio route plans, FFmpeg-family software fallback command plans, and gated execution jobs for every generated audio fixture row, match those jobs against the latest SW/HW H.265 and audio-signal evidence rows, and preserve sample rate, channel count, and source bitrate options so generated codec coverage and pending xHE-AAC, AMR-NB, and AMR-WB generator attempts stay explicit. The route simulator now emits 444,529 TSV lines across 112 generic, Apple family, and model-identifier capability profiles, covers 63x63 source/output codec pairs per profile, and verifies HW-first, HW/SW mixed, SW fallback, and hardware-only route availability behavior for `AV1 -> H.265`, `H.264 -> H.265`, `H.265 -> H.265`, and `ProRes -> H.265`; app-scheme evidence tests also parse the generated route matrix TSV to prove profile coverage, universal route coverage, implemented/planned row counts, and per-side HW decode/encode backend preference. The live H.265 encoder routes now dispatch through a codec registry, with AV1 HW/SW algorithms and Apple-native H.264/H.265/ProRes HW algorithms registered as route implementations and covered by unit tests. The broad SW backend registry now models future software video/audio decode, video/audio encode, and container read/write coverage for all-to-all route planning; `SW_UniversalCodecTranscodeAlgorithm` now adds planned software descriptors for every non-implemented universal route while returning a clear not-bundled error until the broad backend ships. Audio conversion now has `AudioCodecAlgorithm.swift` plus `SW_UniversalAudioCodecTranscodeAlgorithm.swift`, so every universal audio source/output pair has a function-style planned software descriptor and a clear not-bundled execution error until the broad backend ships. The Xcode route planner tests verify the same HW/SW priority behavior inside the app scheme, selected output policy preservation for the generic plan model, and symmetric all-to-all route coverage so pairs such as `H.264 -> AV1` and `AV1 -> H.264` remain first-class planned routes. `TaptionUniversalCodecCompletionAuditor` now turns that final all-to-all target into a single core audit stage: current builds are planning-locked for the universal mesh, but command-plan gaps, software-backend gates, and runtime gaps still block full universal execution. The app now reports per-file planned codec paths as `HW`, `SW`, `HW/SW`, `Planned`, or `Unsupported`; the Home screen exposes output codec/container selectors for the all-to-all roadmap, while current-build video execution is limited to H.265 output with AV1 HW/SW fallback and Apple-native H.264/H.265/ProRes HW routes where the device supports them. Actual bundled broad-codec execution, broad software fallback beyond AV1, and all-to-all conversion algorithms remain implementation work.

Goal: complete the first real conversion path.

Scope:

- Port or rewrite only the narrow AV1 detection and H.265 conversion pieces needed for standalone file-in/file-out.
- Inspect codec metadata, not only extension.
- Detect AV1 input.
- Preserve source-like defaults:
  - resolution
  - frame rate
  - orientation
  - aspect ratio
  - SDR/HDR mode where supported
  - color primaries
  - transfer function
  - color matrix
  - audio timing
- Implement hardware H.265 encode path.
- Implement automatic software fallback paths for unsupported native decode/encode cases.
- Surface actual path:
  - `Hardware Encoder`
  - `Software Encoder`
  - `Mixed Codec Path`
- Implement source-derived quality policy.
- Implement storage checks before encoding and final save.
- Write to temporary output before final save.
- Implement `_taption` naming policy.
- Persist completed temporary outputs when rewarded save cannot finish.
- Restore pending-save jobs on launch so users can retry saving without re-encoding.
- Clean temporary output on cancellation and failure.

Deliverables:

- `MediaInspector`
- `AVFoundationMediaInspector`
- `EncodingJob`
- `EncodingOptions`
- `EncoderService`
- `EncoderPipeline`
- `SourcePreservationPolicy`
- `StorageChecking`
- `OutputNamingPolicy`
- Hardware/software capability checks

Exit criteria:

- Real AV1 sample can encode to H.265 on a device or a documented simulator-compatible fake path.
- Progress reports from the encoder pipeline.
- Cancellation leaves no broken final file.
- Insufficient storage blocks before output.
- Output naming appends `_taption`.

## Phase 3: Monetized 1.0 Launch

Goal: ship the first public version: free AV1 to H.265 with ads.

Scope:

- Integrate Google Mobile Ads SDK.
- Add User Messaging Platform consent if required.
- Use test ad units in Debug builds.
- Prevent production ad IDs in Debug builds.
- Add top and bottom banner placements.
- Add rewarded ad gate before final save.
- Use non-personalized ad requests initially.
- Add app-open, start interstitial, session-end interstitial, and native ad providers behind protocols, with conservative placement switches.
- Add App Store privacy answers for ads, analytics, diagnostics, and tracking.
- Add production AdMob IDs and `app-ads.txt`, privacy policy URL, and support URL through the existing account/site setup.
- Add Live Activity progress where supported.
- Add iOS/iPadOS 26 background encoding option.
- Add iOS/iPadOS 18-25 keep-app-open messaging.
- Add TestFlight and device proof checklist.
- Prepare App Store metadata, screenshots, review notes, and release build.

Deliverables:

- AdMob configuration layer
- Banner provider
- Rewarded save gate
- Consent flow
- Release configuration
- TestFlight build
- App Store release metadata

Exit criteria:

- Rewarded ad completion is required before final save.
- If rewarded ad is unavailable, user can retry now, keep the temporary output for later, or cancel the pending save.
- Relaunching the app restores the pending save state without re-encoding.
- No full-screen ads appear during active encoding, picker presentation, or cancellation.
- Real device smoke test passes.
- App Review submission is ready.
- Version 1.0 is shipped or ready to submit.

## Phase 4: Post-Launch Stabilization And Legacy Software Proof

Goal: make the launched app reliable, especially on old devices.

Scope:

- Maintain iOS/iPadOS 18.0 deployment target for the current SwiftVLC software fallback, or rebuild the software codec stack for a lower deployment target before promising older OS support.
- Build a legacy-device capability matrix.
- Test software encoding on older supported iPhones and iPads.
- Add runtime warnings for slow software encoding.
- Add thermal, battery, memory, and estimated runtime warnings.
- Add ETA smoothing based on processed media duration.
- Add job history for the current session.
- Add remote-configurable ad placement switches and frequency caps.
- Add crash/error diagnostics.
- Tune storage estimation.
- Tune rewarded-save retry/cancel behavior.

Device classes to prove:

- A9/A10 class: supported but slow software mode.
- A11 class: slow/medium software mode.
- A12 and newer: recommended baseline for practical AV1 software work.
- iOS/iPadOS 26 or later: background encoding option.

Exit criteria:

- Old-device behavior is honest and documented.
- Slow devices show clear warnings before long work.
- Software path succeeds or fails with clear English copy.
- Ad frequency can be tuned without a binary update.
- Version 1.1 stabilization release is ready.

## Phase 5: Broad Input Engine

Goal: move from AV1-only toward broad input support. The first milestone is "All to H.265"; the final architecture must support all-to-all codec routes.

Research baseline:

- Use `docs/CODEC_SUPPORT_RESEARCH.md` as the current codec/container/audio target list.
- Use `Scripts/generate_video_codec_fixtures.sh` for synthetic samples with audio.
- Use `Scripts/generate_audio_codec_fixtures.sh` for audio-family-specific samples.
- Use `Scripts/transcode_fixtures_to_hevc.sh` for repeatable SW/HW H.265 fixture conversion tests.
- Use `Scripts/simulate_codec_route_planner.sh` for repeatable HW/SW priority checks across capability profiles.
- Use `xcodebuild test -scheme TaptionEncoder` for app-scheme codec route planner unit tests.
- Use `HW_CodecCapabilityProbe` for runtime device hardware support reporting.
- Use `SW_CodecSupportCatalog` for software fallback and fixture coverage tracking.

Scope:

- Add broad input inspection for:
  - H.264 / AVC
  - H.265 / HEVC
  - VP9
  - VP8
  - MPEG-2 Video
  - ProRes
  - unknown software-codec-supported codecs
- Add broad container inspection for:
  - MP4
  - MOV
  - M4V
  - WebM
  - MKV
  - AVI / DivX
  - TS / MTS / M2TS / TP / TRP / TOD
  - MPEG-PS / VOB / MOD
  - MXF
  - OGM, DVR-MS, and raw elementary stream aliases
- Add software codec backend behind protocols.
- Evaluate FFmpeg-family software codec options and pull broad support as far as App Store, licensing, binary-size, and performance limits allow.
- Accept a larger app binary when broad codec support justifies it and review constraints are satisfied.
- Complete license and binary-size review.
- Add mixed decode/encode path reporting.
- Add unsupported-input explanations.
- Keep output H.265 for this milestone while route modeling already supports future selectable output codecs.
- Keep the final universal contract as a symmetric all-to-all codec mesh, so `H.264 -> AV1`, `AV1 -> H.264`, and same-codec re-encode routes remain first-class planned routes.
- Preserve source-like defaults for broad-format inputs.

Deliverables:

- `SoftwareCodecMediaInspector`
- `SoftwareCodecDecoder`
- `SoftwareCodecHEVCEncoder`
- `CodecCapability`
- `CodecExecutionMode`
- License notice and review notes

Exit criteria:

- Each target codec/container has an inspection result.
- Apple-native path is preferred when possible.
- Software path is used for unsupported Apple-native inputs.
- Mixed path is visible to the user.
- Version 1.2 or 1.3 broad-input release is ready.

## Phase 6: Native FCPXML Project And Merge Planning

Goal: introduce project files and merge planning without yet becoming a full editor.

Scope:

- Use `.fcpxml` as the native project save format.
- Choose and pin FCPXML DTD/version.
- Use the latest stable official FCPXML DTD/version available at implementation time.
- Add FCPXML serializer/parser behind project protocols.
- Add FCPXML validation tests.
- Add project create/open/save flow.
- Add media asset references.
- Add `EncoderProject`.
- Add `VideoSegmentTimeline`.
- Add `VideoSegment`.
- Add merge compatibility inspection.
- Add output canvas resolver.
- Add normalization option generation:
  - output canvas/resolution
  - frame rate
  - color handling
  - audio layout
  - orientation handling
- Add close-enough auto-selection rules.

Deliverables:

- `EncoderProject`
- `ProjectDocument`
- `FCPXMLProjectSerializer`
- `FCPXMLProjectParser`
- `FCPXMLDTDValidator`
- `VideoSegment`
- `VideoSegmentTimeline`
- `MergeCompatibilityInspector`
- `MergeNormalizationPlan`

Exit criteria:

- A project can save and reopen as `.fcpxml`.
- Generated FCPXML validates against the selected DTD/version.
- Merge inputs produce user-selectable normalization options when needed.
- Effectively equivalent values auto-select the closest recommended value.
- Version 1.4 project-planning release is ready.

## Phase 7: Merge Export And Lightweight Video Editing

Goal: let users combine and lightly edit multiple videos into one H.265 output.

Scope:

- Add multi-file selection.
- Add segment-based timeline UI.
- Adapt Taption interaction ideas into Encoder-specific video controls:
  - touch widget controls
  - slice/split interactions
  - video segment ownership
  - preview and commit alignment
- Add edit tools:
  - trim
  - cut
  - split
  - shorten
  - reorder
  - canvas position / fit / fill / center
- Add merge normalization execution.
- Add merge encoding pipeline to one H.265 output.
- Reuse storage, progress, ETA, cancellation, background, and rewarded-save gates.
- Add future `.fcpxmld` bundle support for thumbnails, proxies, and richer metadata after single `.fcpxml` is stable.
- Add managed `.fcpxmld` mode that can copy original media when the user chooses it.

Deliverables:

- `MergeEditorView`
- `VideoSegmentTimelineView`
- `SegmentTouchWidgetView`
- `SliceSplitControl`
- `TimelineEditOperation`
- `SegmentEditOwnership`
- `SplitVideoSegmentOperation`
- `MergeEncodingPipeline`
- `.fcpxmld` bundle plan and first implementation if stable

Exit criteria:

- Multiple videos can merge into one H.265 output.
- User can trim, cut, split, shorten, reorder, and position clips.
- Touch preview and committed edit match.
- FCPXML project reopens with the same timeline.
- Version 1.5 or 2.0 merge/edit release is ready.

## Phase 8: Advanced Controls And Final Product Completion

Goal: complete the final product direction without losing the simple default flow.

Scope:

- Add output codec and output container selectors for the universal all-to-all route matrix.
- Keep H.265 as the recommended default output while allowing supported routes such as H.264 to AV1, AV1 to H.264, VP9 to H.265, and same-codec re-encode.
- Add resolution controls.
- Add frame-rate controls.
- Add bitrate controls.
- Add quality controls.
- Add color-map, tone-map, and HDR/SDR controls.
- Add batch conversion.
- Add per-file presets.
- Add multi-camera merge presets.
- Add format-specific compatibility warnings.
- Add optional compression-first presets.
- Add performance optimization for long jobs.
- Add final App Store metadata refresh and screenshots for advanced features.

Exit criteria:

- The default path remains simple and source-preserving.
- Output selection supports every executable source/output codec pair in the universal matrix, with unavailable pairs shown honestly as planned or blocked.
- Advanced users can intentionally change output size, frame rate, bitrate, quality, and color handling.
- Broad input support is stable enough to market as "All to H.265" within honest compatibility limits.
- Codec routing is generic enough to add routes such as H.264 to AV1, AV1 to H.264, VP9 to H.265, and same-codec re-encode without rewriting the core plan model.
- Old-device software support is documented and verified.
- Project, merge, and edit workflows are stable.
- Final completion release is ready.

## Cross-Phase Workstreams

Testing:

- Unit tests for pure domain logic.
- Fake encoder tests for simulator.
- Device tests for codec and performance proof.
- Real old-device software encoding proof.
- FCPXML round-trip and validation tests.

Ads:

- Debug test ads only during development.
- Production IDs only in release configuration.
- Initial ad requests are non-personalized.
- Rewarded save gate stays required.
- Full-screen ads only at natural pauses.
- Remote placement switches and frequency caps after launch.

Privacy and App Store:

- Privacy policy.
- Support URL.
- `app-ads.txt`.
- App Store privacy nutrition labels.
- ATT copy only if personalized ads or cross-app tracking are introduced later.
- Review notes explaining rewarded save.

Performance:

- Storage estimates before encode and final save.
- Thermal and battery warnings for software mode.
- Runtime estimates for long jobs.
- Capability matrix by device generation.

Documentation:

- Keep `README.md`, `docs/APP_ARCHITECTURE.md`, `docs/ACTION_ITEMS.md`, and this plan aligned.
- Do not mark a phase complete until docs and action items match the implementation.

## Immediate Next Sprint

Recommended next sprint scope:

- Keep iOS/iPadOS 18.0 deployment target for the current SwiftVLC fallback, and track any lower-OS codec build needed for older devices.
- Use `Reset` instead of `Exit`.
- Create module folders.
- Add `AppEnvironment`.
- Add protocol shells for encoder, media inspection, storage, ads, and background.
- Replace placeholder main screen with the real Phase 1 UI.
- Add fake encoding flow with progress, ETA, cancel, completed, failed, and rewarded-save placeholder states.
- Verify iPhone and iPad portrait simulator layouts.
