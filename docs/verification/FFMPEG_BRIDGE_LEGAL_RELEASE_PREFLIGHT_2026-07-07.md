# FFmpeg Bridge Legal And Release Preflight - 2026-07-07

## Scope

- Purpose: review the newly vendored VC-1 raw/Y41P LGPL FFmpeg-family decode bridge for legal/license/EULA/source-availability, HEVC distribution, App Review, release archive size, device proof, and AMR-WB+ separation.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Current bridge proof: `docs/verification/VC1_Y41P_BUNDLED_FFMPEG_DECODE_BRIDGE_2026-07-07.md`.
- Product constraints remain unchanged: output video codec is H.265 / HEVC only, and writable output containers remain MP4/MOV only.

This is an engineering preflight. It is not legal advice, not formal counsel approval, not App Review approval, not TestFlight/App Store Connect proof, not public-release proof, and not iPhone/older-device runtime proof.

## Sources Checked

- FFmpeg legal and license compliance checklist: https://www.ffmpeg.org/legal.html
- GNU LGPL 2.1 text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
- Apple App Review overview: https://developer.apple.com/distribute/app-review/
- Apple App Store Review Guidelines, section 2.5.2 self-contained app rule: https://developer.apple.com/app-store/review/guidelines/
- VCL Advance / Via Licensing Alliance HEVC/VVC program page: https://www.via-la.com/licensing-programs/hevc-vvc/
- VoiceAge AMR-WB+ page: https://voiceage.com/AMR-WBplus.html
- 3GPP TS 26.290 AMR-WB+ specification page: https://www.3gpp.org/dynareport/26290.htm

## Legal, License, EULA, And Source Availability Preflight

Current engineering-pass items:

- The bridge is pinned to FFmpeg 8.1.1 source with SHA-256 recorded in the bridge proof.
- The configure surface disables GPL and nonfree paths, disables programs, disables network/autodetect, enables only `avformat`, `avcodec`, `avutil`, `swscale`, `file`, `vc1`, `avi`, `vc1`, and the required decoders.
- The app bundles an open-source notice at `TaptionEncoder/OpenSourceNotices/FFmpeg-LGPL-Decode-Bridge.txt`.
- The app does not bundle an FFmpeg command-line executable and does not use runtime-downloaded codec plugins.

Open formal-release blockers:

- The current bridge is built as a static XCFramework with `--disable-shared --enable-static`. The FFmpeg legal checklist identifies dynamic linking as the easiest LGPL compliance path, so this static integration needs counsel approval or a revised compliance strategy before App Store release promotion.
- A final corresponding-source delivery package is still required. The app notice pins the official FFmpeg release URL and SHA-256, and local wrapper sources are present under `Vendor/FFmpegLGPLDecodeBridge/Sources`, but there is not yet a release-facing hosted source bundle, exact source mirror, object/relinking package, or `changes.diff` package approved for distribution.
- Final EULA text must not conflict with LGPL-required reverse-engineering or relinking/debugging rights for modified LGPL components.
- Formal enabled-component review must confirm no GPL, nonfree, or incompatible external libraries entered the distributed binary.

Decision: do not promote the bundled FFmpeg bridge into a formal App Store release claim until counsel signs off on static-link LGPL compliance or the bridge is changed to a counsel-approved dynamic/relinkable distribution path.

## HEVC Distribution Preflight

Taption Encoder continues to write H.265 / HEVC output through Apple AVFoundation/VideoToolbox writer paths, not through FFmpeg HEVC encoding. The FFmpeg bridge only decodes selected legacy inputs into frames before Taption Encoder writes HEVC MP4/MOV.

HEVC distribution still remains a separate patent/licensing review surface. The VCL Advance / Via Licensing Alliance HEVC/VVC program page is the current public patent-pool review starting point, but this pass does not determine Taption's royalty or license obligations.

Decision: HEVC output remains the product policy, but formal HEVC distribution/IPR approval remains open.

## App Review Preflight

Engineering App Review posture:

- The bridge is part of the app bundle/build graph, not downloaded after review.
- No codec plugin, script, executable, or external tool is installed or executed from outside the reviewed app bundle.
- No new output codec is introduced. Output remains H.265 / HEVC video in MP4/MOV only.
- The app archive includes the FFmpeg notice resource alongside the other bundled notices.

Suggested App Review note if this bridge is included in a submitted build:

```text
Taption Encoder converts user-selected local videos to H.265/HEVC MP4 or MOV. The app includes all codec bridge code used by this build in the reviewed app bundle and does not download codec plugins, execute external tools, or change codec functionality after review. The bundled Open Source Notices include the FFmpeg LGPL decode bridge used for selected legacy input decoding. H.265/HEVC output writing uses Apple's AVFoundation/VideoToolbox APIs.
```

Decision: the self-contained bundle posture is acceptable for engineering preflight, but App Review submission/approval was not performed.

