# Taption Encoder

Taption Encoder is a free iOS video encoder app intended to make phone-based conversion simple. The long-term goal is broad video input support, H.265 output through hardware or software codecs, old-device compatibility where practical, background encoding where the OS allows it, and multi-video assembly into one output with lightweight editing.

The first release starts by extracting Taption's AV1 to H.265 conversion path into a focused standalone app. Later releases expand toward "almost any video in, H.265 out" and simple multi-camera merge workflows.

Product path: **AV1 to H.265 first, All to H.265 final.**

## Project

- Xcode project: `TaptionEncoder.xcodeproj`
- Scheme: `TaptionEncoder`
- Bundle identifier: `com.taption.encoder`
- Display name: `Taption Encoder`
- Initial platform: iPhone and iPad portrait only
- Minimum OS: iOS/iPadOS 18.0
- iPad UX: use the same portrait-first flow and centered mobile-width layout as iPhone

## Source Core To Port

The current Taption AV1 to H.265 conversion owner path starts from:

- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Release/Media/AV1HEVCTranscodingService.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+AV1Transcoding.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+MediaOpen.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Beta/Export/BurnedSubtitleVideoEncodingPolicy.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Release/Media/VideoPlaybackCodecRegistration.swift`

Next implementation pass should isolate the media conversion core before importing broader editor or subtitle-export code.

## Planning

- App architecture, product plan, UI design, and roadmap: [`docs/APP_ARCHITECTURE.md`](docs/APP_ARCHITECTURE.md)
- Detailed execution plan from launch to completed product: [`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md)
- Phase-by-phase implementation guide for app development: [`docs/DETAILED_DEVELOPMENT_PLAN.md`](docs/DETAILED_DEVELOPMENT_PLAN.md)
- Release action items and launch blockers: [`docs/ACTION_ITEMS.md`](docs/ACTION_ITEMS.md)

## MVP Scope

- Input: AV1 video
- Output: H.265 video in an `.mp4` container
- Default output: preserve source-like resolution, frame rate, orientation, color characteristics, audio timing, and visual quality whenever technically possible
- Device orientation: iPhone and iPad portrait only
- Shared UX: iPad uses the same main-screen flow and control density as iPhone
- Codec path: the app automatically uses hardware where supported and falls back to software when needed; the UI only displays the actual path.
- Sources: Files and Photos
- Photos output: save as a new Photos asset
- Flow: select a video, inspect and show video info, start encoding only after the user taps Start, allow cancellation during encoding, then save after rewarded ad completion
- Rewarded save failure: keep the completed temporary output and let the user retry later without re-encoding
- Progress: show progress bar, percentage, elapsed time, and estimated time remaining when enough progress samples are available
- Background status: on iOS/iPadOS 26 or later, let users opt into background encoding; on iOS/iPadOS 18-25, tell users to keep the app open for reliable encoding
- Save path: create a sibling output named with `_taption` appended to the original filename
- Safety: warn before output when available storage is insufficient
- Ads: non-personalized AdMob banner on the main screen and AdMob rewarded ad before final save

## Implementation Status

- Phase 0 foundation is implemented as of 2026-06-15.
- The app now has `AppEnvironment`, `FeatureFlags`, `AppConfiguration`, the `Features/Home` screen shell, protocol boundaries, and real AVFoundation services for the first AV1-to-H.265 path.
- Phase 1 fake UX/state machine is implemented as of 2026-06-15.
- Files entry now runs a real `importing -> inspecting -> storage checking -> encoding -> rewarded save -> completed` flow for AV1 input, with AVFoundation progress, software AV1 decode fallback, percentage, elapsed time, estimated remaining time, cancellation, reset, and pending-save recovery surfaces.
- Files output saves after the rewarded-save gate to the same folder as the source file, using `_taption` before the `.mp4` extension. Photos import/save, AdMob, audio preservation in the software fallback path, and broad software codec support remain later-phase implementation work.

## Encoder Roadmap

Output remains H.265 first. Future releases should expand input coverage without tying the app to Taption editor, subtitle, or editor-export UI dependencies.

### Final Product Goal

- Product path: AV1 to H.265 first, All to H.265 final.
- Convert almost any practical user video input into H.265.
- Use hardware codecs when available and software codecs when hardware is unavailable or unsupported.
- Evaluate FFmpeg-family software codec options and use the broadest codec support that is safe for App Store review, licensing, binary size, and performance.
- Support older devices where performance and OS APIs allow it.
- Let users choose background encoding on iOS/iPadOS 26 or later; on earlier versions, guide users to keep the app open for reliable encoding.
- Merge multiple videos into one H.265 output, even when the source containers/codecs/cameras differ.
- Preserve the source look by default.
- Add advanced controls over output container, size, frame rate, bitrate, quality, and color mapping after the simple flow is stable.
- Advanced output format means H.265 container choice only, such as `.mp4` and `.mov`.
- Add lightweight edit tools for trim, cut, shorten, reorder, and clip positioning before merge/export.

### Input Codec Roadmap

- AV1
- H.264 / AVC
- H.265 / HEVC
- VP9
- VP8
- MPEG-2 Video
- ProRes
- Other practical user video codecs supported by the selected software codec backend
- App binary size may increase if broad input support requires bundled software codec components.

### Input Container Roadmap

- MP4 (`.mp4`)
- QuickTime Movie (`.mov`)
- M4V (`.m4v`)
- WebM (`.webm`)
- Matroska (`.mkv`)
- AVI (`.avi`)
- MPEG transport streams (`.ts`, `.mts`, `.m2ts`)
- MXF (`.mxf`)

### Future Encoding Options

These options should be represented in the architecture before they are exposed in the UI:

- Output format presets, with H.265 as the first fixed output
- Resolution changes
- Frame-rate changes
- Quality presets
- Bitrate controls
- Color mapping controls
- Multi-file merge into a single output video
- Lightweight editing before merge/export
- Batch conversion

### Merge And Edit Roadmap

- Merge multiple videos into one H.265 output.
- Allow sources from different cameras, codecs, and containers.
- Use a common output canvas when resolutions match or after user-selected normalization.
- Use `.fcpxml` as the native project save format from the first project feature.
- Add a future `.fcpxmld` project bundle for thumbnails, proxies, and richer metadata when the single-document workflow is stable.
- Allow future managed `.fcpxmld` projects to copy original media when the user chooses that mode.
- Reuse Taption's interaction ideas as Encoder-specific video editing concepts:
  - touch widget controls
  - slice/split interactions
  - segment-based editing, with video segments replacing subtitle segments
- Add lightweight editing before merge/export:
  - trim
  - cut
  - split
  - shorten
  - reorder
  - clip position on the output canvas
- When frame rate, color, or audio settings differ, show selectable normalization options based on the detected source values.
- If values are effectively equivalent, auto-pick the closest recommended value and show it in the merge summary.
