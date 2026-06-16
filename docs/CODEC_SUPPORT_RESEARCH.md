# Codec Support Research

Date: 2026-06-16
SDK inspected: `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk`

## Product Target

Taption Encoder starts with AV1 to H.265, then expands to broad input to H.265, and finally to a universal codec router where every supported source codec can be converted to every supported output codec. The final model is symmetric all-to-all routing, so `H.264 -> AV1`, `AV1 -> H.264`, same-codec re-encode routes, and every other supported pair stay represented as first-class routes.

The product should not hard-code one global device table as truth. Apple hardware support varies by chip, OS, resolution, profile, bit depth, thermal state, and active encoder resource pressure. The app must probe the running device and mark each route as:

- `HW`: VideoToolbox/Apple stack can use hardware acceleration.
- `SW`: Taption software path can decode/encode or transcode the route.
- `Hybrid`: one side is hardware and another side is software.
- `Planned`: represented in the route matrix but not implemented yet.
- `Unsupported`: unsupported, DRM-protected, damaged, or not legally/technically shippable.

## Runtime Probe Rules

- Hardware decode: use `VTIsHardwareDecodeSupported(_:)`.
- Hardware encode: on iOS 17.4+ use `VTCopySupportedPropertyDictionaryForEncoder` with `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder`.
- Actual encoding path still needs runtime confirmation after session creation, because hardware resources can be busy.
- Automatic mode priority is always HW first, then SW fallback.

Primary references:

- Apple Developer: `VTIsHardwareDecodeSupported(_:)`
  <https://developer.apple.com/documentation/videotoolbox/vtishardwaredecodesupported(_:)>
- Apple Developer: `VTCopySupportedPropertyDictionaryForEncoder`
  <https://developer.apple.com/documentation/videotoolbox/vtcopysupportedpropertydictionaryforencoder(_:_:_:_:_:_:)>
- Apple Developer: `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder`
  <https://developer.apple.com/documentation/videotoolbox/kvtvideoencoderspecification_requirehardwareacceleratedvideoencoder>
- Apple Developer: `AVAssetWriterInput`
  <https://developer.apple.com/documentation/avfoundation/avassetwriterinput>
- Apple Support iPhone technical specifications, for device-specific media-engine claims:
  <https://support.apple.com/iphone/specs>
- Apple Support iPad technical specifications:
  <https://support.apple.com/ipad/specs>

## Native Apple Codec Constants in iPhoneOS 26.5 SDK

The following CoreMedia video codec constants are present in the installed iPhoneOS 26.5 SDK and should be represented in Taption's internal model where relevant:

| Family | CoreMedia constants or fourCC examples | Taption model |
| --- | --- | --- |
| AV1 | `kCMVideoCodecType_AV1`, `av01` | `av1` |
| HEVC/H.265 | `kCMVideoCodecType_HEVC`, `hvc1`, `hev1` | `hevc` |
| HEVC alpha | `kCMVideoCodecType_HEVCWithAlpha`, `muxa` | `hevcWithAlpha` |
| Dolby Vision HEVC | `kCMVideoCodecType_DolbyVisionHEVC`, `dvh1`, `dvhe` | `dolbyVisionHEVC` |
| H.264/AVC | `kCMVideoCodecType_H264`, `avc1`, `avc3` | `h264` |
| ProRes | ProRes 4444 XQ/4444/422 HQ/422/LT/Proxy | `proRes` |
| ProRes RAW | ProRes RAW/RAW HQ | `proResRaw` |
| VP9 | `kCMVideoCodecType_VP9`, `vp09` | `vp9` |
| MPEG-4 Part 2 | `kCMVideoCodecType_MPEG4Video`, `mp4v` | `mpeg4Visual` |
| MPEG-2 | `kCMVideoCodecType_MPEG2Video`, `mp2v` | `mpeg2` |
| MPEG-1 | `kCMVideoCodecType_MPEG1Video`, `mp1v` | `mpeg1` |
| H.263 | `kCMVideoCodecType_H263`, `h263` | `h263` |
| JPEG/MJPEG | JPEG/OpenDML JPEG | `jpeg`, `motionJPEG` |
| JPEG XL | `kCMVideoCodecType_JPEG_XL`, `jxlc` | `jpegXL` |
| QuickTime legacy | Animation, Cinepak, Sorenson Video, Sorenson Video 3 | `animation`, `cinepak`, `sorensonVideo`, `sorensonVideo3` |
| DV | DV NTSC/PAL | `dv` |
| DVCPro | DVCPro PAL/50 | `dvcPro` |
| DVCPro HD | DVCPro HD 720/1080 variants | `dvcProHD` |

VP8, Theora, VC-1, WMV, and many raw/legacy codecs are not first-class Apple native hardware targets on iPhone/iPad. They remain SW decode targets unless a real device probe or imported decoder proves otherwise.

