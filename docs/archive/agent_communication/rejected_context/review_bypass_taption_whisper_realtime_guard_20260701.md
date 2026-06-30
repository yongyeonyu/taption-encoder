DEX_REVIEW_READY
역할: 서린
범위: Whisper realtime accuracy guard (Bypass off-project Taption-main task)
읽은 파일:
- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Release/Speech/Whisper/WhisperRecognitionSkeleton.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+WhisperProgressiveRecognition.swift`

결론:
실시간 Whisper STT 전사 처리 중 저신뢰도(low-confidence) 드래프트 텍스트가 성급하게 확정(stable/finalized)되어 자막 정확도가 저하되는 현상을 막기 위한 정확성 우선 게이트(accuracy-first gates) 설계를 제안합니다. 라이브 드래프트가 자막 행으로 승격되고 확정되는 로직의 위치를 특정하였으며, 실시간 프리뷰의 즉각성은 보존하면서도 확정 완성도를 높이는 전략적 제안을 정리하였습니다.

findings:
1. **라이브 드래프트 자막 변환 및 확정 제어 위치**:
   - 파일: `WhisperRecognitionSkeleton.swift` 의 `WhisperRecognitionDraftTimelineController` 구조체
   - 드래프트 생성/업데이트: `applyDraftPacket` (라인 2446~)
     - `packet.isStable` 여부에 따라 `.stableDraft` 또는 `.recognizing` 상태를 매핑하여 로컬 `rows`에 추가 및 병합합니다.
   - 확정 상태 업데이트: `applyStableRange` (라인 2483~)
     - 안정 범위(`packet.timeRange`) 내에 오버랩되는 드래프트 행의 상태를 일괄 `.stableDraft`로 승격시킵니다.
   - 최종 자막 세그먼트 생성 필터링: `finalizedSegments` (라인 2523~)
     - `.stableDraft`, `.userEdited`, `.finalized` 상태인 행들만 최종 `SubtitleSegment` 배열로 가공하여 방출하며, `.recognizing` 등 불안정한 라이브 드래프트는 필터링하여 노출을 차단합니다.

2. **정확성 우선 게이트 제안 (Accuracy-First Gates)**:
   - **게이트 A: 신뢰도 임계값 가드 (Confidence Score Threshold Gate)**:
     - `packet.isStable`이 참이더라도, WhisperKit 디코더가 반환한 토큰 또는 문장 수준의 평균 신뢰도 점수가 특정 임계값(예: 85%) 이하인 경우 즉시 `.stableDraft`로 확정하지 않고 계속 `.recognizing` 상태로 보류합니다.
   - **게이트 B: 룩어헤드 맥락 지연 가드 (Contextual Lookahead Buffer Guard)**:
     - Whisper 모델의 문맥 교정 효과를 반영하기 위해, 실시간 프리뷰 화면에서는 저신뢰도 또는 인식 중인 `.recognizing` 텍스트를 즉시 렌더링하되, 자막 로우(`subtitles` 타임라인)에 저장 및 확정할 때는 최소 1.5초~2.0초의 룩어헤드 프레임을 두어 후속 문맥 디코딩이 완료된 시점에만 `.stableDraft`로 승격하도록 지연을 보장합니다.
   - **게이트 C: 노이즈 및 초단기 프레임 필터 (Speech Rate / Short Duration Gate)**:
     - 간투사("어", "음" 등)나 0.4초 미만의 매우 짧은 소리 파편에서 발생한 텍스트 드래프트는 후속 텍스트와 병합되기 전까지는 단독 자막 로우로 확정하지 않는 필터를 추가합니다.

defer:
- 본 태스크는 메인 Taption 프로젝트 관련 off-project 일감이므로 실제 프로젝트 소스 코드의 수정은 가하지 않고, 본 리뷰 리포트만 바이패스 파일 형태로 보존하고 종결합니다.

덱스 확인 포인트:
1. **불필요한 깜빡임 및 확정 취소 위험(Risks)**:
   - 실시간 프리뷰의 렌더링 빈도가 매우 높기 때문에, 너무 타이트하게 게이트를 차단하면 텍스트가 실시간으로 보였다가 사라지는 깜빡임(flickering)으로 사용자에게 시각적 피로를 줄 수 있습니다.
   - 뷰 렌더링 단에서는 애니메이션 디졸브 처리를 부드럽게 가져가는 UX 보완이 함께 설계되어야 합니다.
2. **테스트 제안(Tests)**:
   - 다양한 음성 프레임 속도와 노이즈가 섞인 실시간 오디오 입력 피처 샘플을 주입하여, 신뢰도 임계치에 따른 자막 보류 및 승격 지연 타이밍이 정상적으로 유지되는지 단위 테스트를 유도해야 합니다.
