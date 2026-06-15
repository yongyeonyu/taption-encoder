# Taption Encoder Detailed Development Plan

Status date: 2026-06-15

## Purpose

This document is the implementation-level plan for building Taption Encoder from the current standalone shell into the completed product direction.

The product path is:

- First release: AV1 to H.265.
- Final product: All practical user video inputs to H.265.
- Business model: free app supported by ads.
- Core value: easy phone-based encoding, old-device software encoding support, source-like output defaults, and later multi-video merge/edit workflows.

This plan is more detailed than `docs/DEVELOPMENT_PLAN.md`. Use this document as the phase-by-phase engineering execution guide.

## Global Product Rules

- Minimum OS is iOS/iPadOS 18.0 for the current SwiftVLC software fallback binary.
- iPhone and iPad are portrait-only.
- iPad uses the same centered, mobile-width UX as iPhone.
- Visible app strings must be English.
- The app remains separate from `/Users/u_mo_c/Documents/taption`.
- Main Taption editor code must not be imported unless a file is intentionally ported.
- MVP input is AV1 video.
- MVP output is H.265 video in an `.mp4` container.
- Long-term output remains H.265 video.
- Advanced "format" settings mean H.265 container selection, such as `.mp4` and `.mov`, not non-H.265 output codecs.
- Default quality policy is source-like visual preservation, not smallest file size.
- Hardware encoder is recommended.
- Software encoder remains a first-class option for unsupported hardware, old devices, broad input, and simulator validation.
- Initial ads are non-personalized.
- Rewarded ad gates final save.
- If rewarded save cannot finish, completed temporary output must be preserved and restored later so the user can retry without re-encoding.
- Photos output saves as a new Photos asset.
- FCPXML is the native project save format for merge/edit projects.
- Future `.fcpxmld` bundles may include thumbnails, proxies, richer metadata, and user-selected managed copies of original media.

## Phase Overview

| Phase | Name | Release Intent | Main Result |
| --- | --- | --- | --- |
| 0 | Foundation Lock | Pre-implementation | Correct project settings, architecture skeleton, and policy alignment |
| 1 | Main UX And State Machine | Pre-MVP | Real main UI with fake services and testable states |
| 2 | AV1 To H.265 Core | MVP core | Real AV1 inspection and H.265 encode pipeline |
| 3 | Monetized 1.0 Launch | Version 1.0 | Ad-supported AV1 to H.265 app ready for App Store |
| 4 | Stabilization And Legacy Proof | Version 1.1 | Old-device software proof, warnings, telemetry, recovery |
| 5 | Broad Input Engine | Version 1.2/1.3 | Expanded codec/container input coverage |
| 6 | FCPXML Project Planning | Version 1.4 | Native `.fcpxml` projects and merge planning |
| 7 | Merge Export And Lightweight Editing | Version 1.5/2.0 | Multi-video merge and segment editing |
| 8 | Advanced Controls And Completion | Final product direction | Advanced output controls, batch, presets, final polish |

## Shared Architecture

### Source Tree Target

```text
TaptionEncoder/
  App/
    TaptionEncoderApp.swift
    AppEnvironment.swift
    FeatureFlags.swift
    AppConfiguration.swift

  Features/
    Home/
    Encoding/
    PendingSave/
    MergeEditor/
    Project/
    Settings/

  Core/
    Encoding/
    MediaInspection/
    FileAccess/
    Storage/
    Ads/
    Background/
    PendingSave/
    Project/
    Merge/
    Editing/

  Infrastructure/
    AVFoundation/
    VideoToolbox/
    SoftwareCodecs/
    FileSystem/
    Photos/
    AdMob/
    BackgroundTasks/
    ActivityKit/
    FCPXML/

  Shared/
    UI/
    Utilities/
```

### Dependency Rule

```text
SwiftUI Views -> ViewModels -> Use Cases -> Core Protocols -> Infrastructure
```

Rules:

- SwiftUI views do not inspect codecs.
- SwiftUI views do not directly call AdMob.
- SwiftUI views do not directly move files.
- Encoder logic does not know about ad SDK classes.
- Ad gate does not know how encoding works.
- Storage checks and output naming are pure and testable.
- FCPXML parse/write is hidden behind project protocols.
- Software codec implementation is hidden behind backend protocols.

### Required Fake Services

These fake services should exist before real integrations become complex:

- `FakeEncoderService`
- `FakeMediaInspector`
- `FakeStorageChecker`
- `FakeAdGate`
- `FakeBannerAdProvider`
- `FakeRewardedAdProvider`
- `FakeBackgroundEncodingCoordinator`
- `FakePendingSaveStore`
- `FakeProjectFileStore`
- `FakeFCPXMLValidator`

## Phase 0: Foundation Lock

Implementation status, 2026-06-15: completed for the foundation scope. The app has the Phase 0 source tree, `AppEnvironment`, feature flags, protocol shells, fake services, and Home screen shell. Real AV1 inspection, H.265 encoding, AdMob, Photos import, and final-save execution remain later-phase work.

### Objective

