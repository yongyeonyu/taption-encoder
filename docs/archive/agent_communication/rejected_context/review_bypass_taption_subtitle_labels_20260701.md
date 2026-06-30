DEX_REVIEW_READY
역할: 유진
범위: subtitle edit-log display labels
읽은 파일:
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/SubtitleEditorRowComponents.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/Core/Common/Models/SubtitleSegment.swift`

결론:
자막 에디터 로우 옆에 렌더링되는 회색 소스 텍스트(segment.detail)는 SubtitleEditorRowComponents.swift 파일의 147~153라인에서 렌더링되고 있습니다. 저장된 데이터의 물리적인 소스 값은 건드리지 않고, 화면 렌더링 시에만 표시할 간결한 영문 디스플레이 라벨들을 제안하며, 레이아웃 및 혼동 위험 요소와 검증 테스트를 공유합니다.

findings:
1. **렌더링 위치 및 코드**:
   - 파일: `SubtitleEditorRowComponents.swift` (라인 147~153)
   - 구현 방식:
     ```swift
     if let detail = segment.detail, !detail.isEmpty {
         Text(detail)
             .font(.system(size: 13, weight: .regular, design: .default))
             .foregroundStyle(isTimingOverlapping ? overlapAccent.opacity(0.86) : Color.white.opacity(0.62))
             .lineLimit(1)
             .frame(maxWidth: 120, alignment: .leading)
     }
     ```
   - 렌더링될 때 `segment.detail` (즉 `source` 프로퍼티)을 읽어서 가로 최대 120 포인트 크기의 단일 라인 텍스트로 회색(`Color.white.opacity(0.62)`) 처리하여 보여주고 있습니다.

2. **간결한 영문 디스플레이 라벨 제안 (Concise English Labels)**:
   - 데이터는 그대로 유지하고 렌더링 시점에만 접두어로 붙이거나 매핑할 디스플레이 라벨:
     - `[Raw]` : STT(음성인식) 엔진에서 추출한 원시 텍스트임을 나타내는 직관적인 명칭.
     - `[Orig]` : Original의 축약어로, 편집 전 최초 자막 텍스트와 비교하고자 할 때 범용적인 명칭.
     - `[AI]` : 자동 번역 또는 생성형 자막 데이터임을 의미.
     - `[STT]` : 음성 전사(Speech-To-Text)의 성격을 명확히 공지.
     - `[Src]` : Source의 축약어.
     - `[Draft]` : 임시 초안 상태 표시.
     - `[Manual]` : `source == "manual_add_row"` 또는 수동 생성 시 표시.

defer:
- 해당 작업은 메인 Taption 프로젝트 관련 off-project 일감이므로, 실제 프로젝트 소스 코드 수정은 진행하지 않고 본 분석 및 제안 드래프트만 전달하고 종결(Bypass) 처리합니다.

덱스 확인 포인트:
1. **레이아웃 침범 위험(Risks)**:
   - 현재 프레임 크기가 `maxWidth: 120`으로 좁게 차단되어 있습니다. 여기에 접두사 라벨(`[Raw]` 등)을 추가할 경우 실제 원본 텍스트(detail)가 화면에서 너무 일찍 잘리는(truncation) 사용성 문제가 발생할 수 있습니다.
   - 라벨의 투명도를 한 층 더 낮추거나 폰트 굵기(semibold vs regular)를 다르게 주어 실제 텍스트 내용과 명확히 구분해야 사용자의 인지 혼동을 막을 수 있습니다.
2. **테스트 제안(Tests)**:
   - 다양한 `source` 명칭을 주입한 `SubtitleSegment.examples` 모형 데이터를 사용하여 디스플레이 텍스트가 생략되는 임계 가로폭 테스트를 진행할 것을 추천합니다.
