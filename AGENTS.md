# AGENTS.md

## Project

- Product: YYY Encoder (formerly Taption Encoder)
- Path: `/Users/u_mo_c/Documents/taption_encoder`
- Xcode project: `TaptionEncoder.xcodeproj`
- Scheme: `TaptionEncoder`
- Bundle id: `com.taption.encoder`
- Current release candidate: `1.1.9 (40)` (`WAITING_FOR_REVIEW / AFTER_APPROVAL`, verified 2026-10-07 00:59:24 KST). Branding/configuration/tooling and compact proof were committed and pushed on main at `71d9f67e18e6e6c7f061004599ed143982ee98ae` under CLN07M4Q9B. Review ID: `eb30a21b-6226-4d21-882e-2a99797e27af`. The owner-authorized replacement canceled the prior `1.1.8 (39)` review under NAME06Y2K8.
- Last verified internal TestFlight group build: `1.1.7 (38)` (internal-only)
- TestFlight source commit: `c5e5e8fb832fee4ed06dd86576f81dd9dcbb1e93`
- Latest verified published version: `1.1.5` (App Store Connect readback on 2026-10-06)
- Historical `1.1.3 (34)` code commit: `a04dab782555dac8472c92b3b6fe823146206fc3`

## Maintenance Status

- Feature development ended on 2026-07-17. Keep the project in minimal
  maintenance mode.
- Make changes only for App Review responses, critical defects, security,
  platform compatibility, or an explicit request to resume development.
- On 2026-10-06, NAME06Y2K8 renamed the candidate app to YYY Encoder and
  removed the app-authored home header title, preserving Menu/film icon/stars,
  bundle ID, internal product/scheme and existing user-storage paths. The owner
  explicitly approved canceling review and resubmitting a new build and images.
  Old submission f0a2e763-efe5-4396-bb34-429a8d90ba0b reached COMPLETE after
  cancellation at 22:51:23 KST. The same version resource is now a 1.1.9 draft
  with AFTER_APPROVAL. New Release archive/export and
  focused iPhone/iPad simulator tests (12 each) passed; the separate exact
  record is `/Users/u_mo_c/Documents/TaptionEncoderReleases/1.1.9-40-NAME06Y2K8`.
  Apple validation/upload/processing passed for build 40, delivery/build ID
  44ea1608-1531-462c-8345-121ee09a8d45, VALID / APP_STORE_ELIGIBLE, and the build
  was selected in that draft. On 2026-10-07, the owner authorized native
  precision editing. All 30 ko/en-US screenshots were replaced with exact
  dimensions/order retained; independent pixel comparison verified zero
  changes outside branding/home-title/icon regions. All 26 visible home
  titles, including dimmed iPad sheet backgrounds, were removed. Apple
  delivery, source checksums, dimensions and order were verified for all 30.
  After an interrupted preflight, a read-only resume confirmed no active
  review before a single new submission was created at 00:42:55 KST.
  Review eb30a21b-6226-4d21-882e-2a99797e27af and version 1.1.9 (40) were
  independently confirmed WAITING_FOR_REVIEW / AFTER_APPROVAL at 00:43:56 KST.
  Approval/public release is not yet verified. Preserve the exact release
  and screenshot originals/proofs while that follow-up is active; see
  test.md NAME06Y2K8 and PUB06V8N2R.
- On 2026-10-06, App Store Connect reported `1.1.5` as `READY_FOR_SALE`
  and the newly uploaded TestFlight `1.1.7 (38)` as `VALID / INTERNAL_ONLY`
  with `IN_BETA_TESTING` in `Taption Encoder Internal`. This build includes the
  preview/audio fixes and cannot be used for external testing or App Store
  submission. Verify live state before any further release action; see
  `test.md` (REL06T7M9C) for version-bound evidence.
- On 2026-10-06, App Store version `1.1.8` was created as an unsubmitted
  `PREPARE_FOR_SUBMISSION` draft with Korean/English release notes and
  `AFTER_APPROVAL` release mode. Upload/submission was initially blocked by the
  internal external-approval requirement; see `test.md` (PUB06V8N2R). The owner
  removed that mandatory requirement under RULE06V2Q8; technical checks remain
  mandatory. Build `1.1.8 (39)` was then Apple-validated, uploaded and confirmed
  `VALID / APP_STORE_ELIGIBLE`, selected and submitted at 21:54:54 KST.
  Final 21:54:57 readback: `WAITING_FOR_REVIEW / AFTER_APPROVAL`.
  Local `1.1.8 (39)` review materials were subsequently prepared under LAW06N5K8T;
  that preparation itself did not upload or submit. Submission ID:
  `f0a2e763-efe5-4396-bb34-429a8d90ba0b`; build/delivery UUID:
  `141b3cb7-e2ca-4584-a8f4-4c8fb875cbcb`. Approval/public release remains unconfirmed.
- Do not treat App Store upload, review, or approval as legal clearance for the
  bundled codec dependencies.
- On 2026-10-06, COPY06M2Q8 updated the submitted version's Korean/English
  descriptions, subtitles and keywords to simple video-conversion copy and
  the owner-confirmed contact builday365@gmail.com. Local libVLC/FFmpeg
  source-offer notices now use that address, but the already-submitted build
  `1.1.8 (39)` and its preserved exact-release record still contain the old
  address. Do not claim a metadata/source edit changed that binary or cancel
  review/upload a replacement without the owner's direction.
- COPY06M2Q8 replacement verification completed under NAME06Y2K8: the actual
  1.1.9 (40) IPA's two source-offer notices contain builday365@gmail.com and
  not help@taption.com; that exact build is now submitted. The preserved old
  1.1.8 (39) materials are unchanged and are not evidence of the new email.
