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
- 배포 소스 main 커밋 `99fc7450e02c70cff60218f25d4d936649be290c` 푸시·clean 확인 후 archive했습니다. 고정 Package.resolved 버전(SwiftVLC 0.10.1 / GoogleMobileAds 13.5.0 / UMP 3.1.0)을 다시 받아 resolve 및 Release archive 성공. `build-source.json`/`post-build-source-verification.json`에 추적 파일 전후 hash 불변 확인.
- archive의 앱·Live Activity·thumbnail extension 모두 1.1.13(49), 서명 검증 성공 및 세 요청 기기가 provisioning에 포함됨을 확인했습니다.
- iPad Pro 12.9-inch 6세대(00008112-000964980E45401E), iPhone 11 Pro(00008030-001628201AD2802E), iPhone 18 Pro Max(00008160-000E195A1140000A) 모두 설치·설치 메타데이터 재조회·앱 launch 성공. 각 `*-device-result.json`의 install/installed/launch exitCode 0, 실제 설치 버전 1.1.13(49) 일치. 기존 앱 데이터는 유지하고 실기기 터치 검사를 통과했다고 보고하지 않습니다. 설치본은 개발 서명 Release이고 TestFlight 배포본은 별도로 Apple Distribution export했습니다.
- App Store Connect export 성공 로그와 IPA의 독립 서명/프로파일 검증을 확인했습니다. export 이후 shell 보고용 status 변수에서 readonly 오류가 있었으나 완료된 export와 산출물에는 영향 없으며 후속 Python 검증으로 결과를 기록했습니다. 앱/두 확장 모두 Apple Distribution·4FWG8XXYM7 팀·배포 프로파일(get-task-allow false, ProvisionedDevices 없음) 검증 성공. IPA 28,392,647 bytes, SHA256 `c08ac0d8852bc74df864657927602e0080a05f05c623524e4e40c7c1aa191837`.
- Apple 업로드 성공: delivery/build `a65d584f-a67f-4458-9ae5-8994a6dba70d`. 2026-10-14 03:28 KST **VALID / IN_BETA_TESTING** 확인, 내부 beta group 1개에 빌드 49 포함 확인. 한국어/영어 TestFlight 안내 등록 및 재조회 일치. App Store/외부 beta 심사 제출은 이번 요청 범위에 포함하지 않았습니다.
- 새 생성 자료는 `/private/tmp/BOKKIEncoder-TF14B4J8Q1-4u_q66e3`에 보관하고, 이번 배포 요청으로 필수 입력을 복구한 상태이므로 즉시 빌드 불가로 기술한 직전 소스 보관 기록은 과거 상태입니다.


## FR14A7L5Q3 — 폴더/앨범 자동 연결 미리보기 (2026-10-14)

- File은 시스템 폴더 선택으로 최초 범위를 확보한 뒤 영상 하나를 선택합니다. Folder는 기존 폴더 목록, Album은 PhotoKit의 선택 앨범 목록을 그대로 연결합니다. 개별 파일 권한에서 부모 폴더 권한을 우회하거나 PHPicker의 단일 전송에서 원본 앨범을 추측하지 않습니다.
- 처음 선택한 영상만 변환 목록에 넣고 이전/다음은 전체 원본 목록에서 탐색합니다. Add 후 닫기·큐에서 다시 열기에도 전체 목록을 유지합니다. 앨범은 재생할 영상만 원본 리소스로 가져오며 파일명을 보존합니다. 취소된 가져오기·이전 context가 새 화면을 덮지 않도록 보호하고, 공유 writer의 기다림은 즉시 취소할 수 있습니다.
- Photos 전환에서 이전 파일의 폴더 scope/context를 해제해 잘못된 Connect folder 표시를 없앴습니다. 문서 선택창의 닫힘 전환을 마친 뒤 연결 목록을 표시하고 폴더 카드의 전체 터치 범위를 명시했습니다.
- 최종 소스 전체 활성 검사: `Unit50-modal.xcresult`, **428개 통과, 실패/스킵 0**. 신규 8개는 단일 선택·큐 재열기·정확한 앨범 순서·지연 가져오기·미사용 영상·소스 전환·취소를 검증합니다. 탐색 중 encoder 호출 0회와 Stars 잔액 불변을 확인합니다.
- 작업 전용 iPhone 18 Pro Max 시뮬레이터(F8DCF5A8-0DDA-477B-BF36-9E838052217C, iOS 27.0), 90초 합성 영상 A/B/C에서 실제 UI 검사: `UI-folders8.xcresult`의 File 검사, `UI-folderonly10.xcresult`의 Folder 검사, `UI-connected5.xcresult`의 Album 검사 **각 통과**. 파일명/위치 변경, 양방향 하단 스와이프, Add 상태, 닫기·다시 열기, 폴더 연결 요청 부재를 검증합니다. 지정 앨범에는 A/B만 넣고 외부 영상 C가 섞이지 않음을 확인했습니다.
- 초기 UI 검사에서 unsigned 시뮬레이터의 Keychain/Photos 권한과 카드 좌표 클릭·전환 중 snapshot 문제가 있었습니다. Xcode의 시뮬레이터 서명을 사용하고 표준 버튼 동작 및 전환 안정화로 재검사했습니다. 실패한 시도를 통과로 계산하지 않습니다.
- 생성 자료와 명령/로그/xcresult는 `/private/tmp/BOKKIEncoder-FR14A7L5Q3-m0jrt1ay`에 보관합니다. 실기기 설치와 UI 검사 결과는 별도 기록합니다.
- 최초 네이티브 사진 권한 창에서 사진 선택을 누르고 합성 영상 B/C만 허용했습니다. `UI-permission11.xcresult`는 권한 진입까지만 검증한 진단 단계이며, 최종 `UI-limited12.xcresult`는 **제한 권한 실제 UI 검사 통과**: 허용한 B/C만 표시, 미허용 A 부재, 2개 목록의 양방향 스와이프와 닫기 후 1개 큐 유지 확인. 전면 접근 상태와 제한 접근 상태를 별도로 검사했습니다.
- `UI-denied13.xcresult` **접근 거부 UI 검사 통과**: 설정 안내와 단일 영상 선택 fallback 표시, 정상 닫기 확인. 개인 기기의 사진 접근 권한은 변경하지 않았으며 작업 전용 시뮬레이터에서 검증했습니다.
- 배포 소스 main `f7d62fb49261e167ed6b43420e6c914a9f8d6257` 푸시 및 clean 확인 후 Release archive/배포 export 성공. 앱·Live Activity·thumbnail extension 모두 **1.1.13(50)**, 서명·provisioning 확인 및 추적 파일 133개의 전후 hash 불변 확인.
- 배포 IPA 28,493,750 bytes, SHA256 `d950a7ef552df0438c577d59f079ea436975067391bf1de4b562fa9d5cbae951`. Apple Distribution 서명과 팀, 암호화 신고 값을 검증했습니다.
- Apple upload 성공, delivery/build ID `495cdce5-8224-4d97-b879-ffb2857d6e7e`. 2026-10-14 12:51 KST **VALID / IN_BETA_TESTING**, 내부 beta group 1개 포함, ko/en-US 변경 안내 등록·재조회 일치. App Store/외부 beta 심사는 제출하지 않았습니다.
- 직접 설치 시도에서는 iPhone 11 Pro에 50 설치·버전 재조회 성공, 실행은 잠금 때문에 실패했습니다. iPad/18은 올바른 기기 식별자로 재확인한 결과 연결 assertion을 충족하지 못했습니다. iPad 최초 설치 명령의 식별자 치환 오류를 바로잡고 별도 `ipad-corrected-*50` 기록으로 재검사했으며 최초 실패를 연결 검사로 계산하지 않습니다. 사용자가 **TestFlight 배포로 마무리**를 선택해 추가 실기기 설치·터치 검사는 진행하지 않았습니다. 기존 개인 앱 데이터와 사진 권한은 변경하지 않았습니다.


