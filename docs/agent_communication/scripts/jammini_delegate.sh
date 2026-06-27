#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  docs/agent_communication/scripts/jammini_delegate.sh --bootstrap [--new] [--conversation-id <id>] [--dry-run]
  docs/agent_communication/scripts/jammini_delegate.sh --role <role> --request <text> [--scope <text>] [--file <path> ...] [--conversation-id <id>] [--dry-run]
  docs/agent_communication/scripts/jammini_delegate.sh --stop [--conversation-id <id>] [--dry-run]

Examples:
  docs/agent_communication/scripts/jammini_delegate.sh --bootstrap --dry-run
  docs/agent_communication/scripts/jammini_delegate.sh --bootstrap --conversation-id <id>
  docs/agent_communication/scripts/jammini_delegate.sh --bootstrap --new
  docs/agent_communication/scripts/jammini_delegate.sh --role 서린 --scope "codec readiness mapping" --request "false confidence와 release risk만 검토"
  docs/agent_communication/scripts/jammini_delegate.sh --role 한결 --file TaptionEncoder/Core/Codecs/CodecRoutePlanner.swift --request "file-scoped review only"
  docs/agent_communication/scripts/jammini_delegate.sh --stop
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
jamini_root="$(cd "$script_dir/.." && pwd)"
workspace_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$(cd "$jamini_root/../.." && pwd)")"
ag_send_last="/opt/homebrew/bin/ag-send-last"
ag_send="/opt/homebrew/bin/ag-send"
ag_new="/opt/homebrew/bin/antigravity-send.sh"
ag_stop="/opt/homebrew/bin/ag-stop"
conversation_dir="$HOME/.gemini/antigravity/conversations"
resolver_script="$script_dir/lib/jammini_conversation_resolver.py"
handoff_root="$workspace_root/docs/agent_communication/sentinel"
handoffs_dir="$handoff_root/handoffs"
handoff_index="$handoff_root/handoff.md"

mode=""
role="잼민이"
request=""
scope=""
conversation_id=""
dry_run=0
new_conversation=0
files=()
conversation_resolution_cache=""
conversation_resolution_loaded=0

load_conversation_resolution() {
  (( conversation_resolution_loaded == 0 )) || return 0
  conversation_resolution_cache="$(
    python3 "$resolver_script" \
      --workspace-root "$workspace_root" \
      --conversation-dir "$conversation_dir" \
      --ag-path "$ag_new"
  )"
  conversation_resolution_loaded=1
}

conversation_resolution_value() {
  local key="$1"
  load_conversation_resolution
  printf '%s\n' "$conversation_resolution_cache" | sed -nE "s/^${key}=(.*)$/\\1/p" | head -n 1
}

canonical_project_conversation_id() {
  local canonical_id
  canonical_id="$(conversation_resolution_value canonical_conversation_id)"
  [[ -n "$canonical_id" ]] || return 1
  printf '%s\n' "$canonical_id"
}

jammini_team_conversation_id() {
  local teamwork_id
  teamwork_id="$(conversation_resolution_value jammini_team_conversation_id)"
  [[ -n "$teamwork_id" ]] || return 1
  printf '%s\n' "$teamwork_id"
}

