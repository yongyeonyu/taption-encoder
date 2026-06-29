# Taption Encoder 01.00.01 Release Closeout

Status date: 2026-06-27

## Release Identity

- Company release label: `01.00.01`
- Apple marketing version: `1.0.1`
- Apple build number: `19`
- Bundle identifier: `com.taption.encoder`
- Release commit: `f5af6b3` (`Prepare Taption Encoder 1.0.1 build 19`)

## Product Boundary

- Video output remains fixed to H.265 / HEVC.
- Writable output containers remain MP4 and MOV only.
- Broad input support must continue to be described as input-to-H.265 coverage, not universal codec-to-codec conversion.
- Help, Device Info, marketing copy, and App Store metadata must not advertise unsupported output codecs or unsupported output containers.

## Release Proof

- `Scripts/run_core_codec_truth_checks.sh` passed.
- Full app-scheme XCTest passed with parallel testing disabled: 209 tests, 0 failures.
- `Scripts/verify_codec_fixture_evidence.sh` passed with 90 fixtures and 180 verified transcodes.
- Release archive succeeded at `build/TestFlight-01.00.01-19/TaptionEncoder.xcarchive`.
- App Store Connect/TestFlight export upload succeeded and the uploaded package entered processing.
- Paired iPhone 14 Pro install check reported `Taption Encoder`, `com.taption.encoder`, version `1.0.1`, build `19`.
- Paired iPad Pro 12.9-inch (6th generation) install check reported `Taption Encoder`, `com.taption.encoder`, version `1.0.1`, build `19`.

## Notes For Future Agents

- Treat upload success, App Store processing/review state, public App Store availability, device install proof, runtime launch proof, and app-container logs as separate evidence.
- Do not infer App Review or public availability from the archive/export upload log alone.
- Keep product-visible strings in English.
- Continue using `01.00.01` as the company release label and `1.0.1 (19)` when referring to Apple build settings or installed app metadata.