## GS14P8V2C6 — 중앙 아래 닫기 및 양쪽 밝기·음량 제스처 (2026-10-14)

- 사용자가 확인한 방식대로 화면 왼쪽/중앙/오른쪽 3개 영역을 구분합니다. 왼쪽·오른쪽의 위 스와이프는 밝기·음량을 높이고 아래 스와이프는 낮춥니다. 중앙은 아래로 화면 높이의 12%(최소 72pt, 최대 120pt) 이상 움직인 뒤 놓으면 X와 동일한 닫기 경로를 실행합니다. 작은 움직임·중앙 위·대각선은 닫지 않습니다.
- VLC와 HEVC Alpha 네이티브 재생에 동일한 영역 판정·시스템 음량 조절·피드백을 적용했습니다. 닫을 때 플레이어를 종료하고 기존 Add 목록을 반영합니다. 밝기·음량은 0...100% 범위를 유지합니다.
- 최초 UI 검사에서 폴더 browser의 부모 스크롤/재생 버튼과의 제스처 경쟁, 짧은 드래그의 탭 중복을 확인했습니다. iOS 18 이상 공개 UIGestureRecognizerRepresentable로 공통 pan을 연결하고 실제 banner/transport bounds의 시작 위치를 인식 전에 제외했습니다. 하단 메뉴·타임라인은 기존 제스처를 소유하며, 취소된 pan의 상태를 정리합니다. 실패한 시도를 성공으로 계산하지 않습니다.
- 최종 활성 단위 검사 `Unit-pan.xcresult`: **434개 통과, 실패/스킵 0**. 신규 6개는 영역 경계·위/아래 및 닫기 거리·가로/세로 화면·탭 흔들림·하단/배너 제외·비정상 좌표/음량 범위를 검사합니다.
- 작업 전용 iPhone 18 Pro Max 시뮬레이터(F8DCF5A8-0DDA-477B-BF36-9E838052217C, iOS 27.0) `UI-pan.xcresult`: **5개 모두 통과**. 폴더 preview의 Add 유지와 중앙 닫기, 위젯 숨김 상태 닫기, 중앙 위/짧은 아래 유지, 양쪽 조절 표시값의 증가/감소, 하단 이전/다음·정보·X, 실제 HEVC Alpha 네이티브 영상의 같은 제스처 및 가로 화면 재생 버튼 위 닫기를 확인했습니다.
- HEVC Alpha 합성 영상은 AVAssetWriter로 60초/320x180/24fps MOV를 생성했습니다. 앱 실행 로그에서 HEVC with Alpha 네이티브 경로·첫 프레임·rate 1.0을 확인했습니다. 기존 A/B/C는 90초 H.264 합성 영상입니다. 개인 기기의 영상·사진 권한은 변경하지 않았습니다.
- 밝기·음량의 UI 판정과 조절값 검증은 시뮬레이터 기준입니다. 시뮬레이터에는 물리 음량 장치가 없으므로 실제 iPhone/iPad 화면 밝기와 스피커 출력 변화를 검증했다고 보고하지 않습니다. 앞선 사용자 선택대로 이번에도 TestFlight 배포로 마무리합니다.
- 검사 원본·명령·로그·합성 자료는 `/private/tmp/BOKKIEncoder-GS14P8V2C6-jwz9k7_9`에 보관합니다. 검사 후 제품/검사 소스 hash 일치 확인. Apple의 최신 빌드 50을 재조회해 CURRENT_PROJECT_VERSION 8곳을 51로 올렸으며 마케팅 버전 1.1.13을 유지합니다.
- 배포 소스 main `2032fae048df1446a0c9cbfe1cddf8dc7cf72cb4` 커밋·푸시·clean 확인 후 Release archive 및 배포 export 성공. 앱/Live Activity/thumbnail extension 모두 **1.1.13(51)**, 서명 유효 및 추적 파일 133개 전후 hash 불변 확인. 배포 IPA는 Apple Distribution/4FWG8XXYM7 서명과 배포 프로파일, 암호화 신고 값을 별도로 검증했습니다.
- IPA 28,540,758 bytes, SHA256 `0f71ff50bf88191683d9639562b4d37a9e01fe41a3896081dbda96ede68e6896`. 업로드 성공 delivery/build `e283540b-83c9-460a-87b6-a4150dd0bbba`. 2026-10-14 15:10 KST **VALID / IN_BETA_TESTING**, 내부 beta group 1개 포함, ko/en-US 변경 안내 등록·재조회 일치 확인. App Store/외부 beta 심사 제출과 실기기 설치·물리 출력 검사는 진행하지 않았습니다.


## NV15F4D8K2 — 파일 탐색 연결 유실 및 자동 복구 (2026-10-15)

