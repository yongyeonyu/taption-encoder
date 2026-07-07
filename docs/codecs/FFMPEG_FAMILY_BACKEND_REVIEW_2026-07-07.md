# FFmpeg-Family Broad Codec Backend Review - 2026-07-07

## Scope

This review covers the bundled broad software codec backend needed before VC-1 raw, Y41P, AMR-WB+, and other currently planned routes can become executable inside Taption Encoder. AMR-WB has separate current-build proof for the bundled H.263/3GP sample on the explicitly supported AAC/MP4, PCM/MOV, and ALAC/MOV paths. Vorbis has separate current-build proof for the bundled Theora/Vorbis sample on the explicitly supported PCM/MOV and ALAC/MOV paths through the bundled software VLC audio route. AAC and MP3 also have separate current-build proof for bundled QuickTime Video and Flash Video samples on the explicitly supported PCM/MOV and ALAC/MOV paths through Apple-native audio transcode routes, and AC3/EAC3 have separate current-build proof through bundled H.264 Dolby samples on the requested software path.

This is engineering review evidence only. It is not legal advice, not counsel approval, not App Review approval, not simulator/runtime proof, not real-device proof, and not a TestFlight/App Store Connect proof surface.

Taption Encoder product constraints remain unchanged:

- Output video codec stays fixed to H.265 / HEVC.
- Writable output containers stay limited to MP4 and MOV.
- Non-H.265 output routes remain unsupported.

## Sources Checked

- FFmpeg legal and license checklist: https://www.ffmpeg.org/legal.html
- FFmpeg external-library documentation: https://www.ffmpeg.org/general.html
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- GNU LGPL 2.1 text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
- VoiceAge AMR-WB+ licensing page: https://voiceage.com/AMR-WBplus.html
- 3GPP 26-series specification index: https://www.3gpp.org/dynareport?code=26-series.htm
- x265 licensing summary: https://www.x265.org/

## Current Decision

Select a source-built LGPL FFmpeg-family decode bridge as the backend shape for VC-1 raw and Y41P, but keep the FFmpeg-family backend planning-only in the current app. Do not promote VC-1 raw, Y41P, or broad AMR routes to executable app-side paths until all backend readiness gates close with separate proof.

The safest App Store candidate is an embedded, bundle-contained, license-reviewed FFmpeg-family library profile used primarily for broad demux/decode, feeding Taption Encoder's existing H.265 MP4/MOV writer path where possible. A downloaded ffmpeg binary, side-loaded codec module, plugin-style runtime expansion, or external executable dependency is not acceptable for the App Store path.

## Findings

| Gate | Status | Review finding | Required proof before closing |
| --- | --- | --- | --- |
| License review | Open | FFmpeg can stay on the LGPL path only with a reviewed configuration that avoids GPL and nonfree parts. The current command planner names GPL-sensitive encoders such as `libx265` and `libx264`; these cannot be treated as proprietary App Store-safe without a commercial/source-release decision. | Final configure line, enabled library map, source archive, changes diff, notices/EULA review, HEVC patent/distribution review. |
| App Store policy review | Open | Apple requires apps to remain self-contained and not download/install/execute code that changes functionality. Broad codec execution must ship in the reviewed bundle and operate offline on user-selected files. | App Review notes, no runtime code download path, no plugin/module install path, third-party SDK review. |
| iOS packaging integration | Open | The existing `SW_FFmpegCommandPlan` is a planning boundary. iOS execution needs an in-process runner or equivalent embedded library bridge, not an external command-line binary assumption. | Xcode package/framework integration, runner proof, sandboxed Files/Folder/Photos source access proof. |
| Binary size budget | Open | Broad demux/decode support can significantly increase app size. | Archive/export size diff, enabled component list, launch/import latency comparison. |
| Open-source notice generation | Open | Shipping the backend requires final notice resources for FFmpeg and each enabled external library. | Bundled notice files, source download URL, exact build/config text, release-notice tests. |
| Fixture transcode proof | Open | Host FFmpeg proof and command-plan proof are not enough for VC-1 raw or Y41P execution. | App-side simulator fixture/sample transcodes to H.265 MP4/MOV with output verification. |
| Audio signal proof | Open | AMR-WB now has bundled real-device AAC/MP4 plus PCM/MOV and ALAC/MOV proof, Opus has AAC/PCM/ALAC proof through bundled Theora, Vorbis has PCM/MOV plus ALAC/MOV proof through bundled Theora/Vorbis, MP3 has PCM/MOV plus ALAC/MOV proof through bundled Flash Video, AAC has PCM/MOV plus ALAC/MOV proof through bundled QuickTime Video, and AC3/EAC3 have PCM/MOV plus ALAC/MOV proof through bundled H.264 Dolby samples on the requested software path. AMR-WB+ now has host/reference-code positive sample proof plus a host-side H.263 video-wrapper path, but no bundled decoder/backend or app-side audible-signal proof. | Bundled/license-reviewed AMR-WB+ decoder proof or explicit unsupported decision, AAC output proof for MP4/MOV, non-AAC route proof where explicitly supported. |
| Old-device performance proof | Open | Broad software routes may stress heat, memory, battery, and runtime on older devices. | Real-device runtime encode proof with thermal/battery/memory/ETA warning observations. |