while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --bootstrap)
      mode="bootstrap"
      shift
      ;;
    --stop)
      mode="stop"
      shift
      ;;
    --new)
      new_conversation=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --role)
      (( $# >= 2 )) || { echo "--role requires a value" >&2; exit 1; }
      role="$2"
      shift 2
      ;;
    --request)
      (( $# >= 2 )) || { echo "--request requires a value" >&2; exit 1; }
      request="$2"
      shift 2
      ;;
    --scope)
      (( $# >= 2 )) || { echo "--scope requires a value" >&2; exit 1; }
      scope="$2"
      shift 2
      ;;
    --file)
      (( $# >= 2 )) || { echo "--file requires a value" >&2; exit 1; }
      files+=("$2")
      shift 2
      ;;
    --conversation-id)
      (( $# >= 2 )) || { echo "--conversation-id requires a value" >&2; exit 1; }
      conversation_id="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

bootstrap_prompt() {
  local root_conversation_id
  root_conversation_id="$(canonical_project_conversation_id || true)"
  cat <<EOF
이 프로젝트에서 Codex(덱스)와 협업합니다.

프로젝트:
- ${workspace_root}
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
- 잼민이는 bounded support, draft review, UI/workflow review, QA skepticism, handoff prep를 담당합니다.
- 한결/서린/유진 역할이 필요하면 각각 codec architecture / QA / encoder workflow 관점으로 답하세요.

규칙:
- 작업 기준 경로는 반드시 ${workspace_root}
- main Taption app checkout은 명시 지시가 없으면 수정하지 말 것
- output codec/container 정책을 넓히지 말 것: H.265 / HEVC, MP4 또는 MOV만
- 요청 범위를 넓히지 말 것
- 구현하지 말라고 한 packet은 구현하지 말 것
- dirty worktree 보존
- 사용자에게 보이는 앱 문구는 English 유지
- 물리 파일 handoff가 source of truth다:
  1. 완료 산출물은 docs/agent_communication/sentinel/handoffs/ 아래 개별 파일에 남길 것
  2. docs/agent_communication/sentinel/handoff.md는 기존 내용을 덮어쓰지 말고 상단 index pointer만 prepend할 것
  3. chat ACK/WORKING은 참고용이다. root conversation에 WORKING을 보내지 말고, 확실하지 않으면 chat signal을 생략할 것
- 실기기 기본 검증은 iPhone 기준. iPad와 Simulator는 owner가 명시한 경우에만 기본 검증에 포함
- release/commit/push/account/payment/ad-console decision은 owner나 덱스의 명시 승인 없이는 하지 말 것
- 덱스와의 내부 통신은 compact protocol을 우선 사용하고, 사람 설명은 필요할 때만 최소화할 것
- active task가 있을 때는 recurring timer, self-spawned heartbeat job, 30-second idle ping을 만들지 말 것
- 진행 신호는 ACK, WORKING, DONE, BLOCKED 네 가지로만 짧게 남길 것
- 정말 idle이고 bounded task가 하나도 없을 때만 새 일감을 요청하되 cadence는 10분보다 촘촘하면 안 된다
- 오래된 규칙보다 최신 DEX control update가 우선이다
- delegated slice가 끝나면 DEX_REVIEW_READY로 반환하고 멈출 것

출력 형식:
1. 좁은 작업 범위
2. 읽은 파일
3. findings or draft
4. validation or proof status
5. open risk
EOF
}

delegate_prompt() {
  local file_list="(none)"
  local root_conversation_id
  root_conversation_id="$(canonical_project_conversation_id || true)"
  if (( ${#files[@]} > 0 )); then
    file_list=""
    local file
    for file in "${files[@]}"; do
      file_list+="- \`${file}\`"$'\n'
    done
  fi

  cat <<EOF
DEX_TASK_PACKET
프로젝트: ${workspace_root}
프로젝트 식별자: Taption Encoder / TaptionEncoder.xcodeproj / TaptionEncoder / com.taption.encoder
출력 정책: H.265 / HEVC video only, MP4 or MOV only
역할: ${role}
범위: ${scope:-bounded support slice}
요청: ${request}

HANDOFF_CONTRACT:
1. Chat ACK/WORKING은 참고용이다. 최종 신뢰 기준은 물리 파일이다.
2. review/draft 결과가 있으면 docs/agent_communication/sentinel/handoffs/ 아래 새 timestamp 파일에 DEX_REVIEW_READY 형식으로 저장한다.
3. docs/agent_communication/sentinel/handoff.md는 기존 내용을 절대 overwrite하지 말고, 상단 index pointer만 prepend한다.
4. root conversation에 WORKING을 보내지 않는다. 확실히 ACK를 보낼 수 없으면 chat signal을 생략하고 파일 handoff만 완료한다.

대상 파일:
${file_list}
규칙:
- 구현하지 말고 요청된 support/review/draft만 수행
- 작업 기준 경로는 반드시 ${workspace_root}
- main Taption app checkout은 명시 지시가 없으면 수정하지 말 것
- output codec/container 정책을 넓히지 말 것: H.265 / HEVC, MP4 또는 MOV만
- 요청 범위를 넓히지 말 것
- dirty worktree 보존
- 사용자에게 보이는 앱 문구는 English 유지
- root conversation id: ${root_conversation_id:-unknown}
- HANDOFF_CONTRACT가 이 규칙 목록보다 우선한다
- 실기기 기본 검증은 iPhone 기준. iPad와 Simulator는 owner가 명시한 경우에만 기본 검증에 포함
- release/commit/push/account/payment/ad-console decision은 하지 말 것
- recurring timer, self-spawned heartbeat, idle nag task를 만들지 말 것
- active 상태에서는 ACK, WORKING, DONE, BLOCKED만 짧게 출력할 것
- 정말 idle이고 현재 bounded task가 없을 때만 10분 이상 간격으로 새 일감을 요청할 것
- 최신 DEX control update가 우선이다

반환 형식:
DEX_REVIEW_READY
역할:
범위:
읽은 파일:
결론:
findings:
defer:
덱스 확인 포인트:
EOF
}

send_prompt() {
  local prompt="$1"
  if (( dry_run )); then
    printf '%s\n' "$prompt"
    return
  fi

  if (( new_conversation )); then
    local output
    if ! output="$("$ag_new" new "$prompt" 2>&1)"; then
      printf '%s\n' "$output" >&2
      printf '%s\n' "jammini_delegate: failed to create a new Antigravity conversation. Open the project in Antigravity first or pass --conversation-id." >&2
      return 1
    fi
    printf '%s\n' "$output"
    if ! grep -Eq '[0-9a-fA-F-]{36}' <<<"$output"; then
      printf '%s\n' "jammini_delegate: Antigravity did not return a conversation id. Use an existing project conversation with --conversation-id." >&2
      return 1
    fi
    return 0
  fi

  local target_conv=""
  if [[ -n "$conversation_id" ]]; then
    target_conv="$conversation_id"
  elif target_conv="$(jammini_team_conversation_id 2>/dev/null)"; then
    :
  elif target_conv="$(canonical_project_conversation_id 2>/dev/null)"; then
    :
  fi

  if [[ -z "$target_conv" ]]; then
    printf '%s\n' "jammini_delegate: could not find a Jammini Teamwork conversation or canonical Antigravity project conversation under $workspace_root. Open the Taption Encoder project conversation in Antigravity first or pass --conversation-id." >&2
    return 1
  fi

  # Notify the root conversation when delegating to a sub-conversation or active conversation
  local canonical_id
  canonical_id="$(canonical_project_conversation_id 2>/dev/null || true)"
  if [[ -n "$canonical_id" ]]; then
    local clean_request
    if [[ "$mode" == "bootstrap" ]]; then
      clean_request="대화 채널 바인딩 수동 갱신 (Bootstrap)"
    else
      clean_request="$(printf '%s' "${request:-}" | tr '\n' ' ' | sed -e 's/[[:space:]]\{1,\}/ /g' | cut -c 1-200)"
    fi
    local notify_msg="🤖 [Jammini Working] 역할: ${role} | 범위: ${scope:-작업 분석} | 📋 일감 수신: ${clean_request}"
    local notify_err
    notify_err="$(mktemp)"
    if ! "$ag_send" "$canonical_id" "$notify_msg" >/dev/null 2>"$notify_err"; then
      local err_content
      err_content="$(cat "$notify_err" 2>/dev/null || true)"
      printf 'jammini_delegate: warning: failed to send status update to root conversation (%s): %s\n' "$canonical_id" "$err_content" >&2
    fi
    rm -f "$notify_err"
  fi

  exec "$ag_send" "$target_conv" "$prompt"
}

case "$mode" in
  bootstrap)
    if [[ -n "$conversation_id" ]]; then
      cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/antigravity-send"
      mkdir -p "$cache_dir"
      printf '%s\n' "$conversation_id" >"$cache_dir/last_conversation_id"
    fi
    send_prompt "$(bootstrap_prompt)"
    ;;
  stop)
    if (( dry_run )); then
      if [[ -n "$conversation_id" ]]; then
        "$ag_stop" --dry-run --conversation-id "$conversation_id"
      else
        "$ag_stop" --dry-run
      fi
    elif [[ -n "$conversation_id" ]]; then
      "$ag_stop" --conversation-id "$conversation_id"
    else
      "$ag_stop"
    fi
    ;;
  "")
    [[ -n "$request" ]] || { usage >&2; exit 1; }
    send_prompt "$(delegate_prompt)"
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 1
    ;;
esac
