DEX_REVIEW_READY
역할: 잼민이
범위: Taption Encoder import browser parent navigation and iOS video document handler QA
읽은 파일:
- `TaptionEncoder/Features/Home/HomeViewModel.swift`
- `TaptionEncoder/Info.plist`
- `Scripts/verify_external_player_registration.sh`

결론:
폴더 임포트 시 부모 경로 탐색 가드는 iOS Sandbox 보안 정책에 따라 파일 및 디렉토리 접근 권한(Security Scope) 훼손 및 Unauthorized Access 크래시를 방지하기 위해 반드시 설정된 인증 탐색 루트(Authorized root) 바운더리 검사를 사용해야 함을 확인했습니다.
또한, iOS 시스템 정책상 Info.plist 상의 `CFBundleDocumentTypes` 선언 및 `LSHandlerRank` 설정 외에 앱 단독 런타임 API나 코드로 타 앱(VLC 등)을 밀어내고 시스템 기본 플레이어로 등극하는 방법은 원천적으로 불가능함을 파악했습니다.

findings:
1. **임포트 브라우저 부모 탐색(Parent Navigation) 보안 범위 가드**:
   - `HomeViewModel.swift` 에 구현된 `navigateImportBrowserUp()` 및 `importBrowserURL(_:isInsideRoot:)` 헬퍼 함수 분석 결과:
     ```swift
     private func importBrowserURL(_ url: URL, isInsideRoot rootURL: URL) -> Bool {
         let path = url.standardizedFileURL.path
         let rootPath = rootURL.standardizedFileURL.path
         return path == rootPath || path.hasPrefix(rootPath + "/")
     }
     ```
     - 사용자가 선택한 폴더 상위 디렉토리로 탐색할 때, 탐색 타겟 경로가 앱이 유저 권한을 취득한 `importBrowserRootURL` 의 하위 경로가 아닌 경우 상위 탐색이 강제 제한됩니다.
     - **보안적 이유**: iOS 파일 샌드박스는 `startAccessingSecurityScopedResource()` 권한이 취득된 폴더 하위에 대해서만 파일 읽기를 허가합니다. 가드 없이 부모 폴더 탐색을 허용하여 권한 없는 상위 디렉토리로 이탈하면 iOS 시스템에 의해 파일 읽기(`Permission Error`) 및 탐색 목록 로드 실패 장애(Access Violation)가 발생합니다.

2. **iOS 비디오 플레이어 핸들러 우선순위(LSHandlerRank) 제약**:
   - `Info.plist` 상에 이미 `CFBundleDocumentTypes` 내의 `LSHandlerRank` = `Owner`로 정밀하게 정의되어 있으며, `verify_external_player_registration.sh` 스크립트를 통해 이를 정적으로 정합성 검증하고 있습니다.
   - **강제 오버라이드 가능 여부**: iOS Launch Services 메커니즘상 앱 런타임 Swift/Objective-C 코드로 VLC나 기타 타 플레이어를 강제로 밀어내고 기본 연결 앱 권한을 취득할 수 있는 앱 사이드 메서드나 API는 존재하지 않습니다. 시스템 레벨에서 정적 Info.plist 선언의 우선순위와 설치 순서, 그리고 유저의 최종 선택에 따라서만 기본 핸들러가 결정됩니다.

defer:
- 분석 및 검토 전용 일감이므로 코드는 전혀 수정하지 않고 본 핸드오프 검토 문서만 저장하고 마칩니다.

덱스 확인 포인트:
1. **샌드박스 탐색 이탈 시 오류 처리**:
   - `importBrowserURL` 가드에 걸려 탐색이 차단될 때 사용자에게 무반응 대신 "Cannot navigate outside the imported folder" 등의 피드백 배너나 알림을 제공하는 팝업 UX 처리가 향후 검토될 필요가 있습니다.
2. **연결 앱 검증 보장**:
   - 배포 빌드 시 `Scripts/verify_external_player_registration.sh` 를 빌드 Phase에 추가하여 `LSHandlerRank = Owner` 가 누락되거나 변경되지 않도록 빌드 타임에 강제 확인하는 체계를 활용 중이므로, 이를 계속 빌드 파이프라인에서 유지해야 합니다.
