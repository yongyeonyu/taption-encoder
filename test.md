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

## 커밋·서명·업로드

- 소스 커밋 `3577219fefedf06e3e21c97b1275523bcd3edde9`를 main에 생성하고 origin/main으로 푸시했습니다. clean 상태에서 해당 커밋을 archive했습니다.
- Xcode 27.0 Release archive 및 app-store-connect IPA export가 모두 exit 0으로 성공했습니다. 자동 빌드 번호 변경은 끄고 1.1.13 (44)를 고정했습니다. 근거: `archive-result.json`, `export-result.json`.
- IPA의 앱·Live Activity·Thumbnail 확장 3개 모두 1.1.13 (44), Apple Distribution 서명, Team 4FWG8XXYM7 일치를 확인했습니다. 각 codesign --verify --deep --strict 통과, App Store 배포 프로파일, get-task-allow=false, 프로파일 유효기간을 검증했습니다. 근거: `ipa-verification.json`.
- IPA 크기 28,301,564 bytes, SHA-256 `fe7e70ef5c707eab683923688ebd3c32b065e0d17f50a7b35de4970a2ec96dab`.
- 빌드 후 추적 파일 121개의 SHA-256이 커밋 당시와 모두 일치하고 워크트리 clean입니다. 근거: `post-build-source-verification.json`.
- 2026-10-13 17:24:11 KST, altool UPLOAD SUCCEEDED with no errors(exit 0). Delivery UUID `07b9d10f-018f-48eb-93c3-e376ff40effd`. 근거: `upload-result.json`, `upload.log`.

## 최종 결과 — 완료

- 2026-10-13 17:26:49 KST, Apple API에서 `1.1.13 (44)` processingState=VALID, internalBuildState=IN_BETA_TESTING, usesNonExemptEncryption=false를 확인했습니다. Build ID `07b9d10f-018f-48eb-93c3-e376ff40effd`. 근거: `testflight-ready.json`, `delivery-status.json`.
- 기존 내부 그룹 `Taption Encoder Internal`의 빌드 목록에서도 44/VALID를 확인했습니다. 근거: `internal-group-builds-after.json`(HTTP 200). 새 테스터·그룹 추가 없이 기존 자동 배포 설정으로 사용 가능합니다.
- 이번 배포는 TestFlight 내부 테스트까지입니다. 외부 베타 상태는 READY_FOR_BETA_SUBMISSION이며 App Store 심사 제출은 수행하지 않았습니다.
- 배포 파일은 위 외부 검증 폴더의 `BOKKIEncoder-1.1.13-44.xcarchive` 및 `Export/Taption Encoder.ipa`입니다. 소스 저장소에 IPA·archive·인증 키를 추가하지 않았습니다.
- 검증 완료 항목을 temp.md에서 제거했습니다. 최종 기록 커밋·푸시 후 main/origin/main/실제 원격 SHA 일치, clean 상태 및 배포 소스 119개 일치 확인은 `final-git-verification.json`에 기록합니다.

# IP13S8W4Q1

2026-10-13 요청: iPhone 11에서 미리보기 하단 스와이프로 다음 파일이 재생되지 않는 현상을 실기기로 확인합니다.
근거 폴더: `/private/tmp/BOKKIEncoder-IP13S8W4Q1-ur7esntb`

## 초기 확인 — 실기기 테스트 진행 중

- 시작 HEAD `7c666f2d91db14e2f9ae2915cedbbce43a4bd100`, 워크트리 clean이었습니다.
- 연결 대상은 사용자 iPhone 11 Pro(iPhone12,3), iOS 27.0.1입니다. iPhone 미러링 설정에서도 대상 이름이 iPhone 11 Pro임을 확인했으며 설정을 변경하지 않았습니다.
- devicectl 최초 설치 앱 조회에서 BOKKI Encoder `1.1.12 (43)`이 확인되었습니다. 최신 TestFlight 배포는 `1.1.13 (44)`이므로 최신 설치 상태에서 재현해야 합니다. 일반 배포 앱을 포함한 재조회 결과는 `device-app-before.json`에 보존합니다.
- 현재 미러링 화면은 “iPhone 사용 중 / 연결하려면 iPhone을 잠그십시오”입니다. 사용자에게 화면 잠금을 요청했습니다. 터치 검증과 실제 문제 재현은 아직 수행하지 않았으며 앱 소스를 수정하지 않았습니다.

## 대상 변경 및 연결 준비

- 사용자 요청에 따라 실제 테스트 대상을 iPhone 18 Pro Max(iPhone19,7), iOS 27.2로 변경했습니다. 해당 기기는 이미 `1.1.13 (44)`이 설치되어 있습니다. 근거: `iphone18-app-before.json`, `iphone18-details.json`.
- iPhone 11 Pro에는 대상 변경 메시지를 받기 전에 시작한 동일 소스 Release 개발 서명 빌드 44 설치가 완료되었습니다. 앱 삭제 없이 업데이트했고, 버전 재조회로 44를 확인했습니다. 근거: `install-build44.json`, `iphone11-app-after.json`. 이 기기의 터치 검증은 수행하지 않았습니다.
- Mac의 미러링 선택 기기를 iPhone 18 Pro Max로 변경했습니다. 응답이 멈춘 미러링 앱을 재시작했고 다른 앱은 종료하지 않았습니다.
- 다시 연결한 미러링에도 “iPhone 사용 중 / 연결하려면 iPhone을 잠그십시오”가 표시됩니다. 사용자에게 iPhone 18 Pro Max의 화면 잠금을 요청했습니다. 실제 스와이프 재현·수정·통과 판정은 아직 없으며 작업을 진행 중으로 유지합니다.