## App-Store-Safe Candidate Shape

Preferred next architecture:

1. Build or vendor a minimal FFmpeg-family library profile with GPL and nonfree features disabled unless the company explicitly chooses a compatible commercial/source-release path.
2. Use the backend for broad container demux and source decode, especially VC-1 raw and Y41P, while preserving Taption Encoder's H.265-only output policy.
3. Prefer Taption Encoder's current AVFoundation/VideoToolbox H.265 writer path for output where practical.
4. If software HEVC encode is still required for old hardware, resolve `libx265` licensing separately before any proprietary App Store binary ships.
5. Keep MP4/MOV as the only writable output containers.
6. Attach source, notices, build flags, fixture proof, binary-size proof, and real-device performance proof before setting the backend executable.

Rejected paths for this product:

- Downloading or side-loading an ffmpeg binary after review.
- Shipping GPL/nonfree encoder combinations as a closed-source proprietary App Store binary without a company-approved license/source-release decision.
- Promoting command-plan-only routes to current executable status.
- Adding non-H.265 output codecs or writable output containers beyond MP4/MOV as part of this backend.

## Impact On VC-1 Raw And Y41P

VC-1 raw and Y41P stay planned routes. The review clarifies the backend path they need, but it does not make either sample executable.

Next proof needed for those codecs:

1. Bundle or inject a reviewed app-side backend runner in a test build.
2. Execute the ignored local VC-1 raw and Y41P samples through the app path.
3. Verify H.265 MP4/MOV output, duration, frame decode, and source handling.
4. Keep simulator proof separate from real-device runtime proof.

The focused 2026-07-07 follow-up decision is recorded in `docs/verification/VC1_Y41P_BACKEND_DECISION_2026-07-07.md`: source-built LGPL FFmpeg-family decode bridge was selected as the backend shape, archived/prebuilt FFmpegKit and downloaded codec/plugin paths were rejected, host FFmpeg sanity probes passed for both samples, and app-side fake-runner contract proof was added. This does not close real bundled decoder execution, legal, App Review, binary-size, notice, or old-device gates.

## AMR-WB+ Follow-Up

AMR-WB+ has a different backend risk profile from VC-1 raw and Y41P:

- The local reference-code pass generated positive `sawp` audio-only samples and a later host-side H.263 video-wrapper sample.
- Local FFmpeg can probe `sawp` but still cannot decode it in the current build.
- 3GPP publishes AMR-WB+ reference-code specifications in the 26-series, and VoiceAge lists AMR-WB+ licensing contact information. That makes AMR-WB+ a separate patent/IPR/source-license review item before any reference-code-derived app dependency can be considered.
- Do not assume a future FFmpeg-family broad video backend covers AMR-WB+ unless the selected backend actually decodes `sawp` in the iOS app build.

Next AMR-WB+ proof needed:

1. Decide whether AMR-WB+ is in scope after legal/license review.
2. If in scope, choose a bundled decoder/backend that is license-reviewed and App Store-safe.
3. Run the ignored `amr_wbplus_h263_video_reference.3gp` wrapper through app-side inspection and H.265 MP4/MOV execution.
4. Verify audible output separately from video decode, and keep host/reference-code proof separate from app runtime proof.
