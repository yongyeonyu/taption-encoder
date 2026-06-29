DEX_REVIEW_READY
역할: 한결
범위: Taption Encoder preview playback failure triage
읽은 파일:
- [HomeView.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/HomeView.swift)
- [LoadedFilesPanelView.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/LoadedFilesPanelView.swift)
- [MediaInspector.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Core/MediaInspection/MediaInspector.swift)
- [CodecRoutePlannerTests.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoderTests/CodecRoutePlannerTests.swift)
- [playback_summary.tsv](file:///tmp/taption_encoder_playback_matrix/playback_summary.tsv)

결론: 시뮬레이터 preview 검증 실패 대상 3종(AV1.mp4, Ut Video.avi, QuickTime Graphics.mov)의 결함 원인 판정 및 덱스 조치 가이드 수립

findings:
1) **실패 사실 재확인**
   - **AV1.mp4**: 재생 시 화면이 검게 나오고(`FAIL_BLACK_OR_BLANK`) UI 상에서 동영상 길이(Duration)가 수집되지 않아 통과 실패 판정이 맞음.
   - **Ut Video.avi**: 수동 스크린샷 확인 시 검은 화면이며, AVI 내에 MP3 오디오 트랙이 존재하나 인스펙션 결과에서 오디오가 없음(`No audio`)으로 누락되어 실패함.
   - **QuickTime Graphics.mov**: 재생 프로그레스 시간은 진행되나 실제 비주얼은 계속해서 검은 화면(`FAIL_NO_VISIBLE_VIDEO`)으로 렌더링되어 실패가 맞음.

2) **가장 가능성 높은 원인 분석**
   - **AV1.mp4 / QuickTime Graphics.mov (SMC)**:
     - `QueuePreviewPlayerFactory`가 미디어와 인스턴스에 적용하는 `--avcodec-hw=none` / `:avcodec-hw=none` 옵션이 현재 탑재된 LibVLC(SwiftVLC) 버전에서 지원되지 않는 잘못된 옵션입니다.
     - 이로 인해 LibVLC 내부의 `avcodec` 소프트웨어 디코딩 로더 컴포넌트가 초기화에 실패하거나 오동작하여, 디폴트 AVFoundation으로 처리가 불가능한 AV1 및 SMC 코덱 재생 시 비디오 출력을 내보내지 못하고 화면이 검게 멈춥니다.
   - **Ut Video.avi**:
     - `MediaInspector.swift`의 `normalizedFourCC(_:)` 함수가 AVI 포맷 오디오 헤더의 리틀 엔디언 FourCC 또는 정수 오디오 코덱 ID를 ASCII로 디코딩하는 과정에서 정렬 불일치가 일어나 "mp3"를 올바르게 인식하지 못하고 `.unknown` 코덱 판정을 내렸을 가능성이 높습니다.
     - 썸네일 생성 시에도 `QueuePreviewPlayerFactory.configureSoftwareDecodeOptions`가 동일하게 적용되어 동일하게 썸네일 생성이 실패합니다.

3) **덱스가 즉시 수정해야 할 파일 및 함수**
   - **`TaptionEncoder/Features/Home/HomeView.swift`**
     - `QueuePreviewPlayerFactory` 내의 `configureSoftwareDecodeOptions(on:sourceURL:)` 및 `makeSoftwareDecodeInstance(applicationName:)` 함수.
     - 잘못된 옵션인 `--avcodec-hw=none` 및 `:avcodec-hw=none` 삭제 혹은 지원 규격 옵션(`--avcodec-hwdec=none`)으로 교체.
   - **`TaptionEncoder/Core/MediaInspection/MediaInspector.swift`**
     - `normalizedFourCC(_:)` 함수 및 `audioCodec(from:)` 함수.
     - AVI 컨테이너 내부의 MP3 코덱 FourCC 변환 시 오정렬/바이트 오더 문제 개선.
   - **테스트 우선순위**:
     1. `CodecRoutePlannerTests.swift` 내의 `testQueuePreviewVideoViewProducesVideoOutputForFirstBundledSample` 등 시뮬레이터 preview 플레이어 렌더링 테스트.
     2. `LoadedFilesPanelView` 기반의 썸네일 비디오 렌더링 검증 테스트 케이스 실행.

4) **프로젝트 격리 준수 확인**
   - Taption main project 경로는 일절 참조하지 않았으며 관련 없는 NLE 내용도 포함되지 않았음을 확증합니다. (폐기 대상 아님)

defer:
- (none)

덱스 확인 포인트:
- VLC `avcodec-hw=none` 옵션의 최신 명칭 변경 여부 확인 및 제거 후 플레이어 정상 구동 테스트.
- AVI 오디오 코덱 파싱 시 FourCC 정수 값 바이트 순서 정합성 디버그.
