# Taption Encoder Refactoring Plan (리팩토링 계획서)

본 계획서는 `Taption Encoder` 프로젝트 내 2,000줄을 초과하는 대규모 파일들을 구조화하고 분할하기 위한 리팩토링 가이드를 제공합니다. UI/UX 및 기능적 동작(Behavior)의 변경 없이, 순수 구조 리팩토링(No Behavior Change Structural Refactoring)을 지향합니다.

---

## 1. 폴더 분류 및 파일 분할 기준 (File Splitting Criteria)

코드의 가독성, 빌드 성능(특히 SwiftUI 및 증분 빌드), 유지보수 편의성을 극대화하기 위해 아래와 같은 엄격한 기준을 적용합니다.

### A. SwiftUI View 파일 분할 기준
- **서브 컴포넌트 추출**: 뷰 내부에 정의된 `@ViewBuilder` 또는 `private func helperView() -> some View` 형태의 내부 헬퍼 뷰가 3개 이상이거나, 파일의 전체 라인수가 1,000줄을 초과할 경우 개별 SwiftUI 파일(`struct SubView: View`)로 추출합니다.
- **바인딩 중심 분리**: 상태 관리를 복잡하게 만들지 않기 위해, 부모 뷰로부터 `@Binding` 또는 의존성 주입을 통해 단순 렌더링을 처리하도록 설계합니다.
- **UI/UX 불변 원칙**: 기존의 애니메이션 효과, 레이아웃 메트릭스(HomeLayoutMetrics), 탭 제스처 등의 UX 요소는 한 줄의 코드 수정도 없이 동일하게 파일만 분리되어야 합니다.

### B. ViewModel 및 비즈니스 로직 분할 기준
- **기능 도메인 단위 Extension 분할**: 단일 ViewModel 클래스가 거대해질 경우, 동일 모듈 내에서 `extension`을 활용하여 파일을 기능별로 쪼갭니다.
- **분할 네이밍 규칙**: `ViewModel+{기능도메인}.swift`로 생성하여 기능별 격리를 유지합니다.
  - *예시*: `HomeViewModel+Ad.swift` (광고 처리), `HomeViewModel+Save.swift` (내보내기/저장), `HomeViewModel+Playback.swift` (프리뷰 재생)
- **독립 헬퍼 객체 위임**: 계산 로직이나 상태 머신이 복잡한 경우 별도의 Helper 구조체나 클래스로 비즈니스 논리를 이관합니다.

### C. Core Algorithm 및 Transcoder 분할 기준
- **인코더/디코더 파이프라인 분리**: 포맷 분석, 커맨드라인 빌더, 실행 엔진, 로깅 모니터링 등의 책임을 분리하여 개별 클래스/구조체로 위임합니다.
- **프로토콜 지향 추상화**: 코덱 처리 엔진은 프로토콜을 구현하도록 유도하여 실제 결합을 최소화합니다.

### D. Test Code 분할 기준
- **시나리오 및 대상 단위 분할**: 테스트가 다루는 대상(예: Hardware Route, Software Fallback, Error recovery)에 따라 테스트 클래스를 쪼개고 별도 파일로 분리합니다.

---

## 2. 프로젝트 내 최장 파일 분석

현재 프로젝트의 Swift 소스 코드 분석 결과, **가장 긴 파일**은 아래와 같습니다:
- **전체 최장 파일**: `TaptionEncoderTests/CodecRoutePlannerTests.swift` (9,156줄)
- **App 소스(프로덕션) 최장 파일**: `TaptionEncoder/Features/Home/HomeViewModel.swift` (5,663줄)

---

## 3. 리팩토링 우선순위 및 파일 분할 상세 계획 (우선순위 순)

2,000줄을 초과하는 총 4개의 파일에 대해 리팩토링 우선순위를 설정하고 상세 계획을 수립합니다.

