# PVW13S4N8Q

기준: main 44ba80971ccedb1c383371b7148e1341b69d088f, 시작 시 clean. 추적 파일 119개의 SHA-256은 SourceBefore.json에 기록했습니다.
검증 산출물: /private/tmp/BOKKIEncoder-PVW13S4N8Q-yz_55i02

- initial-build-result.json / initial-build.log: Debug build-for-testing 성공. iOS 27 시뮬레이터, Xcode 27.0. 이후 미사용 상단 배지 헬퍼 제거로 최종 빌드는 다시 확인합니다.
- FocusedUnit.xcresult / focused-unit.log: 관련 단위 테스트 20개, 실패 0. 좌우 스와이프 경계·탭 흔들림/수직 이동 제외, 재생 시간·위치 계산, 추가 후 재생 유지·중복 방지·비용 보존, 파일 이동 및 닫기 계약을 검증했습니다.
- UISmoke.xcresult: 임시 UI 검사 선택자가 배경 홈 화면의 `Select 01 Ocean.mp4`를 먼저 선택해 미리보기를 열지 못했습니다. 앱 회귀 판정에 사용하지 않습니다. 폴더 타일 이름으로 범위를 좁혀 재검증합니다.
- UI 증거용으로 90초 H.264 파일 2개 및 HEVC Alpha 파일 1개를 외부 검증 폴더에서 생성했습니다. 전용 시뮬레이터에만 설치했으며 사용자 미디어는 사용·변경하지 않았습니다.

## 실행 중 발견 및 수정

- `UI-phone.xcresult`: VLC의 기존 `fast: true` 시간 이동은 키프레임 간격이 긴 영상에서 10초 이동 오차가 발생했습니다. 정확한 탐색(`fast: false`)으로 수정했습니다. 후속 실제 UI 검사에서 6→16→6초, HEVC Alpha 7→17→7초를 확인했습니다.
- 첫 FFmpeg Alpha 표본은 `hev1` 컨테이너 표기로 재생 준비가 끝나지 않았습니다. Apple AVAssetWriter로 다시 생성한 `hvc1` HEVC Alpha 표본에서 `ContainsAlphaChannel = 1`을 확인했고, 실제 프레임 출력과 재생을 검증했습니다. 두 표본과 로그를 구분해 보존했습니다.
- HEVC Alpha ↔ VLC 전환 시 각 플레이어의 종료 동작이 새 플레이어의 화면 회전 허용을 덮어쓸 수 있었습니다. 회전 허용/복귀의 소유권을 공통 미리보기 컨테이너로 이동했습니다. 재생 엔진별 오디오·PiP·종료 정리는 보존했습니다.
- 임시 UI 검사도 보완했습니다. 추가 후 X는 기존 계약대로 선택한 파일의 변환 목록으로 복귀하므로 Import All 화면 복귀를 기대한 검사를 수정했습니다. iPad의 폴더 시트 밖/광고 영역을 누르지 않도록 영상 중앙 기준으로 배경 탭을 지정했습니다. 가로 검사는 실제 인터페이스 가로 전환을 먼저 확인하고 전체 화면을 캡처합니다.
- `release-build-result.json`: 정확한 탐색 수정 후 iOS Release generic device 빌드 성공(CODE_SIGNING_ALLOWED=NO). 최종 공통 회전 처리 이후 검증은 아래 최종 결과를 사용합니다.

## 최종 결과 — 완료

2026-10-13, Xcode 27.0 / iOS 27 시뮬레이터. 최종 소스에서 모든 검증이 통과했습니다.

| 검증 | 결과 | 근거 |
| --- | --- | --- |
| iPhone 18 Pro Max UI: VLC / HEVC Alpha | 2개 통과, 실패 0 | UI-phone-proof.xcresult, ui-phone-proof.log |
| iPad Pro 13 UI: VLC / HEVC Alpha | 2개 통과, 실패 0 | UI-pad-proof.xcresult, ui-pad-proof.log |
| 관련 단위 테스트 | 20개 통과, 실패 0 | FinalUnit.xcresult, final-unit.log |
| Debug build-for-testing | 성공 | rotation-build-result.json |
| iOS Release generic device build | 성공, 서명 제외 | release-proof-result.json / release-proof.log |
| 소스 보존 및 diff 형식 | 119개 유지, 삭제 0, 변경 3개, diff --check 통과 | SourceBefore.json / SourceAfter.json |

실제 UI 검증 범위:

