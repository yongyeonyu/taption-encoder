# Video Codec Fixtures

Taption Encoder uses generated codec fixtures for repeatable local testing before real camera samples are collected.

## Generate

```sh
Scripts/generate_video_codec_fixtures.sh
```

The default output folder is:

```text
Samples/CodecFixtures/generated/
```

Generated videos are intentionally ignored by git. The script also writes:

- `fixtures.tsv`
- `video_fixture_generation.tsv`
- one `.ffprobe.json` file per generated video
- per-fixture generation logs under `logs/`

## Transcode To H.265

Run the generated set through both software and hardware H.265 paths:

```sh
Scripts/transcode_fixtures_to_hevc.sh Samples/CodecFixtures/generated
```

For a quick local gate, use the smoke fixtures:

```sh
TAPTION_FIXTURE_DURATION=1 TAPTION_FIXTURE_SIZE=160x90 TAPTION_FIXTURE_FPS=15 \
  Scripts/generate_video_codec_fixtures.sh Samples/CodecFixtures/generated_smoke

Scripts/transcode_fixtures_to_hevc.sh \
  Samples/CodecFixtures/generated_smoke \
  Samples/CodecFixtures/transcode_reports/smoke_latest
```

The transcode report writes:

- `transcode_results.tsv`
- converted `.mp4` files
- one `.ffprobe.json` file per converted output
- per-attempt FFmpeg logs

Each transcode row verifies that the output video probes as H.265 and, when source audio exists, the output has an audio stream with a measured signal above `-60 dB` using FFmpeg `volumedetect`.

The app-scheme unit tests parse `Samples/CodecFixtures/generated_smoke/fixtures.tsv` and compare every implemented target in `SW_CodecSupportCatalog.fixtureTargets` against the manifest. They also parse `video_fixture_generation.tsv` so every implemented fixture target must have a passing generation row, and every optional generation attempt must keep a useful blocking reason when skipped. If a planned or real-world-sample-required target starts generating successfully, the tests intentionally fail until the target is promoted to the correct catalog status. The tests also build source-preserving H.265/MP4 command plans and gated FFmpeg-family execution jobs from every generated video fixture row, then match those jobs against the latest SW/HW H.265 output and audio-signal evidence rows. This keeps generated video sample coverage tied to the app's software codec roadmap, app-core planner, and future executor path, not only to the host-side scripts.

## Audio-Focused Fixture Set

Audio codec coverage lives in:

```text
docs/codecs/AUDIO_CODEC_FIXTURES.md
```

Generate the audio-focused set with:

```sh
Scripts/generate_audio_codec_fixtures.sh
```

The audio smoke set currently validates AAC, PCM variants, A-law, mu-law, ALAC, Opus, MP3, MP2, AC3, EAC3, DTS, TrueHD, FLAC, Vorbis, iLBC, G.722, G.723.1, G.726, MLP, TTA, Nellymoser, RealAudio 1.0, RoQ DPCM, WavPack, WMA, and ADPCM through the same SW/HW H.265 transcode gate.

## Current Fixture Targets

The required smoke manifest currently covers 90 generated video fixtures before optional, planned, and real-sample-only targets. These samples represent the broad all-to-H.265 proof set. `TaptionCodecFixtureEvidence.verifyVideoFixtureCatalogCoverage()` now checks that every `TaptionCodecRegistry.universalSourceCodecs` entry is tracked by the fixture catalog as implemented, conditional, real-world-sample-required, or planned, so input codec additions cannot silently skip sample planning. `verifyVideoContainerFixtureCoverage()` does the same for every non-unknown `TaptionVideoContainer`, every broad readable container, and every declared extension alias such as `.mov`, `.qt`, `.mp4`, `.avi`, `.divx`, `.lrf`, `.ts`, `.m2ts`, `.m2t`, `.tp`, `.trp`, `.tod`, `.mpg`, `.mpe`, `.vob`, `.mod`, `.dat`, `.nut`, `.roq`, `.rm`, `.rmvb`, `.ogm`, `.dvr-ms`, `.3gpp`, `.3gpp2`, `.dif`, `.264`, `.265`, `.m1v`, `.m2v`, and `.vc1`. App-core tests also assert that the iOS document picker UTType list, folder scanner extension policy, and `Info.plist` imported video type declarations cover every core container extension, so file/folder open support cannot drift from the codec planner. App-core tests build FFmpeg-family command plans from every generated source fixture to H.265 output. `verifyVideoFixtureInputToHEVCCommandPlanCoverage()` enforces the H.265-only output contract.