- A separate external counsel approval record is optional, not a mandatory
  App Store upload/submission input under the owner's 2026-10-06 instruction.
  Preserve notices, corresponding sources, relink materials, checksums and
  signing/size/version checks. Never fabricate approval or alter pending records.

## Scope Rules

- Work only in `/Users/u_mo_c/Documents/taption_encoder` for this project.
- Do not edit `/Users/u_mo_c/Documents/taption` unless the user explicitly asks for main Taption work.
- Keep visible app strings in English.
- Output video codec stays fixed to H.265 / HEVC.
- Output containers stay limited to MP4 and MOV.
- Keep proof surfaces separate: local build/test, archive/export, App Store Connect/TestFlight, App Review, device install, and runtime logs are different evidence classes.

## Previous Internal Release Snapshot — 1.1.7 (38)

- `1.1.7 (38)` was clean-archived, distribution-exported, Apple-validated,
  uploaded, and confirmed available to the existing internal TestFlight group
  on 2026-10-06. Delivery UUID: `30e114f0-e77e-48c4-b2e2-8d35c7255fdd`.
- Valid prior simulator regression (75 tests and 28 new tests repeated three
  times) was reused after confirming source hashes. This release did not run
  a new physical-device regression or submit a new App Review version.
- Generated archives, IPA, dSYMs and raw proof were permanently deleted at
  the owner's explicit source-only cleanup request. Exact uploaded-build
  symbols are not guaranteed recoverable; the compact proof remains in Git.

## Preserved Canceled Review Release — 1.1.8 (39)

- Local Release clean archive, ordinary `app-store-connect` export, corresponding
  sources (56 contrib archives), and relink materials (76 app objects) are kept at
  `/Users/u_mo_c/Documents/TaptionEncoderReleases/1.1.8-39-LAW06N5K8T`.
- Base source `ed17d666df085bfd08df1648a07ee907d0e0e53f` plus the version patch and
  a non-bundled provenance-only patch reconstructs the 119 candidate source files.
  Runtime code and library binaries are unchanged from the main source. The
  candidate configuration/provenance were uncommitted at capture. The later
  1.1.9 (40) state is now committed/pushed on main; this historical 39 snapshot
  has not been rewritten to match that newer version.
- Original-library technical relink, app/extension signatures, dSYM UUIDs,
  source checksums and exact shipped notice comparison passed. Under RULE06V2Q8,
  technical gate, Apple validation/upload/processing and App Review submission
  passed. No new simulator or physical-device runtime regression,
  modified-library install test or external review-packet transfer was performed
  for build 39; the release uses the prior verified unchanged runtime source.
- The version/digest-bound approval template is intentionally pending and is
  preserved as an unapproved historical record. The old mandatory approval mode
  reached `Legal status is not approved.`. The owner changed external approval
  to an opt-in check under RULE06V2Q8; technical verification and source-offer
  responsibilities remain separate from any legal assessment. The new default
  technical gate passed; `LEGAL_REVIEW_STATUS=NOT_VERIFIED` remains explicit.
- Preserve this requested exact-release review record, including archive, IPA,
  dSYMs, source and relink objects, while review/release follow-up is active. It is
  not a regenerable cache. See `test.md` (LAW06N5K8T) for current evidence.
- A local handoff ZIP was verified against all 104 packet-file checksums. The
  LAW06N5K8T-only 2.4 GiB scratch/package/DerivedData/document caches and its two
  export-log directories were then deleted; the exact candidate materials and
  private signing credentials were preserved. No simulator data was created or
  changed for this preparation task.

## Historical Release Snapshot — 1.1.3 (34)

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
- The historical mandatory gate was blocked by missing external legal approval;
  that extra project requirement is no longer mandatory under RULE06V2Q8.
  Exact-release candidate materials for `1.1.8 (39)`
  are now preserved separately under LAW06N5K8T; they are not a reconstruction
  of the absent `1.1.3 (34)` record.
- `Vendor/OpenSourceCompliance/legal-approval.pending.json` is intentionally
  non-passing and must not be presented as approval.

## Source-Only Cleanup State

- On 2026-07-07, the working tree was trimmed toward source-only form.
- Historical development docs, proof docs, external generated samples, bundled test videos, sample thumbnail resources, and helper scripts were removed from the working tree.
- Historical material remains recoverable from Git history and remote commits before the source-only cleanup.
- On 2026-07-17, Taption Encoder DerivedData, codec build directories, simulator
  test copies, temporary logs, and shared regenerable development caches were
  removed to minimize local storage.
- On 2026-10-06, Encoder-specific old/new archives, IPA, dSYMs, DerivedData,
  package checkouts, test copies, logs and simulator app/data were permanently
  removed after TestFlight verification. Required vendor/resources/licenses,
  compact tracked proof, original user videos and other projects' simulator
  devices/runtimes/data were preserved.
- The first future build may need to resolve Swift packages and rebuild all
  derived artifacts from scratch.
- Keep new generated samples, archives, logs, and proof files outside the
  working tree.
- On 2026-10-07, CLN07M4Q9B committed/pushed the verified 1.1.9 (40) source
  and removed its 3.1 GiB dedicated /private/tmp build/package/test scratch,
  both NAME06Y2K8 simulators and their logs. Twelve unrelated simulators and
  shared runtimes, user videos, credentials and required vendor/resources
  were preserved. No extra Git worktree existed. The owner was asked whether
  to also delete the 1.3 GiB exact release/review records and 91 MiB screenshot
  originals/proofs; no answer has been received, so those remain preserved.
  CLN07M4Q9B remains pending only for that scope decision. Do not claim all
  non-source materials were deleted. See NEXT_CHAT_PROMPT.txt for handoff.

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
