DEX_REVIEW_READY
역할: 잼민이
범위: Taption Encoder default video handler conflict after simulator experiments
읽은 파일:
- `TaptionEncoder/Info.plist`
- `TaptionEncoder/Features/Home/ImportableVideoTypes.swift`
- `Scripts/verify_external_player_registration.sh`

결론:
가짜 VLC 시뮬레이터 앱과 같이 표준 비디오 UTI(`public.movie`, `public.video`, `public.mpeg-4`)에 대해 동일하게 `LSHandlerRank = Owner`를 선언하고 있는 외부 플레이어 앱이 설치된 경우, Taption Encoder가 시스템 레벨에서 VLC를 제치고 MP4 파일 등의 기본 연결 앱(Default Opener)으로 등극하도록 강제할 수 있는 **iOS 앱 측 단독 API/설정(Actionable app-side method)은 플랫폼 샌드박스 정책상 존재하지 않음을 확인**하였습니다.

findings:
1. **iOS/iPadOS Launch Services 및 파일 연결 동작 제약 (Platform Reasons)**:
   - **기본 앱 설정 API 부재**: iOS/iPadOS는 macOS나 Windows와 달리 설정 앱이나 public API를 통해 일반 파일 확장자(동영상, 문서 등)의 기본 실행 프로그램을 사용자가 수동 지정하거나 앱이 권한을 얻는 설정 기능을 전혀 제공하지 않습니다. (웹 브라우저 및 메일 앱만 iOS 14+부터 제한적으로 허용)
   - **동등한 Owner 랭크 경쟁 휴리스틱**: 두 개 이상의 앱이 특정 표준 UTI에 대해 동일하게 `LSHandlerRank = Owner`로 경쟁할 때, 시스템 Launch Services는 설치 순서, 내부 앱 번들 식별자 정렬 또는 OS의 고유 휴리스틱 알고리즘에 의존하여 라우팅 우선순위를 부여합니다. 이를 앱이 코드로 우회할 방법은 없습니다.
   - **UTExportedTypeDeclarations 및 exported UTI 제한**: `public.mpeg-4` 와 같은 시스템 표준 UTI를 `UTExportedTypeDeclarations`로 자체 정의하여 덮어쓰려 하는 시도는 컴파일 충돌을 일으키거나 앱 스토어 심사 리젝트 사유가 됩니다.
   - **CFBundleURLTypes (Custom Scheme)**: 특정 커스텀 URL 스키마(예: `taption://`) 라우팅에만 제한되며, 시스템 Files 앱 등에서 발생하는 로컬 파일(`file://`) 오픈 액션의 기본 플레이어 동작에는 영향을 줄 수 없습니다.
   - **Share/Action Extension 및 App Intents**: 공유 시트(Share Sheet)나 단축어(Shortcuts) 목록에 Taption Encoder를 노출시켜 유저가 수동 선택하도록 유도할 수는 있으나, 파일 더블탭/오픈 시 기본 비디오 플레이어 동작을 가로채는 솔루션은 되지 못합니다.

defer:
- 분석 및 검토 전용 일감이므로 실제 프로젝트 소스 코드 수정은 가하지 않고 본 핸드오프 검토 문서만 저장하고 마칩니다.

덱스 확인 포인트:
1. **사용자 수동 선택 유도 UX 설계**:
   - 샌드박스 시스템 특성상 자동 오버라이드는 불가능하므로, VLC 등 타 앱과 충돌하여 파일 자동 연결이 안 될 때를 대비해 "Files 앱에서 비디오 파일을 롱탭(Long-press)한 후 공유 -> Taption Encoder를 선택하여 여는 가이드 안내"를 앱 도움말(Help Screen)이나 파일 임포트 실패 화면에 시각적으로 안내하는 가이드라인 보완이 최선입니다.
2. **정적 검증 스크립트 유지**:
   - `Scripts/verify_external_player_registration.sh` 에서 `LSHandlerRank = Owner` 와 `LSSupportsOpeningDocumentsInPlace = true` 가 정상적으로 정의되어 있는지를 지속 유효성 검사하는 것만으로 정적 수준에서 앱이 제어 가능한 모든 범위의 기본 설정을 보장하고 있습니다.
