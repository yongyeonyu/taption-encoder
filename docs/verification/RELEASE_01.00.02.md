# Taption Encoder 01.00.02 Release Proof

## Release Identity

- Company release label: `01.00.02`
- Apple marketing version: `1.0.2`
- Apple build number: `24`
- Bundle identifier: `com.taption.encoder`
- Release date: 2026-07-01

## Scope

- Keep H.265 / HEVC as the only video output codec.
- Keep output containers constrained to MP4 and MOV.
- Stabilize queue preview playback, preview badge wrapping, thumbnail generation separation, bundled sample audio, software-inspection fallback metadata, save destination choice, and folder-batch sibling output behavior.
- Stabilize queue-card editing gestures, grouped queue reordering, multi-select delete, Photos queue behavior, and real-device model display naming.
- Reorganize development documentation so only `AGENTS.md` remains at the project root and typed documents live under `docs/`.
- Archive old release notes, old reports, completed Taption Encoder handoffs, and rejected Taption-main handoffs under `docs/archive/`.

## Proof Surfaces

- [x] Code review completed: App Store Connect rejected the first build `21` upload attempt because the thumbnail extension declared system-supported types in `QLSupportedContentTypes`; the release-blocking issue was fixed by limiting the thumbnail extension to `com.taption.legacy-video`, then re-archiving and re-uploading.
- [x] Code review completed for build `24`: build `23` upload failed because the thumbnail extension again declared system-supported `QLSupportedContentTypes`; the release-blocking issue was fixed by restoring `QLSupportedContentTypes` to `com.taption.legacy-video` only and adding an XCTest guard for the App Store Connect rule.
- [x] `plutil -lint TaptionEncoder/Info.plist TaptionEncoderThumbnailExtension/Info.plist TaptionEncoderLiveActivityExtension/Info.plist` passed.
- [x] Thumbnail extension archive inspection passed: `QLSupportedContentTypes` contains only `com.taption.legacy-video`.
- [x] Focused queue-edit/device/Photos XCTest passed:
  - `CodecRoutePlannerTests/testQueueSwipeSelectionAndDeleteSelectedItems`
  - `CodecRoutePlannerTests/testQueueDragHandleMovesSelectedItemsAsGroup`
  - `CodecRoutePlannerTests/testQueueDragHandleMovesSelectedItemsDownAsGroup`
  - `CodecRoutePlannerTests/testQueueCardGestureControlsAreWiredForSelectionDeleteAndDrag`
  - `CodecRoutePlannerTests/testAlbumImportQueuesWithoutAutoOpeningPreview`
  - `CodecRoutePlannerTests/testDeviceCodecReportDisplaysIPhone14ProMarketingName`
- [x] Focused queue-preview/thumbnail XCTest passed:
  - `CodecRoutePlannerTests/testQuickLookThumbnailExtensionCoversDocumentBrowserVideoTypes`
  - `CodecRoutePlannerTests/testQueuePreviewCanMinimizeIntoBannerOnlyFloatingPlayer`
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
- [x] Release archive succeeded at `build/TestFlight-01.00.02-24/TaptionEncoder.xcarchive`; archived app Info.plist reported `com.taption.encoder`, version `1.0.2`, build `24`.
- [x] TestFlight/App Store Connect export/upload succeeded with `Uploaded package is processing`, `Upload succeeded`, and `Uploaded TaptionEncoder`.

## Upload Notes

- Build `21` upload remains historical proof for the first thumbnail-extension fix. Build `22` remains historical proof for save-destination stabilization. Build `23` failed App Store Connect validation because `QLSupportedContentTypes` included system-supported types. Build `24` is the current uploaded package for release `01.00.02`.
- Upload command used `build/TestFlight-01.00.02-24/ExportOptions.plist` with App Store Connect upload destination.
- Upload produced non-blocking dSYM warnings for `GoogleMobileAds.framework` UUID `F92C0D16-4B31-32A6-9EAB-0737AE1FA74D` and `UserMessagingPlatform.framework` UUID `B28A828D-312C-3A66-B319-6009CFA2F082`; the app package upload still succeeded.

## Boundaries

- TestFlight/App Store Connect upload success is not App Review approval, App Store processing completion, or public availability.
- Device install and runtime logs are separate proof surfaces and must be reported separately if verified.
- Rejected Taption-main handoffs in `docs/archive/agent_communication/rejected_context/` are preserved only as rejected context, not as Taption Encoder proof.
