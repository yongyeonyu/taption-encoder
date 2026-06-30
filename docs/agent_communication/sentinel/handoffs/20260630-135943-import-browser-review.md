DEX_REVIEW_READY
역할: 유진
범위: File/Folder import should enter in-app browser before system picker
읽은 파일:
- [HomeView.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/HomeView.swift)
- [HomeViewModel.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/HomeViewModel.swift)
- [LoadedFilesPanelView.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/LoadedFilesPanelView.swift)
- [VideoDocumentPicker.swift](file:///Users/u_mo_c/Documents/taption_encoder/TaptionEncoder/Features/Home/VideoDocumentPicker.swift)
결론: iOS App Sandbox 제약으로 인해 외부 저장소는 최초 1회 시스템 Picker를 통한 권한 획득이 필수적이며, 이후에는 Security-scoped Bookmark를 활용해 시스템 Picker를 생략하고 인앱 브라우저로 다이렉트 진입하는 하이브리드 아키텍처가 안전합니다.

## findings

### 1. 시스템 Picker가 반드시 필요한 지점 (iOS Sandbox 제약)
- **외부 파일/폴더의 최초 접근**: iCloud Drive, 기기 로컬 파일(On My iPhone), 외장 스토리지 등 앱의 전용 컨테이너 외부 경로에 접근할 때는 반드시 시스템 픽커(`UIDocumentPickerViewController` 또는 SwiftUI `fileImporter`)를 거쳐야만 해당 경로에 대한 보안 범위 URL(Security Scoped URL) 및 임시 권한(`startAccessingSecurityScopedResource()`)을 획득할 수 있습니다.
- 시스템 픽커를 거치지 않고 외부 경로를 인앱 탐색기로 바로 노출하는 것은 iOS 시스템 정책상 원천 차단됩니다.

### 2. 인앱 탐색기(In-app Browser)로 바로 노출할 수 있는 지점
- **앱 자체 Sandbox 내부 경로**: Documents, Library, Caches, Temp 디렉토리 및 App Bundle 리소스 등. 현재 `openSampleLibrary()`가 시스템 픽커 없이 로컬 Documents/Samples를 바로 로드하는 방식이 이에 해당합니다.
- **사전 권한이 획득된 폴더**: 사용자가 이전에 시스템 픽커로 선택하여 권한이 부여된 루트 폴더는 `Security-scoped bookmark` 데이터로 저장해 두면, 재실행 시 시스템 픽커 호출 없이 인앱 탐색기(`FolderPreviewBrowserView`)를 통해 하위 비디오 파일들을 즉시 리스팅하고 썸네일을 시딩할 수 있습니다.

### 3. User-Confusion Risk (사용자 혼선 리스크)
- **외부 폴더 지정 유실**: 폴더 임포트 시 인앱 브라우저를 첫 진입점으로 삼을 경우, 사전에 루트 폴더 권한 위임이 완료되지 않은 상태라면 비어있거나 불완전한 경로만 보여주게 되어 사용자가 파일 탐색을 진행하지 못하는 인지적 혼선이 발생합니다.
- **북마크 만료 리스크**: iOS 시스템 상황에 따라 기존 보안 북마크가 무효화(`bookmarkDataIsStale`)될 수 있으며, 이때 인앱 브라우저 내에서 "권한 없음" 오류가 났을 때 시스템 픽커를 다시 띄워 권한을 갱신하게 만드는 예외 처리 루프가 유기적으로 연동되어야 혼선이 없습니다.

### 4. Safe Recommendation (안전한 구현 권장 아키텍처)
- **북마크 데이터 영구화**:
  - `HomeViewModel`에서 외부 폴더를 처음 임포트받았을 때(`startFolderFlow`), 해당 URL에 대해 영구 북마크 데이터를 생성 및 저장합니다.
    ```swift
    let bookmarkData = try url.bookmarkData(options: .minimalBookmark, residencyIdentifier: nil)
    // UserDefaults 또는 로컬 DB 저장
    ```
- **하이브리드 진입점 설계**:
  - 사용자가 'Folder' 버튼을 탭할 때:
    - 기존에 저장된 유효한 폴더 북마크가 **존재하는 경우**: 곧바로 인앱 브라우저(`FolderPreviewBrowserView`)를 모달/시트로 열고 내부 목록을 직접 그립니다.
    - 기존 북마크가 **없거나 유효하지 않은 경우**: 시스템 픽커(`VideoDocumentPicker`)를 열어 루트 폴더 위임을 먼저 받습니다.
  - 인앱 탐색기 내부 상단/우측에 "Change Root Folder" 혹은 "Open System Files" 버튼을 명시적으로 노출하여, 사용자가 언제든 시스템 Picker를 호출해 루트 권한을 재설정할 수 있는 탈출구를 열어줍니다.

### 5. Validation Hint
- **북마크 영구성 테스트**: 특정 폴더 임포트 완료 후, 앱을 강제 종료하고 다시 실행했을 때 시스템 파일 앱을 거치지 않고도 해당 폴더의 파일 목록과 썸네일이 인앱 브라우저에 즉각 리스팅되는지 확인합니다.
- **만료/예외 샌드박스 검증**: 권한 만료 또는 `startAccessingSecurityScopedResource()`가 실패했을 때 크래시 없이 시스템 픽커를 자연스럽게 트리거하여 권한 갱신 다이얼로그로 복구되는지 여부를 검증합니다.

## defer
- (none)

## 덱스 확인 포인트
- 본 인앱 탐색기 아키텍처 설계를 토대로 인앱 폴더/파일 북마킹 로직과 진입점 분기 구현 지시 시 작업 착수가 가능합니다.
