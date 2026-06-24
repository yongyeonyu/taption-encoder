# AGENTS.md

## Project

- Product: Taption Encoder
- Path: `/Users/u_mo_c/Documents/taption_encoder`
- Xcode project: `TaptionEncoder.xcodeproj`
- Scheme: `TaptionEncoder`
- Bundle id: `com.taption.encoder`

## Intent

This project is the standalone app shell for Taption's AV1 to H.265 conversion feature. It should stay separate from the main Taption editor unless a file is intentionally ported.

## Product Direction

- First release: AV1 to H.265.
- Next milestone: broad practical video inputs to H.265.
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
- Do not edit `/Users/u_mo_c/Documents/taption` while working in this project unless explicitly asked.
- Keep visible app strings in English.
- Port the conversion core narrowly before adding editor, subtitle, monetization, or export UI dependencies.

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
