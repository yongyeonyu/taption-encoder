# Taption Encoder 01.01.01 TestFlight Build-Up Proof

## Release Identity

- Company release label: `01.01.01`
- Apple marketing version: `1.1.1`
- Apple build number: `31`
- Bundle identifier: `com.taption.encoder`
- Latest preparation date: 2026-07-07

## Scope

- Keep H.265 / HEVC as the only video output codec.
- Keep output containers constrained to MP4 and MOV.
- Build and upload the next TestFlight/App Store Connect candidate after App Store Connect closed the `1.1.0` train for new build submissions.
- Keep App Review submission, TestFlight availability, processing completion, public release, real-device install, and runtime logs as separate proof surfaces.

## Preflight Outcome

- A first `1.1.0 (31)` upload attempt was rejected by App Store Connect validation.
- App Store Connect reported `Invalid Pre-Release Train. The train version '1.1.0' is closed for new build submissions` (`90186`).
- App Store Connect also reported `CFBundleShortVersionString [1.1.0] ... must contain a higher version than that of the previously approved version [1.1.0]` (`90062`).
- The candidate was then moved to `1.1.1 (31)` and rebuilt.

## Proof Surfaces

- [x] Apple marketing version/build set to `1.1.1 (31)`.
- [x] `plutil -lint TaptionEncoder/Info.plist TaptionEncoderThumbnailExtension/Info.plist TaptionEncoderLiveActivityExtension/Info.plist` passed.
- [x] `xcodebuild -project TaptionEncoder.xcodeproj -scheme TaptionEncoder -showBuildSettings` reported `MARKETING_VERSION = 1.1.1`, `CURRENT_PROJECT_VERSION = 31`, and `PRODUCT_BUNDLE_IDENTIFIER = com.taption.encoder`.
- [x] `Scripts/run_core_codec_truth_checks.sh` passed.
- [x] Focused XCTest passed on the iPhone 17 Pro iOS 26.5 simulator: 9 tests, 0 failures.
- [x] Local Release archive succeeded at `build/TestFlight-01.01.01-31/TaptionEncoder.xcarchive`.
- [x] Archived app Info.plist reports `com.taption.encoder`, version `1.1.1`, build `31`.
- [x] App extensions report version `1.1.1`, build `31`.
- [x] Thumbnail extension archive inspection reports `QLSupportedContentTypes` as `com.taption.legacy-video` only.
- [x] App Store Connect/TestFlight upload succeeded and App Store Connect reported `Uploaded package is processing` followed by `Upload succeeded`.

## Command Evidence

- `Scripts/run_core_codec_truth_checks.sh` passed with 63 planned video route pairs, 93 Apple device models, 2 video output selections, and 56 audio output selections.
- Focused XCTest passed with these `CodecRoutePlannerTests`:
  - `testMultiFileStartPromptsBeforeEncodingAndMergeChoiceShowsUnavailableAlert`
  - `testMultiFilePromptEncodeSeparatelyContinuesBatchEncoding`
  - `testFolderBatchWithPartialStarBalanceActivatesTopCardsAndEncodesOnlyThose`
  - `testFolderBatchStopsAfterCurrentItemWhenPowerDisconnectsDuringEncoding`
  - `testKnownBlackPreviewCodecsStayEncodableButNotPreviewableInQueue`
  - `testQueuePreviewPlaylistNavigationSkipsEnabledNonPreviewableItems`
  - `testEncodingRuntimeWarningEvaluatorCombinesThermalBatteryMemoryAndRuntimeWarnings`
  - `testHomeViewModelStartsAndStopsResourceMonitoringAroundEncoding`
  - `testBundledFFmpegDecodeBridgeEncodesVC1RawAndY41PToHEVCMP4MOVInSimulator`
- Local archive inspection reports the app bundle as `com.taption.encoder`, version `1.1.1`, build `31`; thumbnail extension as `com.taption.encoder.thumbnail`, version `1.1.1`, build `31`; and Live Activity extension as `com.taption.encoder.liveactivity`, version `1.1.1`, build `31`.
- Thumbnail extension archive inspection reports `NSExtension:NSExtensionAttributes:QLSupportedContentTypes` as `com.taption.legacy-video` only.
- Local archive size was `117M`; archived app bundle size was `91M`.
- `xcodebuild -exportArchive` uploaded `TaptionEncoder` from `build/TestFlight-01.01.01-31/TaptionEncoder.xcarchive`; App Store Connect reported `Uploaded package is processing` and `Upload succeeded`; Xcode ended with `** EXPORT SUCCEEDED **`.
- Upload completed with non-fatal symbol warnings for missing third-party dSYMs:
  - `GoogleMobileAds.framework` UUID `D873B778-F5C9-3EBB-B9F1-90F9E544BB4C`
  - `UserMessagingPlatform.framework` UUID `FD32F182-2DE3-3B42-92D2-0BD6A00B071A`

## Upload Notes

- App Store Connect/TestFlight upload was performed during this preparation pass.
- App Store Connect reported the uploaded package is processing.
- App Store Connect version metadata for `1.1.1` was not created or edited during this pass.
- App Review submission was not performed during this pass.
- TestFlight availability after processing was not verified during this pass.
- Public App Store release was not performed during this pass.
- Real-device install, launch, runtime, thermal, battery, and memory proof were not performed during this pass.

## Boundaries

- Local validation and archive success are not App Store Connect upload success.
- App Store Connect upload success is not App Review approval, processing completion, TestFlight availability, or public availability.
- App Store Connect upload validation treated `1.1.0` as closed/previously approved, but this pass did not independently verify public App Store availability.
- Device install and runtime logs are separate proof surfaces and must be reported separately if verified.
