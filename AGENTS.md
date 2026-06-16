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
- Final direction: universal all-to-all codec conversion.
- Treat routes such as `H.264 -> AV1` and `AV1 -> H.264` as equally valid planned routes.
- Keep source and output codec catalogs symmetric unless a codec is intentionally excluded from the universal product contract.
- H.265 is the recommended default output, not a permanent architecture limit.
- Codec implementations must stay route-based and portable through explicit `HW_` and `SW_` core files.

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
