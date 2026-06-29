DEX_REVIEW_READY
역할: 한결
범위: in-app sample explorer and sample-source review only
읽은 파일:
- [HomeView.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/HomeView.swift)
- [HomeViewModel.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/HomeViewModel.swift)
- [SourceActionBar.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/SourceActionBar.swift)
- [LoadedFilesPanelView.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/LoadedFilesPanelView.swift)
- [TestVideoSeeder.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/App/TestVideoSeeder.swift)
- [SAMPLE_SOURCES.txt](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/TestVideos/SAMPLE_SOURCES.txt)

결론: iPhone 파일 앱(Files) 썸네일 무한 로딩/실패를 우회하기 위한 인앱 샘플 익스플로러(in-app sample explorer) 아키텍처 및 미디어 교체 리스크 리뷰 완료

findings:
1. **iPhone Files 앱 썸네일 생성 실패의 근본적 원인**
   - 현재 `test video` 폴더에는 iOS의 native 미디어 프레임워크(AVFoundation)가 지원하지 않는 수십 개의 번외 포맷(AV1, VP9, WMV, FLV, AVI, ROQ 등)이 혼재되어 있습니다.
   - 사용자가 시스템의 `UIDocumentPickerViewController`를 통해 이 폴더를 열면, iOS 파일 앱의 백그라운드 썸네일 생성 컴포넌트(QuickLook Thumbnail Extension)가 이를 분석하려고 시도하다 프로세스 행(Hang) 또는 예외 실패를 무한 반복하며 랙을 유발합니다.

2. **Files 썸네일을 우회하는 최적의 인앱 샘플 익스플로러(In-app Sample Explorer) 연동 설계**
   - **시스템 탐색 차단 및 인앱 UI 제공**: `SourceActionBar`에 `Samples` (또는 `Bundled Test Videos`) 신규 버튼을 배정하고, 터치 시 시스템 파일 앱을 띄우지 않고 앱 내부의 Custom SwiftUI List View(`SampleExplorerSheet`)를 띄웁니다.
   - **정적 데이터 매핑**: `TaptionTestVideoSeeder.expectedBundledVideoSampleFilenames` 및 `SAMPLE_SOURCES.txt`를 파싱하여, 파일 이름, 예상 코덱 정보, 파일 포맷 등을 정적 리스트로 정렬하여 표출합니다.
   - **비주얼 렌더 랙 방지**: 썸네일 렌더러 동작 시 발생하는 성능 오버헤드를 막기 위해, 초기에는 이미지 썸네일 없이 단순 **코덱 타입별 뱃지 아이콘**과 텍스트 정보만으로 리스트를 구성하여 경량화합니다.
   - **기존 프리뷰 플레이어 직접 연동**:
     - 사용자가 리스트 내 샘플 항목을 탭하면, `HomeViewModel`에 새롭게 선언할 `openPreviewForBundledSample(filename:)` 함수를 호출합니다.
     - 해당 파일명에 매핑되는 내부 Documents 폴더(`test video/`) 내의 URL을 확보하여 `QueueVideoPreview` 구조체를 즉각 인스턴스화합니다.
     - `presentPreview(preview)`를 바로 실행하여 `HomeView`에 결합된 풀스크린 `QueueVideoPreviewView`를 띄움으로써, 파일 앱의 디렉터리 접근 및 썸네일 생성을 완벽하게 우회합니다.

3. **반복 비주얼 샘플을 실제 공개 소스 클립으로 대체할 시의 잠재 리스크**
   - **번들 용량 1MB 제한 초과 리스크**: 구형/비압축 코덱(LJPG, RAW, YUV, R10K 등)은 고유 비주얼 데이터로 5초만 채워도 수십 MB에 도달하여 앱 빌드 번들 크기가 비정상적으로 팽창됩니다.
   - **오디오-비디오 동기화 및 유실 리스크**: 소스 미디어를 변경하면서 MP3/AAC 등 기존 오디오 트랙 코덱 구조가 파손되면, 플레이헤드 재생 시간 싱크 밀림 현상이나 재생 디코더 에러가 발생하기 쉽습니다.
   - **테스트 케이스 회귀 리스크**: `CodecRoutePlannerTests.swift` 및 타 테스트 스펙이 기존 bear 클립 기준의 Duration(5초)이나 해상도 상수값을 정밀 단언(Assertion)하고 있으므로, 교체 시 관련 통합 XCTest가 대규모 실패할 수 있습니다.

defer:
- (none)

덱스 확인 포인트:
- `SourceActionBar` 내 `Samples` 메뉴 추가에 따른 레이아웃 조율.
- `SampleExplorerSheet` 내 썸네일 백그라운드 추출 적용 여부 결정 (가독성을 위한 텍스트/뱃지 전용 뷰 권장).