## Release Archive Size Review

Current commit:

```text
commit: f8e8200 Add bundled LGPL FFmpeg decode bridge
archive: build/FFmpegBridgeReview-2026-07-07/TaptionEncoder.xcarchive
command: xcodebuild archive -project TaptionEncoder.xcodeproj -scheme TaptionEncoder -configuration Release -destination 'generic/platform=iOS' -archivePath build/FFmpegBridgeReview-2026-07-07/TaptionEncoder.xcarchive COMPILER_INDEX_STORE_ENABLE=NO SKIP_INSTALL=NO
result: ** ARCHIVE SUCCEEDED **
```

Baseline commit:

```text
commit: 9729328 Select VC-1 Y41P backend runner path
archive: /tmp/taption_encoder_pre_bridge_size/build/PreBridgeSizeReview-2026-07-07/TaptionEncoder.xcarchive
command: xcodebuild archive -project TaptionEncoder.xcodeproj -scheme TaptionEncoder -configuration Release -destination 'generic/platform=iOS' -archivePath build/PreBridgeSizeReview-2026-07-07/TaptionEncoder.xcarchive COMPILER_INDEX_STORE_ENABLE=NO SKIP_INSTALL=NO
result: ** ARCHIVE SUCCEEDED **
```

Size comparison:

| Surface | Baseline `9729328` | Current `f8e8200` | Delta |
| --- | ---: | ---: | ---: |
| `.xcarchive` | 119 MB | 119 MB | 0 MB at `du -sh` precision |
| `.app` bundle | 91 MB | 91 MB | 0 MB at `du -sh` precision |
| Main executable | 39,348,096 bytes | 39,381,456 bytes | +33,360 bytes |
| `OpenSourceNotices` | 28 KB | 32 KB | +4 KB |
| `Frameworks` | 132 KB | 132 KB | 0 KB |
| `PlugIns` | 3.4 MB | 3.4 MB | 0 MB |
| `dSYMs` | 26 MB | 26 MB | 0 MB |

Largest current app bundle entries:

| Entry | Size |
| --- | ---: |
| `TestVideos` | 42 MB |
| `Taption Encoder` executable | 38 MB |
| `Assets.car` | 4.7 MB |
| `PlugIns` | 3.4 MB |
| `SampleThumbnails` | 3.1 MB |

Vendored bridge artifact:

```text
Vendor/FFmpegLGPLDecodeBridge/TaptionFFmpegDecodeBridge.xcframework: 8.6 MB
```

Archive inspection notes:

- `otool -L` did not show FFmpeg/libav dynamic dependencies in the app executable.
- The app bundle did not contain a separate FFmpeg framework or static archive file; the only app-bundle file matching FFmpeg was `OpenSourceNotices/FFmpeg-LGPL-Decode-Bridge.txt`.
- The archive used `Release` configuration but Apple Development signing. This is a local release-configuration size preflight only, not an App Store distribution export, not notarized/signing finality, and not upload proof.
- No IPA/export size was produced in this pass.

Decision: the current bridge has minimal measured archive-size impact in this Release archive preflight. Final App Store export/IPA size and App Store Connect processing must be reviewed separately before submission.

## Device Runtime Proof Status

Current device availability:

```text
iPad Pro (12.9-inch) (6th generation) (iPad14,6): available (paired)
iPhone 14 Pro (iPhone15,2): unavailable
older device: not connected
```

No iPhone runtime proof, no older-device thermal/battery/memory/runtime threshold proof, and no real-device FFmpeg-bridge VC-1/Y41P execution proof were collected in this pass.

Decision: device proof remains open and must be collected separately from this legal/App Review/archive-size preflight.

## AMR-WB+ Separation

AMR-WB+ remains separate from the VC-1 raw/Y41P bridge decision.

- 3GPP TS 26.290 identifies AMR-WB+ transcoding functions.
- VoiceAge publishes AMR-WB+ licensing/IPR contact information.
- The local AMR-WB+ reference-code path produced positive host-side `sawp` samples, but the reference code is not bundled, not product-reviewed, and not approved for App Store distribution.
- Local FFmpeg still cannot decode the `sawp` AMR-WB+ audio track.
- The current VC-1 raw/Y41P bridge does not prove AMR-WB+ decode.

Decision: keep AMR-WB+ unsupported/planned until a separate backend, patent/IPR, source-license, EULA, App Review, and app-side execution proof path is approved.

## Outcome

- Engineering preflight completed for the VC-1 raw/Y41P bridge legal/App Review/release-size surface.
- Formal legal/license/EULA/source-availability/HEVC approval remains open.
- App Review submission/approval remains open.
- Current release archive size impact is low in local measurement, but final App Store export/IPA size remains open.
- iPhone and older-device runtime/thermal/battery/memory proof remains uncollected because the iPhone was unavailable and no older device was connected.
- AMR-WB+ remains a separate backend/IPR item.
