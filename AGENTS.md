# AGENTS.md

## Project

- Product: Taption Encoder
- Path: `/Users/u_mo_c/Documents/taption_encoder`
- Xcode project: `TaptionEncoder.xcodeproj`
- Scheme: `TaptionEncoder`
- Bundle id: `com.taption.encoder`
- Current release source: `1.1.7 (38)` (TestFlight preparation)
- Latest verified published version: `1.1.5` (App Store Connect readback on 2026-10-06)
- Historical `1.1.3 (34)` code commit: `a04dab782555dac8472c92b3b6fe823146206fc3`

## Maintenance Status

- Feature development ended on 2026-07-17. Keep the project in minimal
  maintenance mode.
- Make changes only for App Review responses, critical defects, security,
  platform compatibility, or an explicit request to resume development.
- On 2026-10-06, App Store Connect reported `1.1.5` as `READY_FOR_SALE`
  and TestFlight `1.1.6 (37)` as `VALID / APP_STORE_ELIGIBLE`.
  The preview/audio fixes were local-only at that readback. Verify live state
  before any further release action; see `test.md` for version-bound evidence.
- Do not treat App Store upload, review, or approval as legal clearance for the
  bundled codec dependencies.

## Scope Rules

- Work only in `/Users/u_mo_c/Documents/taption_encoder` for this project.
- Do not edit `/Users/u_mo_c/Documents/taption` unless the user explicitly asks for main Taption work.
- Keep visible app strings in English.
- Output video codec stays fixed to H.265 / HEVC.
- Output containers stay limited to MP4 and MOV.
- Keep proof surfaces separate: local build/test, archive/export, App Store Connect/TestFlight, App Review, device install, and runtime logs are different evidence classes.

## Latest Release Snapshot

- `1.1.3 (34)` introduced the Cool Slate UI palette, aligned the Exit and
  Watch Ad control widths, removed the Privacy & Ads menu item, and improved
  display geometry for selected legacy codecs with non-square pixels.
- Release and Debug test builds passed before upload.
- The App Store distribution IPA passed Apple validation and upload processing
  with status `VALID / APP_STORE_ELIGIBLE`.
- Delivery UUID: `0c043b6a-f0f6-4014-9d2d-07c3c7911c3f`.
- The latest physical codec regression before the version-only release bump
  passed `120/120` samples; the VC-1 raw and Y41P focused lane passed `4/4`.
- Output remained H.265 / HEVC in MP4 or MOV throughout those checks.

## Release Artifacts

- Preserve the compact release record at
  `/Users/u_mo_c/Documents/TaptionEncoderReleases/1.1.3-34-a04dab7`.
- It contains the verified archive ZIP, App Store IPA, App Thinning report,
  relink materials, export options, and `RELEASE_MANIFEST.txt`.
- Do not delete this record while App Review or legal follow-up is active.
- On 2026-10-06, the exact record path was not present on this host. Do not
  claim it is still available locally or reconstruct it from another version.
- The local public-distribution gate remains blocked because the exact-release
  corresponding-source bundle and external legal approval are missing.
- `Vendor/OpenSourceCompliance/legal-approval.pending.json` is intentionally
  non-passing and must not be presented as approval.

## Source-Only Cleanup State

- On 2026-07-07, the working tree was trimmed toward source-only form.
- Historical development docs, proof docs, external generated samples, bundled test videos, sample thumbnail resources, and helper scripts were removed from the working tree.
- Historical material remains recoverable from Git history and remote commits before the source-only cleanup.
- On 2026-07-17, Taption Encoder DerivedData, codec build directories, simulator
  test copies, temporary logs, and shared regenerable development caches were
  removed to minimize local storage.
- The first future build may need to resolve Swift packages and rebuild all
  derived artifacts from scratch.
- Keep new generated samples, archives, logs, and proof files outside the
  working tree.

## Resume Checklist

1. Read this file and run `git status --short --branch`.
2. Confirm `main` and `origin/main` before changing source.
3. Verify the current App Store Connect review/release state separately.
4. Resolve packages and run a clean generic iOS build before debugging stale
   binary or codec behavior.
5. For codec or geometry changes, rerun the focused tests and the full physical
   sample regression rather than relying on the historical result above.
6. Increment both marketing version and build number for any new upload.
7. Create new release artifacts without overwriting the preserved `1.1.3 (34)`
   record.