### 1순위: [HomeViewModel.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/HomeViewModel.swift) (5,663줄)
* **우선순위 이유**: 앱의 핵심 상태 제어기이자 가장 큰 프로덕션 파일입니다. 상태 동기화 및 생명주기가 UI와 얽혀있어 가장 조심스럽지만, 파일 가독성을 위해 가장 먼저 분할이 시급합니다.
* **리팩토링 상세 계획**:
  - `extension`을 이용해 성격에 따라 다음 파일로 쪼갭니다.
    - [NEW] `HomeViewModel+Ad.swift`: 광고 조회, 보상형 광고 시청, 보상 스타 적립 로직 일체
    - [NEW] `HomeViewModel+Save.swift`: 샌드박스 폴더 권한 복구, 임시 저장 파일의 최종 경로 내보내기 로직
    - [NEW] `HomeViewModel+SourceFlow.swift`: Single File/Folder/Photos/Samples 소스 흐름 분석 및 상태 체크
    - [NEW] `HomeViewModel+Preview.swift`: 프리뷰 비디오 브라우저 제어 및 미니플레이어 연동
  - **기능 유지 보장**: ViewModel의 `@Published` 프로퍼티 선언부 및 `init/deinit`은 원래 파일에 유지하고, 기능 메서드들만 extension으로 이관하여 기능 수정 위험을 원천 차단합니다.

### 2순위: [HomeView.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/HomeView.swift) (2,984줄)
* **우선순위 이유**: 홈 화면 렌더링 파일로, SwiftUI의 특성상 긴 선언적 코드가 집중되어 있어 소규모 뷰 변경 시에도 컴파일 속도에 영향을 줍니다.
* **리팩토링 상세 계획**:
  - UI 컴포넌트를 서브 뷰로 명확히 추출하여 신규 파일로 분리합니다.
    - [NEW] `HomeView+Header.swift`: 상단 메뉴바 및 스타 배지 뷰 (`header`, `starBadge` 메서드 이관)
    - [NEW] `HomeView+OutputSelector.swift`: 해상도, 타깃 사이즈, 포맷 선택 메뉴 뷰 (`outputSelector` 이관)
    - [NEW] `HomeView+MiniPlayerOverlay.swift`: 하단 미니 플레이어 오버레이 UI (`miniPlayerOverlay` 이관)
  - **기능 유지 보장**: `@State` 프로퍼티와 메인 뷰 계층 구조 바인딩은 원래 파일에 그대로 두어 뷰 계층 구조나 애니메이션 타이밍에 영향을 주지 않도록 합니다.

### 3순위: [SW_AV1HEVCCodecAlgorithm.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Core/Codecs/AV1/SW_AV1HEVCCodecAlgorithm.swift) (2,675줄)
* **우선순위 이유**: 소프트웨어 디코딩/인코딩 관련 알고리즘 코어 파일입니다. 로직이 밀접해 있으나 코드 길이가 길어 흐름 추적이 어렵습니다.
* **리팩토링 상세 계획**:
  - 변환 프로세스의 단계별 책임을 분리하여 서브 클래스 혹은 델리게이트로 쪼갭니다.
    - [NEW] `AV1HEVCTranscodePipeline.swift`: 실질적인 디코딩/인코딩 파이프라인 프레임 처리 로직
    - [NEW] `AV1HEVCCommandBuilder.swift`: FFmpeg 인수 생성 및 파라미터 매핑 헬퍼
  - **기능 유지 보장**: Core Transcoder 유닛 테스트(`CodecRoutePlannerTests`)를 리팩토링 직전/직후에 수행하여 비디오 출력 품질이나 프레임 유실이 발생하지 않도록 완전 무결성을 유지합니다.

### 4순위: [CodecRoutePlannerTests.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoderTests/CodecRoutePlannerTests.swift) (9,156줄)
* **우선순위 이유**: 테스트 코드이므로 프로덕션 실기기 런타임에는 영향을 주지 않으나, 프로젝트에서 줄 수가 가장 길어 유지보수에 심각한 방해 요인이 됩니다.
* **리팩토링 상세 계획**:
  - 테스트 케이스 시나리오의 성격에 따라 개별 테스트 스위트 파일로 분리합니다.
    - [NEW] `CodecRouteHardwareTests.swift`: Apple Device Hardware HEVC 변환 경로 검증 테스트
    - [NEW] `CodecRouteSoftwareTests.swift`: FFmpeg Fallback 및 소프트웨어 인코더 변환 경로 검증 테스트
    - [NEW] `CodecRouteFallbackTriageTests.swift`: HW/SW 미결정 상태에서의 Triage 및 에러 복구 시나리오 검증 테스트
  - **기능 유지 보장**: 단순히 테스트 케이스를 쪼개어 파일로 나누는 것이므로 전체 테스트 커버리지 및 성공 여부(`xcodebuild test`)에는 전혀 영향을 주지 않습니다.