- 사용자는 1.1.13(51)에서 하단 스와이프 시 `Connect the folder in ⓘ` 안내와 다음 파일 이동 실패를 확인했습니다. 사진 속 원본 영상의 최초 진입 경로는 질문한 상태이며 아직 답변이 없습니다. 연결된 iPad/iPhone 11 앱 로그만 읽어 복사했으며 해당 영상의 오류는 없었습니다. 원본 기기에서 직접 재현했다고 보고하지 않습니다.
- 후속 답변으로 문제를 테스트한 기기가 **실제 iPhone 18**임을 확인했습니다. `devices-after-iphone18-confirmation.json` 재조회에서 해당 실제 기기(00008160-000E195A1140000A)는 unavailable이고, 연결된 iPhone 18 시뮬레이터와 구분했습니다. 새 빌드 52 설치·테스트 여부와 최초 진입 경로는 이 답변만으로 확인되지 않았습니다.
- 이후 최초 진입을 **‘아이폰 파일 앱 → BOKKI로 열기’**로 확인했습니다. `startFilesFlow`는 파일 검사 전에 저장된 해당 폴더 bookmark를 조회·취득하고, `restoreSingleFilePreviewNavigation`도 같은 권한으로 재시도합니다. 정보 화면의 `Connect folder`는 승인한 폴더를 저장하고 현재 영상 재생을 유지합니다. 기존 통과한 438개 결과와 `testConnectedPreviewFolderBookmarkSurvivesSourceAndModelReplacement`·`testFolderPickerGrantIsRememberedForLaterSingleFilePreview`의 검증 범위를 재사용했으며, 추가 코드 변경·빌드·실기기 원본 검사는 하지 않았습니다. 원본의 기존 폴더 승인 여부는 답변에 포함되지 않아 최초 승인 부재를 확정 원인으로 단정하지 않습니다.
- File 폴더 목록에서 한 영상을 선택할 때 기존 목록을 버리고 폴더를 다시 스캔하던 경로를 수정했습니다. 이미 읽은 목록을 전달하고, 소스 전환 시 필요한 기존 폴더 scope를 해제·재취득하지 않도록 유지합니다. 다른 경로로 전환할 때에는 새 scope를 확보한 뒤 필요 없는 이전 scope만 해제합니다.
- 최초 폴더 읽기 실패가 고정되던 상태도 수정했습니다. 하단 스와이프에서 이미 허용한 저장 권한으로 목록을 다시 읽고, 복구되면 그 스와이프 방향의 파일을 재생합니다. 복구에 실패하면 현재 재생과 목록을 보존하며 시스템 탐색창을 자동으로 띄우지 않습니다.
- 별도의 소스 복사본(`Baseline51`, main 72d4afb)에 새 회귀 검사 1개만 추가해 실행했습니다. 폴더 선택 후 목록 읽기 권한을 일시적으로 제거하면 H.264/HEVC Alpha 모두 playlist가 nil·폴더 연결 필요 상태로 바뀌고 다음 영상으로 이동하지 못했습니다. `Baseline51-regression.xcresult`의 **실패 1개는 문제 재현을 위한 기대된 실패**입니다. 작업 중인 소스나 브랜치를 되돌리지 않았습니다.
- 수정본 `Unit-navigation.xcresult`: **438개 통과, 실패/스킵 0**. 신규 4개는 공유 scope의 끊김 없는 이전, provider 재스캔 실패에도 원본 3개 목록 유지(H.264/Alpha), 스와이프 재조회 후 즉시 다음 파일 이동, 실제 권한 부재 시 현재 재생 보존을 검사합니다. 변환 호출 0회와 Stars 잔액 불변을 확인했습니다.
- 작업 전용 iPhone 18 Pro Max 시뮬레이터(F8DCF5A8-0DDA-477B-BF36-9E838052217C, iOS 27.0)에서 실제 UI **6개 통과**: Album/File/Folder의 양방향 탐색·Add·큐 재열기, 폴더 선택 후 목록 읽기가 불가능해져도 B→C→B→A 이동, 최초 읽기 실패 후 복구된 폴더의 한 번 스와이프 이동, 계속 권한이 없는 경우 현재 영상 유지와 자동 picker 부재를 확인했습니다.
- `UI-navigation.xcresult`는 5개 통과 및 Folder 검사 1개 도구 실패(native File View가 전환 중 중복되어 단일 요소 조회 실패)입니다. 검사 선택자만 firstMatch로 보정한 `UI-folder-retry.xcresult`에서 해당 Folder 검사 1개가 통과했습니다. 이 결과들을 합쳐 고유한 UI 검사 6개를 통과로 계산합니다. 초기 xctestrun 설정 형식 오류는 UI 검사 실행 전 도구 설정 오류로 구분했습니다.
- 합성 영상 전용 `BOKKI-Review-NV15F4D8K2` 폴더에만 호스트가 0o300/0o700을 적용해 읽기 실패/복구를 제어했고 검사 종료 후 0o700 복구를 확인했습니다. 영상 SHA256은 원래 합성 입력과 일치합니다. 실제 표시 프레임과 파일명 A/1-of-3 전환을 screenshot으로 확인했습니다. 개인 기기 권한·원본 영상은 변경하지 않았습니다.
- 외부 앱이 파일 1개의 권한만 전달하면 iOS는 부모 폴더 권한을 자동으로 주지 않습니다. 최초 폴더 승인 자체를 우회했다고 보고하지 않습니다. 기존 승인과 일시 오류를 자동 복구하는 범위이며, 실제 폴더 권한이 없다면 최초 한 번 연결이 필요합니다. 근거: https://developer.apple.com/documentation/uikit/providing-access-to-directories
- 원본 명령·로그·xcresult·스크린샷·기대된 51 회귀 실패는 `/private/tmp/BOKKIEncoder-NV15F4D8K2-gdhefdom`에 보관합니다. 제품/검사 소스 hash 일치와 합성 폴더 권한 복구를 확인했습니다. Apple의 최신 빌드 51을 재조회해 프로젝트 build 8곳을 52로 올렸고 마케팅 버전은 1.1.13을 유지합니다.
- 배포 소스 main `ce3779581201a6a4fb0cee4c9c5171eb694dcd22` 커밋·푸시·clean 확인 후 Release archive/배포 export 성공. 앱/Live Activity/thumbnail extension 모두 **1.1.13(52)**, 서명 유효 및 추적 파일 133개 전후 hash 불변 확인. IPA Apple Distribution·팀·배포 프로파일·암호화 신고 값 검증 성공.
- IPA 28,545,727 bytes, SHA256 `3b6db437d2a6e9301d80724ba8eb2eeddaa8bad1b37838f275ce88ed9a029dbf`. Apple upload 성공, delivery/build `20a38e1c-8897-4b32-8a4c-f7dd33a08bd0`. 2026-10-15 13:50 KST **VALID / IN_BETA_TESTING**, 내부 beta group 1개 포함, ko/en-US 안내 등록·재조회 일치 확인. App Store/외부 beta 심사는 제출하지 않았습니다. 새 빌드를 실기기에 직접 설치하거나 사진 속 원본 영상에서 재검증했다고 보고하지 않습니다.

## FP15A9K3R6 — 외부 영상 진입 시 폴더 접근 안내 (2026-10-15)

