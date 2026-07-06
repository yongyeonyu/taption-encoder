# Audio Codec Fixtures

Date: 2026-06-16

## Purpose

Taption Encoder must eventually handle broad audio inputs while converting video to H.265. Audio should either be preserved when compatible or transcoded to a compatible output, with the default MVP output using AAC in MP4.

This fixture set focuses on audio families. Each generated file contains:

- A short synthetic video track.
- One audio track with the target codec.
- A manifest row compatible with `Scripts/transcode_fixtures_to_hevc.sh`.
- An `.ffprobe.json` sidecar.

Generated media is ignored by git.

## Generate

```sh
Scripts/generate_audio_codec_fixtures.sh
```

The default output folder is:

```text
Samples/CodecFixtures/audio_generated/
```

For a quick smoke run:

```sh
TAPTION_AUDIO_FIXTURE_DURATION=1 TAPTION_AUDIO_FIXTURE_SIZE=160x90 TAPTION_AUDIO_FIXTURE_FPS=15 \
  Scripts/generate_audio_codec_fixtures.sh Samples/CodecFixtures/audio_generated_smoke
```

The script writes:

- `fixtures.tsv` for generated pass cases.
- `audio_fixture_generation.tsv` for pass, skip, and fail status.
- one `.ffprobe.json` per generated file.
- per-target generation logs.

## Transcode To H.265

```sh
Scripts/transcode_fixtures_to_hevc.sh \
  Samples/CodecFixtures/audio_generated_smoke \
  Samples/CodecFixtures/transcode_reports/audio_smoke_latest
```

The transcode gate uses both:

- `SW_HEVC`: `libx265`
- `HW_HEVC`: `hevc_videotoolbox`

Each passing row requires:

- Output video codec probes as `hevc`.
- Output audio stream exists.
- Output audio signal is detected by FFmpeg `volumedetect`.
- Output audio peak is above `TAPTION_AUDIO_SIGNAL_THRESHOLD_DB`, default `-60 dB`.

## App-Core Execution Readiness

`TaptionAudioCodecExecutionReadinessReporter` summarizes every planned audio source/output route before the broad software backend ships. It separates:

- Copy routes that can remain in the selected container.
- Apple-native decode/encode routes.
- FFmpeg-family command-plan routes that are not runnable until the backend is bundled and reviewed.
- Output encoder gaps such as `xHE-AAC` and `AMR`.

The report is intentionally stricter than route selection: every route can stay in the universal roadmap while still exposing whether the current app build can execute it, can only plan it, or needs another encoder decision.

`HW_AudioCodecAlgorithmCatalog` and `TaptionAudioCodecDescriptorRegistry` expose the same split as code descriptors: Apple-native/copy routes prefer `HW_` descriptors, FFmpeg-family routes use `SW_` descriptors, and missing output encoders remain blocked instead of pretending to be executable.

`TaptionCodecFixtureEvidence.verifyAudioFixtureCatalogCoverage()` now checks the audio fixture catalog against `TaptionAudioCodecRoutePlanner.universalAudioCodecs`. Every universal audio codec must be tracked as either generated or explicitly pending, so broad audio support cannot add a source/output family without also updating the sample plan.

`TaptionCodecFixtureEvidence.verifyAudioFixtureGeneration()` also checks `audio_fixture_generation.tsv` directly. Pending generator codecs such as `xHE-AAC`, `AMR-NB`, and `AMR-WB` must keep a concrete generator attempt row, attempted encoder name, no output file, and a useful blocking reason such as a missing local FFmpeg encoder. The generator now also tries an Apple `afconvert` alternate for those pending codecs before recording the skip, so the evidence distinguishes "not attempted" from "tried FFmpeg and Apple system encoding on this machine." Local sample-backed app execution can still advance separately from generated fixture status: xHE-AAC and AMR-NB have focused simulator execution proof through acquired samples, AMR-WB now has bundled real-device Debug XCTest proof for AAC/MP4 plus PCM/MOV and ALAC/MOV output even while generated audio fixture rows remain pending, Vorbis now has bundled Theora/Vorbis real-device Debug XCTest proof for PCM/MOV and ALAC/MOV output through the bundled software VLC audio route, MP3 now has bundled Flash Video/MP3 real-device Debug XCTest proof for PCM/MOV and ALAC/MOV output through the Apple-native audio route, AAC now has bundled QuickTime Video/AAC real-device Debug XCTest proof for PCM/MOV and ALAC/MOV output through the Apple-native audio route, and AC3/EAC3 now have bundled H.264 Dolby real-device Debug XCTest proof for PCM/MOV and ALAC/MOV output on the requested software path.

