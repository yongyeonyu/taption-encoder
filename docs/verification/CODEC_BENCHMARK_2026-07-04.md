# Codec Benchmark Proof - 2026-07-04

## Scope

- Purpose: verify the bundled sample set against the simulator playback probe and H.265 encoding probe after adding the Battery Options encoding optimization selector.
- Build under test: local Debug simulator app, `Taption Encoder` `1.1.0 (29)`.
- Device: iPhone 17 Pro simulator `90456E92-9E4B-4901-BA92-6565CF83E41D`.
- Profile: `performance`.
- This is local runtime evidence only. It is not App Store Connect, TestFlight processing, real-device install, or App Review proof.

## Command

```sh
Scripts/benchmark_bundled_codecs_simulator.sh \
  --device 90456E92-9E4B-4901-BA92-6565CF83E41D \
  --profile performance \
  --mode both \
  --timeout 120 \
  --skip-build
```

## Result

- Bundled samples exercised: 56.
- Playback probe: `playback_unavailable` 51, `playback_timeout` 5.
- Encoding probe: `encoding_completed` 37, `encoding_failed` 17, `encoding_blocked` 1, `encoding_timeout` 1.
- Completed encodes averaged 10.51 seconds per sample in this simulator run.
- Completed backend split: 1 Apple VideoToolbox path, 36 software VLC decoder paths.

## Non-Completed Encoding Samples

- `ASUS V1.avi`: `encoding_failed`
- `Apple ProRes.mov`: `encoding_blocked`
- `DV.dv`: `encoding_failed`
- `DVCPro.mov`: `encoding_failed`
- `Lossless JPEG.avi`: `encoding_failed`
- `MPEG-4 Visual.mov`: `encoding_failed`
- `Microsoft MPEG-4 V3.wmv`: `encoding_failed`
- `Microsoft RLE.avi`: `encoding_failed`
- `QuickTime Graphics.mov`: `encoding_timeout`
- `R10K.mov`: `encoding_failed`
- `R210.avi`: `encoding_failed`
- `RealVideo 1.0.rm`: `encoding_failed`
- `RealVideo.rm`: `encoding_failed`
- `Snow.avi`: `encoding_failed`
- `Ut Video.avi`: `encoding_failed`
- `V308.mov`: `encoding_failed`
- `V408.mov`: `encoding_failed`
- `V410.mov`: `encoding_failed`
- `Windows Media Video.wmv`: `encoding_failed`

## Notes

- Simulator playback status is based on the debug PiP probe. A simulator `playback_unavailable` result means the probe reached the app and the current simulator/runtime did not report PiP playback as possible; it is not a real-device playback proof.
- The benchmark script now treats core transcode failures and software decoder no-frame failures as immediate encoding failures so unsupported/failed samples do not wait for the full per-sample timeout unnecessarily.
- Battery Saver, Balanced, and Max Performance remain H.265-only output modes. The selector changes output limits and scheduling, not the product output codec policy.
