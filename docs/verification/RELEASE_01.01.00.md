# Taption Encoder 01.01.00 Release Preparation Proof

## Release Identity

- Company release label: `01.01.00`
- Apple marketing version: `1.1.0`
- Apple build number: `30`
- Bundle identifier: `com.taption.encoder`
- Latest preparation date: 2026-07-06

## Scope

- Keep H.265 / HEVC as the only video output codec.
- Keep output containers constrained to MP4 and MOV.
- Carry forward the latest queue editing, source-preserving validation, privacy/ad, bundled sample, preview, background-status, and multi-file encoding-mode prompt work.
- Prepare the App Store candidate and upload it to App Store Connect/TestFlight. App Review submission and public release are owner-decided follow-up steps.

## Proof Surfaces

- [x] Apple marketing version/build set to `1.1.0 (30)`.
- [x] `plutil -lint TaptionEncoder/Info.plist TaptionEncoderThumbnailExtension/Info.plist TaptionEncoderLiveActivityExtension/Info.plist` passed.
- [x] Focused multi-file encoding-mode XCTest passed:
  - `CodecRoutePlannerTests/testMultiFileStartPromptsBeforeEncodingAndMergeChoiceShowsUnavailableAlert`
  - `CodecRoutePlannerTests/testMultiFilePromptEncodeSeparatelyContinuesBatchEncoding`
  - `CodecRoutePlannerTests/testFolderBatchWithPartialStarBalanceActivatesTopCardsAndEncodesOnlyThose`
  - `CodecRoutePlannerTests/testFolderBatchStopsAfterCurrentItemWhenPowerDisconnectsDuringEncoding`
- [x] `Scripts/run_core_codec_truth_checks.sh` passed.
- [x] Local release archive succeeded at `build/TestFlight-01.01.00-30/TaptionEncoder.xcarchive`.
- [x] Archived app Info.plist reports `com.taption.encoder`, version `1.1.0`, build `30`.
- [x] App extensions report version `1.1.0`, build `30`.
- [x] Thumbnail extension archive inspection reports `QLSupportedContentTypes` as `com.taption.legacy-video` only.
- [x] App Store Connect/TestFlight upload succeeded and App Store Connect reported the uploaded package is processing.
- [x] App Store Connect version `1.1.0` was created in `PREPARE_FOR_SUBMISSION` with `MANUAL` release type.
- [x] App Store Connect What's New text was filled in for English (`en-US`) and Korean (`ko`).

## Command Evidence

- `xcodebuild -project TaptionEncoder.xcodeproj -scheme TaptionEncoder -showBuildSettings` reports `MARKETING_VERSION = 1.1.0`, `CURRENT_PROJECT_VERSION = 30`, and `PRODUCT_BUNDLE_IDENTIFIER = com.taption.encoder`.
- Focused XCTest passed on the iPhone 17 Pro iOS 26.5 simulator: 4 tests, 0 failures. Result bundle: `/Users/u_mo_c/Library/Developer/Xcode/DerivedData/TaptionEncoder-cppuipnwyznujvabarpyvzevtqvq/Logs/Test/Test-TaptionEncoder-2026.07.06_01-33-50-+0900.xcresult`.
- `Scripts/run_core_codec_truth_checks.sh` passed with 63 planned video route pairs, 93 Apple device models, 2 video output selections, and 56 audio output selections.
- Local archive inspection reports the app bundle as `com.taption.encoder`, version `1.1.0`, build `30`; thumbnail extension as `com.taption.encoder.thumbnail`, version `1.1.0`, build `30`; and Live Activity extension as `com.taption.encoder.liveactivity`, version `1.1.0`, build `30`.
- Thumbnail extension archive inspection reports `NSExtension:NSExtensionAttributes:QLSupportedContentTypes` as `com.taption.legacy-video` only.
- `xcodebuild -exportArchive` uploaded `TaptionEncoder` from `build/TestFlight-01.01.00-30/TaptionEncoder.xcarchive`; App Store Connect reported `Uploaded package is processing` and `Upload succeeded`; Xcode ended with `** EXPORT SUCCEEDED **`.
- Upload completed with non-fatal symbol warnings for missing third-party dSYMs for `GoogleMobileAds.framework` and `UserMessagingPlatform.framework`.
- Existing App Store Connect API verification from the build `29` preparation pass reports version id `ec0a36ea-752e-46f3-884b-482df2bebb41`, version `1.1.0`, state `PREPARE_FOR_SUBMISSION`, and release type `MANUAL`.
- Existing `altool --app-store-text --download` verification from the build `29` preparation pass verified the English (`en-US`) and Korean (`ko`) What's New text from App Store Connect.

## Build History

- Build `30` on 2026-07-06 is the latest uploaded `1.1.0` candidate. App Store Connect accepted the upload and reported the package is processing.
- Build `29` on 2026-07-03 was the initial uploaded `1.1.0` candidate and also prepared the App Store Connect version page plus localized What's New text.

## What's New Text

English (`en-US`):

```text
What's New in Version 1.1.0

- Added a clearer prompt before multi-file encoding so selected videos can be handled intentionally.
- Improved queue editing with multi-select, drag reordering, swipe selection, and safer delete feedback.
- Made preview playback more intentional with double-tap playback and steadier controls while moving between files.
- Strengthened H.265 output validation, background status reporting, and privacy/ad readiness.
```

Korean (`ko`):

```text
버전 1.1.0의 새로운 기능

- 여러 파일 인코딩 시작 전에 선택한 영상을 어떻게 처리할지 확인하는 안내를 추가했습니다.
- 멀티 선택, 드래그 순서 변경, 스와이프 선택, 삭제 피드백 등 큐 편집 동작을 개선했습니다.
- 더블 탭으로만 미리보기 재생이 시작되도록 하고, 파일 이동 중 컨트롤 안정성을 높였습니다.
- H.265 출력 검증, 백그라운드 상태 표시, 개인정보/광고 준비 상태를 강화했습니다.
```

## Upload Notes

- App Store Connect/TestFlight upload was performed during this preparation pass.
- App Store Connect version metadata was prepared during the build `29` preparation pass and reused for the build `30` upload.
- App Review submission was not performed during this preparation pass.
- Public App Store release was not performed during this preparation pass.
- Owner will decide whether to select the build in App Store Connect, submit for review, or release publicly.

## Boundaries

- Local archive success is not App Store Connect upload success.
- App Store Connect upload success is not App Review approval, App Store processing completion, TestFlight availability, or public availability.
- Device install and runtime logs are separate proof surfaces and must be reported separately if verified.