- 사용자 요청: iPhone 파일 앱 → BOKKI로 열기에서 폴더 권한이 없을 때 자동으로 물어봅니다. 공통 미리보기 화면이 열릴 때 `Connect this folder?` 안내와 `Connect folder` / `Not now` 선택을 표시하고, 연결 선택 시 기존 iOS 폴더 선택창과 bookmark 저장 경로를 사용합니다. 초기 재생 컨트롤이 숨겨져 있어도 안내가 가능합니다.
- 같은 소스 흐름에서는 안내를 1회만 요청합니다. 취소 후 큐에서 같은 영상을 다시 열어도 반복하지 않으며, 정보 메뉴의 수동 연결은 유지합니다. 다음 외부 소스는 별도 요청이 가능하고 이미 폴더를 읽을 수 있는 경우와 앨범에는 안내가 없습니다. 이전 미리보기의 지연된 요청은 현재 소스를 소비하지 않습니다.
- `Unit-permission.xcresult`: **440개 통과, 실패/스킵 0**. 신규 2개와 기존 검사 확장으로 H.264·HEVC Alpha의 요청 1회/잘못된 preview ID/취소 후 재열기/새 외부 파일 요청/이미 읽을 수 있는 폴더/저장한 폴더의 모델 교체/앨범 미요청을 확인했습니다. 요청 중 재생 대상·큐·Stars 잔액 보존과 변환 호출 0회를 확인했습니다.
- 검사 명령·소스 hash·xcresult와 이후 UI/배포 근거는 `/private/tmp/BOKKIEncoder-FP15A9K3R6-nf_l1vxl`에 기록합니다. 단위 검사는 Debug 52 설정으로 실행했고 동일 제품 소스의 배포 번호만 53으로 올렸습니다. 앱·확장 8개 설정 모두 53이며 마케팅 버전은 1.1.13입니다.
- 추가 요청에 따라 최초 실행의 상위 영상 폴더 연결 안내를 구현했습니다. iOS의 승인 범위는 선택한 폴더와 하위 폴더이며 모든 저장 위치의 일괄 승인은 제공하지 않습니다. 안내·오류·iOS 폴더 선택창을 미리보기와 최초 실행에서 공통으로 사용하고, 사용자 선택은 저장해 재실행 시 반복 요청하지 않습니다. 영상이나 다른 메뉴가 열려 있으면 최초 실행 안내를 겹쳐 띄우지 않습니다. 근거: https://developer.apple.com/documentation/uikit/providing-access-to-directories
- `Unit-parent-permission.xcresult`: **443개 통과, 실패/스킵 0**. 추가 3개는 최초 요청의 모델 교체 후 유지, 상위 폴더 승인 후 서로 다른 하위 폴더의 재생/목록과 범위 밖 비승인, 읽기 불가·파일 URL·네트워크 URL 연결 거부입니다. 이후 다른 메뉴와의 동시 표시 방지 조건만 보완한 최종 Debug 53 빌드도 성공했고, 최종 UI 검사 제품 소스 102개 hash를 고정했습니다.
- `UI-initial-clean-install.xcresult`: 새 작업 전용 iPhone 18 Pro Max 시뮬레이터(D87474D1-2B4B-4AC3-8CA2-C81636076510, iOS 27)의 최초 설치 흐름 **1개 통과(143.980초)**. 최초 안내 → 실제 iOS 폴더 선택창에서 상위 폴더 선택 → 큐 0개 유지 → 앱 재실행 후 TripA/TripB의 각 B→C→B 탐색과 두 권한 안내 미표시를 확인했습니다. 안내 화면과 두 하위 폴더 재생 화면은 Initial-attachments에 내보내 실제 표시를 확인했습니다. 이 시뮬레이터는 검사 완료 후 종료했습니다.
- 최초 설치 UI의 앞선 시도는 차가운 Files 서비스의 대기 시간·Browse 위치 선택 및 요청 이력 재사용 때문에 실패했습니다. 원래 xcresult를 보존했고, **이 작업에서 만든 시뮬레이터의 QA 앱만** 재설치한 뒤 합성 입력 SHA256을 확인해 복원하여 실제 새 설치 검사에 통과했습니다. 개인 기기나 원본 영상은 변경하지 않았습니다. 초기 UI 7개 실행은 선택자/비동기 상태 대기 실패 3개였고, 이후 중간 실행은 5개 통과·2개 실패였습니다. 아래 최종 재검사 결과와 구분합니다.
- 최종 결과: **고유 UI 8개 모두 통과**. `UI-final-permission.xcresult`에서 Album/File/Folder 회귀 및 안내 취소·연결 5개, `UI-final-retry.xcresult`에서 취소 후 수동 재연결 1개, `UI-wrong-folder.xcresult`에서 무관한 폴더의 오류 안내·기존 영상 유지 1개, 최초 설치 bundle에서 상위/서로 다른 하위 폴더 재사용 1개입니다. 마지막 두 경로의 기존 실패는 native Files의 앱 컨테이너 아이콘 진입과 비동기 목록 갱신을 기다리는 검사 코드 보정 후 통과했습니다. 제품 소스는 동일한 102개 hash이며, 이전 실패 bundle도 보관합니다.
- `test-verification.json`에서 단위 443개·고유 UI 8개의 최종 성공을 집계하고 합성 폴더 0o700 복구·매체 SHA256 일치를 확인했습니다. 실제 iPhone 18 원본 영상의 재검증은 아직 하지 않았습니다. 최초 440개 결과는 추가 요청 이전 단계의 기록이며 최종 단위 결과는 443개입니다.
- 배포 소스 main `179244034d66d1dc0c6b2dd95b8908b6a6547bda` 커밋·푸시·clean 확인 후 Release archive/export 성공. 앱·Live Activity·thumbnail extension 모두 **1.1.13(53)**이며 서명 유효, 추적 입력 133개 hash 불변, Apple Distribution·팀·프로파일·암호화 신고 값을 검증했습니다. IPA **28,573,684 bytes**, SHA256 `9d945789250a9f238284a4f4d87dbc8a84997f4a0618a5eca2cdf60579b6789d`.
- Apple 업로드 성공, delivery/build `6319c8be-2562-45c8-ad7c-c771728002ab`. 2026-10-15 **16:18 KST VALID / IN_BETA_TESTING**, 내부 beta group 1개 포함, ko/en-US 안내 등록·재조회 일치 확인. `release-verification.json`과 원본 응답을 보관합니다. App Store/외부 beta 심사 제출이나 실기기 53 설치·원본 재검증은 하지 않았습니다. 완료된 FP15A9K3R6 항목만 temp.md에서 제거하고 원본 실기기 검사 NV15F4D8K2는 유지합니다.

## CL15B6T9P4 — TestFlight 54 및 생성 파일 정리 (2026-10-15)

- 사용자 요청: main 커밋·푸시·clean, TestFlight 새 빌드 배포 후 소스를 제외한 프로젝트 생성 산출물 전체 삭제. 시작 main `e7300e5`는 origin/main과 같고 clean이었으며, Apple 최신 업로드는 1.1.13(53) VALID였습니다. 앱·확장·검사의 CURRENT_PROJECT_VERSION 8곳만 54로 올리고 마케팅 버전 1.1.13과 기능 소스는 유지합니다.
- 검증 재사용: FP15A9K3R6의 단위 443개·고유 UI 8개 성공과 현재 제품/검사 입력 102개 SHA256의 일치를 확인했습니다. 정렬된 경로→hash JSON의 SHA256은 `80c771b850ea7b1cafadbf89b50b1e02779bd9b72695e4888ab22e5ec9f195d8`입니다. 기능 변경이 없어 같은 전체 검사를 재실행하지 않으며, 54의 Release archive/export·배포 서명·고정 소스·Apple 처리 상태는 새로 검증합니다. 실제 iPhone 18 원본 및 iPad 터치 검사 대기는 유지합니다.
- 삭제 대상 사전 조사: `/private/tmp`의 BOKKI 전용 FP15A9K3R6, FR14A7L5Q3, GS14P8V2C6, NV15F4D8K2, TF14B4J8Q1 작업 폴더 5곳(할당량 합계 약 4.984 GiB), 현재 CL15B6T9P4 배포 폴더와 경로 포인터, 프로젝트 전용 DerivedData 로그 및 빈 SwiftPM configuration 디렉터리입니다. archive·IPA·dSYM·xcresult·화면 캡처·재생성 QA harness/합성 입력·패키지 복제본을 포함합니다. 삭제 전 알려진 경로의 열린 파일과 활성 빌드 소유권을 확인하고, 54 배포가 끝날 때까지 필요한 빌드/패키지 경로는 보존합니다.
- 전용 QA 시뮬레이터 `F8DCF5A8-0DDA-477B-BF36-9E838052217C`(BOKKI FR14A7L5Q3 iPhone)와 `D87474D1-2B4B-4AC3-8CA2-C81636076510`(BOKKI FP15A9K3R6 first connection)은 이 작업용 생성 기기입니다. 두 기기의 사용자 앱은 `com.taption.encoder`와 `com.bokki.previewvalidation.FR14A7L5Q3.xctrunner`뿐임을 Bundle ID로 확인했습니다. 종료 기기의 listapps 조회 실패는 삭제 성공으로 취급하지 않고 해당 앱 번들의 Info.plist를 직접 확인했습니다. 다른 프로젝트의 실행 중인 테스트·시뮬레이터·공유 런타임/캐시는 정리 범위에서 제외합니다.
- Git 추적 소스·검사·문서·프로젝트·아이콘/필수 리소스·Vendor의 필수 라이브러리 및 Package.resolved, Git 이력·서명 인증 키·실기기 앱/영상은 보존합니다. 생성된 원본 검증 파일은 요청에 따라 삭제하되 검사 결과·소스/배포 식별자는 이 문서에 남깁니다. 삭제 완료와 확보 용량은 배포 확인 후 아래에 기록합니다.

