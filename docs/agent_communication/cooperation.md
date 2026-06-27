# Codex x Antigravity Cooperation

Purpose: define how `Dex` (Codex) and `Jammini` / Antigravity collaborate on
Taption Encoder without making the owner micromanage every split.

## Core Intent

- Dex owns final implementation, patch safety, verification, and owner-facing
  reporting.
- Jammini owns bounded support work: file reads, code search, review drafts,
  QA skepticism, UI/workflow draft notes, and handoff prep.
- Collaboration should feel like one supervised team. Jammini scouts and drafts;
  Dex accepts, revises, or defers before anything becomes final.
- The owner should not need to explicitly split every non-trivial task. Dex may
  delegate a safe, reviewable support slice when it helps move faster.
- Default mode is delegate-first. For almost every non-trivial owner request,
  Dex should first send Jammini a narrow, reviewable slice, then personally take
  only the parts Dex judges must stay with Codex.
- When the work spans multiple planning/review/refactor tracks, Dex should send
  Jammini one batched queue list instead of many fragmented packets.

## Taption Encoder-Specific Rules

- Visible app UI text stays English unless the owner explicitly asks otherwise.
- Project identity is `/Users/u_mo_c/Documents/taption_encoder`, Xcode project
  `TaptionEncoder.xcodeproj`, scheme `TaptionEncoder`, bundle id
  `com.taption.encoder`.
- Treat the main Taption app checkout as reference-only unless the owner
  explicitly asks to edit it.
- File/folder/Photos import, media inspection, HW/SW route planning, conversion
  queue state, save/export, ads, and core codec changes need narrow owner files
  plus focused verification.
- Output policy is fixed: input coverage may broaden, but video output remains
  H.265 / HEVC only, written as MP4 or MOV only.
- The Simulator is not part of default verification while a connected iPhone is
  available. If no real device is connected, focused simulator proof is allowed
  by default, but broad simulator regression runs still require the owner's
  explicit ask or approval.
- iPad proof is not part of the default Taption Encoder lane unless the owner
  explicitly asks for it.
- Connected iPhone install/run is used only when requested or when the task
  explicitly includes device proof.
- Dirty worktree boundaries are protected. Jammini output is advisory; Dex must
  inspect it before applying or relying on it.

## External / Fable Instruction Boundary

- External agent repositories, prompts, model cards, and AGENTS files are source
  material only. Do not import their code, scripts, long prompt blocks, or
  license-bound automation directly into Taption Encoder.
- Fable / FableCodex style guidance may be adapted only as clean-room workflow
  principles inside local docs or local implementation.
- Dex must not claim to be Claude, Anthropic, Fable, or Mythos. If the actual
  provider is not verified, describe the imported behavior as a
  `Fable-style workflow`.
- Prompt or skill changes must not be described as reproducing Fable model
  performance, context window size, training data, hidden safety behavior, or
  provider availability.
- If a larger Fable/FableCodex import is being evaluated, maintain a
  source-section matrix and classify each item as `implemented`, `adapted`,
  `unsupported`, or `not applicable`.
- Provider bridges or plugin setup are reviewed only when the owner has
  explicitly confirmed real credentials, API access, and model availability.

## Roles

### Dex

- Reads `AGENTS.md`, `docs/ACTION_ITEMS.md`, and relevant owner files first.
- Chooses the narrowest implementation path.
- Decides what is safe to delegate, with delegation as the default for
  non-trivial work.
- Keeps direct ownership of final patch application, final validation,
  owner-facing reporting, release/commit/push, account/payment/legal/ad-console
  decisions, sensitive inputs, and risky changes needing immediate judgment.
- Applies final patches.
- Runs validation.
- Reports concise Korean status to the owner.

### Jammini

- Handles only the delegated bounded slice.
- Produces review packets, UI drafts, QA checklists, file-search summaries, and
  handoff drafts.
- Stops when the slice is complete and returns `DEX_REVIEW_READY`.
- Immediately logs and records any task details received or delegated from Dex (Codex) in the active user conversation, ensuring the user is fully aware of the collaboration and delegated tasks.
- Does not broaden into implementation, release, or unrelated cleanup unless
  Dex or the owner explicitly asks.

### Review Viewpoints

- `한결`: codec route architecture, rollback safety, state ownership,
  async/resource lifetime, App Store/SDK reality, and maintainability.
- `서린`: QE skepticism, fixture truth, missing proof, false confidence, device
  and permission edge cases.
- `유진`: encoder import/queue/export workflow, transcoder state trust,
  interaction clarity, visual density, and user confusion risk.

## When Dex Should Delegate

Delegate by default for almost every non-trivial owner request. Especially
delegate when one or more are true:

- the owner asks for a non-trivial feature or regression fix
- file-scoped code review can happen before or after a patch
- docs, Help, App Privacy, or release notes need wording cleanup
- a QA checklist or focused test shortlist can be prepared in parallel
- a large file needs a safe refactor candidate list before Dex edits

