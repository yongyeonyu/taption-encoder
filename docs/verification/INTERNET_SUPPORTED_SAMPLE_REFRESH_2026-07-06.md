# Internet Supported Sample Refresh - 2026-07-06

## Scope

- Purpose: find internet-sourced samples for currently tracked codec families that are not already present in `TaptionEncoder/TestVideos`, then create a local sample set for follow-up app-side testing.
- Local sample folder: `/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/`.
- Evidence folder: `docs/verification/internet_supported_missing_2026-07-06/`.
- Output policy remains unchanged: Taption Encoder still outputs H.265 / HEVC video only, and implemented output containers remain MP4/MOV only.
- This is local sample acquisition and host-tool verification only. It is not simulator app proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.

`Samples/Downloaded/` is intentionally ignored by git, so the video samples stay local. The tracked TSV files preserve source URL, status, hashes, probe results, and host transcode-probe results.

## Already Excluded

The refresh skipped codec families already covered by bundled files under `TaptionEncoder/TestVideos`, including AV1, VP8/VP9, H.264, H.265, ProRes, MPEG-1/2/4 Visual, H.261/H.263, Theora, RealVideo, RoQ, WMV, Microsoft MPEG-4, Microsoft Video 1, ASUS V1/V2, Flash Video/Flash Screen Video, ZMBV, CLJR, Snow, FFV1, HuffYUV, Ut Video, MagicYUV, DV/DVCPro, CineForm, DNxHD, PNG Video, R10K/R210/V210/V308/V408/V410, Microsoft RLE, QuickTime Graphics, YUV4, Raw Video, Motion JPEG, JPEG 2000, JPEG-LS, Lossless JPEG, Apple Animation, Cinepak, Sorenson Video, Sorenson Video 3, and QuickTime Video.

## Created Local Samples

| Target | Local sample | Source | Probe result |
| --- | --- | --- | --- |
| HEVC-with-alpha candidate | `hevc_with_alpha_layer.mp4` | ByteDance HEVC public test page | HEVC Main, 1280x720 |
| HEVC-with-alpha candidate | `hevc_with_alpha_layer_2.mp4` | ByteDance HEVC public test page | HEVC Main, 496x438 |
| VC-1 raw elementary | `vc1_advanced_profile_2.vc1` | FFmpeg samples archive | VC-1 Advanced Profile, 720x480 |
| QuickTime RPZA | `rpza_1701-D.mov` | FFmpeg samples archive | RPZA, 160x120 |
| AMR-NB video sample | `amr_nb_h263_video.3gp` | FFmpeg AMR-NB source audio plus generated video | H.263 video plus AMR-NB audio |
| xHE-AAC video sample | `xhe_aac_hevc_video.mp4` | Fraunhofer xHE-AAC source audio plus generated H.265 video | H.265 video plus xHE-AAC/USAC audio |
| Y41P video sample | `y41p_from_internet_image.avi` | FFmpeg image sample converted locally | Y41P video plus PCM audio |
| AMR-WB+ negative sample | `amr_wbplus_negative.3gp` | FFmpeg samples archive | 3GP opens, audio codec remains unresolved by local tools |

The two HEVC-with-alpha candidates are kept because the public page labels them as alpha samples, but local FFprobe reports ordinary HEVC Main/yuv420p streams. Treat them as candidates until Apple-side inspection confirms or rejects alpha metadata.

## Host Transcode Probe

The following samples were also checked with short host-side H.265 MP4 and MOV transcode probes:

- `hevc_with_alpha_layer.mp4`: MP4 pass, MOV pass.
- `hevc_with_alpha_layer_2.mp4`: MP4 pass, MOV pass.
- `vc1_advanced_profile_2.vc1`: MP4 pass, MOV pass.
- `rpza_1701-D.mov`: MP4 pass, MOV pass.
- `amr_nb_h263_video.3gp`: MP4 pass, MOV pass.
- `y41p_from_internet_image.avi`: MP4 pass, MOV pass.

`xhe_aac_hevc_video.mp4` was not counted as a host FFmpeg transcode pass because FFmpeg can probe the xHE-AAC stream but local decode remains limited. macOS `afinfo` identifies the audio as `usac`, 48 kHz stereo.

## Follow-Up App-Core Routing

- 2026-07-06 follow-up implementation: the VC-1 raw elementary route is now registered in the current-build software VLC decoder path and live H.265 transcoding registry.
- This follow-up is app-core routing evidence only. It is not simulator sample execution, real-device sample execution, TestFlight/App Store Connect proof, App Review proof, or public release proof.
- The generated fixture policy remains unchanged: `vc1_raw_elementary` stays a skipped real-world-sample-required generated row until the local sample is promoted into a durable fixture policy.

## Blocked Or Deferred

| Target | Status | Reason |
| --- | --- | --- |
| Dolby Vision HEVC | Deferred | Public candidates were found, but the checked MP4 candidate was about 479 MB and was not downloaded while disk space is constrained. |
| ProRes RAW | Deferred | Public candidates were found, but the smallest observed candidate was about 622 MB and still needs storage headroom plus license/use approval. |
| JPEG XL frame sequence | Deferred | This is an image/frame-sequence target rather than a video-file target; no bundled video sample was created in this pass. |
| AMR-WB / AMR-WB+ passing video | Blocked | The available AMR-WB+ sample is useful as a negative sample, but local FFmpeg and Apple tools do not decode it as a passing route. |

## Evidence Files

- `source_manifest.tsv`: internet URL, source, byte count, SHA-256, and blocked/deferred records.
- `sample_results.tsv`: local sample paths and hashes.
- `probe_results.tsv`: FFprobe result summary.
- `transcode_probe_results.tsv`: short host H.265 MP4/MOV probe summary.