- 54 배포 검증: main `f814ed8f92a5c29eb01cccbbfc5b19d4469b6c80` 커밋·푸시·clean 후 Release archive/export 성공. 앱·Live Activity·thumbnail extension 모두 **1.1.13(54)**이며 서명·Apple Distribution·팀·배포 프로파일·암호화 신고 값이 유효합니다. 추적 입력 133개 hash가 배포 전후 그대로였습니다. IPA **28573681 bytes**, SHA256 `da047d6e40e6cf8179cfa5d781483bb8fbe9464446409c5117d7df5e5354d24b`.
- Apple 업로드 오류 0, delivery/build `87641ae3-3035-4ccf-b5a0-5b2213f6a238`. **2026-10-15 16:36 KST VALID / IN_BETA_TESTING**, 내부 테스트 그룹 1개 포함, ko/en-US 안내 등록·재조회 일치 확인. 54는 53과 같은 기능 소스의 새 배포이며, App Store/외부 beta 심사 제출이나 실기기 신규 설치/직접 터치 검사는 수행하지 않았습니다. 아래 정리 이후 원본 산출물 대신 이 기록과 Git 소스를 보존합니다.

- 정리 완료: 전용 QA 시뮬레이터 2대 및 프로젝트 생성 경로 19개를 삭제하고 각 경로·기기 ID의 부재를 재조회했습니다. 확인된 삭제 대상 할당량 합계는 12.401 GiB이며, 정리 직전/직후 디스크 여유 공간은 1.096 → 5.495 GiB입니다(다른 프로젝트 동시 작업으로 시스템 여유 공간 차이는 삭제량과 다를 수 있음). BOKKI 임시 루트/포인터·배포 로그·전용 DerivedData·생성 ignored 항목은 남지 않았습니다. 다른 시뮬레이터 8대는 유지했습니다.
- 삭제 후 추적 입력 중 문서 2개를 제외한 131개 hash와 인증 키의 크기·mtime·inode가 보존되어 있음을 확인했습니다. 로컬 archive·IPA·dSYM·검사 원본은 사용자 요청에 따라 삭제했고, 소스·필수 의존성·리소스·검사 결과 및 배포 식별자는 Git에 남깁니다. 실제 기기 앱/영상은 변경하지 않았습니다.

## FB15C7N2L4 — Connect folder 탐색·폴더 선택 개선 (2026-10-15)

- 사용자는 iOS 파일 탐색기가 다운로드 폴더 안의 영상 목록을 보여 폴더 선택이 어렵다고 보고했습니다. 기존 `.folder` 단일 선택·원본 접근 모드는 유지하고, 미리보기 연결에서는 대상 폴더의 상위 위치를 시작 힌트로 지정합니다. 현재 폴더를 연결하는 우측 상단 Open/열기 및 폴더명 메뉴·뒤로 탐색 방법을 최초 안내와 영상 정보 양쪽에 표시합니다.
- 시스템 취소 버튼·dismiss 제스처 및 기존 미리보기 수명을 보존하도록 UIKit 기본 모달 방식을 유지합니다. 평가 중 사용한 fullScreen/overFullScreen 설정은 최종 소스에 포함하지 않았습니다. iOS의 directoryURL은 시작 위치 힌트이며, 공급자가 앱의 최상위 폴더를 표시하면 그 안에서 원하는 폴더로 이동합니다. 근거: https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/directoryurl
- 본앱 및 단위 검사 번들 `Product-build-for-testing.xcresult`: **TEST BUILD SUCCEEDED**, 고정된 SwiftVLC 0.10.1·GoogleMobileAds 13.5.0·UMP 3.1.0을 복원해 Debug arm64 시뮬레이터 구성 전체를 컴파일했습니다. 기존 GoogleMobileAds umbrella header 및 호환 API 경고는 이 변경과 별개입니다.
- 실제 UIKit 폴더 선택을 검사하기 위해 최종 `QueuePreviewModalPresenters.swift`를 직접 컴파일하는 격리된 QA 앱과 전용 iPhone 18 Pro Max 시뮬레이터 `FCD8D795-A579-4529-A4D6-CA62F5805795`를 만들었습니다. 초기 2개 UI 검사는 QA 앱의 생성 Info.plist에 UIFileSharingEnabled가 누락되어 빈 위치를 본 환경 실패이며, 본앱의 명시적 Info.plist에는 해당 설정이 정상입니다. 다음 2개는 시작 힌트가 반드시 하위 폴더까지 이동한다는 검사 가정, 그다음 2개는 폴더 선택 모드에서도 영상 파일이 표시된다는 검사 가정 때문에 실패했습니다. 실제 파일 탐색기 구조에 맞게 검사 탐색 경로·확정 버튼 식별자를 보정했으며 이 초기 실패를 성공으로 계산하지 않습니다.
- 실패한 UI 실행은 2개 사례의 실패 기록을 확인한 뒤 진단 수집에서 대기하는 해당 작업의 xcodebuild만 종료했습니다. 단위 검사 첫 요청도 같은 시뮬레이터에 UI 검사와 함께 실행되지 않도록 검사 시작 전에 중단하고, 제품 빌드와 실제 검사 실행을 분리했습니다. 다른 프로젝트의 기기·프로세스·데이터는 변경하지 않았습니다. 최종 실행 결과는 아래에 기록합니다.
- `Unit-folder-verified.xcresult`: **3개 통과, 실패/스킵 0**. 최초 안내 이력의 재실행 유지, 권한 안내 취소 시 현재 재생 대상 보존, 상위 폴더 승인 후 서로 다른 하위 폴더의 탐색·범위 밖 비승인을 확인했습니다. 검사 후 이 모델·검사 소스는 변경하지 않았으며, 최종적으로 제거한 부가 picker 설정은 아래 제품 빌드와 UI 검사에서 다시 확인했습니다.
- `Product-final-build.xcresult`: **TEST BUILD SUCCEEDED**. 최종 제품 소스 전체와 단위 검사 번들의 Debug arm64 시뮬레이터 컴파일 성공. 최종 presenter SHA256은 `2dd21366ce8297eb58df42b3df08de2bbfe240889255b4a75cec3733f5a52ac3`, QueuePreviewViews.swift는 `191d0f540019dfde41a5706483f3b6d42f3dc938ff3bf9a0579fe484d53152ff`이며 UIKit 기본 표시·취소 설정과 기존 delegate 흐름을 유지합니다.
- `UI-final-folders.xcresult`: **2개 통과, 실패/스킵 0**. 최종 presenter 파일을 그대로 컴파일한 QA 앱에서 실제 iOS 탐색기를 열어 `Downloads` 및 `Other Videos` 폴더의 선택·Open 확정·정확한 폴더 URL과 파일 수 반환·다시 연결하기를 확인했습니다. 상위 폴더 목록과 선택 결과 화면을 내보내 확인했고, picker가 열리고 닫혀도 기존 SwiftUI 화면의 appear 1회/disappear 0회를 확인했습니다. 실제 영상의 지속 재생이나 인코딩을 수행한 검사로 계산하지 않습니다.
- 최종 UI 중 native Cancel 버튼은 해당 격리 앱의 탐색창에 나타나지 않았으므로, 같은 폴더를 다시 승인한 뒤 다른 폴더로 연결하는 경로를 실행했습니다(`QA_NATIVE_CANCEL_BUTTON_AVAILABLE false`). 앞선 swipe 취소 검사는 실제 닫힘을 보장하지 못해 완료 횟수 검증에 실패했고, 그 결과와 최종 폴더 재연결 성공을 구분합니다. 실제 native 취소 제스처를 검증했다고 보고하지 않으며 취소 코드는 변경하지 않았습니다. 초기 UI 선택/재시도 검사에서 비동기 디렉터리 이동·콜백 반영 전에 값을 읽던 실패도 실제 폴더 제목·결과 상태 대기로 구분해 보존했습니다.
- 최종 결과 JSON·명령·검사 원본·QA 소스는 `/var/folders/q1/0p9tcvnx7yx5l12y55zm4tdm0000gn/T/BOKKIEncoder-FB15C7N2L4-ak697h1_`에 있습니다. 전용 시뮬레이터만 종료했으며 다른 기기나 개인 영상은 변경하지 않았습니다. 현재 수정은 main의 미커밋 소스이며 **TestFlight 1.1.13(54)에는 아직 반영하지 않았습니다**. 실제 iPhone 18 원본 검사는 기존 NV15F4D8K2 대기로 유지합니다.