## Latest Local Smoke Result

Command:

```sh
TAPTION_AUDIO_FIXTURE_DURATION=1 TAPTION_AUDIO_FIXTURE_SIZE=160x90 TAPTION_AUDIO_FIXTURE_FPS=15 \
  Scripts/generate_audio_codec_fixtures.sh Samples/CodecFixtures/audio_generated_smoke

Scripts/transcode_fixtures_to_hevc.sh \
  Samples/CodecFixtures/audio_generated_smoke \
  Samples/CodecFixtures/transcode_reports/audio_smoke_latest
```

Generation:

| Status | Count |
| --- | ---: |
| PASS | 30 |
| SKIP | 3 |
| FAIL | 0 |

Transcode:

| Metric | Count |
| --- | ---: |
| Input fixtures | 30 |
| SW_HEVC attempts | 30 |
| HW_HEVC attempts | 30 |
| Total attempts | 60 |
| Passed | 60 |
| Skipped | 0 |
| Failed | 0 |
| Audio signal checks passed | 60 |

## Generated Audio Coverage

| Taption audio model | Fixture coverage |
| --- | --- |
| `aac` | AAC in MP4; bundled `QuickTime Video.mov` now has focused simulator and real-device iPad Debug XCTest proof for H.265 MOV with AAC-to-PCM and AAC-to-ALAC output through the Apple-native audio route |
| `xheAAC` | Generated fixture skipped locally; 2026-07-06 real-sample acquisition found Chromium and Fraunhofer xHE-AAC MP4 samples, with the Fraunhofer sample passing Apple `afconvert` decode-to-AAC proof while FFmpeg decode remains unavailable; 2026-07-07 focused simulator XCTest proved the Fraunhofer-derived local xHE-AAC/USAC sample executes app-side through Apple-native decode/export to AAC at 44.1 kHz |
| `pcm` | PCM S16LE, S24LE, F32LE in MOV |
| `aLaw` | PCM A-law in AVI |
| `muLaw` | PCM mu-law in AVI |
| `alac` | ALAC in MOV |
| `opus` | Opus in WebM and MKV |
| `mp3` | MP3 in AVI; bundled `Flash Video.flv` now has focused simulator and real-device iPad Debug XCTest proof for H.265 MOV with MP3-to-PCM and MP3-to-ALAC output through the Apple-native audio route |
| `mp2` | MP2 in MPEG-PS |
| `ac3` | AC3 in MP4; bundled `H.264 AC3.mp4` now has focused simulator and real-device iPad Debug XCTest proof for H.265 MOV with AC3-to-PCM and AC3-to-ALAC output on the requested software path |
| `eac3` | EAC3 in MP4; bundled `H.264 EAC3.mp4` now has focused simulator and real-device iPad Debug XCTest proof for H.265 MOV with EAC3-to-PCM and EAC3-to-ALAC output on the requested software path |
| `dts` | DTS/DCA in MKV |
| `trueHD` | TrueHD in MKV |
| `flac` | FLAC in MKV |
| `vorbis` | Vorbis in MKV; bundled `Theora Vorbis.ogv` now has focused simulator and real-device iPad Debug XCTest proof for H.265 MOV with Vorbis-to-PCM and Vorbis-to-ALAC output through the bundled software VLC audio route |
| `amr` | Generated fixture skipped locally; 2026-07-06 real-sample acquisition proved AMR-NB host FFmpeg decode into H.265 MP4/MOV, and 2026-07-07 focused simulator XCTest proved app-side AMR-NB decode/resample/AAC execution through bundled VLC for the H.263/3GP sample. A separate 2026-07-07 ETSI TS 126 174-derived AMR-WB sample now host-decodes as `amr_wb`/`sawb`; follow-up simulator XCTest surfaced that audio through the bundled VLC metadata path, and focused real-device iPad Debug XCTest encoded bundled `AMR-WB H.263.3gp` to H.265 MP4 with AAC 48 kHz mono output plus H.265 MOV with PCM and ALAC 48 kHz mono output. AMR-WB+ stayed a negative sample because local FFmpeg and Apple audio tools could not decode it |
| `ilbc` | iLBC in MOV via AudioToolbox encoder |
| `g722` | G.722 in MKV |
| `g723` | G.723.1 in MKV |
| `g726` | G.726 in MKV |
| `mlp` | MLP in MKV |
| `tta` | TTA in MKV |
| `nellymoser` | Nellymoser in FLV |
| `realAudio` | RealAudio 1.0 in MKV |
| `roqDPCM` | RoQ DPCM in RoQ |
| `wavPack` | WavPack in MKV |
| `wma` | WMA2 in WMV/ASF |
| `adpcm` | IMA WAV ADPCM and Microsoft ADPCM in AVI |

