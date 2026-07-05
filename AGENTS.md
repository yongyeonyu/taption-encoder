# AGENTS.md

## Project

- Product: Taption Encoder
- Path: `/Users/u_mo_c/Documents/taption_encoder`
- Xcode project: `TaptionEncoder.xcodeproj`
- Scheme: `TaptionEncoder`
- Bundle id: `com.taption.encoder`

## Intent

This project is the standalone app shell for Taption's AV1 to H.265 conversion feature. It should stay separate from the main Taption editor unless a file is intentionally ported.

## Current Release State

- Release `01.01.00` maps to Apple marketing version `1.1.0` and current release candidate build `30`.
- Release `01.01.00` build `30` archive/export/upload succeeded on 2026-07-06: version/build were set to `1.1.0 (30)`, plist lint passed, focused multi-file/folder XCTest passed, core codec truth checks passed, a local archive was created and inspected at `build/TestFlight-01.01.00-30/TaptionEncoder.xcarchive`, and App Store Connect reported `Uploaded package is processing` followed by `Upload succeeded`. App Review submission, TestFlight availability, processing completion, and public release were not performed or verified in this pass. The upload completed with non-fatal dSYM warnings for `GoogleMobileAds.framework` and `UserMessagingPlatform.framework`.
- Release `01.01.00` build `29` archive/export/upload succeeded on 2026-07-03: version/build were set to `1.1.0 (29)`, plist lint passed, focused multi-file/folder XCTest passed, core codec truth checks passed, a local archive was created and inspected at `build/TestFlight-01.01.00-29/TaptionEncoder.xcarchive`, and App Store Connect reported the uploaded package is processing. App Store Connect version `1.1.0` was created in `PREPARE_FOR_SUBMISSION` with `MANUAL` release type, and the English (`en-US`) plus Korean (`ko`) What's New text was filled in. App Review submission and public release were not performed; the owner will decide those steps separately. The upload completed with non-fatal dSYM warnings for `GoogleMobileAds.framework` and `UserMessagingPlatform.framework`.
- Release `01.00.02` maps to Apple marketing version `1.0.2` and uploaded build `28`.
- Release `01.00.02` build `20` archive/export/upload succeeded on 2026-06-29. Build `21` archive/export/upload succeeded on 2026-06-30 after tightening the thumbnail extension `QLSupportedContentTypes` declaration. Build `22` archive/export/upload succeeded on 2026-06-30 after adding the save destination chooser and folder-batch sibling output behavior. Build `23` upload failed on 2026-07-01 because the thumbnail extension again declared system-supported `QLSupportedContentTypes`. Build `24` archive/export/upload succeeded on 2026-07-01 after queue-edit interaction fixes, iPhone model display correction, Photos queue behavior, and restoring thumbnail extension `QLSupportedContentTypes` to `com.taption.legacy-video` only. Build `25` archive/export/upload succeeded on 2026-07-01 after queue-card gesture UI polish, queue thumbnail play badges, queue height fit adjustment, preview system-volume control, and output summary/card text cleanup. Build `26` archive/export/upload succeeded on 2026-07-01 after moving queue-card drag to the full card, restricting queue-card playback to the thumbnail play badge, and moving right-swipe delete feedback to a large trailing trash indicator. Build `27` archive/export/upload succeeded on 2026-07-01 after changing queue-card preview playback to require a double tap on the thumbnail surface. Build `28` archive/export/upload succeeded on 2026-07-02 after changing the Star sheet to Pro Mode purchase guidance and preserving preview/details/editing interactions for Star-limited queue cards. App Store Connect reported the uploaded package is processing. App Review, processing completion, TestFlight availability, and public App Store availability are separate states and are not verified here.
- Release `01.00.01` remains the archived shipped baseline. The `01.00.01` release train used commit `f5af6b3` (`Prepare Taption Encoder 1.0.1 build 19`).
- App Store Connect/TestFlight upload proof is separate from App Review or store-processing status. Do not report processing, review, or public availability as complete unless that exact state was verified or reported by the company.
- The last release proof set for `01.00.01` included:
  - `Scripts/run_core_codec_truth_checks.sh` passed.
  - Full app-scheme XCTest passed with parallel testing disabled: 209 tests, 0 failures.
  - `Scripts/verify_codec_fixture_evidence.sh` passed with 90 fixtures and 180 verified transcodes.
  - Release archive/export upload succeeded for `1.0.1 (19)`.
  - Paired iPhone 14 Pro and iPad Pro 12.9-inch (6th generation) install checks both reported `com.taption.encoder` version `1.0.1`, build `19`.