## FA15M8R3Q7 — 여러 상위 폴더의 접근 권한 관리 (2026-10-15)

- iOS의 전체 기기 파일 권한은 제공되지 않습니다. 선택한 디렉터리와 하위 항목의 security-scoped 접근을 저장하는 공개 API를 사용합니다. Apple 근거: https://developer.apple.com/documentation/uikit/providing-access-to-directories . Infuse의 로컬 폴더 추가도 폴더 안으로 이동해 Open을 누른 뒤 등록 목록에서 탐색하는 방식임을 공식 안내로 확인했습니다: https://support.firecore.com/hc/en-us/articles/33226933888151-Streaming-from-iCloud-Drive .
- Menu → Folder Access를 추가하고, 등록된 상위 폴더와 하위 전체 접근 범위를 표시합니다. 네이티브 `.folder` 선택창에서 추가한 여러 폴더의 읽기 가능 여부와 bookmark 생성을 모두 확인한 뒤 함께 저장합니다. 취소·유효하지 않은 선택·bookmark 생성 실패는 기존 권한을 보존합니다. 기존 미리보기의 단일 폴더 연결 콜백은 호환성을 유지합니다. 이전 20개 제한으로 다른 저장 권한을 조용히 버리던 동작을 제거하고 중복 URL은 병합합니다.
- 기존 FB15C7N2L4 QA 루트·고정 패키지·전용 시뮬레이터를 재사용하며 추가 검사 파일은 그 안 `FA15M8R3Q7`에 보관합니다. `Product.xcresult`: 본앱·단위 검사 번들 Debug arm64 **TEST BUILD SUCCEEDED**. `Unit.xcresult`: **14개 통과, 실패/스킵 0**. 복수 상위 폴더 승인 후 모델 재생성·각 하위 영상의 이전/다음·범위 밖 비승인, 기존 권한 보존·원자적 실패·취소, 24개 권한 유지, 기존 폴더/앨범/외부 단일 파일 회귀를 확인했습니다. 이 검사는 실제 iPhone의 샌드박스 권한 승인을 대신하는 것으로 보고하지 않습니다.
- 단위 검사 종료 뒤 전용 시뮬레이터가 Shutdown 상태여서 첫 get_app_container 요청은 149로 실패했습니다. 기기 ID·이름을 재확인한 뒤 해당 기기만 부팅하고 정상 컨테이너를 조회했습니다. 실제 앱 UI 검사용 합성 폴더는 이 QA 앱 컨테이너 안 `Documents/FA15M8R3Q7 Library`에만 만듭니다.
- 첫 실제 앱 UI 검사 `UI-menu.xcresult`는 Menu → Folder Access 화면 표시까지 성공한 뒤, 기존 단일 선택창의 Open 식별자만 찾는 검사 가정 때문에 1개 실패했습니다. 같은 실행의 화면 캡처에서 실제 네이티브 선택창과 Open이 표시되었음을 확인했으며, 복수 선택 모드에서도 실제 Open/열기 라벨을 함께 찾도록 QA 선택자를 보정했습니다. 이 초기 실패를 통과로 계산하지 않습니다.
- 최종 실제 앱 UI `UI-permissions.xcresult`: **1개 통과, 실패/스킵 0**. 본앱 `com.taption.encoder`의 Menu → Folder Access → 네이티브 Browse → On My iPhone → BOKKI Encoder에서 QA `Library A`를 Open으로 연결하고, 프로세스를 종료·재실행해 등록 1개를 복구했습니다. 이어 `Library B` 추가 시 A를 보존하고 등록 2개로 갱신한 뒤 다시 종료·재실행해 두 폴더가 모두 복구됨을 확인했습니다. 이번 실제 UI는 폴더를 각각 연결하는 경로이며 한 번의 네이티브 복수 선택 제스처나 실제 iCloud/개인 영상 재생까지 검증했다고 보고하지 않습니다.
- `verification.json`에 제품 빌드 exit 0·단위 14개·최종 UI 1개 및 검사한 소스 7개의 SHA256을 보관했습니다. 검사 전후 제품/검사 소스 hash 일치와 `git diff --check`를 확인했습니다. 최종 화면 `permissions-final.png`를 직접 확인했고 등록 2개·Add Folders·하위 폴더 포함 범위가 정상 표시됩니다. 변경은 main의 미커밋 소스이며 이번 작업에서 commit/push·TestFlight 업로드는 수행하지 않았습니다. iPhone 18 원본 실기기 검사는 NV15F4D8K2 대기로 유지합니다.