Make the repository safe for implementation and lock the non-negotiable technical policies.

### Product Scope

- No real encoding yet.
- No real AdMob yet.
- No merge/editor UI yet.
- The app should compile as an iOS/iPadOS 18.0+ portrait app.
- The app should have the correct project policy documented and visible to future agents.

### Engineering Tasks

Project configuration:

- Keep `IPHONEOS_DEPLOYMENT_TARGET = 15.0`.
- Keep `TARGETED_DEVICE_FAMILY = "1,2"`.
- Keep portrait-only orientation for iPhone and iPad.
- Keep `UIRequiresFullScreen = YES`.
- Keep bundle id `com.taption.encoder`.
- Keep scheme `TaptionEncoder`.

Repository rules:

- Keep `AGENTS.md` updated.
- Keep polite/formal Korean collaboration rules in `AGENTS.md`.
- Keep visible app strings in English.
- Keep Taption source reference paths documented.
- Do not edit `/Users/u_mo_c/Documents/taption` from this project.

Code skeleton:

- Create `AppEnvironment`.
- Create feature flag container.
- Create protocol directories.
- Move placeholder `ContentView` toward `Features/Home`.
- Keep APIs compatible with the declared iOS/iPadOS 18.0 deployment target.
- Avoid `NavigationStack` until a version-gated replacement is intentionally added.

Architecture protocols:

- `MediaInspecting`
- `EncoderServicing`
- `StorageChecking`
- `SourceOpening`
- `OutputResolving`
- `PendingSaveStoring`
- `AdGate`
- `BannerAdProviding`
- `RewardedAdProviding`
- `BackgroundEncodingCoordinating`
- `ProjectDocumentStoring`

Documentation:

- Keep `README.md`, `APP_ARCHITECTURE.md`, `DEVELOPMENT_PLAN.md`, `DETAILED_DEVELOPMENT_PLAN.md`, and `ACTION_ITEMS.md` aligned.
- Move confirmed decisions from `P0 Decisions Needed` to `Confirmed Product Policies`.

### Files To Create Or Move

- `TaptionEncoder/App/AppEnvironment.swift`
- `TaptionEncoder/App/FeatureFlags.swift`
- `TaptionEncoder/App/AppConfiguration.swift`
- `TaptionEncoder/Features/Home/HomeView.swift`
- `TaptionEncoder/Features/Home/HomeViewModel.swift`
- `TaptionEncoder/Features/Home/HomeScreenState.swift`
- `TaptionEncoder/Core/Encoding/EncoderService.swift`
- `TaptionEncoder/Core/MediaInspection/MediaInspector.swift`
- `TaptionEncoder/Core/Storage/StorageChecking.swift`
- `TaptionEncoder/Core/Ads/AdGate.swift`
- `TaptionEncoder/Core/PendingSave/PendingSaveStore.swift`

### Tests

- Build test on iPhone simulator.
- Build test on iPad simulator.
- Static search for APIs above iOS/iPadOS 18.0 unless they are feature-gated.
- Static search for direct `GoogleMobileAds` imports outside infrastructure once ads are added.

### Exit Criteria

- iPhone simulator build succeeds.
- iPad simulator build succeeds.
- The project target is iOS/iPadOS 18.0.
- No UI string violates English-visible-string rule.
- Architecture skeleton compiles.
- Documents agree on Phase 0 decisions.

### Risks

- Xcode templates may add iOS 16+ APIs silently.
- Future agents may accidentally import Taption editor files.
- AdMob SDK integration may later force deployment target constraints; verify before integration.

## Phase 1: Main UX And State Machine

Implementation status, 2026-06-15: completed for fake UX/state-machine scope. The app has componentized Home UI, automatic codec-path info, output summary, progress display, pending-save recovery view, fake progress/ETA, cancellation, reset, rewarded-save waiting, and completed state surfaces. Real AV1 inspection, real H.265 conversion, real Photos import, real AdMob, and final save execution remain later-phase work.

### Objective

Build the real main screen and state machine using fake services so UX, progress, reset, and pending-save behavior are testable before real encoding.

### Product Scope

Main screen top-to-bottom:

- Top banner ad container.
- App title: `Taption Encoder`.
- Subtitle: `AV1 to H.265`.
- Source buttons:
  - `Files`
  - `Photos`
  - `Reset`
- Codec path info:
  - `Codec Path: Automatic`
  - `Hardware is used where supported. Software fallback is automatic.`
- Output summary:
  - `Output`
  - `H.265`
  - `.mp4`
- Status/progress area:
  - selected filename
  - backend label
  - progress bar
  - percentage
  - elapsed time
  - estimated time remaining
  - cancel button
- Pending save recovery area if a completed temporary output exists.

### Home States

```swift
enum HomeScreenState: Equatable {
    case idle
    case importing
    case inspecting
    case storageBlocked(StorageIssue)
    case encoding(EncodingProgress)
    case cancelling
    case waitingForReward(CompletedTemporaryOutput)
    case pendingSave(PendingSaveJob)
    case saving
    case completed(SavedOutput)
    case failed(EncodingError)
    case cancelled
}
```