## 연결 후 검사 준비

- 사용자 화면 잠금 후 iPhone 18 미러링 연결 및 실제 BOKKI Encoder 빌드 44의 홈 화면을 확인했습니다. 다만 미러링 좌표 터치는 `noWindowsAvailable` 오류로 수행되지 않았습니다. 이 도구 오류를 앱의 스와이프 실패로 판정하지 않습니다.
- 별도 검증 폴더의 실기기 XCTest UI 검사 프로젝트를 배포 서명하여 준비했습니다. 앱 소스는 변경하지 않았습니다. 첫 검사 `DeviceSnapshot.xcresult`는 UI 검사 초기화 시 잠금 인증 실패(com.apple.sharing.authentication error 12)로 종료됐습니다. 스와이프 검사는 실행되지 않았으므로 앱 회귀 판정에 사용하지 않습니다. 근거: `device-snapshot-result.json`, `device-snapshot.log`.
- 실기기 자동 검사를 위해 사용자에게 iPhone 18 Pro Max의 실제 화면 잠금 해제를 요청했습니다. 제어된 합성 영상 2개(01 Ocean.mp4, 02 Sunset.mp4)를 task ID가 포함된 별도 폴더로 준비합니다. 원본 사용자 영상은 수정하지 않습니다.
- 합성 영상 2개의 별도 폴더 `Documents/BOKKI-Swipe-IP13S8W4Q1-ur7esntb` 전송이 완료됐습니다. 근거: `fixture-copy.json`, `fixture-hashes.json`.
- 미러링 앱을 정상 종료했습니다. 이후 devicectl lockState에서 passcodeRequired=true, unlockedSinceBoot=true를 확인했습니다. 자동 검사에 필요한 실제 잠금 해제를 대기합니다. 근거: `iphone18-lock-state.json`. 아직 스와이프의 실기기 통과·실패 결과는 없습니다.

## 최종 실기기 결과 — 완료

2026-10-13, 실제 iPhone 18 Pro Max(iPhone19,7, UDID 00008160-000E195A1140000A), iOS 27.2(24B5099f), 설치된 BOKKI Encoder 1.1.13 (44)에서 검사했습니다. 앱 소스 119개의 SHA-256은 배포본과 동일합니다. 근거: `final-device-verification.json`.

| 검증 | 결과 | 근거 |
| --- | --- | --- |
| 폴더의 영상 2개 미리보기 | 실제 UI 검사 1개 통과, 실패 0 | `device-bottom-swipe-build44-r2.xcresult`, `device-bottom-swipe-summary.json` |
| 1개만 선택한 큐의 미리보기 | 실제 UI 검사 1개 통과, 실패 0; 다음/이전 파일이 없는 상태 재현 | `device-single-file-build44.xcresult`, `device-single-file-summary.json` |

복수 파일 검사 상세:

- 동일한 하단 정보·공유·파일명·Add·X 줄에서 6번 좌우 스와이프했습니다. 01 Ocean → 02 Sunset → 01 Ocean의 실제 파일 이동 4회 및 첫/마지막 경계 유지 2회가 통과했습니다.
- 새 파일의 이름·목록 위치(1 / 2, 2 / 2)·재생/일시정지 상태와 재생 시간 진행을 확인했습니다. 파일을 바꿔도 미리보기가 닫히지 않습니다.
- 정보 버튼에서 시작한 드래그도 이전 파일로 이동하며 정보창을 잘못 열지 않습니다. 정상 정보 버튼 탭 및 정보창 닫기는 작동하고 재생이 유지됩니다.
- Add 후 Added/중복 추가 비활성화, 다른 파일로 이동 후 돌아왔을 때 체크 상태 보존, 추가 후 계속 재생, X로 미리보기 종료를 확인했습니다. 실제 외부 공유 전송·변환·Star 차감은 수행하지 않았습니다.

단일 파일 비교와 원인 근거:

- 테스트 파일 1개만 남은 큐에서 썸네일로 미리보기를 다시 열었습니다. 접근성 목록 위치는 1 / 1입니다. 같은 하단 줄을 양방향으로 길게 스와이프해도 동일 파일을 계속 재생하는 상태가 재현됐습니다. 이동할 인접 파일이 없는 상태입니다.
- 검사 전 기기 기록에서도 외부 파일 열기 후 `Queue preview opened ... position=single`가 확인됩니다. 개인 파일명은 검증 요약에서 제외했습니다. 근거: `prior-preview-modes-sanitized.json`.
- 코드상 단일 파일 흐름은 folderBatch를 비우고, currentReviewPreview에는 playlist가 없습니다. 하단 스와이프는 playlist의 hasNext/hasPrevious가 있을 때만 이동합니다. 복수 파일 흐름·폴더 미리보기는 playlist를 구성합니다.
- 사용 경로: 홈의 Folder에서 영상이 여러 개 있는 폴더를 선택하거나, File에서 여러 영상을 선택하면 이전/다음 이동할 목록이 생깁니다. 현재 재현 결과에 따라 앱 코드를 변경하지 않았습니다. 다른 복수 파일 목록에서 실패한다면 해당 목록의 파일·진입 경로로 별도 재현이 필요합니다.

