# AGENTS.md

## Project

- Product: Taption Encoder
- Path: `/Users/u_mo_c/Documents/taption_encoder`
- Xcode project: `TaptionEncoder.xcodeproj`
- Scheme: `TaptionEncoder`
- Bundle id: `com.taption.encoder`

## Scope Rules

- Work only in `/Users/u_mo_c/Documents/taption_encoder` for this project.
- Do not edit `/Users/u_mo_c/Documents/taption` unless the user explicitly asks for main Taption work.
- Keep visible app strings in English.
- Output video codec stays fixed to H.265 / HEVC.
- Output containers stay limited to MP4 and MOV.
- Keep proof surfaces separate: local build/test, archive/export, App Store Connect/TestFlight, App Review, device install, and runtime logs are different evidence classes.

## Source-Only Cleanup State

- On 2026-07-07, the working tree was trimmed toward source-only form.
- Historical development docs, proof docs, external generated samples, bundled test videos, sample thumbnail resources, and helper scripts were removed from the working tree.
- Historical material remains recoverable from Git history and remote commits before the source-only cleanup.
- `AGENTS.md` is intentionally kept as the minimal routing and safety file.
