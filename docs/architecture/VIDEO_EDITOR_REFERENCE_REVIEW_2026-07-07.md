# Video Editor Reference Review - 2026-07-07

## Scope

- Purpose: review the OpenCut and CapCut/JianYing automation candidates as architecture references for Taption Encoder's future merge/lightweight-editing work.
- Repository: `/Users/u_mo_c/Documents/taption_encoder`.
- Evidence surface: GitHub repository metadata, README files, and LICENSE files checked through GitHub search/API. No source tree was cloned, no package was installed, and no media/proof artifact was downloaded.
- 2026-07-07 follow-up: the user-supplied shortlist was executed as a reference review refresh through GitHub API metadata checks only. The latest no-clone refresh on the same date found no adoption-guidance changes; only OpenCut's live metadata drifted to 61647 stars and 6632 forks.
- Product boundary: Taption Encoder still outputs H.265 / HEVC video only, and implemented writable containers remain MP4/MOV only.
- This is architecture/reference evidence only. It is not codec execution proof, simulator proof, real-device proof, TestFlight/App Store Connect proof, App Review proof, or public release proof.

## Latest Metadata Snapshot

Checked through the GitHub API on 2026-07-07. Repositories were not cloned or installed.

| Priority | Candidate | Stars | Forks | Primary language | License signal | Latest pushed/updated signal | Read |
| --- | --- | ---: | ---: | --- | --- | --- | --- |
| 1 | OpenCut | 61647 | 6632 | TypeScript | MIT | pushed 2026-06-21, updated 2026-07-06 | First-pass architecture reference for shared core/API/plugin/headless direction. |
| 2 | pyJianYingDraft | 3856 | 615 | Python | Apache-2.0 | pushed 2026-07-05, updated 2026-07-06 | Mature draft-generation/project-model reference. |
| 3 | capcut-mate | 1307 | 223 | Python | Apache-2.0 | pushed 2026-07-05, updated 2026-07-06 | API/workflow automation shape reference. |
| 4 | pyCapCut | 580 | 81 | Python | No root license in API response | pushed 2025-09-12, updated 2026-07-06 | CapCut-specific draft generation reference, but license/maturity need caution. |
| 5 | capcut-cli | 140 | 24 | TypeScript | MIT | pushed 2026-07-03, updated 2026-07-06 | Strong deterministic CLI/library boundary reference despite smaller scale. |
| 6 | SmartCut MCP / capcut-ai-editor | 67 | 16 | Python | MIT | pushed 2026-07-01, updated 2026-07-05 | AI-assisted edit workflow and backup-risk reference. |
| 7 | capcut-export | 49 | 4 | TypeScript | MIT | pushed 2024-12-11, updated 2026-07-06 | Clip-range/source-path accounting reference; also a private-format fragility warning. |
| 8 | capsrt | 4 | 0 | HTML | MIT | pushed 2026-01-07, updated 2026-06-15 | Small subtitle/text-layer extraction reference. |

## Reviewed Candidates

| Candidate | Current source | License signal | Reference value for Taption Encoder | Adoption guidance |
| --- | --- | --- | --- | --- |
| OpenCut | https://github.com/OpenCut-app/OpenCut | MIT license file | Highest-value architecture reference. README advertises a shared web/desktop/mobile codebase, Rust core, plugin-first architecture, and headless mode. | Use as a product-shape reference for a portable editor core, plugin/API boundaries, and batch/headless workflows. Do not import implementation until a separate dependency and license review exists. |
| capcut-cli | https://github.com/renezander030/capcut-cli | MIT license file | Useful model for deterministic command APIs around project inspection, captions, timing, speed, volume, templates, and long-form-to-shorts operations. README explicitly says it is unofficial and not ByteDance-affiliated. | Use as a reference for command/lint/save boundaries and schema-aware write helpers. Do not target CapCut/JianYing draft compatibility as a Taption feature without a separate product/legal decision. |
| pyCapCut | https://github.com/GuanYixuan/pyCapCut | No root LICENSE found in this pass | Useful for draft-generation object modeling and SRT/text automation ideas, but the README says the project is migrating from pyJianYingDraft and that Windows CapCut is still needed for export. | Treat as read-only design inspiration only until licensing and maturity are clarified. |
| pyJianYingDraft | https://github.com/GuanYixuan/pyJianYingDraft | Apache-2.0 license file | Mature Python reference for draft folder/project generation, template loading, separate imported vs generated tracks, SRT import, and batch export concepts. | Use for project-model separation ideas. Keep Taption's project format first-party and avoid direct private-draft writes. |
| capcut-mate | https://github.com/Hommy-master/capcut-mate | Apache-2.0 license file plus NOTICE | FastAPI-based automation surface covering material addition, subtitles, effects, masks, keyframes, and render workflow. | Use as an API surface reference for future automation/headless editing. Do not introduce a server dependency into the iOS app. |
| capsrt | https://github.com/barashik07/capsrt | MIT license file | Small focused parser for extracting subtitles/text layers from `draft_content.json` to SRT. | Use as a lightweight reference for subtitle extraction/import ergonomics, not as a dependency. |
| capcut-export | https://github.com/emosheeep/capcut-export | MIT license file | Useful for source-path and clip-range tracing, with ffmpeg stream-copy export as a conceptual model. README warns newer CapCut/JianYing encryption affected the project and it is entering end-of-life mode. | Use only as a cautionary reference for private draft-format fragility and clip-range accounting. |
| SmartCut MCP / capcut-ai-editor | https://github.com/mrbuslov/capcut-ai-editor | MIT license file | Useful AI/MCP workflow reference: uses captions to cut silences/duplicate takes and updates the project. README warns it modifies projects in place without backup. | Use as a warning to require backup/undo/project-copy semantics before AI-assisted destructive edits. |
| draft_content schema cheat sheet | https://gist.github.com/renezander030/80823f1d47081c312d2c1f9edd20dc22 | Gist/reference note, not a dependency | Useful schema warning: materials and tracks are decoupled, and hand-writing draft JSON is risky; command helpers should own writes. | Use as a design principle for Taption's own project format: typed operations and validation should own edits, not ad hoc JSON mutation. |