검사 과정 보완:

- `device-snapshot-unlocked.xcresult`는 검사 선택자 오류로 실제 검사 0개가 실행됐으므로 통과 근거에서 제외했습니다. 선택자를 고친 `device-snapshot-real.xcresult`에서 실제 기기 및 앱 화면 연결을 확인했습니다.
- 첫 폴더 진입 검사는 Files 격자 셀의 중앙(이름 영역) 탭으로 폴더를 열지 못했습니다. 폴더 아이콘 중심으로 검사 터치 좌표를 바꾼 후 올바른 테스트 폴더가 열렸습니다. 첫 실패는 앱의 스와이프 실패로 분류하지 않습니다.
- 완료된 항목은 temp.md에서 제거했습니다. Git HEAD는 `7c666f2`를 유지하며 변경은 검증 기록 temp.md/test.md뿐입니다. 새 앱 빌드·TestFlight 업로드·커밋·푸시는 하지 않았습니다.

실제 실기기 화면: `/Users/u_mo_c/.codex/visualizations/2026/10/06/01a1120c-6544-7a80-b5b5-8056e18d2f90/IP13S8W4Q1`

대표 캡처: `iPhone18-Build44-Next.png`, `iPhone18-Build44-Previous.png`, `iPhone18-Build44-Added-Returns.png`, `iPhone18-SingleFile-AfterSwipe.png`. 합성 테스트 영상 및 실제 배포 앱의 광고 설정으로 캡처했습니다. 검증용 영상은 별도 폴더에만 추가했고 기존 사용자 영상을 삭제·수정하지 않았습니다.

# SB13N6F8Q2

한 파일을 선택하거나 외부에서 열어도 같은 폴더의 영상을 하단 스와이프로 이전/다음 재생하는 수정입니다. 앞선 IP13S8W4Q1 기록은 빌드 44의 수정 전 결과입니다.

근거 폴더: `/private/tmp/BOKKIEncoder-SB13N6F8Q2-5l7s8kfr`