- AV1 in MP4 and WebM
- AV1 in MKV
- H.264 software and VideoToolbox
- H.264 with AAC, PCM, FLAC, Vorbis, AC3, EAC3
- H.264 in M4V, QuickTime `.qt`, MPEG-TS aliases (`.ts`, `.m2ts`, `.tp`, `.trp`, `.tod`), FLV/`.f4v`, NUT, and raw elementary stream form
- DJI-style `.lrf` H.264/AAC proxy container smoke sample
- H.265 software and VideoToolbox
- H.265 with AAC and ALAC
- VP9 and VP8
- ProRes with PCM and ALAC
- FFV1 with FLAC
- HuffYUV, FFVHuff, Ut Video, and MagicYUV
- GoPro CineForm, DNxHD/DNxHR, PNG video, R10k, V210, R210, V410, Y41P, Microsoft RLE, QuickTime Graphics, V308, V408, and YUV4
- MPEG-1 and MPEG-2 program streams plus `.dat`, `.mod`, and `.vob`
- MPEG-2 in MXF
- MPEG-4 Part 2 in AVI and `.divx`
- Microsoft MPEG-4 V2/V3 and Microsoft Video 1
- Flash Video, Flash Screen Video, and Flash Screen Video 2
- H.263 in 3GP and 3G2
- H.261
- Motion JPEG, JPEG 2000, JPEG-LS, and Lossless JPEG
- QuickTime Animation
- Cinepak
- Sorenson Video 1 and QuickTime RPZA
- VP8/Vorbis in `.ogm`
- ASUS V1/V2, ZMBV, CLJR, and Snow
- WMV2/WMA2 in WMV, ASF, and `.dvr-ms`
- RealVideo 1.0 and 2.0 in RealMedia `.rm`
- RoQ game-cinematic video
- Raw AV1 OBU, H.263, rawvideo `.y4m`, MPEG-1 `.m1v`, and MPEG-2 `.m2v`
- DV
- Theora when the local FFmpeg build supports it
- VC-1 raw elementary streams when a real-world sample or alternate generator is available; the local smoke generation evidence must keep the skipped `vc1_raw_elementary` row and explain the missing encoder path until that happens

## Tracked Pending Video Fixture Targets

These codecs are part of the universal source/output contract but do not yet have a required generated smoke fixture:

- Planned generator work: H.265 with Alpha, JPEG frame-sequence import, JPEG XL frame-sequence import, DVCPro, and DVCPro HD
- Conditional local FFmpeg work: Theora
- Real-world or alternate-generator samples required: Dolby Vision HEVC, ProRes RAW, Sorenson Video 3, VC-1, DJI `.lrf` camera proxy samples

## Why Generated Fixtures

Synthetic fixtures are useful for exercising codec/container routing, media inspection, file picking, queue behavior, and SW/HW fallback logic. They do not replace real-world media because real devices add edge cases such as rotation metadata, variable frame rate, HDR, nonstandard audio tracks, camera-specific atoms, damaged files, and very large bitrates.

## Recommended Real-World Set Later

Collect real samples for each family:

- iPhone/iPad: H.264, H.265, HDR, Cinematic, slow motion
- Android: H.264, H.265, AV1 when available
- Action camera: DJI, GoPro, Insta360
- Camera/editor exports: ProRes, MXF, MPEG-2, MPEG-4 Part 2
- Web downloads: VP8, VP9, AV1 in WebM/MP4

## Related Matrix

The broader codec/container research and support tiers live in:

```text
docs/codecs/CODEC_SUPPORT_RESEARCH.md
```

The latest checked-in summary of the local smoke H.265 transcode gate lives in:

```text
docs/verification/HEVC_TRANSCODE_TEST_RESULTS.md
```
