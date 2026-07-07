# AMR-WB+ Backend And Wrapper Review - 2026-07-07

## Scope

- Purpose: follow up the AMR-WB+ reference sample proof with backend/license review and a local video-wrapper sample path check.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Product constraints remain unchanged: Taption Encoder outputs H.265 / HEVC video only, and writable output containers remain MP4/MOV only.

This is host-side sample/container proof plus engineering review evidence. It is not legal advice, not counsel approval, not App Review approval, not app-side execution proof, not simulator XCTest proof, not real-device proof, not TestFlight/App Store Connect proof, and not public-release proof.

## Sources Checked

- FFmpeg legal and license checklist: https://www.ffmpeg.org/legal.html
- GNU LGPL 2.1 text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
- Apple App Review Guidelines, section 2.5.2: https://developer.apple.com/app-store/review/guidelines/
- VoiceAge AMR-WB+ licensing page: https://voiceage.com/AMR-WBplus.html
- 3GPP 26-series specification index: https://www.3gpp.org/dynareport?code=26-series.htm

## Backend Review

AMR-WB+ cannot be promoted to an app-side executable route in the current build.

The reference-code path generated and decoded positive `sawp` samples on the host, but that toolchain is not product-reviewed, not bundled, and not approved as an App Store dependency. 3GPP lists AMR-WB+ transcoding/reference-code specifications in the 26-series, while VoiceAge lists AMR-WB+ licensing contact information. That means AMR-WB+ needs a separate patent/IPR and source-license review before any reference-code-derived decoder is considered for the app.

The FFmpeg-family path also remains gated. FFmpeg can only stay on an LGPL route with a reviewed non-GPL/nonfree configuration, source availability, notices, EULA/reverse-engineering compatibility, and enabled-library review. App Store policy also requires the backend to be self-contained in the reviewed bundle; a downloaded codec, side-loaded module, or external executable is not acceptable.

Practical decision:

- VC-1 raw and Y41P remain best served by a minimal bundled FFmpeg-family or equivalent demux/decode backend after license/App Store review.
- AMR-WB+ should not be assumed covered by that same backend unless the selected backend actually decodes `sawp` in the app build.
- If AMR-WB+ requires 3GPP/reference-code integration, treat it as a separate dependency review from the broad FFmpeg-family video backend.

## Video-Wrapper Sample Path

Local ignored input artifacts used:

```text
Samples/Downloaded/internet_supported_missing_2026-07-07/sample_videos/amr_wb_h263_video.3gp
Samples/Downloaded/internet_supported_missing_2026-07-07/sample_audio/amr_wbplus_reference_stereo.3gp
```

FFmpeg could not mux `sawp` directly because it sees the codec as `none`, so the wrapper was created by atom-level 3GP merging:

- Keep the H.263 video track and original chunk offsets from the existing AMR-WB/H.263 3GP sample.
- Append the AMR-WB+ `sawp` audio payload from the reference stereo sample into the combined `mdat`.
- Add the AMR-WB+ audio `trak` to the video file's `moov`.
- Update track IDs, AMR-WB+ chunk offsets, movie duration, and AMR-WB+ edit-list duration.

Generated ignored wrapper:

```text
Samples/Downloaded/internet_supported_missing_2026-07-07/sample_videos/amr_wbplus_h263_video_reference.3gp
```

Wrapper hash and size:

```text
size: 158062 bytes
sha256: dc3ea89e78213d2905f387ad99ebececfa7e4a6b00838e7ba654a66ac6f4ecfc
```

## Probe Results

`ffprobe` result:

- Container: QuickTime / MOV family, `3gp4` brand.
- Stream 0: H.263 video, `s263`, 176x144, 15 fps, 3.000000s, 45 frames.
- Stream 1: AMR-WB+ audio sample entry, `sawp`, 6464 Hz metadata, 2 channels metadata, 4.880000s, 61 frames.
- Format duration: 4.880000s.

Decode result:

```text
ffmpeg -i amr_wbplus_h263_video_reference.3gp -map 0:v:0 -frames:v 1 -f null -
```

- Result: pass, video-only decode exit 0.

Full decode result:

```text
ffmpeg -i amr_wbplus_h263_video_reference.3gp -f null -
```

- Result: fail, exit 234.
- Error: `Decoding requested, but no decoder found for: none`.

## Real-Device Attempt Boundary

An iPhone 14 Pro Debug XCTest run was attempted for the existing real-device Theora/AMR-WB bundled sample proof:

```sh
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS,id=00008120-00092C3E14F0201E' \
  -derivedDataPath /tmp/taption_encoder_iphone_runtime_dd \
  -resultBundlePath /tmp/taption_encoder_iphone_runtime_result.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testRealDeviceBundledTheoraOpusSampleEncodesHEVCWithAACAudio \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testRealDeviceBundledAMRWBH263SampleEncodesHEVCWithAACAudio
```

Outcome: build progressed to the test launch phase, but Xcode blocked on `Unlock iPhone to Continue` and the run was interrupted. `xcresulttool` could not read `/tmp/taption_encoder_iphone_runtime_result.xcresult` because the interrupted result bundle did not contain `Info.plist`. This is not iPhone runtime proof.

Connected devices observed in this pass:

- iPhone 14 Pro, `iPhone15,2`, destination id `00008120-00092C3E14F0201E`.
- iPad Pro 12.9-inch 6th generation, `iPad14,6`, destination id `00008112-000964980E45401E`.

No older physical device was connected, so older-device thermal/battery/memory/runtime threshold proof was not collected.

## Outcome

- AMR-WB+ now has a host-side video-wrapper sample path in addition to audio-only reference-code positive sample proof.
- The wrapper is useful for future app-side inspection/backend testing, but it is not bundled and it does not prove current app execution.
- Current FFmpeg cannot decode the AMR-WB+ `sawp` track, so app-side execution remains blocked on a bundled, license-reviewed decoder/backend or an explicit unsupported decision.
- VC-1 raw and Y41P remain planned routes pending the same bundled broad backend review tracked in `docs/codecs/FFMPEG_FAMILY_BACKEND_REVIEW_2026-07-07.md`.
- iPhone runtime proof and older-device threshold proof remain separate follow-ups.