- 원인: 단일 파일 선택 흐름에 인접 파일 재생 목록이 없었습니다.
- 수정: 같은 폴더의 영상 파일을 자연 정렬하고 선택 파일의 위치에서 시작합니다. 인접 파일은 재생할 때 검사하며, 숨김 파일·디렉터리·비영상·오디오 전용 파일은 제외합니다. 재생할 수 없는 인접 항목은 이동 과정에서 건너뜁니다.
- 변환 목록은 선택 파일과 명시적으로 +Add한 파일만 유지합니다. 미리보기를 닫거나 다시 열어도 폴더 탐색과 추가 상태가 보존되며, 큐의 삭제·순서 변경을 되돌리지 않습니다.
- 단일 문서 권한만 있어 폴더를 읽지 못할 경우 첫 수평 스와이프에서 iOS 폴더 선택을 요청합니다. 같은 폴더 또는 상위 폴더를 허용하면 화면을 종료하지 않고 탐색을 이어가며, 관계없는 폴더는 거부합니다.
- 자동 검사: `FocusedUnit-r3.xcresult`, `focused-unit-summary.json` — 27개 실행, 27개 통과, 실패·건너뜀 0. 신규 7개와 기존 미리보기/큐 회귀 20개입니다.
- 검사 보완: 첫 실행의 두 파일명 비교는 단일 카드의 ID 형식 대신 fileName을 검사하도록 수정했습니다. 두 번째 실행에서는 기존 다중 파일 준비 완료 검사(기본 2초)가 Mac 자원 압박 중 시간 초과했습니다. 해당 검사의 대기 한도를 10초로 변경했고 최종 전체 27개가 통과했습니다. 두 번째 실행은 저장 공간 소진 중 결과 저장이 끝나지 않아 이 작업의 프로세스만 종료했으며 완료 근거로 사용하지 않습니다.
- 빌드: Release `1.1.13 (45)` 성공. 앱 및 Thumbnail/Live Activity 확장 모두 버전 45, 팀 4FWG8XXYM7, 서명 검증 통과. 근거: `release-build-result.json`, `release-signatures.json`, `release-source.json`.
- 실기기 설치: iPhone 18 Pro Max(00008160-000E195A1140000A, iOS 27.2)에 기존 앱을 업데이트하고 설치 버전 45 확인. 근거: `iphone18-install45.json`, `iphone18-installed45.json`.
- 실제 File 선택 검사 완료: 작업 소유 합성 영상 폴더에 00 Before.mp4와 03 Alpha.mov를 추가하고 네 파일 중 01 Ocean.mp4 하나만 선택했습니다. Files 선택된 셀 1개, 홈 변환 큐 1개, 선택 파일의 재생 목록 위치 2 / 4를 검증했습니다.
- 실제 iPhone 18 Pro Max, 빌드 45, iOS 27.2: `device-single-file45-r3.xcresult`, `device-single-file45-summary.json` — 1개 실행, 1개 통과, 실패·건너뜀 0, 111.258초. 실제 하단 줄 스와이프 10회(파일 이동 8회, 양 끝 경계 2회), 재생 시간 증가, 정보 시트, 일반 VLC 재생↔HEVC Alpha 네이티브 재생 전환, +Add 후 재생 유지, 추가 체크 보존, X로 종료, 변환 큐 2개만 유지, 다시 열어 폴더 4개 탐색을 확인했습니다.
- 기존 Folder 모드 실기기 회귀: `device-folder45.xcresult`, `device-folder45-summary.json` — 1개 실행, 1개 통과, 실패·건너뜀 0, 38.840초. 단일 파일 세션 뒤 같은 폴더를 Folder로 다시 열고 3번의 실제 스와이프를 검사했습니다. 앞선 세션의 Added 표시가 새 폴더 세션에 남지 않고, X로 폴더 목록 복귀 및 폴더 목록 닫기도 통과했습니다.
- 실기기 검사 보완: 첫 실행은 iOS 파일 선택의 열기 버튼 식별자가 폴더 선택과 달라 선택을 확정하지 못했습니다. 관측한 파일 선택 버튼 식별자로 수정했습니다. 두 번째 실행은 XCTest가 애니메이션 완료를 두 번 각각 60초 기다리면서 90초 테스트 영상이 종료되어 실패했습니다. 검사 프로세스에서만 XCUIApplication의 idleAnimationWaitEnabled를 false로 설정한 뒤 동일한 Release 앱에서 모든 터치·재생 상태 검사가 통과했습니다. 관련 인터페이스 확인: https://github.com/appium/WebDriverAgent/blob/master/PrivateHeaders/XCTest/XCUIApplication.h . 앱 코드·광고·재생 시간은 이 검사 보완 과정에서 변경하지 않았습니다.
- 접근 권한 요청·관계없는 폴더 거부·폴더 허용 전 원래 미리보기 유지 조건은 자동 검사로 확인했습니다. 실기기 두 검사는 앱 소유 테스트 폴더에서 수행하여 추가 폴더 권한이 필요한 외부 공급자 상황을 실기기에서 재현하지는 않았습니다.
- 캡처 10개: `/Users/u_mo_c/.codex/visualizations/2026/10/06/01a1120c-6544-7a80-b5b5-8056e18d2f90/SB13N6F8Q2` . 대표 캡처는 `iPhone18-Build45-OnlyOneSelected.png`, `iPhone18-Build45-SelectedMiddle.png`, `iPhone18-Build45-Previous.png`, `iPhone18-Build45-Next.png`, `iPhone18-Build45-NativeAlpha.png`, `iPhone18-Build45-TwoItem-Queue.png`, `iPhone18-Build45-FolderMode-Regression.png`입니다. 실제 기기 캡처이며 이미지 편집을 하지 않았습니다.
- 최종 소스는 Release 빌드 당시 해시와 일치합니다(test.md/temp.md의 기록 변경 제외). 선택·재생 과정에서 변환을 실행하거나 Star를 차감하지 않았습니다. 기존 사용자 영상·키·다른 프로젝트 파일을 삭제하지 않았고, 검사에 사용한 BOKKI 전용 시뮬레이터는 종료했습니다.
- 완료 항목은 temp.md에서 제거합니다. Git HEAD는 7c666f2를 유지합니다. 이번 수정은 커밋·푸시·TestFlight 업로드 전이며, 빌드 45는 iPhone 18에 직접 설치한 실기기 검증용 빌드입니다.

# SW14F6P2R9

사용자 재현: 재생 중 파일명·버튼이 있는 하단 줄을 스와이프하면 영상 이동 대신 탐색창이 뜹니다. 빌드 45의 앱 내부 폴더 검증으로 외부 문서 권한 흐름까지 검증됐다고 판단할 수 없습니다.

근거 폴더: `/var/folders/q1/0p9tcvnx7yx5l12y55zm4tdm0000gn/T/BOKKIEncoder-SW14F6P2R9-1wfkt_4o`

