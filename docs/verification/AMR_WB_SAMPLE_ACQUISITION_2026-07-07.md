# AMR-WB Sample Acquisition - 2026-07-07

## Scope

- Purpose: acquire a decodable AMR-WB sample candidate after the prior AMR-WB+ sample stayed negative, then separate host decode proof from app-side runtime proof.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Local sample folder: `/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-07/`.
- Evidence folder: `docs/verification/amr_wb_sample_acquisition_2026-07-07/`.
- Output policy remains unchanged: Taption Encoder still outputs H.265 / HEVC video only, and implemented output containers remain MP4/MOV only.
- This is local sample acquisition, host decode, and focused simulator block evidence. It is not passing AMR-WB app-side execution proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.

`Samples/Downloaded/` is intentionally ignored by git, so the generated sample files stay local. The checked-in TSV files preserve the source URL, source hash, generated sample hashes, host probe results, and the current app-side block.

## Source

The successful source was the ETSI TS 126 174 V19.0.0 companion archive:

```text
https://www.etsi.org/deliver/etsi_ts/126100_126199/126174/19.00.00_60/ts_126174v190000p0.zip
```

The ETSI/3GPP document states that the AMR-WB digital test sequence files are provided as ZIP archives accompanying the document. The downloaded companion ZIP contained `readme.txt`, `S.zip`, and `T.zip`.

The selected encoded sequence was:

```text
T.zip -> T/T_1265/T02_1265.cod
```

`T02_1265.cod` is a 12.65 kbit/s AMR-WB serial test-vector file. The local conversion packed the first 150 20 ms frames into the AMR-WB storage format with the `#!AMR-WB` header, then muxed the resulting audio with a generated H.263 video test pattern into a 3GP sample.

## Created Local Samples

| Target | Local sample | Size | SHA-256 | Result |
| --- | --- | ---: | --- | --- |
| AMR-WB audio | `sample_audio/amr_wb_t02_1265.awb` | 4,959 bytes | `050ddecc011ce2566b9012a7ff79c19dd153c4738b2ba3713cfb605a2fd26c98` | Host FFprobe identifies `amr_wb` / `sawb`, 16 kHz mono, 3.093750s. |
| AMR-WB video container | `sample_videos/amr_wb_h263_video.3gp` | 148,699 bytes | `af9398db3c70b2bc32d8ade87f11fee79b6b2a7344b58cb96d7ea901791c0fc1` | Host FFprobe identifies H.263 video plus `amr_wb` / `sawb` audio, 16 kHz mono, 3.000000s. |

## Host Decode Probe

Host FFmpeg 8.1.1 decoded both the `.awb` file and the 3GP audio stream without corruption errors.

| Sample | FFprobe | Decode signal |
| --- | --- | --- |
| `amr_wb_t02_1265.awb` | `amr_wb`, `sawb`, 16 kHz mono, 12.8 kb/s, 3.093750s | Peak level 6.694738 dB, RMS level -17.168818 dB |
| `amr_wb_h263_video.3gp` | H.263 video plus `amr_wb`, `sawb`, 16 kHz mono, 13.2 kb/s, 3.000000s | Peak level 6.694738 dB, RMS level -17.168818 dB |

## Focused App-Side Simulator Proof

The newly added opt-in XCTest documents the current app-side block:

```sh
touch /tmp/taption_run_local_real_sample_tests
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination "platform=iOS Simulator,id=BCFE1251-F1C1-4637-A0F9-F47813B1DA81" \
  -derivedDataPath /tmp/taption_encoder_amrwb_dd \
  -resultBundlePath /tmp/taption_encoder_amrwb_block_result_rerun.xcresult \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testLocalRealAMRWBH263SampleDocumentsCurrentAppAudioInspectionBlock
rm -f /tmp/taption_run_local_real_sample_tests
```

Result: passed, 1 selected test, 0 failures.

The simulator was a temporary iPhone 17 Pro iOS 26.5 device named `TaptionEncoder-AMRWB-Proof-iPhone-17-Pro` with UDID `BCFE1251-F1C1-4637-A0F9-F47813B1DA81`.

The test confirms:

- The app can prepare the 3GP as a video source and inspect the H.263 video track.
- Host FFmpeg sees the `sawb` AMR-WB audio track, but the current app inspection path does not surface that audio track as `TaptionAudioTrackInfo`.
- The prepared app plan has no `audioPlan`, so AMR-WB is not promoted to current-build AAC execution.
- No H.265/AAC output is claimed for AMR-WB in this pass.

## Outcome

- Decodable AMR-WB sample acquisition is no longer blocked at the host/sample level.
- AMR-WB app-side execution remains blocked: current app inspection/runtime does not surface the `sawb` audio track for this 3GP sample, so no AAC output proof exists yet.
- The previous AMR-WB+ sample remains a negative sample.
- Next AMR-WB work should add a first-party `sawb`/AMR-WB inspection path or a bundled license-reviewed backend that can expose and decode the audio track before attempting H.265/AAC execution proof.