## TF15B7N4K2 — 폴더 접근 개선 TestFlight 55 (2026-10-15)

- 사용자 요청은 최신 수정사항의 TestFlight 새 빌드입니다. App Store Connect의 BOKKI Encoder(`6780777838`, `com.taption.encoder`) 최신 빌드는 1.1.13(54) VALID였고, 기존 내부 그룹 `Taption Encoder Internal` 1개는 모든 빌드 접근이 켜져 있었습니다. main HEAD `0e7fb12`의 기존 미커밋 기능 수정과 검증 기록을 보존하고, 앱·확장·검사의 CURRENT_PROJECT_VERSION 8곳을 **55**로 올렸습니다. 마케팅 버전은 **1.1.13**을 유지합니다. 이번 요청에서는 Git commit/push·생성 파일 삭제·App Store 심사 제출·실기기 설치를 수행하지 않습니다.
- FB15C7N2L4/FA15M8R3Q7의 폴더 선택 안내·Folder Access 관리 변경이 포함됩니다. FA15M8R3Q7에서 컴파일·단위 14개·실제 앱 UI 1개를 통과한 제품/검사 소스 7개의 SHA256이 현재와 일치하여 해당 검증을 재사용합니다. 모든 검사를 재실행했다고 보고하지 않습니다. 배포 입력 131개 hash 및 미커밋 패치는 기존 QA 루트의 `TF15B7N4K2` 하위에 보관합니다.
- Release `Archive.xcresult`: **ARCHIVE SUCCEEDED**, `Export`: **EXPORT SUCCEEDED**. 앱·Live Activity·thumbnail extension 모두 **1.1.13(55)**이고, archive 및 IPA의 strict/deep 서명 검증을 통과했습니다. 최종 IPA의 세 번들 모두 Apple Distribution·팀 `4FWG8XXYM7`·유효한 App Store 프로파일·get-task-allow=false·일치하는 application-identifier를 확인했습니다. 앱의 비면제 암호화 사용 신고는 false입니다. 배포 입력 131개 hash도 유지됩니다.
- IPA **28608909 bytes**, SHA256 `4db31434050c1a05c1da26b0e0ad79ef380d120d321aa3952711f2f05c92da78`. `archive-verification.json`, `ipa-verification.json` 및 각 명령·exit 결과를 보관하고 Apple에 업로드합니다. 전송·Apple 처리 및 내부 테스트 상태의 최종 결과는 아래에 기록합니다.
- Apple 업로드 **오류 0**, delivery/build `3dbe9b5e-b8b2-477a-8453-42a7a61926ee`. **2026-10-15 19:07 KST VALID / IN_BETA_TESTING**, 기존 내부 그룹 `Taption Encoder Internal`(`10a4640f-864b-4952-bb94-cd2ea87a96c0`) 포함을 확인했습니다. ko/en-US의 이번 변경·폴더 연결·재실행 후 하단 이전/다음 테스트 안내를 갱신하고 실제 텍스트 일치를 재조회했습니다. 외부 상태는 READY_FOR_BETA_SUBMISSION이며 외부 beta/App Store 심사는 제출하지 않았습니다.
- 그룹 확인 중 build → betaGroups의 직접 GET은 Apple이 허용하지 않아 403, app/build 두 relationship filter 동시 사용은 400으로 거부됐습니다. Apple 공식 List beta groups 문서와 실제 API 응답을 확인해 `filter[builds]` 하나로 재조회했고, 기존 내부 그룹의 자동 연결을 확인했으므로 중복 배포·그룹 생성/수정은 하지 않았습니다. 초기 API 조회 실패와 최종 배포 성공을 구분해 audit JSONL에 보관합니다.
- 최종 `release-verification.json`에서 55의 버전·processing/내부 테스트 상태·delivery ID·그룹·두 언어 안내·IPA hash 및 제품 입력 131개 보존을 확인했습니다. 원본 경로는 기존 QA 루트 하위 `TF15B7N4K2`이며 `/private/tmp/BOKKIEncoder-TF15B7N4K2-current.txt`가 가리킵니다. Git main의 기능 수정·검사·빌드 번호·결과 문서는 미커밋 상태로 보존합니다. 실제 iPhone 18 원본 및 iPad 터치 대기 항목은 유지하며 이번 배포 성공을 원본 실기기 문제의 직접 해결 확인으로 보고하지 않습니다.

## BR15L6F2Q9 — Studio 방식의 파일·폴더 열기와 시작 안내 (2026-10-15)