- 기기 로그: 외부 파일 열기 직후 Single file preview needs folder access 분기 확인. 개인 파일명·경로를 제외한 근거는 `before-sanitized-events.json`입니다. 원본 로그는 저장소 밖에만 보존했습니다.
- 수정: 스와이프는 이전·다음 이동만 수행하며 권한 미보유 상태에서 폴더 선택창을 열지 않습니다. 짧은 안내만 표시하고, 정보 메뉴의 Connect folder를 눌렀을 때만 폴더 선택을 표시합니다.
- 정보 시트를 닫은 후 폴더 선택을 표시해 두 모달이 겹치지 않도록 했습니다. 연결 후에는 현재 영상이 유지되며 다음 스와이프부터 폴더 내 이동이 가능합니다.
- 허용한 입력 폴더·명시적으로 연결한 폴더의 북마크를 앱 설정에 보관하고, 해당 폴더의 파일을 다시 열면 security scope를 복원합니다. 관련 없는 폴더를 적용하지 않고, 손상된 북마크는 제외하며 복원 과정에서 UI를 표시하지 않습니다.
- 자동 검사: `FocusedUnit.xcresult`, `focused-unit-summary.json` — 30개 실행, 30개 통과, 실패·건너뜀 0. 권한 미보유 스와이프 결과 분리, 연결 북마크의 모델 교체 후 보존, 손상/관계없는 북마크, Folder 선택 권한 재사용 및 기존 탐색/큐 회귀를 포함합니다.
- Release 1.1.13 (46) 빌드·앱 및 두 확장 서명 검증 통과. iPhone 18 Pro Max 업데이트 설치와 버전 46을 확인했습니다. `release-build-result.json`, `release-signatures.json`, `iphone18-install46.json`, `iphone18-installed46.json`.
- 실기기 외부 경로 검사 준비: Files 앱의 로컬 위치 조회 후 테스트 소유 영상을 로컬 외부 폴더로 복사하려 했으나 File View를 찾지 못해 복사 작업을 시작하지 못했습니다. 사용자 파일을 수정·삭제하지 않았습니다. 이 준비 검사는 BOKKI 기능 통과 근거로 사용하지 않습니다.
- 사용자에게 빌드 46에서 문제가 났던 같은 영상을 다시 열어 재생 화면에 두도록 요청했고, 같은 영상을 열어 두었다는 답변을 받았습니다. 앱 소유 합성 파일 대신 실제 해당 외부 파일로 검증했습니다.
- 실제 파일 위치: iCloud Drive의 다운로드 폴더. 파일명·개인 경로는 이 기록과 최종 요약에 포함하지 않습니다. 별도의 source-private.json 및 XCTest 원본은 저장소 밖에만 보관했습니다.
- UI 보완: 정보 메뉴의 폴더 이름 표시, 안내가 타임라인과 겹치지 않도록 위치 조정, 폴더 선택을 UIKit에서 직접 표시하며 delegate 및 interactive dismissal 모두 표시 상태를 정리하도록 수정했습니다. 최종 빌드는 1.1.13 (47)입니다.
- 최종 자동 검사: `FocusedUnit47.xcresult`, `focused-unit47-summary.json` — 30개 실행, 30개 통과, 실패·건너뜀 0. 빌드 47 소스로 재실행했습니다.
- 실제 권한 미보유 동작: 빌드 46의 외부 열기 및 빌드 47의 같은 iCloud 파일 선택에서 양방향 하단 스와이프가 Files 선택창을 열지 않고 현재 미리보기를 유지했습니다. `actual-external47-r4.log`의 EXTERNAL_BLOCKED_SWIPE_NO_PICKER_PASSED로 단계 결과를 확인합니다.
- 실제 취소 및 연결: `actual-external47-r4.log`의 EXPLICIT_FOLDER_CANCEL_KEEPS_PREVIEW_PASSED, 그리고 iCloud 다운로드 폴더를 명시적으로 선택한 뒤 목록 수가 1보다 커지는 것을 확인했습니다. 이 실행 전체는 파일 이동 후 메뉴가 숨겨지는 동안 접근성 파일명을 바로 읽은 검사 도구 오류로 실패했으므로 전체 테스트 통과로 기록하지 않습니다.
- 실제 연결 후 및 재실행: `connected-icloud47.xcresult`, `connected-icloud47-summary.json` — 실제 iPhone 18 Pro Max(00008160-000E195A1140000A, iOS 27.2), 1개 실행, 1개 통과, 실패·건너뜀 0, 67.021초. 현재 파일 닫기/선택 파일 다시 열기, 실제 이전·다음 재생, 앱 종료·재실행 후 같은 파일 하나만 재선택, 추가 폴더 요청 없이 목록 복원, 연결 버튼이 재등장하지 않음, 양방향 이동 재검증을 통과했습니다. 메뉴가 숨겨진 경우 배경 탭으로 다시 표시한 뒤 파일명·재생 상태를 검사합니다.
- 검사 도구 보완: 재생 중 스와이프 직후 정보 메뉴는 애니메이션·안내 표시가 정리된 뒤 확인했습니다. iOS 27 폴더 선택창에 취소 텍스트 버튼이 없어 표준 시트 스와이프 닫기로 검사했습니다. directoryURL은 권한 없는 iCloud 부모 폴더로 처음부터 이동시키지 못해, 실제 iCloud Drive → 다운로드 폴더를 명시적으로 탐색해 연결했습니다. 잘못된 폴더를 선택해 검증을 통과시키지 않았습니다.
- 최종 배포/보존: 앱 및 두 확장 모두 빌드 47·서명 검증, iPhone 18 설치 버전 47 확인. 실제 iCloud 다운로드 폴더는 연결되어 있으며 마지막 검사는 원래 선택 파일의 재생 화면으로 돌아왔습니다. 변환 실행·Star 차감·외부 공유 전송·사용자 미디어 삭제/수정은 수행하지 않았습니다.
- 저장 공간 보완: 진행 중 디스크가 소진되어, 활성 BOKKI 빌드가 없음을 확인한 뒤 이 작업이 생성한 전용 Debug Build 캐시와 Release Intermediates.noindex만 제거했습니다. 소스·패키지 의존성·인증 키·기존 사용자 영상·검사 결과·Release 앱은 보존했고 다른 프로젝트 캐시는 삭제하지 않았습니다. 필요한 캐시는 빌드 47 검사에서 재생성했습니다.
- `final-verification.json`: 최종 소스 해시가 Release 47 빌드와 일치, git diff --check 통과. Git HEAD는 7c666f2를 유지하며 이번 수정의 커밋·푸시·TestFlight 업로드는 하지 않았습니다. 완료 항목을 temp.md에서 제거합니다.