- 처음에는 조작 위젯이 숨겨지고 영상 탭으로 표시됩니다. 중앙에 재생/일시정지 및 ±10초 버튼이 하나씩 표시됩니다.
- 일시정지 → +10초 → -10초, 탐색 막대 이동, 재생 재개 후 시간이 진행되는 것을 확인했습니다. VLC 6→16→6초, Alpha 6→16→6초 또는 7→17→7초입니다.
- 하단 정보 · 공유 · 파일명 · + Add · X의 순서와 터치 영역, 가로/세로 화면의 배치를 확인했습니다.
- 정보창에 파일 이름·용량·길이·컨테이너·영상 형식·해상도·프레임률·오디오 및 변환 경로를 표시합니다. 닫은 뒤 재생이 이어집니다.
- Apple 기본 공유창에 현재 파일 이름과 용량이 전달됩니다. 공유창 취소 및 다시 열기를 확인했고, iPad의 공유 버튼에 연결된 팝오버도 확인했습니다. 실제 외부 전송은 하지 않았습니다.
- + Add 후 ✓ Added로 전환되고 중복 추가가 차단됩니다. 추가해도 재생이 유지됩니다.
- 하단 좌/우 스와이프가 다음/이전 파일을 재생합니다. 첫/마지막 파일 경계를 지키며, i 버튼에서 시작한 드래그는 정보창을 열지 않고 파일을 이동합니다.
- 다른 파일로 이동 후 돌아와도 추가 상태가 유지됩니다. HEVC Alpha ↔ VLC 전환 후에도 실제 가로 회전과 세로 복귀가 정상입니다.
- X로 닫으면 추가된 파일만 변환 목록에 남습니다. 미리보기에서 추가/정보/공유 동작으로 화면이 닫히지 않습니다.

실제 화면 캡처(검증용 영상, 기존 DEBUG 광고 요청 억제 설정 사용):
`/Users/u_mo_c/.codex/visualizations/2026/10/06/01a1120c-6544-7a80-b5b5-8056e18d2f90/PVW13S4N8Q`

대표 파일: BOKKI-Preview.png, BOKKI-Video-Info.png, BOKKI-Native-Share.png, BOKKI-Preview-Added.png, BOKKI-Preview-Landscape.png, BOKKI-iPad-Preview.png, BOKKI-iPad-Share.png.

범위: 시뮬레이터 상호작용과 빌드 검증까지 완료했습니다. 실기기 설치·서명 배포·App Store 제출·Git 커밋/푸시는 실행하지 않았습니다. main HEAD는 시작 시점 44ba809로 유지되며, 기존 추적 파일 중 Preview Swift 2개와 관련 단위 테스트 파일 1개만 수정했습니다. 프로젝트 버전·키·의존성·광고 설정은 변경하지 않았습니다. 이번 검증용 시뮬레이터 2개만 종료해 실행 자원을 반환했습니다.

# TF13B4K9Q2

2026-10-13 요청: 승인된 미리보기 변경을 main에 커밋·푸시하고 워크트리를 clean으로 만든 뒤 TestFlight 빌드를 업로드합니다.

검증·배포 산출물: `/private/tmp/BOKKIEncoder-TF13B4K9Q2-ui73fb9h`

## 배포 준비

- `git fetch origin` 후 HEAD와 origin/main은 `44ba80971ccedb1c383371b7148e1341b69d088f`로 일치(0 ahead / 0 behind)했습니다.
- 이전 최종 검증 스냅샷과 현재 추적 파일 119개의 SHA-256이 모두 일치합니다. UI 4개·단위 테스트 20개 및 Release 빌드의 성공 결과를 재사용합니다. 근거: `reused-verification.json`.
- Apple API 실시간 조회: 최신 빌드는 `1.1.12 (43)`, 처리 VALID, 내부 IN_BETA_TESTING입니다. App Store 버전 1.1.12는 READY_FOR_DISTRIBUTION입니다. 근거: `builds-before.json`, `versions-before.json`.
- 기존 내부 그룹 `Taption Encoder Internal`은 hasAccessToAllBuilds=true입니다. 그룹·테스터 설정은 유지합니다. 근거: `groups-before.json`.
- 앱·확장·테스트의 Debug/Release 8개 설정을 모두 `1.1.13 (44)`로 올렸습니다. 인증 키는 기존 저장소 외부 경로를 사용하고, 유효한 Apple Distribution 인증서를 확인했습니다.
- 서명 archive, IPA 검증 및 Apple 처리 결과는 진행 후 아래에 추가합니다.