## Audio Codec Targets

Audio should be copied when compatible with the output container and quality policy. If not compatible, the default output policy should transcode to AAC while preserving sample rate, channel layout, and perceived quality where possible.

| Family | Taption model | Initial route |
| --- | --- | --- |
| AAC / HE-AAC / xHE-AAC | `aac`, `xheAAC` | Native first |
| PCM | `pcm`, `aLaw`, `muLaw` | Native or SW depending container |
| ALAC | `alac` | Native when possible |
| Opus | `opus` | SW/imported decoder |
| MP3 / MP2 | `mp3`, `mp2` | Native or SW depending source |
| AC3 / EAC3 | `ac3`, `eac3` | Native or SW depending source/output |
| DTS / TrueHD | `dts`, `trueHD` | SW/imported decoder target |
| FLAC / Vorbis / WavPack | `flac`, `vorbis`, `wavPack` | SW/imported decoder target |
| AMR / iLBC / ADPCM / WMA | `amr`, `ilbc`, `adpcm`, `wma` | SW/imported decoder target |

Current audio fixture coverage is tracked in `docs/AUDIO_CODEC_FIXTURES.md`. The local smoke set generated AAC, PCM, A-law, mu-law, ALAC, Opus, MP3, MP2, AC3, EAC3, DTS, TrueHD, FLAC, Vorbis, iLBC, WavPack, WMA, and ADPCM samples with audio signal verification after SW/HW H.265 conversion. xHE-AAC, AMR-NB, and AMR-WB remain alternate-generator or real-sample targets because the current local FFmpeg build does not provide those encoders.

The app core now includes an audio route planner:

- `HW_AudioCodecCapabilityCatalog.swift`: Apple-native decode/encode and container copy compatibility.
- `SW_AudioCodecSupportCatalog.swift`: software decode and generated-fixture coverage status.
- `AudioCodecRoutePlanner.swift`: source audio codec to output audio codec route selection, defaulting to AAC for MP4/H.265 output.

This is route-selection and command-planning coverage only. App-scheme evidence tests now parse objective audio signal proof and build AAC/MP4 app-core audio route plans from the generated audio fixtures, but actual app-side audio transcode execution still needs to migrate from host-side scripts into route tests.

## Container Targets

Taption should accept a broad import set, then write the requested output container selected by the route. The default MVP output remains MP4/H.265.

| Container | Extensions | Initial purpose |
| --- | --- | --- |
| MP4/M4V | `.mp4`, `.m4v` | Primary Apple/web/camera path |
| MOV/QuickTime | `.mov`, `.qt` | iPhone, ProRes, editor exports |
| AVI/DivX | `.avi`, `.divx` | Legacy cameras and Windows exports |
| MKV | `.mkv` | Web/archive imports |
| WebM | `.webm` | AV1/VP9/VP8 web imports |
| MXF | `.mxf` | Professional camera/editor imports |
| MPEG-TS | `.ts`, `.mts`, `.m2ts`, `.tp`, `.trp`, `.tod` | Broadcast/action camera imports |
| MPEG-PS/VOB | `.mpg`, `.mpeg`, `.vob`, `.mod` | DVD/archive imports |
| LRF | `.lrf` | DJI low-resolution proxy imports; real sample required |
| DV | `.dv` | Tape capture imports |
| Ogg/Ogv/OGM | `.ogg`, `.ogv`, `.ogm` | Theora/Vorbis archive imports |
| FLV/F4V | `.flv`, `.f4v` | Legacy web imports |
| 3GP/3G2 | `.3gp`, `.3g2` | Legacy mobile imports |
| ASF/WMV | `.asf`, `.wmv`, `.dvr-ms` | Windows media imports |
| Raw elementary | `.h264`, `.h265`, `.hevc`, `.ivf`, `.obu`, `.y4m`, `.av1`, `.h263`, `.m1v`, `.m2v`, `.vc1` | Diagnostic/import edge cases |

## Fixture Policy

Synthetic generated fixtures are required for repeatable CI and local smoke tests. They do not replace real-world samples.

Generated fixtures must cover:

- Video codec family.
- Container family.
- At least one audio track where the container supports audio.
- Rotation/color/HDR/VFR variants in later fixture phases.
- A manifest row and `.ffprobe.json` for every generated file.

Real-world samples are still required for:

- DJI `.LRF`.
- GoPro/Insta360/DJI high-bitrate camera files.
- iPhone HDR/Dolby Vision/Cinematic/slow-motion files.
- Damaged files and odd metadata.
- DRM-protected content should be explicitly unsupported.

## Device Matrix Policy

The app should expose a Device Info menu that shows:

- Device model identifier.
- OS version.
- Runtime hardware decode support per codec.
- Runtime hardware encode support per codec at the probe resolution.
- Apple-native audio decode and encode support per planned audio codec.
- Audio copy compatibility for common output containers such as MP4 and MOV.
- Current app routing priority: HW first, SW fallback.