## RF14T0P10A — 다방면 코드 리뷰 / 상위 10개 리팩토링 (2026-10-14)

기존 SB13N6F8Q2·SW14F6P2R9 미커밋 구현과 검증 기록을 보존한 상태에서 시작했습니다. 구현·파일 접근·취소/수명·큐·메모리·저장 복구·용량·수치·UIKit 모달·배포 경계를 검토했습니다. 재생성 자료는 `/private/tmp/BOKKIEncoder-RF14T0P10A-5nan1f74`에 두고 원본 영상/인증 키/타 프로젝트 자료는 변경하지 않았습니다.

| 우선순위 | 개선 항목 | 발견 근거와 반영 내용 |
| --- | --- | --- |
| 1 | 인코딩 원본 보호 | EncoderService가 임시 경로를 먼저 삭제하므로 원본과 같은 경로/링크인 잘못된 계획이 원본을 지울 수 있었습니다. MediaFileIdentity로 동일 경로·심볼릭 링크·하드 링크를 사전 거부하고 취소 여부도 삭제 전에 확인합니다. 기존 출력 삭제 오류도 숨기지 않습니다. |
| 2 | 초기화 정리 범위 | reset 이후 비동기 전체 디렉터리 정리가 새 작업 출력까지 제거할 수 있었습니다. PendingSaveCleanup이 초기화 시 캡처한 작업만 정리하며 기록 삭제 실패 시 영상은 보존합니다. |
| 3 | 저장 복구의 오류 구분 | fileExists(false)가 접근 오류와 실제 누락을 함께 취급했습니다. 일반 파일 여부를 검사하고 누락만 복구/정리하며 권한·IO 오류는 전파해 manifest를 보존합니다. 디렉터리는 영상으로 복구하지 않습니다. |
| 4 | 보안 범위 접근 수명 | URL 배열과 수동 start/stop이 분산되고 모델 해제 시 scope 회수가 없었습니다. SecurityScopedAccessStore가 표준 경로별 획득을 중복 제거하고 성공한 획득만 해제·deinit 회수합니다. encodingStartTask 해제 취소도 추가했습니다. 광고 polling의 self 강한 참조가 sleep/await 동안 지속되는 수명 문제도 제거하고 operation ID로 취소/교체된 조회의 상태 덮어쓰기를 막았습니다. |
| 5 | 검사 캐시의 메모리 상한 | 검사 결과가 무제한 누적됐습니다. InspectedMediaCache를 큐 모델에서 분리해 128개 LRU 상한·접근 갱신·fingerprint 불일치 무효화를 적용했습니다. |
| 6 | 폴더 북마크 책임 분리 | HomeViewModel 안의 저장·복원·중복 제거 로직이 섞이고 stale 북마크가 갱신되지 않았습니다. PreviewFolderBookmarkStore가 UI 없는 복원, stale 갱신, 잘못된/중복 데이터 정리와 20개 상한을 담당합니다. 경로 포함 검사는 공통화했습니다. |
| 7 | 저장 용량의 안전한 계산 | Int64 합산 overflow와 아직 없는 출력 디렉터리의 용량 조회 실패 가능성이 있었습니다. StorageByteBudget이 포화 합산/음수 보정을 하고 실제 존재하는 출력 볼륨의 상위 경로에서 용량을 조회합니다. |
| 8 | 영상 정보·재생 수치 공통화 | 매우 큰 duration/fps의 Int 변환이 trap을 일으킬 수 있고 UI 파일에 계산이 섞여 있었습니다. LoadedVideoInfoFactory·MediaDisplayFormatting·QueuePreviewPlaybackMath로 분리하고 비정상 수치·geometry를 거부합니다. native seek도 유한 시간/CMTime 표현 범위로 제한합니다. |
| 9 | 큐 입력 중복 제거 | FolderEncodingBatch의 Dictionary(uniqueKeysWithValues:)가 중복 URL에서 crash할 수 있었습니다. 표준 경로 기준 입력을 순서 보존 중복 제거하고 파일 선택 진입에도 적용했습니다. |
| 10 | 미리보기 모달/실패 상태 | UIKit 공유·폴더 presenter를 별도 파일로 분리했습니다. 닫힌 뒤 예약된 async present가 실행되지 않도록 요청 ID를 무효화하고 이미 열린 모달 위 중복 표시를 막습니다. native 오디오 활성화 실패가 무한 로딩으로 남지 않도록 오류 상태와 session 정리도 적용했습니다. |