- The current `01.01.00` proof set is tracked in `docs/verification/RELEASE_01.01.00.md` and includes version/build setup, plist lint, focused XCTest, core codec truth checks, local archive creation, archive Info.plist inspection, App Store Connect upload proof, App Store version creation, and localized release-notes proof. The previous `01.00.02` upload proof remains tracked in `docs/verification/RELEASE_01.00.02.md`.
- The latest local post-upload performance pass is tracked in `docs/verification/CODEC_BENCHMARK_2026-07-04.md`: Battery Options expose Battery Saver, Balanced, and Max Performance encoding profiles, and the bundled-codec simulator benchmark exercised all 56 samples in performance mode. This is local Debug simulator proof only, not TestFlight/App Store Connect, real-device install, or App Review proof.

## Product Direction

- Released baseline: `01.00.01` / `1.0.1 (19)` ships the standalone H.265 / HEVC conversion app with fixed H.265 video output, MP4/MOV output containers, file/folder/Photos sources, route-based HW/SW handling, rewarded-save recovery, release assets, and App Store metadata.
- Current release train: `01.01.00` / `1.1.0 (30)` keeps H.265-only output, preserves the standalone encoder scope, and carries the latest queue, source-preserving validation, privacy/ad, multi-file encoding-mode prompt, and Battery Options profile work forward.
- Previous release train: `01.00.02` / `1.0.2 (28)` keeps H.265-only output, preserves the standalone encoder scope, and carries the preview/sample/documentation/save-destination stabilization work forward.
- Final direction: broad practical input coverage with H.265 / HEVC as the only video output codec.
- Output video codec is fixed to H.265. Do not add selectable output video codecs unless the company explicitly changes this policy.
- Routes such as `H.264 -> AV1`, `AV1 -> H.264`, `VP9 -> AV1`, or same-codec re-encode as a non-H.265 output are out of product scope.
- Source and output codec catalogs are intentionally not symmetric: source coverage expands broadly, output video codec remains H.265 only.
- Current implemented output file formats are MP4 and MOV only. Do not advertise or enable AVI, WebM, MKV, or other writable output containers unless the company explicitly changes this policy.
- Advanced output work may add container, resolution, bitrate, quality, frame-rate, and color controls while keeping video output H.265 and the implemented output formats constrained to approved containers.
- Codec implementations must stay route-based and portable through explicit `HW_` and `SW_` core files.
- Non-H.265 video output routes, including `H.264 -> AV1`, `AV1 -> H.264`, `VP9 -> AV1`, and ProRes RAW as an output codec, are unsupported rather than planned.

## Current Codec Implementation Rules

- H.264 input to H.265 output is runnable in the current build. On devices with H.264 decode but without HEVC encode hardware, use the mixed path: hardware decode plus software HEVC encode.
- H.265 / HEVC input to H.265 output is runnable in the current build. On the oldest supported devices without HEVC hardware, use the software fallback path.
- Device-facing codec status must be based on the installed device's route selection, not just the static launch catalog.
- Use the runtime labels `Now(HW)`, `Now(SW)`, `Now(HW/SW)`, `Needs HW`, `Planned`, and `No` consistently in Device Info and Help surfaces.
- Broad FFmpeg-family command plans may remain visible for roadmap coverage, but they are not executable in the current app unless the backend is actually bundled, executable, and license-reviewed.

## Starting Rules