### User Flows

Files flow:

```text
Idle -> Files -> fileImporter -> Inspecting -> StorageCheck -> Encoding -> WaitingForReward -> Saving -> Completed
```

Photos flow:

```text
Idle -> Photos -> PhotosPicker -> Importing -> Inspecting -> StorageCheck -> Encoding -> WaitingForReward -> SavingPhotosAsset -> Completed
```

Reward failure flow:

```text
EncodingCompleted -> WaitingForReward -> RewardUnavailable -> PendingSave -> Relaunch -> PendingSave -> RetryReward -> Saving
```

Reset flow:

```text
Any non-encoding state -> Reset -> Idle
Encoding state -> Reset disabled or asks to cancel first
PendingSave state -> Reset asks whether to keep or discard pending output
```

### Engineering Tasks

UI:

- Build responsive mobile-width layout.
- Keep iPad centered at approximately 420 points.
- Add stable dimensions for buttons and progress area.
- Keep ad container visually separated from primary actions.
- Add disabled states for source buttons while encoding.
- Add reset behavior.
- Add pending save recovery banner.

View model:

- Use dependency injection from `AppEnvironment`.
- Own `HomeScreenState`.
- Start fake encoding after successful fake inspection.
- Generate fake progress samples.
- Generate ETA after enough progress samples.
- Persist fake pending save jobs through `FakePendingSaveStore`.

Fake services:

- Fake file source.
- Fake Photos source.
- Fake media inspector.
- Fake encoder.
- Fake ad gate.
- Fake pending save store.
- Fake storage checker.

### Files To Create

- `Features/Home/HomeView.swift`
- `Features/Home/HomeViewModel.swift`
- `Features/Home/HomeScreenState.swift`
- `Features/Home/SourceActionBar.swift`
- `Features/Encoding/EncodingProgressView.swift`
- `Features/Encoding/EncoderModePicker.swift`
- `Features/Encoding/OutputSummaryView.swift`
- `Features/PendingSave/PendingSaveRecoveryView.swift`
- `Shared/UI/PrimaryActionButton.swift`
- `Shared/UI/StatusBanner.swift`
- `Shared/UI/ProgressCard.swift`

### Tests

Unit tests:

- `HomeScreenStateTests`
- `HomeViewModelStateTransitionTests`
- `EncodingProgressEstimatorTests`
- `PendingSaveRecoveryStateTests`
- `ResetBehaviorTests`

Simulator tests:

- iPhone portrait layout.
- iPad portrait layout.
- Files button enters fake flow.
- Photos button enters fake flow.
- Fake progress reaches waiting-for-reward.
- Cancel stops fake encoding.
- Reset clears idle/completed/failed state.
- Pending save appears after fake reward failure.
- Relaunch restores fake pending save.

### Exit Criteria

- Main UI no longer looks like placeholder.
- Files, Photos, Reset, Hardware, Software, H.265 output, progress, ETA, cancel, and pending-save surfaces exist.
- Fake flows pass.
- No real encoder dependency is required.
- No real AdMob dependency is required.

### Risks

- UI may become too much like a full editor too early.
- Pending save recovery can confuse users if copy is unclear.
- Reset must not accidentally delete completed temporary output without user confirmation.

## Phase 2: AV1 To H.265 Core

Implementation status, 2026-06-15: partially implemented for the first Files-based AV1 path. AVFoundation inspection, AV1 codec validation, AVFoundation HEVC export, automatic SwiftVLC/libVLC software AV1 decode fallback, VideoToolbox hardware capability reporting, real progress/ETA, cancellation cleanup, storage checks, security-scoped Files access, and `_taption.mp4` final save after the save gate are in place. Photos import/save, durable pending-save restoration, AdMob, software fallback audio preservation, and broad software codec fallback remain open.

### Objective

Implement the real single-file AV1 to H.265 encoding path with source-like defaults, storage safety, progress, cancellation, and pending save support.

### Product Scope

- Input: AV1 video.
- Output: H.265 video in `.mp4`.
- Sources: Files and Photos.
- Default preservation:
  - resolution
  - frame rate
  - orientation
  - aspect ratio
  - SDR/HDR mode where supported
  - color primaries
  - transfer function
  - YCbCr matrix
  - audio timing
  - source-like visual quality
- Codec paths:
  - Hardware Codec Path
  - Software Codec Path
  - Mixed Codec Path

### Domain Models

```swift
struct EncodingJob: Equatable, Identifiable {
    var id: UUID
    var source: SourcePickerResult
    var metadata: MediaMetadata
    var options: EncodingOptions
    var destination: OutputDestination
}

struct EncodingOptions: Equatable {
    var backend: EncoderBackend
    var outputCodec: OutputCodec
    var outputContainer: OutputContainer
    var preservation: SourcePreservationPolicy
    var resolution: ResolutionOption?
    var frameRate: FrameRateOption?
    var quality: QualityOption?
    var bitrate: BitrateOption?
    var colorMapping: ColorMappingPolicy?
}

struct EncodingProgress: Equatable {
    var fractionCompleted: Double
    var processedDuration: TimeInterval
    var totalDuration: TimeInterval?
    var elapsedTime: TimeInterval
    var estimatedTimeRemaining: TimeInterval?
    var currentSpeed: Double?
    var backend: EncoderBackend
    var phase: EncodingPhase
}
```