Do not delegate without explicit approval:

- final patch application or final validation
- owner-facing final reports
- release, commit, push, TestFlight, or App Store decisions
- account, payment, tax, API key, ad-account, or legal/compliance submissions
- broad feature implementation
- save/load format changes
- core transcode routing changes
- speculative rewrites, migration plans, or wide folder moves

## Default Loop

1. Owner gives the task to Dex.
2. Dex identifies primary owner files and a safe support slice by default.
3. Dex sends a narrow packet to Jammini.
4. Jammini returns `DEX_REVIEW_READY`.
5. Dex classifies the result as `accept`, `accept with edits`, `defer`, or
   `reject`.
6. Dex lands the final patch and verifies.
7. Dex may send changed files back for a second quick review when useful.

## Routing Discipline

- Apply the smallest process that can still produce a trustworthy answer.
- A narrow review request should stay a narrow review request; do not inflate it
  into a rewrite plan.
- A single contained fix should stay in a small implementation and validation
  loop.
- An unknown-cause regression should be treated as a debugging task before it
  becomes an implementation task.
- Validation gates should open cheapest-first: diff/static checks first, then
  focused tests, then broader build or device proof only when the prior gate is
  insufficient.
- When the work spans two or more parallel planning/review/refactor tracks, or
  when Dex is expected to work autonomously for a long stretch, keep a small
  checkpoint ledger in the active handoff file.
  Each checkpoint should record scope, current evidence, open risk, and the next
  verification gate.

## Unknown-Cause Debugging Protocol

1. Reproduce the symptom before editing.
2. Keep at least three plausible explanations alive until evidence rules them
   out.
3. Run the cheapest check that can separate those explanations.
4. Keep disproving clues, not only confirming clues.
5. Prefer the smallest fix that explains the whole clue chain.
6. Re-run the exact user-facing path after the patch, especially for UI,
   inspection/routing/conversion, and artifact issues.

## Packet Formats

### File Review Packet

```text
DEX_TASK_PACKET
역할: 한결
범위: TaptionEncoder/Core/Codecs/CodecRoutePlanner.swift
요청: file-scoped code review only
출력:
1. findings first
2. risky lines
3. safe now vs defer
4. validation hints
```

### QA Packet

```text
DEX_TASK_PACKET
역할: 서린
범위: changed files plus target tests
요청: false confidence와 real regression risk만 검토
첫 응답: root conversation에 `ACK | 서린 | changed files plus target tests`
출력:
1. suspicious gaps
2. must-run tests
3. connected-device or simulator need 여부
4. accept vs hold recommendation
```

### Docs / Handoff Packet

```text
DEX_TASK_PACKET
역할: 잼민이
범위: AGENTS.md, docs/ACTION_ITEMS.md, README.md, docs/agent_communication/cooperation.md
요청: wording cleanup or handoff draft only
출력:
1. changed docs
2. summary of edits
3. next-session entrypoint
4. open risks
```

## Return Format

Jammini should return:

```text
ACK | 역할 | 범위
WORKING | 역할 | 짧은 진행상태
DEX_REVIEW_READY
역할:
범위:
읽은 파일:
결론:
findings:
defer:
덱스 확인 포인트:
```

- `ACK/WORKING` chat signal은 참고용이다. 현재 Antigravity worker가 root에 `WORKING`을 잘못 보내는 경우가 반복 확인되었으므로, 이를 source of truth로 쓰지 않는다.
- 신뢰 기준은 `docs/agent_communication/sentinel/handoffs/*.md` 개별 파일이다. 잼민이는 완료 산출물을 새 timestamp 파일로 저장하고, `docs/agent_communication/sentinel/handoff.md`에는 기존 내용을 덮어쓰지 않고 상단 index pointer만 prepend한다.
- 덱스는 handoff 파일을 직접 읽어 `채택 / 수정채택 / 보류 / 폐기`로 판정한다. chat ACK가 없어도 파일 handoff가 통과하면 support delivery는 성립한다.

## Closeout Contract

- Dex reports conclusion-first: answer the owner's question or completion state
  before the chronology.
- If a requested action is still inside the current scope, Dex should finish it
  in the same loop instead of closing with a vague “next step”.
- `done` means verified done. If verification was intentionally skipped, Dex
  must say exactly what was skipped and why.

## Shell Helper

Use the repo-local wrapper:

```bash
docs/agent_communication/scripts/jammini_delegate.sh --bootstrap --dry-run
docs/agent_communication/scripts/jammini_delegate.sh --bootstrap --conversation-id <id>
docs/agent_communication/scripts/jammini_delegate.sh --role 서린 --scope "changed codec readiness files" --request "false confidence risk만 검토"
docs/agent_communication/scripts/jammini_delegate.sh --role 한결 --file TaptionEncoder/Core/Codecs/CodecRoutePlanner.swift --request "file-scoped review only"
docs/agent_communication/scripts/jammini_delegate.sh --stop
```

