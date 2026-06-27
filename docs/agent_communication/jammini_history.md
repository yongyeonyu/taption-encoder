# 잼민이 히스토리 (Codex 인수인계 문서)

이 문서는 덱스(Codex)가 자리를 비운 동안 잼민이(Antigravity)가 수행한 작업 내역을 카테고리별로 기록한 인수인계 문서입니다.

---

## 🔍 1. dex와의 통신 체계 구축 (2026-06-28)
- **내용**: standalone 인코더 앱인 `taption_encoder` 프로젝트에 적합하도록 에이전트 협업 체계를 포팅하고 통신 체계를 구축했습니다.
- **조치 결과**:
  - `cooperation.md` 에이전트 협업 규칙 문서 및 초기 `jammini_history.md` 생성 완료.
  - `sentinel` 디렉토리 하위의 `BRIEFING.md` 및 `handoff.md` 초기화 완료.
  - `agents` 페르소나 파일 복사 완료.
  - `scripts/jammini_delegate.sh`, `scripts/jammini_watchdog.sh`, `scripts/lib/jammini_conversation_resolver.py` 스크립트 포팅 및 경로 보정 완료.
  - 스크립트 실행 권한 부여 및 수동 검증 수행.

## 🛠 2. Taption Encoder 전용 경로/역할 재보정 (2026-06-28)
- **내용**: Taption 편집기 기준으로 남아 있던 역할 카드와 watchdog 기본 요청을 Taption Encoder 기준으로 재정렬했습니다.
- **조치 결과**:
  - 기준 workspace를 `/Users/u_mo_c/Documents/taption_encoder`로 명시했습니다.
  - Xcode project `TaptionEncoder.xcodeproj`, scheme `TaptionEncoder`, bundle id `com.taption.encoder`를 bootstrap/delegate prompt에 추가했습니다.
  - main Taption app checkout은 명시 요청 없이는 수정하지 않는 reference-only 경계로 기록했습니다.
  - 역할 관점을 codec architecture / QA fixture truth / encoder import-queue-export workflow로 교체했습니다.
  - 기본 검증 표면을 iPhone 중심으로 정리하고, iPad/Simulator는 명시 요청 시에만 포함하도록 조정했습니다.