The implementation now has `HW_CodecCapabilityProbe` as the core provider for this screen, including VideoToolbox video probes and Apple-native audio capability rows. `CodecRoutePlanner` remains the app-side route selector that reports `HW`, `SW`, `HW/SW`, `Planned`, or `Unsupported` per imported file.

Route-selection simulation is tracked in `docs/DEVICE_CODEC_ROUTE_SIMULATION.md` and can be regenerated with `Scripts/simulate_codec_route_planner.sh`.

Apple device-family simulation is tracked in `docs/APPLE_DEVICE_CODEC_MATRIX.md` and implemented in `HW_AppleDeviceCodecProfiles.swift`. The catalog currently covers the oldest iPadOS 18 A10 class, A12/A13/A14/A15/A16 HEVC classes, iPhone/iPad ProRes classes, A17 Pro/A18 AV1-decode classes, and modern M3/M4 iPad AV1/ProRes classes. These profiles are simulation inputs only; real-device `HW_CodecCapabilityProbe` output remains the app authority.

## Current Implementation State

- Implemented routes: AV1 to H.265 using HW first with SW fallback, plus Apple-native HW-only `H.264 -> H.265`, `H.265 -> H.265`, and `ProRes -> H.265` on profiles that can hardware-decode the source and hardware-encode H.265.
- Implemented catalog: universal route model, function-style codec request/options/output API, expanded codec/container/audio enums, HW probe file, Apple device-family HW profile catalog, SW fixture catalog file, app-side route planner, and capability-profile route simulation.
- Implemented audio route planner: default all-planned-audio-to-AAC route selection with copy/native/SW/planned states and fixture coverage status.
- Implemented algorithm files: `HW_AppleHEVCCodecAlgorithm.swift`, `HW_AV1HEVCCodecAlgorithm.swift`, and `SW_AV1HEVCCodecAlgorithm.swift` expose `TaptionCodecTranscodeRequest -> TaptionCodecTranscodeOutput` entry points. The app software fallback path now uses the shared request API, while the Apple-native H.265 HW path is separated from the AV1-specific wrapper for future Taption reuse.
- Implemented planned universal software catalog: `SW_UniversalCodecTranscodeAlgorithm.swift` exposes software descriptors for every non-implemented universal source/output route and reports a clear not-bundled backend error until the broad software codec backend is actually shipped.
- Implemented planned universal audio software catalog: `AudioCodecAlgorithm.swift` defines the function-style audio request/options/output API, and `SW_UniversalAudioCodecTranscodeAlgorithm.swift` exposes software descriptors for every universal audio source/output route with the same not-bundled backend error boundary.
- Implemented FFmpeg-family command planning: `SW_FFmpegCodecCommandPlanner.swift` converts video and audio codec requests into explicit argument plans, including all-to-all examples such as `H.264 -> AV1` and `AV1 -> H.264`, advanced output options, audio copy/transcode decisions, input/output container readability checks, and explicit gap reporting for codecs without a selected FFmpeg-family encoder. Xcode tests now guard the full video and audio all-to-all command-plan matrix for every plannable output codec, every declared readable input container, every declared writable output container, and representative legacy/raw import aliases, not only example routes. `TaptionUniversalCodecCompletionAuditor` now summarizes the same final contract as one core gate, separating planning-locked all-to-all coverage from command-plan gaps, runtime backend gaps, and output-selector coverage gaps. `CodecOutputCatalog` and `TaptionAudioCodecOutputCatalog` expose matching video/audio output readiness catalogs for the Home output selectors, Device Info, and saved device JSON snapshots. Fixture evidence tests also build source-preserving H.265/MP4 command plans for every generated video fixture manifest row, AAC/MP4 audio command plans for every generated audio fixture row, and gated FFmpeg-family execution jobs for both fixture sets, then match those jobs against the latest SW/HW H.265 and audio-signal evidence rows, so the sample catalog is tied to app-core planning as well as host-side scripts.
- Implemented fixture generator: broad video/audio fixture set plus dedicated audio codec fixture set with manifest/probe output. The video fixture set includes representative container/raw aliases such as DivX, TP/TRP/TOD, MOD, OGM, DVR-MS, AV1 OBU, H.263, M1V, and M2V; VC-1 remains a real-world or alternate-generator sample target because the current local FFmpeg build has no VC-1 encoder.
- Not complete yet: bundled broad-codec execution, app-side all-to-H.265 conversion algorithms for every fixture, all-to-all output algorithms, real-device HW report capture, and migration of every SW/HW algorithm into one function-per-route implementation. Host-side proof now covers the expanded 45-fixture video smoke set through both SW_HEVC and HW_HEVC with 90/90 H.265 attempts passing, 80 audio-signal checks passing, and 10 no-source-audio raw elementary attempts explicitly recorded.