### Engineering Tasks

Media inspection:

- Inspect AVAsset tracks.
- Detect codec by metadata, not extension.
- Detect container.
- Read duration.
- Read natural size.
- Read preferred transform.
- Read nominal frame rate.
- Read color metadata when available.
- Read audio tracks.
- Produce user-facing unsupported errors.

Files:

- Use security-scoped access.
- Keep access alive during inspection and encode.
- Resolve sibling destination.
- Apply `_taption` naming.
- Use app temp directory for intermediate output.
- Move/copy to final destination only after reward.

Photos:

- Use Photos picker.
- Export selected original to app temporary input.
- Encode to app temporary output.
- Save new Photos asset after reward.
- Preserve `_taption` local filename where possible.

Encoding:

- Build AVFoundation reader/writer path.
- Use VideoToolbox capability checks for hardware HEVC.
- Add software encoder abstraction.
- Add software implementation or temporary explicit fallback policy.
- Preserve source-like options.
- Report progress from processed sample duration.
- Support cancellation.
- Clean temp files on cancellation.
- Keep completed temp files on reward failure.

Pending save:

- Create `PendingSaveJob`.
- Persist output temp URL, source summary, created date, file size, destination kind, and save intent.
- Validate temp file still exists on launch.
- Restore `pendingSave` home state.
- Let user retry reward/save.
- Let user delete pending output.

Storage:

- Estimate input/output/temp space.
- Check before encoding.
- Check before final save.
- Use conservative estimate.
- Show clear English copy when blocked.

### Files To Create

- `Core/Encoding/EncodingJob.swift`
- `Core/Encoding/EncodingOptions.swift`
- `Core/Encoding/EncodingProgress.swift`
- `Core/Encoding/EncodingPhase.swift`
- `Core/Encoding/EncoderBackend.swift`
- `Core/Encoding/EncoderPipeline.swift`
- `Core/Encoding/SourcePreservationPolicy.swift`
- `Core/MediaInspection/MediaMetadata.swift`
- `Core/MediaInspection/InputCodec.swift`
- `Core/MediaInspection/InputContainer.swift`
- `Core/FileAccess/SourcePickerResult.swift`
- `Core/FileAccess/OutputNamingPolicy.swift`
- `Core/FileAccess/DestinationResolver.swift`
- `Core/PendingSave/PendingSaveJob.swift`
- `Core/PendingSave/PendingSaveStore.swift`
- `Infrastructure/AVFoundation/AVFoundationMediaInspector.swift`
- `Infrastructure/AVFoundation/AVAssetReaderDecoder.swift`
- `Infrastructure/AVFoundation/AVAssetWriterHEVCEncoder.swift`
- `Infrastructure/VideoToolbox/VideoToolboxHardwareCapabilities.swift`
- `Infrastructure/Photos/PhotosSourceLoader.swift`
- `Infrastructure/Photos/PhotosOutputSaver.swift`

### Tests

Unit tests:

- `MediaInspectionTests`
- `OutputNamingPolicyTests`
- `DestinationResolverTests`
- `SourcePreservationPolicyTests`
- `StorageCheckingTests`
- `EncodingProgressEstimatorTests`
- `PendingSaveStoreTests`
- `EncoderBackendPolicyTests`

Device tests:

- AV1 sample detection.
- H.265 output playback.
- Hardware encoder success where supported.
- Software encoder behavior or documented fallback.
- Source resolution preservation.
- Orientation preservation.
- Frame rate preservation where possible.
- Color metadata preservation where possible.
- Audio timing preservation.
- Cancellation cleanup.
- Reward failure pending output restoration.

### Exit Criteria

- A real supported AV1 file encodes to H.265 `.mp4`.
- Files output uses `_taption`.
- Photos output creates a new asset.
- Progress and ETA update.
- Cancellation works.
- Insufficient storage blocks safely.
- Pending save survives relaunch.
- Hardware/software/mixed path is visible.

### Risks

- AV1 decode support may require software decoder path earlier than planned.
- Hardware HEVC options can vary by device.
- HDR/color metadata preservation may be partial.
- Long software encodes on old devices may overheat or be too slow.

## Phase 3: Monetized 1.0 Launch

### Objective

Ship the first App Store-ready product: free AV1 to H.265 conversion with non-personalized AdMob placements and rewarded save.

### Product Scope

- AV1 to H.265 `.mp4`.
- Automatic hardware/software codec path with info-only display.
- Files and Photos inputs.
- Progress, ETA, cancel, reset.
- Pending save recovery.
- Non-personalized ads.
- Rewarded save gate.
- iOS 26+ background option.
- iOS 18-25 keep-app-open guidance.

### Ad Policy

Initial ad behavior:

