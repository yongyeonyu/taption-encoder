# Taption Encoder 01.00.02 Release Proof

## Release Identity

- Company release label: `01.00.02`
- Apple marketing version: `1.0.2`
- Apple build number: `22`
- Bundle identifier: `com.taption.encoder`
- Release date: 2026-06-30

## Scope

- Keep H.265 / HEVC as the only video output codec.
- Keep output containers constrained to MP4 and MOV.
- Stabilize queue preview playback, preview badge wrapping, thumbnail generation separation, bundled sample audio, software-inspection fallback metadata, save destination choice, and folder-batch sibling output behavior.
- Reorganize development documentation so only `AGENTS.md` remains at the project root and typed documents live under `docs/`.
- Archive old release notes, old reports, completed Taption Encoder handoffs, and rejected Taption-main handoffs under `docs/archive/`.

## Proof Surfaces

- [x] Code review completed: App Store Connect rejected the first build `21` upload attempt because the thumbnail extension declared system-supported types in `QLSupportedContentTypes`; the release-blocking issue was fixed by limiting the thumbnail extension to `com.taption.legacy-video`, then re-archiving and re-uploading.
- [x] `plutil -lint TaptionEncoder/Info.plist TaptionEncoderThumbnailExtension/Info.plist TaptionEncoderLiveActivityExtension/Info.plist` passed.
- [x] Thumbnail extension archive inspection passed: `QLSupportedContentTypes` contains only `com.taption.legacy-video`.
- [x] Focused queue-preview/thumbnail XCTest passed:
  - `CodecRoutePlannerTests/testPreviewRegressionSamplesProduceVisibleVideoSnapshots`
  - `CodecRoutePlannerTests/testBundledAvailableNowSamplesGenerateQueueThumbnails`
- [x] `Scripts/verify_bundled_test_videos.sh` passed: 55 bundled videos, target duration 4.85-5.15 seconds, documented size exceptions `DV.dv` and `DVCPro HD.mov`, documented audio exceptions `H.261.h261` and `RoQ Video.roq`.
- [x] `Scripts/run_core_codec_truth_checks.sh` passed: 63 planned video route pairs, 93 Apple device models, 2 video output selections, 56 audio output selections.
- [x] External video player registration verification passed for source and built app Info.plist.
- [x] External video player flow verification passed in both warm and cold modes on the iPhone 17 Pro simulator.
- [x] App-scheme XCTest passed with parallel testing disabled.
- [x] Build `22` focused save-destination XCTest passed:
  - `CodecRoutePlannerTests/testPendingSaveRequestsDestinationPromptBeforeFinalSave`
  - `CodecRoutePlannerTests/testFolderBatchFolderDestinationSavesIntoSiblingTaptionFolder`
  - `CodecRoutePlannerTests/testPendingSaveConflictOpensExportPickerWithoutOverwritePrompt`
- [x] Build `22` pending-save, rewarded-save, and folder-batch regression XCTest passed.
- [x] Build `22` file/folder picker and queue-preview XCTest passed.
- [x] Release archive succeeded at `build/TestFlight-01.00.02-22/TaptionEncoder.xcarchive`; archived app Info.plist reported `com.taption.encoder`, version `1.0.2`, build `22`.
- [x] TestFlight/App Store Connect export/upload succeeded with `Uploaded package is processing`, `Upload succeeded`, and `EXPORT SUCCEEDED`.

## Upload Notes

- Build `21` upload remains historical proof for the thumbnail-extension fix. Build `22` is the current uploaded package for release `01.00.02`.
- Upload command used `build/TestFlight-01.00.02-22/ExportOptions.plist` with App Store Connect upload destination.
- Upload produced non-blocking dSYM warnings for `GoogleMobileAds.framework` UUID `97DFF24C-CF1E-33FD-92D5-232B7ADF89FD` and `UserMessagingPlatform.framework` UUID `80CA0D32-5403-3D46-B37D-77C6EDDC6E16`; the app package upload still succeeded.

## Boundaries

- TestFlight/App Store Connect upload success is not App Review approval, App Store processing completion, or public availability.
- Device install and runtime logs are separate proof surfaces and must be reported separately if verified.
- Rejected Taption-main handoffs in `docs/archive/agent_communication/rejected_context/` are preserved only as rejected context, not as Taption Encoder proof.
