DEX_REVIEW_READY
역할: 서린
범위: iPad STT fixture rule and video info popup regression (Bypass off-project Taption-main task)
읽은 파일:
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/ContentViewModel+MediaOpen.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/EditorCanvasView+Popups.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/VideoPlayerPanelView.swift`
- `/Users/u_mo_c/Documents/taption/ios/Taption/UI/Release/VideoTimelinePopupViews.swift`

결론:
Downloads 폴더에서 대용량 비디오 파일 임포트 시 발생하는 `stt_large_document_picker_repro` 오류 원인과 `VideoPlayerPanel` 정보 팝업(`button.video.info`/`popup.video.info`)의 렌더링/라우팅 실패 원인을 분석하여 공유합니다.

findings:
1. **stt_large_document_picker_repro (대용량 Downloads 비디오 접근 실패)**:
   - **소유 파일**: `ContentViewModel+MediaOpen.swift` (라인 62~84)
   - **원인 분석**:
     - `loadVideoDirectlyIfAllowed` 에서 코덱 감지 태스크(`detectAV1Codec`)를 비동기로 수행할 때, `url.startAccessingSecurityScopedResource()` 권한을 얻지만, `defer` 구문에 의해 `await` 비동기 동작이 완료되거나 대기하는 시점에 `stopAccessingSecurityScopedResource()` 가 성급하게 실행됩니다.
     - 이로 인해 Whisper STT 백그라운드 엔진이 대용량 미디어 파일에서 오디오 트랙을 추출하기 위해 파일 입출력을 수행하는 도중 보안 권한이 도중에 차단(Permit expired)되어 디코더가 미디어 데이터를 읽지 못하고 오류를 뿜게 됩니다.
     - 또한, `replaceSelectedVideoURL` 등에서 이전 URL에 대해 `stopAccessingSecurityScopedResource()`를 강제 호출할 때, 동일한 파일 스트림을 멀티스레드 환경에서 여전히 읽고 있다면 IO Exception이 발생할 수 있습니다.

2. **VideoPlayerPanel 정보 팝업 (button.video.info/popup.video.info) 실패 분석**:
   - **소유 파일**: `EditorCanvasView+Popups.swift` (라인 328~339, 734~742), `VideoPlayerPanelView.swift`
   - **원인 분석**:
     - **가드 조건에 의한 조기 반환**: `requestVideoInfo()` 메소드가 호출될 때 `guard isVideoLoaded else { return }` 가드가 존재합니다. 비디오 메타데이터 로딩이나 리소스 셋업이 지연되는 레이싱 상태에서 사용자가 정보 버튼을 탭하면, 상태 값은 로딩 중이지만 가드를 뚫지 못해 `isVideoInfoPopupPresented`가 참으로 변하지 않고 조기 반환(Silent drop)됩니다.
     - **Z-Order/Overlay 가림 현상**: `isVideoInfoPopupPresented`에 의해 활성화되는 `VideoInfoDetailPopupView`는 ZStack의 조건부 렌더링으로 배치됩니다. 만약 상위에 다른 모달 팝업 레이어(예: 프리미엄 결제 팝업 등)가 불투명하게 마운트되거나 Hit-testing을 가로막을 경우 UI 테스트(XCTest) 기기가 이 버튼이나 팝업 엘리먼트를 찾지 못하거나 터치 이벤트가 소실됩니다.

defer:
- 본 일감은 메인 Taption 프로젝트 관련 off-project 일감이므로 실제 프로젝트 소스 코드 수정은 가하지 않고, 본 핸드오프 검토 문서만 저장하고 종결합니다.

덱스 확인 포인트:
1. **대용량 파일 Coordinate Read 보완**:
   - Downloads 폴더 등 외부 스토리지에서 대용량 파일 복사/로드 진행 시, `NSFileCoordinator`를 사용하여 안전하게 로컬 캐시 폴더에 파일 복사를 끝마친 뒤, 해당 캐시 경로의 로컬 URL로 Whisper STT 처리를 유도하면 샌드박스 보안 스코프 유효기간 문제를 완벽히 해결할 수 있습니다.
2. **이벤트 루프 레이싱 방지**:
   - `requestVideoInfo()` 가 비디오 로딩 진행률에 구애받지 않고 언제나 최소한의 메타데이터(예: "Loading..." 플레이스홀더)를 표시할 수 있도록 `isVideoLoaded` 가드 조건을 대폭 완화하는 방향으로 코드 패치를 권장합니다.
