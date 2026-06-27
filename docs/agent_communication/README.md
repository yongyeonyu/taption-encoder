# Taption Encoder Agent Communication

This folder contains the local Dex/Jammini cooperation contract for Taption
Encoder.

## Workspace Boundary

- Workspace: `/Users/u_mo_c/Documents/taption_encoder`
- Xcode project: `TaptionEncoder.xcodeproj`
- Scheme: `TaptionEncoder`
- Bundle id: `com.taption.encoder`
- Output policy: H.265 / HEVC video only, MP4 or MOV only

The main Taption app checkout is reference-only from this workspace unless the
owner explicitly asks to edit it.

## Entry Points

- `cooperation.md`: collaboration rules and packet format.
- `scripts/jammini_delegate.sh`: send bounded review/support packets.
- `scripts/jammini_watchdog.sh`: inspect routing status and run route probes.
- `sentinel/BRIEFING.md`: lightweight current-state briefing.
- `sentinel/handoff.md`: index of physical handoff files.

Use `--dry-run` before sending a prompt when the active Antigravity conversation
is uncertain.