검증 진행 기록:
- 작업 전 변경은 `before.patch`, git 상태는 `before-status.txt`에 보존했습니다.
- 신규 회귀 15개 + 기존 관련 회귀 45개: `ReviewUnit48-r2.xcresult`, **60개 통과, 실패/스킵 0**.
- 전체 활성 검사 첫 실행: 419개, 4 assertion 실패(3개 테스트). 샘플 이미지 삭제 후 이전 필수 리소스 가정, 변경된 외부 승인 선택 정책, FFmpeg decoder 나열 순서를 예전 문자열로 확인하던 검사입니다. 기존 source-only 정리와 현재 배포/빌드 레시피에 맞게 검사를 교정했으며 해당 제품 소스/배포 게이트를 완화하지 않았습니다.
- 빌드 번호는 앱·확장·검사 구성 모두 48, 마케팅 버전은 1.1.13입니다.
- 수명 추가 검사: 광고가 unavailable일 때 polling 시작 후 HomeViewModel을 해제하면 weak 참조가 nil인지 검증했습니다. 최종 전체 활성 검사 `ReviewAll48-final.xcresult`: **420개 통과, 실패/스킵 0**(`review-all-final-summary.json`).
- 최종 Release `build analyze`: 모두 성공(`release-build-result.json`, `release-build.log`). 기존 AVAssetExportSession 호환 어댑터의 deprecated API 경고는 남아 있으며, 이 범위에서는 호환성 변경을 하지 않았습니다.
- 실제 iPad Pro 12.9-inch 6세대(iPad14,6, iPadOS 27.0.1)에 최종 1.1.13(48) 설치 성공(`ipad-install48-final.json`). 기존 앱 데이터는 유지했습니다. 작업 전용 synthetic fixture 3개만 Documents/BOKKI-Review-RF14T0P10A에 추가했습니다.
- 실기기 UI 첫 시도는 XCTest runner가 automation mode 활성화 시간 초과로 시작하지 못했습니다(`ipad-review48.xcresult`/summary). 앱 기능 테스트가 통과한 것으로 계산하지 않습니다. 잠금 해제 요청을 보냈으며, iPad 시뮬레이터 검사를 별도로 진행합니다.
- iPad 시뮬레이터(iPad Pro 13-inch M5, iPadOS 27.0) UI: `IPadSimulator48.xcresult`, **2개 통과, 실패/스킵 0**. VLC/HEVC Alpha 재생·양방향 footer swipe·첫/마지막 경계·10초 이동·정보·native 공유 및 재열기/취소·Add 중복 방지·목록 복귀·portrait/landscape 배치를 검증했습니다. 화면은 작업용 합성 영상이며 원본/공유 대상에 외부 전송하지 않았습니다.
- 실제 iPad는 최종 설치 메타데이터 `ipad-installed48-final.json`으로 1.1.13(48)을 확인했고 `ipad-launch48.json`에서 앱 실행 성공을 확인했습니다. 실기기 터치 검사는 앞서 기록한 자동화 연결 제한으로 미완료이며 시뮬레이터 결과와 구분합니다.
- 배포 소스 커밋: `2e14c1d110a7e93c90ad289e35ba6133a0fa9036`, main 커밋/푸시·git clean 확인 후 동일 소스를 archive했습니다. `build-source.json`과 `post-archive-source-verification.json`의 소스 hash 일치.
- `BOKKIEncoder-1.1.13-48.xcarchive` archive 및 App Store Connect export 성공. 앱·Live Activity·thumbnail extension 모두 1.1.13(48), Apple Distribution 서명·팀·배포 provisioning 검증 성공(`ipa-verification.json`). IPA 28,392,614 bytes, SHA256 `09ef456adcce7b01c828e0f633d0ddcc954dce0a04cb991c020499ec0d9481fd`.
- Apple upload 성공(`upload-result.json`, `upload.log`). Delivery/build ID `9188d2c9-d649-4980-a13c-e5bc6b0a48ee`.
- 2026-10-14 02:57 KST Apple 처리 **VALID / IN_BETA_TESTING** 확인(`testflight-ready.json`). 내부 beta group 1개에 빌드 48 포함 확인(`internal-groups48-verified.json`). 한국어/영어 TestFlight 안내 등록 후 내용 재조회 일치(`beta-notes-verified.json`). 외부 beta 심사/App Store 재심사는 이번 요청 범위에서 제출하지 않았습니다.


