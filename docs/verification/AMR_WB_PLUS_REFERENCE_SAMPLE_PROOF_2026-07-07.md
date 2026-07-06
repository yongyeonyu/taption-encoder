# AMR-WB+ Reference Sample Proof - 2026-07-07

## Scope

- Purpose: acquire a decodable positive AMR-WB+ sample after the FFmpeg samples archive candidate remained a negative `sawp` sample.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Output policy: Taption Encoder video output remains H.265 / HEVC only, with MP4/MOV as the only writable output containers.
- Proof boundary: this is local host-side reference-code sample generation and reference-code decode proof only. It is not app-side execution proof, simulator XCTest proof, real-device proof, bundled-backend approval, license approval, TestFlight/App Store Connect proof, App Review proof, or public-release proof.

## Evidence Files

Checked-in TSV evidence is stored under:

```text
docs/verification/amr_wbplus_reference_sample_2026-07-07/
```

Ignored local sample artifacts are stored under:

```text
Samples/Downloaded/internet_supported_missing_2026-07-07/sample_audio/
Samples/Downloaded/internet_supported_missing_2026-07-07/probe_reports/
```

## Reference Source

The local reference build used the external AMR-WB+ reference-code wrapper repository:

```text
https://github.com/kholia/amr-wbp-plus.git
commit b3f202dcfca359875676f8890b8bc4812e328560
```

This source was used only as a local sample-generation tool. It is not bundled in the app and has not passed product dependency, App Store, patent, or license review.

## Temporary Local Build Fixes

The unmodified macOS native build could create raw AMR-WB+ frames, but the 3GP path first crashed because `moov` was never initialized, then produced malformed 3GP files because the sample description and sample tables were incomplete. The following local-only changes were applied in `/tmp` to generate a valid proof sample:

- Use the portable macOS include path for allocation helpers.
- Initialize the movie with `MP4NewMovie(&moov, 0, 0, 0, 0, 0, 0)` before setting brands/tracks.
- Create the track with the audio bit plus the AMR-WB+ bit.
- Use `ISONewAMRWPSampleDescription(...)` so the sample entry is `sawp` instead of generic `mp4s`.
- Restore per-sample size and duration entries in the handles as native `u32` values before the library writes the final MP4/3GP atoms.

These changes are not product code. They only document what was required to make the local reference generator produce a usable AMR-WB+ 3GP sample.

## Generated Positive Samples

| Sample | Local path | Size | SHA-256 | Probe result |
| --- | --- | ---: | --- | --- |
| AMR-WB+ reference mono-source 3GP | `Samples/Downloaded/internet_supported_missing_2026-07-07/sample_audio/amr_wbplus_reference_mono.3gp` | 9,984 bytes | `d48b0c027e83f795eacecee461f111950905c034799fe69215ef812304fa394f` | `sawp`, 4.880000s, 61 frames |
| AMR-WB+ reference stereo 3GP | `Samples/Downloaded/internet_supported_missing_2026-07-07/sample_audio/amr_wbplus_reference_stereo.3gp` | 10,472 bytes | `92c7e6b800de1edd369c1519a2b7a133e7a720d5103e9d7956da7dc3f26dce5e` | `sawp`, 4.880000s, 61 frames |

Both files are audio-only 3GP samples. FFmpeg can probe the container and `sawp` sample entry, but it still cannot decode AMR-WB+ audio in this local build.

## Decode Proof

The patched local reference decoder decoded both generated `sawp` samples back to 48 kHz stereo PCM WAV:

| Sample | Reference decoder result | Decoded WAV SHA-256 |
| --- | --- | --- |
| `amr_wbplus_reference_mono.3gp` | pass, 61 frames processed, 4.880000s WAV | `dbf30050ab652160e437305f6188365b0e10820c67adb27dc11240a2e6ea3cdd` |
| `amr_wbplus_reference_stereo.3gp` | pass, 61 frames processed, 4.880000s WAV | `eaa3bc22388dc9df1198ad6d6ca5fb362c3b4e39458adca4675b93963214a8b4` |

Local FFmpeg decode remains blocked:

```text
exit code: 234
Decoding requested, but no decoder found for: none
```

FFmpeg also refused to mux the `sawp` stream into a synthetic video wrapper because it treats the audio codec as `none`, so no app-side video-source wrapper was created in this pass.

## Outcome

- AMR-WB+ now has a decodable positive `sawp` reference sample at the host/reference-tool level.
- AMR-WB+ is still not promoted to current app-side execution.
- The existing FFmpeg archive AMR-WB+ sample remains a useful negative sample.
- App-side AMR-WB+ execution still requires a bundled, license-reviewed, App Store-safe decoder/backend or an explicit unsupported-product decision.
- No AMR-WB+ sample was bundled into `TaptionEncoder/TestVideos` in this pass.