- Check `git status --short --branch` first if this folder becomes a git repo.
- Read this `AGENTS.md` first. For active work, use `docs/planning/ACTION_ITEMS.md`; for product overview, use `docs/overview/README.md`.
- Do not edit `/Users/u_mo_c/Documents/taption` while working in this project unless explicitly asked.
- Keep visible app strings in English.
- Keep `/Users/u_mo_c/Documents/taption_encoder` as the owner path when communicating with Jamini or other agents. Do not reuse Taption main-project handoffs as Taption Encoder proof.
- Port the conversion core narrowly before adding editor, subtitle, monetization, or export UI dependencies.
- When updating release docs, keep proof surfaces separate: tests, fixture evidence, archive/export, TestFlight/App Store Connect state, real-device install, and actual runtime logs are different evidence classes.
- Keep the project root free of development documents except `AGENTS.md`. Store development docs under `docs/` by type, and store completed or stale evidence under `docs/archive/`.

## Documentation Layout

- `AGENTS.md`: root routing file and next-chat handoff source.
- `docs/overview/README.md`: product overview, release summary, and verification commands.
- `docs/planning/ACTION_ITEMS.md`, `docs/planning/DEVELOPMENT_PLAN.md`, `docs/planning/DETAILED_DEVELOPMENT_PLAN.md`: active planning and roadmap documents.
- `docs/planning/COMPLETED_ACTION_ITEMS.md`: completed checklist items moved out of `ACTION_ITEMS.md` so the active list stays focused on remaining work.
- `docs/architecture/APP_ARCHITECTURE.md`: app/module architecture.
- `docs/codecs/`: codec matrices, generated fixture policy, and route simulation docs.
- `docs/verification/`: current verification summaries.
- `docs/agent_communication/`: Jamini communication scripts, briefing, and live handoff area.
- `docs/archive/releases/`: old release closeout notes.
- `docs/archive/reports/`: old build/install/log reports.
- `docs/archive/agent_communication/handoffs/`: completed valid Taption Encoder handoffs and watchdog probes.
- `docs/archive/agent_communication/rejected_context/`: off-project or Taption-main handoffs that must not be treated as Taption Encoder proof.

## Collaboration Rules

- Use polite/formal Korean with the user by default.
- Treat the user as the company representative/CEO and respond as a staff member reporting work, decisions, and blockers.
- Do not use casual Korean speech unless the user explicitly asks for it.

## Taption Source References

- Core transcoder: `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Release/Media/AV1HEVCTranscodingService.swift`
- AV1 UI bridge: `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+AV1Transcoding.swift`
- Media-open prompt path: `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+MediaOpen.swift`
- HEVC policy: `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Beta/Export/BurnedSubtitleVideoEncodingPolicy.swift`
- Codec support checks: `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Release/Media/VideoPlaybackCodecRegistration.swift`

## First Implementation Step

Create a clean encoder module in this project, then migrate only the AV1 detection and HEVC conversion pieces needed for a standalone file-in/file-out workflow.

## Next Chat Handoff

- Continue from `/Users/u_mo_c/Documents/taption_encoder` only.
- Treat `01.01.00` / `1.1.0 (30)` as the current uploaded release train. App Store Connect reported the build `30` package as processing after upload, the `1.1.0` App Store version page exists in `PREPARE_FOR_SUBMISSION` with `MANUAL` release type, and English/Korean What's New text has been filled in. App Review submission, TestFlight availability, processing completion, and public release are separate follow-up states and must not be reported as complete unless explicitly performed and verified.
- The latest post-upload performance work was committed as `72d5df0` (`Add encoding optimization profiles`): Battery Options now expose Battery Saver, Balanced, and Max Performance profiles, Max Performance raises the automatic bitrate budget and aggressive scheduling/resource sampling, and `Scripts/benchmark_bundled_codecs_simulator.sh` records bundled-codec playback/encoding probes. Treat `docs/verification/CODEC_BENCHMARK_2026-07-04.md` as local Debug simulator evidence only, separate from TestFlight/App Store Connect, real-device install, and App Review proof.
- Use `docs/planning/ACTION_ITEMS.md` for active work and `docs/archive/` only for historical evidence.
- Jamini communication must identify the project as Taption Encoder and use this repository's `docs/agent_communication/` scripts and handoff folders.
- Keep proof surfaces separate in reports: code review, tests, fixture evidence, build/archive, TestFlight/App Store Connect upload, device install, runtime logs, and manual UI proof are distinct.
