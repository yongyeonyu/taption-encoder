# H.265 Transcode Fixture Results

Date: 2026-06-16
Host: local macOS development machine
Input fixture set: `Samples/CodecFixtures/generated_smoke/fixtures.tsv`
Report output: `Samples/CodecFixtures/transcode_reports/smoke_latest/transcode_results.tsv`
Audio-focused report output: `Samples/CodecFixtures/transcode_reports/audio_smoke_latest/transcode_results.tsv`

Generated report outputs are ignored by git because they contain media files and per-run logs.

## Command

```sh
Scripts/transcode_fixtures_to_hevc.sh \
  Samples/CodecFixtures/generated_smoke \
  Samples/CodecFixtures/transcode_reports/smoke_latest
```

## Result Summary

| Metric | Count |
| --- | ---: |
| Input fixtures | 45 |
| SW_HEVC attempts | 45 |
| HW_HEVC attempts | 45 |
| Total attempts | 90 |
| Passed | 90 |
| Skipped | 0 |
| Failed | 0 |
| Audio signal checks passed | 80 |
| No-source-audio attempts | 10 |
| Output peak range | -20.6 dB to -17.3 dB |

## Audio-Focused Smoke Summary

Audio fixture generation:

| Metric | Count |
| --- | ---: |
| Generated audio fixtures | 22 |
| Skipped audio targets | 2 |
| Generation failures | 0 |

Audio fixture transcode:

| Metric | Count |
| --- | ---: |
| SW_HEVC attempts | 22 |
| HW_HEVC attempts | 22 |
| Total attempts | 44 |
| Passed | 44 |
| Skipped | 0 |
| Failed | 0 |
| Audio signal checks passed | 44 |

The skipped generation targets are xHE-AAC, AMR-NB, and AMR-WB because the local FFmpeg build does not provide those encoders. They remain real-sample or alternate-generator targets.

## Covered Fixture Families

- AV1 in MP4, WebM, and MKV with Opus audio
- H.264 in MP4, MOV, MKV, and DJI-style `.lrf`
- H.264 with AAC, PCM, FLAC, Vorbis, AC3, and EAC3
- H.264 in M4V, MPEG-TS aliases (`.ts`, `.tp`, `.trp`, `.tod`), FLV, and raw elementary stream form
- HEVC in MP4 and MOV with AAC and ALAC
- VP9 and VP8 in WebM with Opus
- ProRes in MOV with PCM and ALAC
- MPEG-1 and MPEG-2 program streams with MP2, including `.mod`
- MPEG-2 in MXF with PCM
- MPEG-4 Part 2 in AVI and `.divx` with MP3
- H.263 in 3GP and 3G2 with AAC
- Motion JPEG in AVI with PCM
- QuickTime Animation and Cinepak in MOV with PCM
- VP8/Vorbis in `.ogm`
- WMV2 in WMV/ASF/`.dvr-ms` with WMA2
- Raw AV1 OBU, H.263, MPEG-1 `.m1v`, and MPEG-2 `.m2v`
- DV with PCM

VC-1 raw elementary streams remain tracked as a real-world or alternate-generator target because the current local FFmpeg build can mux VC-1 but does not provide a VC-1 encoder.

## Covered Audio Fixture Families

- AAC
- PCM S16LE, S24LE, and F32LE
- A-law and mu-law PCM
- ALAC
- Opus in WebM and MKV
- MP3 and MP2
- AC3 and EAC3
- DTS/DCA and TrueHD
- FLAC and Vorbis
- iLBC
- WavPack
- WMA2
- IMA WAV ADPCM and Microsoft ADPCM

## Verification Per Attempt

Each row is counted as pass only when:

- FFmpeg completed successfully.
- The output file exists and is non-empty.
- The first output video stream probes as `hevc`.
- If the source had audio, the output contains at least one audio stream.
- If the source had audio, `volumedetect` must find a real output signal above `-60 dB`.
- The report records `source_audio_peak_db` and `output_audio_peak_db` for each attempt.
- A `.ffprobe.json` file is written for the output.

## Current Meaning

This proves the local synthetic fixture set can be decoded and re-encoded to H.265 through both:

- `SW_HEVC`: `libx265`
- `HW_HEVC`: `hevc_videotoolbox`

This is not yet proof that the iOS app has migrated every route. It is a repeatable host-side codec and audio-signal coverage gate for building and validating the later app integration.

## Remaining Proof Needed

- Run the same kind of route tests on real iPhone/iPad hardware after the app-side generic codec router is integrated.
- Capture `HW_CodecCapabilityProbe` reports from representative Apple devices.
- Add app-side objective audio signal checks after route tests move into the app/test target.
- Add real-world samples for DJI `.lrf`, GoPro/Insta360/DJI originals, iPhone HDR/Dolby Vision, Cinematic, slow motion, and damaged/nonstandard metadata.
- Expand from all-to-H.265 to implemented all-to-all output routes after output codec selection is implemented; the route planner already tracks every planned source/output codec pair.