- 사용자가 55에서 iCloud Drive/다운로드를 벗어날 수 없다고 보고했고, 비교 사진의 두 번째 앱은 Taption Studio임을 명시했습니다. 사진의 상위 경로 메뉴는 iCloud Drive/다운로드와 나의 iPhone/Taption Studio의 차이를 보여 주며, ‘나의 iPhone’ 전용 권한이 없다는 근거로 해석하지 않습니다. 별도 전체 파일 권한 팝업·비공개 API·권한 우회는 추가하지 않습니다.
- Studio의 `ios/Taption/ContentView.swift` 파일 가져오기·폴더 sheet와 `UI/Release/Features/BatchCaptionQueue/BatchCaptionQueuePickerView.swift`를 읽기 전용으로 비교했습니다. Studio는 파일/폴더의 content types와 복수 선택을 구분하고, native picker 자체를 SwiftUI sheet에 표시하며, 표시 후에는 directoryURL/선택 모드를 재설정하지 않습니다. BOKKI도 같은 구성으로 공통 `VideoDocumentPicker`를 적용하고, 홈 File의 폴더 강제 선택과 숨겨진 UIKit anchor의 수동 present/dismiss 코드를 제거합니다. File은 지원 영상 복수 선택, Folder/출력은 폴더 단일 선택이며 홈의 선택 결과는 sheet 종료 후 처리합니다. 미리보기·시작 안내·Folder Access의 연결창도 직접 sheet를 사용합니다. Studio 소스는 수정하지 않았습니다.
- 앱의 로컬 Documents에 Videos 폴더를 준비하고 이를 기본 시작 위치 힌트로 사용합니다. 기존 UIFileSharingEnabled/LSSupportsOpeningDocumentsInPlace를 유지하고, 실제 UIDocumentBrowser 앱이 아닌데 켜져 있던 UISupportsDocumentBrowser 선언을 제거해 Studio와 같은 문서 공유 구성을 사용합니다. 이 플래그를 원본 문제의 확정 원인으로 보고하지 않습니다. 위치 전환 안내는 상위 경로 메뉴 대신 하단 Browse에서 나의 iPhone/iCloud Drive를 선택하도록 갱신했습니다.
- 저장된 폴더가 없으면 과거 `preview.folderAccessRequestShown=true` 여부와 무관하게 새 HomeViewModel 실행 세션마다 한 번 연결을 묻습니다. 같은 실행에서 취소 후 재표시하지 않으며, 저장된 폴더 승인이 있으면 다음 실행에서도 생략합니다. 외부 영상에서 이미 안내한 실행에서는 중복으로 시작 안내를 띄우지 않습니다. iOS의 선택 폴더·하위 항목 권한 범위는 유지합니다. Apple 근거: https://developer.apple.com/documentation/uikit/providing-access-to-directories , https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/directoryurl .
- 첫 검사 빌드는 현재 SDK에 없는 UIDocumentPickerViewController.documentTypes를 검사 코드에서 읽어 실패했습니다. 제품 소스 컴파일 오류가 아니며, 공개 picker의 모드·복수 선택·초기 위치와 실제 content type 입력을 검사하도록 보정했습니다. 다음 단위 실행은 17개 중 한 소스 계약 사례에서 옛 코드 문자열 두 조건이 남아 실패했으며, 3분 이상 진단 수집에서 대기해 이미 끝난 해당 xcodebuild PID만 종료했습니다(exit -15). 기존 구현 문자열을 고정한 두 조건을 제거하고 새 UIKit 동작 검사와 실제 UI로 대체했으며 이 초기 실패를 성공으로 계산하지 않습니다.
- `Product-verified.xcresult`: 본앱·검사 번들 Debug arm64 **TEST BUILD SUCCEEDED**. `Unit-verified.xcresult`: **17개 통과, 실패/스킵 0**. 파일·폴더 구성 구분, 갱신 시 탐색 위치 유지·콜백 중복 방지, 기존 거절 후 다음 세션 재안내·같은 세션 중복 방지·승인 후 생략 및 기존 권한/영상 탐색 회귀를 확인했습니다.
- UI 검사는 기존 전용 시뮬레이터 `FCD8D795-A579-4529-A4D6-CA62F5805795`에서 실제 BOKKI 앱을 사용합니다. 실제 iPhone 18은 devicectl에서 unavailable로 확인됐으며 개인 기기 데이터는 수정하지 않았습니다. QA 앱 Documents/BR15L6F2Q9 Library에만 합성 H.264 영상 4개를 만들고 Downloads/Other Videos 탐색을 검사합니다. 실제 iCloud 계정/원본 영상 권한 승인과 시뮬레이터의 로컬 탐색 결과를 구분합니다.
- 첫 실제 앱 UI `UI.xcresult`는 Folder Access의 하위 Downloads → Browse → 나의 iPhone 이동·취소, 기존 거절 이력이 있어도 다음 앱 실행 시 재안내되는 2개 사례가 통과했습니다. 홈 Folder의 위치 이동·다른 폴더 선택 후에는 선택창이 닫혀도 홈이 0 videos로 남는 사례가 실패했습니다. xcresult의 실제 앱 계층과 unified log의 `reason=dismissed`를 확인해, 단순 선택자 오류가 아닌 선택 결과 전달 누락으로 구분했습니다.
- 홈의 결과를 임시 @State 값에만 두는 대신 request ID와 선택·닫힘 상태를 보관하는 HomeDocumentPickerHandoff로 전달합니다. 닫힘과 선택 콜백이 어느 순서로 와도 실제 닫힘 뒤 한 번 처리하고, 이전 요청 결과는 수락하지 않습니다. `Product-handoff.xcresult`: **TEST BUILD SUCCEEDED**, `Unit-handoff.xcresult`: **18개 통과, 실패/스킵 0**. 두 콜백 순서·중복·이전 요청·취소의 실제 전달 규약을 추가로 검사했습니다.
- 최종 UI 재검사에서는 빠른 영상 종료가 파일 선택 검사에 섞이지 않도록 합성 영상을 120초로 만들었습니다. 첫 2초 입력과 초기 manifest도 별도로 보존합니다. 홈 Folder에서 Downloads → Browse → 나의 iPhone → 다른 폴더 → 정확한 영상 목록 반환, 이어 File에서 영상 직접 선택 → 실제 미리보기의 파일명·닫기·홈 복귀 사례가 통과했습니다. 폴더 탐색의 성공과 H.264 합성 영상의 미리보기 진입 확인을 실제 iCloud 원본 재생 확인으로 확대하지 않습니다. 전체 최종 UI 결과는 아래에 기록합니다.
- 최종 `UI-handoff.xcresult`: **3개 통과, 실패/스킵 0**. Folder Access의 Downloads 탈출·나의 iPhone 위치 표시·취소 후 기존 등록 목록 보존, 홈 Folder/File의 실제 선택 반환·영상 미리보기·닫기, 권한이 없는 다음 앱 실행의 재안내·동일 실행 중 중복 방지·시작 안내에서 native 폴더 창 열기/취소를 모두 확인했습니다. 성공한 native Browse 화면과 실제 H.264 미리보기 화면을 내보내 직접 확인했습니다.
- `verification.json`에 최종 제품 빌드 exit 0·단위 18개·UI 3개와 제품/검사 입력 8개 hash 일치를 기록했습니다. `plutil -lint`와 `git diff --check`도 통과했습니다. 원본·합성 입력·검사·화면은 기존 QA 루트의 `BR15L6F2Q9` 아래, 포인터는 `/private/tmp/BOKKIEncoder-BR15L6F2Q9-current.txt`입니다. 이번 개선은 **main의 미커밋 소스이며 TestFlight 55에는 포함되지 않았습니다**. commit/push·신규 TestFlight 배포·개인 기기 설치/데이터 수정은 수행하지 않았습니다. 실제 iPhone 18 원본 iCloud 경로의 확인은 NV15F4D8K2로 유지합니다.

## RL15V6B2K9 — main 통합 및 새 버전 출시 제출 (2026-10-15)

- 사용자 요청에 따라 현재 파일·폴더 탐색 개선을 main에 통합하고 새 TestFlight/App Store 버전으로 제출합니다. Apple 실조회에서 현재 공개 버전은 **1.1.12**(READY_FOR_SALE/READY_FOR_DISTRIBUTION), 진행 중인 심사는 없고 최신 TestFlight는 **1.1.13(55)** VALID입니다. 새 App Store 버전은 **1.1.13**, 빌드는 앱·확장·검사 8곳 모두 **56**으로 올립니다. 승인 후 자동 출시(AFTER_APPROVAL)를 사용합니다.
- BR15L6F2Q9의 최종 제품 빌드 성공·단위 18개·실제 앱 시뮬레이터 UI 3개 통과 근거와 제품/검사 소스 8개 SHA256이 현재와 일치해 해당 기능 검증을 재사용합니다. 새 archive/export·서명·Apple 처리·배포/심사 상태는 별도로 확인합니다. 원본 iPhone 18 iCloud 경로의 직접 검증은 NV15F4D8K2 대기로 보존합니다.
- 출시 안내(ko/en-US)는 미리보기의 정보·공유·목록 추가와 제스처, 파일·폴더 선택/연결 안내, 연결한 폴더·앨범의 이전·다음 탐색 개선으로 간단히 정리합니다. 근거와 배포 입력은 기존 QA 루트의 RL15V6B2K9에 보관하며 포인터는 /private/tmp/BOKKIEncoder-RL15V6B2K9-current.txt입니다.