- Non-personalized requests.
- Top anchored adaptive banner.
- Rewarded ad before final save.
- App-open ads only when no encoding is active.
- Interstitials only at natural pauses.
- Native ads only in idle/completed non-primary areas.

Disallowed:

- No full-screen ads during encoding.
- No full-screen ads while picker is open.
- No full-screen ads during cancellation.
- No banner/native ad directly beside primary source buttons.
- No production ad IDs in Debug builds.

### Engineering Tasks

AdMob:

- Add Google Mobile Ads SDK.
- Add UMP SDK if required.
- Add `GADApplicationIdentifier`.
- Add SKAdNetwork identifiers.
- Add Debug test unit IDs.
- Add production config placeholders.
- Add `AdMobBannerView`.
- Add `AdMobRewardedAdGate`.
- Add app-open provider.
- Add interstitial provider.
- Add native provider.
- Add placement policy.
- Add frequency caps.
- Add remote-configurable placement switches.

Rewarded save:

- Require clear `Watch Ad to Save` user opt-in.
- Load rewarded ad after temporary output completes.
- If ad succeeds, save output.
- If ad fails, keep pending output.
- If user cancels reward, keep or discard based on user choice.
- Relaunch restores pending save.

Privacy:

- Keep initial ad requests non-personalized.
- Add consent flow where regional consent is required.
- Add privacy options entry point when required.
- Add ATT purpose string only if personalized ads or tracking is introduced later.
- Prepare App Store privacy nutrition labels.

Background:

- Add iOS/iPadOS 26+ background encoding option behind availability checks.
- Add iOS/iPadOS 18-25 keep-app-open guidance.
- Add Live Activity progress where supported.
- Do not request notification permission for MVP.

Release:

- Prepare app icon.
- Prepare screenshots.
- Prepare description.
- Prepare review notes explaining rewarded save.
- Publish privacy policy.
- Publish support URL.
- Publish `app-ads.txt`.
- Confirm category: Video.
- Confirm export compliance answers.
- Archive release build.
- Upload TestFlight.
- Smoke test TestFlight.
- Submit App Review.

### Files To Create

- `Core/Ads/AdPlacementPolicy.swift`
- `Core/Ads/RewardedAdProviding.swift`
- `Core/Ads/BannerAdProviding.swift`
- `Core/Ads/AppOpenAdProviding.swift`
- `Core/Ads/InterstitialAdProviding.swift`
- `Core/Ads/NativeAdProviding.swift`
- `Infrastructure/AdMob/AdMobAdConfiguration.swift`
- `Infrastructure/AdMob/AdMobBannerView.swift`
- `Infrastructure/AdMob/AdMobRewardedAdGate.swift`
- `Infrastructure/AdMob/AdMobAppOpenAdManager.swift`
- `Infrastructure/AdMob/AdMobInterstitialAdProvider.swift`
- `Infrastructure/AdMob/AdMobNativeAdView.swift`
- `Infrastructure/BackgroundTasks/ContinuedProcessingEncodingTask.swift`
- `Infrastructure/ActivityKit/EncodingLiveActivity.swift`

### Tests

Unit tests:

- `AdPlacementPolicyTests`
- `RewardedSaveGateTests`
- `AdConfigurationTests`
- `PendingSaveRewardRetryTests`
- `BackgroundEncodingCapabilityTests`

Simulator tests:

- Banner placeholder loads with fake provider.
- Rewarded save blocks final save until success.
- Reward failure preserves pending output.
- Pending output restores after relaunch.
- Interstitial does not show during active encoding.

Device tests:

- AdMob test banner.
- AdMob test rewarded ad.
- Files save after reward.
- Photos save after reward.
- Pending save restore after force quit.
- iOS 26+ background option proof.
- iOS 18-25 fallback message proof.

### Exit Criteria

- Version 1.0 build is App Store-ready.
- TestFlight smoke passes.
- Rewarded save works.
- Reward failure recovery works.
- Non-personalized ad policy is implemented.
- Privacy policy/support/app-ads surfaces are ready.
- No launch blocker remains except external App Review decision.

### Risks

- Rewarded ad save gate can attract App Review scrutiny.
- Non-personalized ads may still require regional consent.
- Ad SDK updates can change minimum supported OS or Xcode.
- Background encoding may not behave uniformly across devices.

## Phase 4: Post-Launch Stabilization And Legacy Software Proof

### Objective

Turn the launched product into a reliable old-device-friendly encoder.

### Product Scope

- Keep AV1 to H.265 as main product.
- Improve reliability.
- Prove software encoding behavior on older devices.
- Add clear runtime warnings.
- Tune ad frequency.
- Improve pending-save recovery.

### Engineering Tasks

Legacy device matrix:

- Define device classes:
  - A9/A10: supported slow software mode.
  - A11: slow/medium software mode.
  - A12+: practical baseline for AV1 software work.
  - iOS/iPadOS 26+: background option.
- Track:
  - decode support
  - encode support
  - estimated speed
  - thermal risk
  - memory risk
  - recommended max resolution
  - background support

Runtime warnings:

