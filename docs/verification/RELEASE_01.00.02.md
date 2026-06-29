# Taption Encoder 01.00.02 Release Proof

## Release Identity

- Company release label: `01.00.02`
- Apple marketing version: `1.0.2`
- Apple build number: `20`
- Bundle identifier: `com.taption.encoder`
- Release date: 2026-06-29

## Scope

- Keep H.265 / HEVC as the only video output codec.
- Keep output containers constrained to MP4 and MOV.
- Stabilize queue preview playback, preview badge wrapping, thumbnail generation separation, bundled sample audio, and software-inspection fallback metadata.
- Reorganize development documentation so only `AGENTS.md` remains at the project root and typed documents live under `docs/`.
- Archive old release notes, old reports, completed Taption Encoder handoffs, and rejected Taption-main handoffs under `docs/archive/`.

## Proof Surfaces

- [x] Code review completed: no release-blocking code issues remained after checking the preview/sample/doc diffs and `git diff --check`.
- [x] `plutil -lint TaptionEncoder/Info.plist` passed.
- [x] Focused queue-preview/thumbnail XCTest passed:
  - `CodecRoutePlannerTests/testPreviewRegressionSamplesProduceVisibleVideoSnapshots`
  - `CodecRoutePlannerTests/testBundledAvailableNowSamplesGenerateQueueThumbnails`
- [x] `Scripts/verify_bundled_test_videos.sh` passed: 55 bundled videos, target duration 4.85-5.15 seconds, documented size exceptions `DV.dv` and `DVCPro HD.mov`, documented audio exceptions `H.261.h261` and `RoQ Video.roq`.
- [x] `Scripts/run_core_codec_truth_checks.sh` passed: 63 planned video route pairs, 93 Apple device models, 2 video output selections, 56 audio output selections.
- [x] App-scheme XCTest passed with parallel testing disabled: 245 tests, 2 skipped, 0 failures.
- [x] Release archive succeeded at `build/TestFlight-01.00.02-20/TaptionEncoder.xcarchive`; archived app Info.plist reported `com.taption.encoder`, version `1.0.2`, build `20`.
- [x] TestFlight/App Store Connect export/upload succeeded with `Uploaded package is processing`, `Upload succeeded`, and `EXPORT SUCCEEDED`.

## Upload Notes

- Upload command used `build/TestFlight-01.00.02-20/ExportOptions.plist` with App Store Connect upload destination.
- Upload produced non-blocking dSYM warnings for `GoogleMobileAds.framework` and `UserMessagingPlatform.framework`, matching the existing release pattern; the app package upload still succeeded.

## Boundaries

- TestFlight/App Store Connect upload success is not App Review approval, App Store processing completion, or public availability.
- Device install and runtime logs are separate proof surfaces and must be reported separately if verified.
- Rejected Taption-main handoffs in `docs/archive/agent_communication/rejected_context/` are preserved only as rejected context, not as Taption Encoder proof.