## Remaining Work

- Implemented app-core route planning now lives in `HW_AudioCodecCapabilityCatalog.swift`, `SW_AudioCodecSupportCatalog.swift`, and `AudioCodecRoutePlanner.swift`.
- App-core tests verify that every planned source audio codec has a default route to AAC for MP4/H.265 output, compatible AAC can be copied, and software-only codecs such as Opus route through software decode before Apple-native AAC encode.
- App-core fixture evidence tests now build AAC/MP4 audio route plans, FFmpeg-family software fallback command plans, and gated executor jobs from every generated audio fixture row while preserving sample rate, channel count, and source bitrate options. They also match those jobs against the latest SW/HW H.265 output and audio-signal evidence rows.
- Audio fixture catalog tests now prove every universal audio codec is either generated locally or explicitly marked pending for a real or alternate generator path.
- Audio fixture generation tests now enforce that every pending codec has a concrete skipped/failed generation attempt with a useful blocking reason and an Apple `afconvert` alternate attempt where applicable, and that a successfully generated pending codec must be promoted to generated coverage.
- App-core tests now build FFmpeg-family command plans from every generated audio fixture to currently plannable compatible output audio codecs while preserving source sample rate, channel count, and bitrate options. `verifyAudioFixturePlannableCommandPlanCoverage()` covers that command-plan surface.
- AAC/MP4 audio fixture execution jobs now rebuild a function-style `TaptionAudioCodecTranscodeRequest` and run through `SW_FFmpegAudioCodecTranscodeExecutor` with a fake runner when the broad software backend gates are satisfied.
- Broader app-side audio execution still needs to cover compatible audio outputs for H.265 video containers after the FFmpeg-family backend is bundled and license-reviewed. AAC and MP3 now have sample-backed Apple-native PCM/MOV and ALAC/MOV proof, and AC3/EAC3 now have software-path simulator plus real-device proof, so the remaining gap is focused on codecs that still need software or broad-backend decode/encode execution.
- Acquire a decodable AMR-WB+ sample or make a clear unsupported decision from the selected broad backend; AMR-WB now has bundled real-device Debug XCTest proof for AAC/MP4, PCM/MOV, and ALAC/MOV output.
- Add real-world multichannel, surround, high sample-rate, odd channel-layout, and silent/damaged audio samples.
- Keep objective audio signal verification in app-scheme evidence tests and expand executor coverage beyond the current AAC/MP4 audio route test surface.
- Decide when audio can be copied versus transcoded to AAC or another selected output audio codec.