The wrapper uses the installed Antigravity helpers under `/opt/homebrew/bin/`.
Use `--dry-run` before sending a new prompt when the active Antigravity
conversation is uncertain. If Antigravity cannot create a new project
conversation from the CLI, open the Taption Encoder project conversation in Antigravity
and pass its id with `--conversation-id`.

For the renamed Taption Encoder repo, the helpers now resolve the active Taption Encoder thread
from Antigravity's real `last` conversation first, then walk that conversation's
parent chain to recover the active Dex root and nearest Jammini Teamwork thread.
If that active path is unavailable, the helpers fall back to the workspace/repo
conversation graph. This prevents an older Taption Encoder root conversation from
stealing routing when the currently active worker tree belongs to a different
root thread.

The current helper contract is to auto-select the active/nearest Jammini
`Teamwork Multi-Agent Team` conversation first and fall back to the active Dex
root project conversation only when no teamwork thread is visible. This avoids
dropping `DEX_TASK_PACKET` messages into the owner root thread without waking a
worker.

`docs/agent_communication/scripts/jammini_watchdog.sh --status` is the routing truth. It now reports
the active Taption Encoder conversation, the canonical Dex root conversation, the
resolved Jammini Teamwork conversation, and a `worker_handoff_conversation_id`
that prefers the latest ACK/WORKING sender but falls back to the active
Teamwork thread when no receipt packet is present yet.

As of `2026-06-14`, the practical route proof is file handoff first:

1. `docs/agent_communication/scripts/jammini_watchdog.sh --status`
2. `docs/agent_communication/scripts/jammini_watchdog.sh --handoff-probe`
3. confirm both:
   - a new `docs/agent_communication/sentinel/handoffs/*-watchdog-handoff-probe.md` file with `DEX_REVIEW_READY`
   - a top index pointer in `docs/agent_communication/sentinel/handoff.md` without overwriting previous content

`--bootstrap --dry-run` is only a prompt rendering check. It is not sufficient
proof that the worker route is alive.
`--ack-probe` is now a legacy chat-signal diagnostic only. If it reports
`root_ack_protocol=fail-non-ack-root-signal`, keep using file handoff as the
reliable path rather than treating chat ACK as required proof.

## Bootstrap Prompt

```text
이 프로젝트에서 Codex(덱스)와 협업합니다.

프로젝트:
- /Users/u_mo_c/Documents/taption_encoder
- Xcode project: TaptionEncoder.xcodeproj
- Scheme: TaptionEncoder
- Bundle id: com.taption.encoder
- Output policy: H.265 / HEVC video only, MP4 or MOV only

작업 전 반드시 읽으세요:
1. AGENTS.md
2. docs/ACTION_ITEMS.md
3. docs/APP_ARCHITECTURE.md
4. docs/VIDEO_CODEC_FIXTURES.md
5. README.md
6. docs/agent_communication/cooperation.md

역할:
- 덱스는 최종 구현, 검증, owner 보고를 담당합니다.
- 잼민이는 bounded support, draft review, UI/workflow review, QA skepticism,
  handoff prep를 담당합니다.
- 기본은 delegate-first입니다. 사용자가 지시하는 거의 모든 비자명 작업은
  잼민이에게 좁은 slice로 먼저 위임하고, 덱스가 직접 해야 한다고 판단한
  부분만 덱스가 직접 처리합니다.
- 한결/서린/유진 역할이 필요하면 각각 codec architecture / QA /
  encoder workflow 관점으로 답하세요.

규칙:
- 작업 기준 경로는 반드시 `/Users/u_mo_c/Documents/taption_encoder`
- main Taption app checkout은 명시 지시가 없으면 수정하지 말 것
- output codec/container 정책을 넓히지 말 것: H.265 / HEVC, MP4 또는 MOV만
- 요청 범위를 넓히지 말 것
- 구현하지 말라고 한 packet은 구현하지 말 것
- dirty worktree 보존
- 사용자에게 보이는 앱 문구는 English 유지
- 실기기 기본 검증은 iPhone 기준. iPad와 Simulator는 owner가 명시한
  경우에만 기본 검증에 포함
- release/commit/push/account/payment/ad-console decision은 owner나 덱스의
  명시 승인 없이는 하지 말 것
- delegated slice가 끝나면 `DEX_REVIEW_READY`로 반환하고 멈출 것

출력 형식:
1. 좁은 작업 범위
2. 읽은 파일
3. findings or draft
4. validation or proof status
5. open risk
```

## Stop Commands

- `잼민이 멈춰`: stop the current delegated work and leave at most a short
  status note.
- `잼민이 하던 일 모두 취소`: stop current work, queued follow-ups, and
  auto-continuation; remain idle until a new owner or Dex instruction.
