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

- Release `01.00.02` maps to Apple marketing version `1.0.2` and build `20`.
- Release `01.00.02` archive/export/upload succeeded on 2026-06-29, and App Store Connect reported the uploaded package is processing. App Review, processing completion, TestFlight availability, and public App Store availability are separate states and are not verified here.
- Release `01.00.01` remains the archived shipped baseline. The `01.00.01` release train used commit `f5af6b3` (`Prepare Taption Encoder 1.0.1 build 19`).
- App Store Connect/TestFlight upload proof is separate from App Review or store-processing status. Do not report processing, review, or public availability as complete unless that exact state was verified or reported by the company.
- The last release proof set for `01.00.01` included:
  - `Scripts/run_core_codec_truth_checks.sh` passed.
  - Full app-scheme XCTest passed with parallel testing disabled: 209 tests, 0 failures.
  - `Scripts/verify_codec_fixture_evidence.sh` passed with 90 fixtures and 180 verified transcodes.
  - Release archive/export upload succeeded for `1.0.1 (19)`.
  - Paired iPhone 14 Pro and iPad Pro 12.9-inch (6th generation) install checks both reported `com.taption.encoder` version `1.0.1`, build `19`.
- The current `01.00.02` proof set is tracked in `docs/verification/RELEASE_01.00.02.md` and includes document reorganization, preview/sample stabilization, focused XCTest, full app-scheme XCTest, bundled sample verification, core codec truth checks, release archive, and App Store Connect upload proof.

## Product Direction

- Released baseline: `01.00.01` / `1.0.1 (19)` ships the standalone H.265 / HEVC conversion app with fixed H.265 video output, MP4/MOV output containers, file/folder/Photos sources, route-based HW/SW handling, rewarded-save recovery, release assets, and App Store metadata.
- Current release train: `01.00.02` / `1.0.2 (20)` keeps H.265-only output, preserves the standalone encoder scope, and carries the preview/sample/documentation stabilization work forward.
- Next milestone: stabilize `01.00.02` feedback and continue broad practical video-input execution toward H.265-only output.
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
- Treat `01.00.02` / `1.0.2 (20)` as the current uploaded release train; verify processing/TestFlight/App Review/public availability separately before reporting those states.
- Use `docs/planning/ACTION_ITEMS.md` for active work and `docs/archive/` only for historical evidence.
- Jamini communication must identify the project as Taption Encoder and use this repository's `docs/agent_communication/` scripts and handoff folders.
- Keep proof surfaces separate in reports: code review, tests, fixture evidence, build/archive, TestFlight/App Store Connect upload, device install, runtime logs, and manual UI proof are distinct.