- Show slow software warning.
- Show long runtime warning.
- Show battery warning.
- Show thermal warning.
- Show storage warning.
- Show background limitation warning.

Reliability:

- Improve ETA smoothing.
- Add speed estimates.
- Add crash diagnostics.
- Add user-friendly error taxonomy.
- Add job history for current session.
- Add pending-save cleanup policy.
- Add failed temp output cleanup policy.
- Add remote ad configuration.
- Add frequency caps.

### Files To Create

- `Core/Devices/LegacyDeviceProfile.swift`
- `Core/Devices/DeviceCapabilityMatrix.swift`
- `Core/Encoding/RuntimeWarningPolicy.swift`
- `Core/Encoding/EncodingRuntimeEstimator.swift`
- `Core/Diagnostics/EncodingDiagnostics.swift`
- `Core/History/SessionJobHistory.swift`

### Tests

- Runtime warning policy tests.
- Device matrix tests.
- ETA smoothing tests.
- Pending-save cleanup tests.
- Ad frequency cap tests.
- Old-device manual test checklist.

### Exit Criteria

- Old devices show honest warnings.
- Software mode is usable within documented limits.
- A failed/closed app can restore pending saves.
- App Store feedback and crash issues from 1.0 are triaged.
- Version 1.1 stabilization release is ready.

### Risks

- Very old devices may technically run but be impractically slow.
- Software codec performance can vary sharply by resolution and duration.
- Too many warnings can make UX feel hostile; copy must be short and clear.

## Phase 5: Broad Input Engine

### Objective

Expand input support from AV1-only toward broad practical user video support while keeping output H.265.

### Product Scope

Supported input roadmap:

- AV1
- H.264 / AVC
- H.265 / HEVC
- VP9
- VP8
- MPEG-2 Video
- ProRes
- Other practical codecs supported by selected software backend

Supported container roadmap:

- MP4
- MOV
- M4V
- WebM
- MKV
- AVI
- TS
- MTS
- M2TS
- MXF

### Engineering Tasks

Codec strategy:

- Prefer AVFoundation/VideoToolbox for Apple-native inputs.
- Use software backend for unsupported input decode.
- Use hardware H.265 encode when possible.
- Use software H.265 encode when hardware is unavailable or settings are unsupported.
- Show `Hardware Encoder`, `Software Encoder`, or `Mixed Codec Path`.

Software codec evaluation:

- Evaluate FFmpeg-family options.
- Review LGPL/GPL risk.
- Review dynamic/static linking implications.
- Review App Store acceptability.
- Review patent/licensing exposure.
- Review binary size.
- Review performance on old devices.
- Decide bundled codec subset.

Capability matrix:

- Input codec support.
- Input container support.
- Decode backend.
- Encode backend.
- Hardware availability.
- Software fallback availability.
- Estimated speed class.
- User warning.

### Files To Create

- `Core/Encoding/CodecCapability.swift`
- `Core/Encoding/CodecExecutionMode.swift`
- `Infrastructure/SoftwareCodecs/SoftwareCodecMediaInspector.swift`
- `Infrastructure/SoftwareCodecs/SoftwareCodecDecoder.swift`
- `Infrastructure/SoftwareCodecs/SoftwareCodecHEVCEncoder.swift`
- `Infrastructure/SoftwareCodecs/SoftwareCodecLicenseNotice.swift`
- `Infrastructure/SoftwareCodecs/SoftwareCodecCapabilityProbe.swift`

### Tests

- Sample matrix for each container.
- Sample matrix for each codec.
- Unsupported codec error tests.
- Mixed path reporting tests.
- License notice presence tests.
- Old-device software fallback tests.

### Exit Criteria

- Each target codec/container has an explicit support answer.
- Unsupported inputs fail with clear English copy.
- Mixed paths are visible and understandable.
- App binary size increase is documented and accepted.
- Version 1.2 or 1.3 broad-input release is ready.

### Risks

- Software codec licensing can block certain configurations.
- App size can grow substantially.
- MXF and transport stream handling may require more edge-case work.
- Some codec/container combinations may be technically valid but impractical on old devices.

## Phase 6: Native FCPXML Project And Merge Planning

### Objective

Introduce native `.fcpxml` project files and merge planning before shipping the full timeline editor.

### Product Scope

- `.fcpxml` is native save format.
- Use latest stable official FCPXML DTD/version available at implementation time.
- Save/open project.
- Reference source media.
- Build video segment timeline.
- Generate normalization choices.
- Do not expose full editor complexity yet.

### Domain Models

```swift
struct EncoderProject: Equatable, Identifiable {
    var id: UUID
    var title: String
    var assets: [ProjectMediaAsset]
    var timeline: VideoSegmentTimeline
    var outputOptions: EncodingOptions
    var fcpxmlVersion: FCPXMLVersion
}

struct ProjectMediaAsset: Equatable, Identifiable {
    var id: UUID
    var source: SourcePickerResult
    var metadata: MediaMetadata
}

struct VideoSegmentTimeline: Equatable {
    var segments: [VideoSegment]
    var outputCanvas: OutputCanvas
}

struct VideoSegment: Equatable, Identifiable {
    var id: UUID
    var assetID: ProjectMediaAsset.ID
    var sourceRange: ClosedRange<TimeInterval>
    var timelineStart: TimeInterval
    var placement: ClipPlacement
    var audioPolicy: SegmentAudioPolicy
}
```