## CL14R7G2K9 — 생성 자료 및 BOKKI 전용 시뮬레이터 삭제 (2026-10-14)
- 사용자 요청에 따라 BOKKI 소유 임시 빌드/검사 캐시, SPM 다운로드 캐시, archive/IPA/dSYM/xcresult, 테스트 harness 및 합성 영상, 배포 로그, 소개/검증용 화면을 삭제했습니다. 삭제 후보의 실행 중 xcodebuild 및 열린 파일이 없음을 확인하고 삭제 후 경로 부재를 재검사했습니다.
- 임시 생성 자료 점유 약 3.53GiB(3,787,980,800 bytes), 전용 시뮬레이터 2개 점유 약 7.75GiB를 제거했습니다. 디스크 여유는 약 45GiB에서 54GiB로 증가했습니다(APFS 공유 블록 때문에 점유 합과 확보 공간은 다릅니다).
- 삭제된 전용 simulator: E12CAC71-2275-48A6-B014-557B27787A35 / 306181D1-49AC-456A-91F7-B69B6B53D774. 다른 Taption 프로젝트의 실행 중 simulator 023E6D0E-B678-4239-8E6D-C79FF4BC1DEF / 40489265-CA76-4F54-A051-A1F54F01741B는 유지 확인했습니다.
- iPad/iPhone의 com.bokki.previewvalidation.* 검사 runner 제거 및 작업용 Documents/BOKKI-Review-RF14T0P10A, Documents/BOKKI-Swipe-IP13S8W4Q1-ur7esntb 폴더 부재를 확인했습니다. 빈 폴더로 교체하는 도구는 삭제 후 경로 재조회 오류를 반환했으나, 별도 files 조회가 성공하며 0개를 반환해 실제 삭제를 확인했습니다. 설치한 본 앱(iPad 48 / iPhone 47)과 개인 영상은 유지했습니다.
- 추적 파일 131개의 전후 SHA256을 비교했으며 작업 기록 temp.md/test.md 외 129개 입력의 내용/존재가 동일합니다. 소스·Xcode 프로젝트/설정·아이콘/테스트 입력·링크에 필요한 Vendor 의존성·인증키와 Git 이력을 보존했습니다. 프로젝트 plist 검사 및 git diff --check 성공.
- 제출된 TestFlight 빌드 48은 로컬 파일 삭제로 변경되지 않습니다. 삭제한 archive/IPA/dSYM/원본 검사 결과/검증 이미지 경로는 이전 기록에 역사적 참고로만 남아 있으며 복구는 보장되지 않습니다. 재검사는 소스와 새 QA 자료에서 다시 생성해야 합니다.


## CL14C0D8N2 — 사용자 반복 요청에 따른 소스 보관 형태 정리 (2026-10-14)
- 이전 정리에서 보존했던 사전 컴파일 FFmpeg xcframework 전체(두 lib.a 및 생성된 header/modulemap/Info.plist), 앱 아이콘 PNG 3개, 영상 테스트 입력(VC-1/Y41P), 비코드 라이선스/배포 안내 문서를 삭제했습니다. 생성 header/modulemap은 삭제 전에 Vendor/Sources의 원본과 동일함을 확인했습니다.
- 원본 코드 94개(Swift/C/header/modulemap/shell script)는 SHA256 전후 일치. Xcode 프로젝트/Info.plist/asset manifest/Package.resolved 및 배포 도구의 원본 JSON/TSV 설정, Git 이력, 사용자 지시된 작업 기록은 보존합니다. 인증 키와 설치된 기기 앱/TestFlight 빌드는 변경하지 않았습니다.
- 현재 checkout은 소스 보관 형태입니다. 즉시 앱 빌드/일부 테스트/배포가 가능한 상태로 보고하지 않습니다. 재사용하려면 Vendor/FFmpegLGPLDecodeBridge/build_ffmpeg_lgpl_decode_bridge.sh로 framework를 재생성하고, 아이콘/테스트 입력/라이선스 자료는 삭제 전 커밋 0836a13에서 복구해야 합니다.
- 이미지·영상·정적 라이브러리 및 생성 산출물 부재, 설정 plist 구문과 git diff --check를 검사했습니다. 재생성 가능 파일을 다시 만들지 않도록 빌드/테스트는 실행하지 않았습니다.

## TF14B4J8Q1 — main 정리·3기기 설치·TestFlight 빌드 49 (2026-10-14)
- 새 빌드/설치 요청에 따라 소스 보관 정리에서 삭제했던 필수 입력 22개를 0836a13에서 복구했습니다. framework·아이콘·영상 검사 입력·라이선스/빌드 자료는 해당 커밋의 내용과 byte 단위 일치합니다.
- 원본 코드 94개는 2e14c1d(빌드 48의 420개 활성 단위 검사 + iPad 시뮬레이터 UI 검사 2개 통과)와 동일합니다. 이번에는 구현 변경이 없으므로 유효한 이전 기능 검증을 재사용하고 새 archive·IPA 서명·실기기 설치/실행·Apple 처리 상태를 별도로 확인합니다. 기존 원본 xcresult는 사용자 요청으로 삭제되어 기록만 보존됩니다.
- Apple API에서 최신 빌드 48 확인 후, 앱 및 두 확장과 검사 구성의 CURRENT_PROJECT_VERSION 8곳을 49로 올렸습니다. 마케팅 버전 1.1.13 유지. git diff --check / project plist 검사 성공.
