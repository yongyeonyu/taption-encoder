# Codec Sample Acquisition Proof - 2026-07-06

## Scope

- Purpose: acquire currently missing practical codec samples and run host-side decode/transcode probes before app-side broad backend work.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Local tools: FFmpeg 8.1.1, `ffprobe`, macOS `afinfo`, and macOS `afconvert`.
- Output probe policy: video output remains H.265 / HEVC only, and only MP4/MOV containers were tested.
- This is local host-side sample/tool evidence only. It is not simulator app proof, real-device encode/playback proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.

## Evidence Files

Raw TSV evidence is checked in under:

```text
docs/verification/codec_sample_acquisition_2026-07-06/
```

- `source_discovery.tsv`
- `download_results.tsv`
- `probe_summary.tsv`
- `transcode_results.tsv`
- `apple_audio_results.tsv`

Temporary downloaded samples and generated outputs were kept under ignored `build/codec-sample-acquisition-2026-07-06/` during the run and are not product fixtures.

## Source Discovery

| Codec family | Sample | Source | Result |
| --- | --- | --- | --- |
| Theora | `746-theora-vorbis-sample.ogg` | FFmpeg samples archive | Selected, downloaded |
| AMR-NB | `sample2.amr` | FFmpeg samples archive | Selected, downloaded |
| AMR-WB+ | `amr-wb+_encoded.3gp` | FFmpeg samples archive | Selected, downloaded |
| xHE-AAC | `noise-xhe-aac-mono.mp4` | Chromium media test data | Selected, downloaded and base64-decoded |
| xHE-AAC | `Sintel_24kbps_rap5s.mp4` | Fraunhofer IIS demo content | Selected, downloaded |
| VC-1 raw | `advanced_profile_2.vc1` | FFmpeg samples archive | Selected, downloaded |
| ProRes RAW | C500 Mark II / downloadable public candidates | Daejeon Chronicles / FilmplusGear | Located but not downloaded; observed candidates were about 622 MB to 2 GB, so this stayed blocked on storage and license/use approval |

## Download And Probe Summary

| Sample | Download | Probe | Key stream result |
| --- | --- | --- | --- |
| `theora_roundup_746` | pass, 324,256 bytes | pass | Ogg with Theora video 304x304 and Vorbis audio |
| `amr_nb_sample2` | pass, 2,840 bytes | pass | AMR-NB audio, 8 kHz |
| `amr_wbplus_3gp` | pass, 6,432 bytes | partial | 3GP container opened, audio codec unresolved as `sawp` / unknown |
| `xhe_aac_chromium_mono` | pass, 11,592 bytes | FFmpeg fail, Apple `afinfo` pass | `afinfo` reports USAC / xHE-AAC-style audio, 29.4 kHz mono |
| `xhe_aac_fraunhofer_sintel_24k` | pass, 2,808,426 bytes | pass | MP4 with xHE-AAC / USAC, 48 kHz stereo |
| `vc1_advanced_profile_2` | pass, 700,252 bytes | pass | Raw VC-1 Advanced Profile video, 720x480 |

## Host H.265 MP4/MOV Transcode Summary

These are host FFmpeg probes only. Audio-only samples used a generated test pattern video plus source audio to verify audio decode into H.265 MP4/MOV outputs.

| Sample | MP4 | MOV | Notes |
| --- | --- | --- | --- |
| `theora_roundup_746` | pass | pass | Theora/Vorbis to H.265/AAC succeeded |
| `amr_nb_sample2` | pass | pass | AMR-NB audio decode plus generated H.265 video succeeded |
| `amr_wbplus_3gp` | fail | fail | FFmpeg could not resolve/decode the `sawp` audio stream |
| `xhe_aac_chromium_mono` | fail | fail | FFmpeg failed with invalid AAC sampling-rate index |
| `xhe_aac_fraunhofer_sintel_24k` | fail | fail | FFmpeg probed xHE-AAC but failed audio decode |
| `vc1_advanced_profile_2` | pass | pass | Raw VC-1 to H.265 succeeded with `-f vc1` input |

## Apple Audio Stack Summary

| Sample | `afinfo` | `afconvert` to AAC | Notes |
| --- | --- | --- | --- |
| `amr_nb_sample2` | pass | fail | Apple stack identifies AMR-NB but `afconvert` did not produce AAC output |
| `amr_wbplus_3gp` | fail | fail | Apple stack did not open the sample |
| `xhe_aac_chromium_mono` | pass | fail | Apple stack identifies USAC, but `afconvert` failed during read |
| `xhe_aac_fraunhofer_sintel_24k` | pass | pass | AudioToolbox decoded xHE-AAC/USAC and encoded AAC output |

## Follow-Up AMR-WB+ Archive Recheck - 2026-07-07

The FFmpeg samples archive was rechecked for AMR-WB+ candidates after AMR-WB execution proof advanced. `allsamples.txt` still surfaced the same `A-codecs/amr/amr-wb+_encoded/amr-wb+_encoded.3gp` candidate, and the directory README describes that candidate as historically undecodable in FFmpeg-family tooling. Local `ffprobe` still opened the container only partially, reporting `codec_name=unknown`, `codec_tag_string=sawp`, 6464 Hz, stereo, 2.400s, and `handler_name=VoiceAge AMR-WB+`.

Sources rechecked:

- https://samples.ffmpeg.org/A-codecs/amr/
- https://samples.ffmpeg.org/A-codecs/amr/amr-wb%2B_encoded/
- https://samples.ffmpeg.org/A-codecs/amr/amr-wb%2B_encoded/README.amr-wb%2B_encoded

Outcome: no decodable positive AMR-WB+ sample was found in the FFmpeg sample archive during this pass. Keep the existing AMR-WB+ file as a negative sample and do not promote AMR-WB+ to executable app-side proof.

## Outcome

- Promoted to next app-side implementation candidates: Theora, AMR-NB, VC-1 raw, and Fraunhofer xHE-AAC.
- Still blocked: AMR-WB+ execution needs a decodable App Store-safe path; the located AMR-WB+ sample is useful as a negative fixture but not a passing decode proof. AMR-WB advanced separately on 2026-07-07 through a decodable `sawb`/AMR-WB bundled H.263 sample and is tracked in `docs/verification/AMR_WB_SAMPLE_ACQUISITION_2026-07-07.md`.
- Still blocked: ProRes RAW sample execution needs storage headroom, license/use approval, and then separate app/real-device proof.
- Follow-up simulator runtime status is tracked separately in `docs/verification/SAMPLE_RUNTIME_STATUS_2026-07-06.md`; do not treat these host-side FFmpeg/Apple-tool results as app-side execution proof.
- The next engineering proof should remain separate: app-side execution, simulator benchmark, real-device install/run, and TestFlight/App Store Connect state should not be inferred from this host-side pass.