## Taption Design Takeaways

1. Keep Taption's project model first-party.
   - The CapCut/JianYing ecosystem shows that private draft formats drift, encrypt, and break tooling.
   - Taption should keep `.fcpxmld`/internal project data under our own typed model, with export/import bridges as separate compatibility layers.

2. Separate materials from timeline segments.
   - The CapCut schema references repeatedly separate material pools from timeline tracks/segments.
   - Taption's `VideoSegment` / `VideoSegmentTimeline` should keep media identity, clip ranges, transforms, captions, and companion effects as explicit references instead of nested ad hoc payloads.

3. Route all writes through typed edit operations.
   - capcut-cli and the schema cheat sheet both point toward command-level write helpers rather than direct JSON edits.
   - Taption should continue toward shared edit operations for trim, cut, split, shorten, reorder, canvas position, caption import/export, and future batch/headless actions.

4. Require backup/undo semantics before destructive automation.
   - SmartCut's in-place warning is a useful negative proof.
   - Any Taption AI-assisted edit, silence-removal pass, or batch retiming flow should create a restorable project snapshot before mutation.

5. Keep headless/batch as an architecture shape, not an immediate app feature.
   - OpenCut and capcut-mate make headless/API workflows attractive, but Taption Encoder's current release scope is the standalone iOS H.265 encoder.
   - For now, encode queue operations, fake encoder UI tests, and future project operations should be designed so a headless runner can call them later.

6. Keep codec policy unchanged.
   - These editor references do not change Taption Encoder's output contract.
   - Video output remains H.265 / HEVC only; writable containers remain MP4/MOV only.

## Immediate Planning Impacts

- P1 merge/lightweight editing should use OpenCut as the first architecture reference for shared core boundaries and headless/batch shape.
- P1 project save/open should borrow the "typed command writes, schema validation, and backup-before-mutation" lesson from capcut-cli, pyJianYingDraft, and SmartCut.
- Subtitle import/export work can use capsrt and pyJianYingDraft as ergonomic references, while keeping Taption's subtitle/project format first-party.
- capcut-export should inform source-path and clip-range tracking, but its own CapCut/JianYing private-format dependency is a caution, not a target.
- capcut-mate is useful for future automation API shape but should not drive an iOS server architecture.

## Sources Checked

- OpenCut repository: https://github.com/OpenCut-app/OpenCut
- capcut-cli repository: https://github.com/renezander030/capcut-cli
- pyCapCut repository: https://github.com/GuanYixuan/pyCapCut
- pyJianYingDraft repository: https://github.com/GuanYixuan/pyJianYingDraft
- capcut-mate repository: https://github.com/Hommy-master/capcut-mate
- capsrt repository: https://github.com/barashik07/capsrt
- capcut-export repository: https://github.com/emosheeep/capcut-export
- capcut-ai-editor repository: https://github.com/mrbuslov/capcut-ai-editor
- draft schema cheat sheet: https://gist.github.com/renezander030/80823f1d47081c312d2c1f9edd20dc22