### Engineering Tasks

FCPXML:

- Choose DTD/version at implementation time.
- Build serializer.
- Build parser.
- Build validator.
- Round-trip project fixtures.
- Keep XML mutation out of SwiftUI views.
- Store app-specific metadata safely.
- Keep external media references by default.
- Add future managed project flag.

Project flow:

- Create project.
- Add media.
- Save `.fcpxml`.
- Open `.fcpxml`.
- Re-link missing media.
- Show project summary.
- Show compatibility summary.

Merge planning:

- Inspect all media.
- Build compatibility report.
- Resolve output canvas.
- Generate normalization options:
  - resolution/canvas
  - frame rate
  - color handling
  - audio layout
  - orientation handling
- Auto-select close-enough values.
- Ask user when values meaningfully differ.

### Files To Create

- `Core/Project/EncoderProject.swift`
- `Core/Project/ProjectMediaAsset.swift`
- `Core/Project/ProjectDocument.swift`
- `Core/Project/FCPXMLVersion.swift`
- `Core/Merge/MergeCompatibilityInspector.swift`
- `Core/Merge/MergeNormalizationPlan.swift`
- `Core/Merge/OutputCanvas.swift`
- `Infrastructure/FCPXML/FCPXMLReader.swift`
- `Infrastructure/FCPXML/FCPXMLWriter.swift`
- `Infrastructure/FCPXML/FCPXMLDTDValidator.swift`
- `Infrastructure/FCPXML/FCPXMLMetadataMapper.swift`

### Tests

- FCPXML write tests.
- FCPXML parse tests.
- FCPXML round-trip tests.
- FCPXML DTD validation tests.
- Missing media reference tests.
- Merge compatibility tests.
- Normalization option generation tests.
- Close-enough auto-selection tests.

### Exit Criteria

- Project can save as `.fcpxml`.
- Project can reopen from `.fcpxml`.
- Generated FCPXML validates.
- Project model round-trips.
- Merge compatibility report is understandable.
- Version 1.4 project planning release is ready.

### Risks

- FCPXML compatibility can drift if app-specific metadata is written carelessly.
- File security-scoped references may not survive all provider behaviors.
- Missing media relink UX can become complex.

## Phase 7: Merge Export And Lightweight Video Editing

### Objective

Ship the merge/edit workflow where multiple videos become one H.265 output through a simple video-segment timeline.

### Product Scope

Editing tools:

- trim
- cut
- split
- shorten
- reorder
- canvas position
- fit/fill/center placement

Interaction concepts:

- Taption subtitle segment becomes `VideoSegment`.
- Taption timeline becomes `VideoSegmentTimeline`.
- Taption touch widget becomes video segment controls.
- Taption slice/split becomes non-destructive segment split.
- Preview and commit calculations must match.

### Engineering Tasks

Timeline:

- Build segment timeline view.
- Show video segments.
- Show selected segment.
- Show handles for trim.
- Show split/slice control.
- Show reorder affordance.
- Show canvas placement control.

Edit operations:

- `trimStart`
- `trimEnd`
- `cutRange`
- `splitAt`
- `shortenOutPoint`
- `reorder`
- `placeOnCanvas`
- `fit`
- `fill`
- `center`

Merge encoding:

- Build normalized composition.
- Apply segment source ranges.
- Apply ordering.
- Apply canvas placement.
- Apply audio policy.
- Encode one H.265 output.
- Reuse progress, ETA, cancellation, storage, background, reward, pending-save logic.

FCPXML:

- Save edits to `.fcpxml`.
- Reopen same timeline.
- Add `.fcpxmld` bundle support after `.fcpxml` is stable.
- Add managed `.fcpxmld` mode that can copy original media when user chooses it.

### Files To Create

- `Features/MergeEditor/MergeEditorView.swift`
- `Features/MergeEditor/MergeEditorViewModel.swift`
- `Features/MergeEditor/VideoSegmentTimelineView.swift`
- `Features/MergeEditor/SegmentTouchWidgetView.swift`
- `Features/MergeEditor/SliceSplitControl.swift`
- `Features/MergeEditor/ClipPlacementView.swift`
- `Core/Editing/TimelineEditOperation.swift`
- `Core/Editing/SegmentEditOwnership.swift`
- `Core/Editing/TouchWidgetInteraction.swift`
- `Core/Editing/SplitVideoSegmentOperation.swift`
- `Core/Merge/MergeEncodingPipeline.swift`

### Tests

- Video segment split tests.
- Trim validation tests.
- Cut range tests.
- Reorder tests.
- Canvas placement tests.
- Touch ownership tests.
- Preview/commit alignment tests.
- Merge export fake tests.
- Merge export device tests.
- FCPXML timeline persistence tests.

### Exit Criteria

- User can merge multiple files into one H.265 output.
- User can trim, cut, split, shorten, reorder, and position clips.
- User-selected normalization is applied.
- Close-enough normalization is auto-applied.
- Progress, ETA, cancellation, reward gate, pending save, and storage checks all work for merge jobs.
- `.fcpxml` project reopens with the same timeline.
- Version 1.5 or 2.0 merge/edit release is ready.

### Risks

- Timeline editing can expand into a full NLE if scope is not controlled.
- Gesture preview/commit mismatch can create trust issues.
- Mixed source frame rates and audio layouts can create sync bugs.
- Merge jobs will be slower and more storage-heavy than single-file jobs.

## Phase 8: Advanced Controls And Final Product Completion

### Objective

Complete the final product direction while keeping the default flow simple.

### Product Scope

Advanced settings:

- H.265 output container:
  - `.mp4`
  - `.mov`
- resolution
- frame rate
- bitrate
- quality
- color map
- tone map
- HDR/SDR conversion
- audio policy
- batch conversion
- per-file presets
- multi-camera merge presets
- optional compression-first presets

### Engineering Tasks

Settings:

- Add advanced settings screen.
- Keep simple default mode first.
- Hide advanced controls until user opens advanced mode.
- Add reset-to-source defaults.
- Add preset save/load.
- Add per-file preset assignment.

Encoding:

- Feed advanced settings into storage estimation.
- Feed advanced settings into encoding options.
- Add validation for impossible combinations.
- Add warnings for quality loss.
- Add warnings for long runtime.
- Add warnings for HDR/SDR conversion.

Batch:

- Queue multiple jobs.
- Show batch progress.
- Show per-job progress.
- Support pause/cancel where possible.
- Apply rewarded save policy per completed output or chosen batch policy if later approved.

Final polish:

- Optimize long jobs.
- Optimize memory.
- Improve accessibility.
- Improve localization readiness while keeping visible strings English for now.
- Refresh App Store screenshots.
- Refresh App Store description.
- Refresh review notes.

### Files To Create

- `Features/Settings/AdvancedEncodingSettingsView.swift`
- `Features/Settings/AdvancedEncodingSettingsViewModel.swift`
- `Core/Encoding/EncodingPreset.swift`
- `Core/Encoding/AdvancedEncodingValidation.swift`
- `Core/Batch/BatchEncodingJob.swift`
- `Core/Batch/BatchEncodingQueue.swift`
- `Features/Batch/BatchQueueView.swift`

### Tests

- Preset validation tests.
- Bitrate validation tests.
- Resolution validation tests.
- Frame-rate conversion tests.
- Color mapping policy tests.
- Storage estimation with advanced options.
- Batch queue tests.
- Batch cancellation tests.
- Device tests with advanced settings.

### Exit Criteria

- Default user flow is still simple.
- Advanced controls work and are validated.
- Broad input support is stable enough for honest "All to H.265" marketing.
- Old-device software support remains documented and verified.
- FCPXML project, merge, edit, and export workflows are stable.
- Final completion release is ready.

### Risks

- Advanced settings can overwhelm the main UX.
- Bitrate/quality controls can make output worse if copy is unclear.
- Batch encoding can multiply thermal/storage/ad complexity.
- HDR/color controls require careful device proof.

## Cross-Phase Quality Gates

Every phase must satisfy these gates before it is considered complete.

Documentation gate:

- Update `README.md` if product surface changes.
- Update `APP_ARCHITECTURE.md` if architecture changes.
- Update `ACTION_ITEMS.md` when decisions move from open to confirmed.
- Update this document when phase scope changes.

Build gate:

- iPhone simulator build succeeds.
- iPad simulator build succeeds.
- No new iOS 16+ API usage without availability checks.

Test gate:

- New pure domain logic has unit tests.
- Risky view model state transitions have unit tests.
- Fake service flows exist before real service flows.
- Device-only behavior is documented when simulator cannot prove it.

Product gate:

- UI strings are English.
- iPad does not become a separate UX.
- Ads do not interrupt active encoding.
- Rewarded save behavior is explicit.
- Source-like output remains default.

Old-device gate:

- Software path is available or clearly explains why it is unavailable.
- Slow devices receive honest warnings.
- iOS/iPadOS 18-25 receives keep-app-open guidance.
- iOS/iPadOS 26+ receives background option where available.

## Immediate Implementation Order

Recommended exact next order:

1. Create module folders.
2. Move `ContentView` into `Features/Home/HomeView`.
3. Add `AppEnvironment`.
4. Add protocol shells.
5. Add `HomeScreenState`.
6. Add fake services.
7. Build the real main UI.
8. Add fake encoding progress and ETA.
9. Add fake rewarded save gate.
10. Add fake pending-save restoration.
11. Add iPhone/iPad simulator UI verification.
12. Start AV1 media inspection.

## Open Decisions

Current remaining decisions:

- Whether final save must always require rewarded ad even if App Review asks for a fallback.
- Whether merge MVP scope is exactly trim, cut, split, shorten, reorder, and canvas position.
- Final software codec stack after licensing and App Store review analysis.
