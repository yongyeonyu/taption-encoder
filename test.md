# DEL29K8M2Q 삭제 전 인벤토리

아직 삭제하지 않음. 대상 확정 대기.

확인된 로컬 대상:
- `/Users/u_mo_c/Documents/taption_encoder` — 81M, iOS 프로젝트 소스/테스트/Vendor 포함
- `/Users/u_mo_c/Documents/TaptionEncoderAppStoreScreenshots` — 92M, App Store 제출 스크린샷
- `/Users/u_mo_c/Library/TaptionMacEncoder` — 17M, Mac Encoder FFmpeg 런타임
- `/Users/u_mo_c/Library/Application Support/TaptionMacEncoder` — 319M, Mac Encoder 실행 파일/업로드·미디어 데이터
- `/Users/u_mo_c/Library/Logs/TaptionMacEncoder` — 0B
- `/Users/u_mo_c/Library/Application Support/CrashReporter/Taption Encoder_68AFE63E-E23B-5D88-A2B2-B7BBD6F6780F.plist` — 4K, 크래시 보고서

삭제 결과:
- 위 6개 로컬 산출물/지원 데이터 경로를 영구 삭제함.
- TaptionEncoder 전용 DerivedData, Xcode product, CoreSimulator 설치 앱이 남아 있지 않음.
- 프로젝트 소스(`TaptionEncoder.xcodeproj`, `TaptionEncoder/`)와 `.git` 이력은 유지함.
- 다른 Taption 제품과 GitHub 원격 저장소는 변경하지 않음.

확인 결과:
- `~/Library/Developer/Xcode/DerivedData`에 TaptionEncoder 항목 없음
- `~/Library/Developer/CoreSimulator`에 TaptionEncoder 항목 없음
- `/Users/u_mo_c/Documents/TaptionEncoderReleases`는 현재 없음
- 다른 Taption 제품 경로는 삭제 대상에서 제외해야 함

## LRF29Q6M1A

- `TaptionEncoder/Info.plist`가 `.lrf` 파일 확장자를 등록함.
- `TaptionVideoContainer.lrf`가 입력 컨테이너로 정의되고 `.lrf`를 추론함.
- `TaptionLaunchSupportCatalog.supportedInputContainers`에 `.lrf`가 포함됨.
- `SW_SoftwareCodecBackendRegistry`의 FFmpeg/VLC 읽기 컨테이너에 `.lrf`가 포함됨.
- `SW_CodecSupportCatalog`에 `dji_style_lrf_h264_aac` 입력 fixture가 있음.
- 출력 정책은 H.265/HEVC이며 출력 컨테이너는 MP4 또는 MOV로 제한됨.
- 결론: DJI 스타일 LRF(H.264/AAC 계열)는 입력으로 받아 H.265/HEVC MP4 또는 MOV로 변환할 수 있도록 구현되어 있음. LRF 자체로 출력하는 기능은 없음.

## ICL29P7N4Q

- `ImportableVideoTypes`와 `HomeViewModel`은 security-scoped URL 접근을 시작하지만 iCloud 항목의 로컬 다운로드를 요청하거나 완료를 기다리는 코드가 없음.
- 폴더 스캔은 `NSFileCoordinator`를 사용하지만, 개별 미디어 재생은 `Media(url: preview.sourceURL)`로 원본 URL을 직접 넘김.
- 따라서 Files 앱에서 구름 아이콘이 남아 있거나 파일이 아직 내려받는 중이면 자막 포함 여부와 관계없이 재생 실패 또는 영상 출력 없음이 발생할 수 있음.
- 진단 결론: 가장 유력한 원인은 iCloud 파일이 로컬에 완전히 다운로드되지 않은 상태에서 직접 재생을 시도하는 경로이며, 현재 소스에는 이를 보장하는 처리가 없음. 실제 파일이 완전 다운로드된 뒤에도 실패하면 해당 파일의 컨테이너/코덱 로그가 추가로 필요함.

재확인 결과:
- `HIST0929B1_1min-news_20160929_v5.mp4`: 23,477,803 bytes, MP4, H.264 1080x1920 + AAC 2ch, 53.077초
- `Downloads/shorts_1080x1920_92775fa56ce7437cbcdc11cf6c13639d.mp4`: 20,763,466 bytes, MP4, H.264 1080x1920 + AAC 1ch, 36.156초
- 두 파일 모두 CloudDocs에 실제 로컬 파일로 존재하며 0바이트 placeholder가 아님.
- 따라서 다운로드 대기 문제는 해소된 상태이고, 이 파일도 앱에서 재생되지 않으면 앱의 File Provider URL 처리 또는 VLC 재생 로그를 확인해야 함.

## IPD29R6K2A

- 외부 파일 진입점은 준비 화면이 아닌 `autoOpenPreviewAfterPrepare: true` 경로로 변경함.
- iCloud ubiquitous item은 미디어 검사 전에 다운로드 요청 후 완료 상태까지 대기하도록 변경함.
- 시뮬레이터 빌드 및 외부 URL 실제 터치 검증 결과는 아래에 추가 기록한다.

검증 결과:
- iPad Air 11-inch (M4) 시뮬레이터, iOS 27: arm64 빌드 성공. 외부 URL 로그에서 `autoOpenPreview=true`, 준비 완료, `Queue preview opened`, `Queue preview video output ready` 확인.
- iPhone 17e 시뮬레이터: 외부 URL이 앱으로 전달되고 `autoOpenPreview=true`까지 확인했으나 기존 시뮬레이터 저장공간 부족으로 준비 단계에서 중단됨.
- 새 iPhone 18 Pro Max 시뮬레이터 부팅은 호스트 디스크 여유 부족으로 실행하지 못함.
- 검증용 `/tmp` 빌드 산출물과 시뮬레이터 설치 앱은 삭제함.

## TF29M8Q4L1

- TestFlight 새 업로드를 위해 1.1.6 (37)로 버전을 올리고, Release archive/export 및 App Store Connect 처리·내부 그룹 노출을 별도 게이트로 검증한다.

실행 결과:
- 1.1.6 (37) Release archive 성공
- App Store 배포 IPA export 성공
- altool validation 성공: `VERIFY SUCCEEDED with no errors`
- altool upload 성공: Delivery UUID `4414480f-eed2-42f5-a183-64db007489c5`
- App Store Connect API readback: build 37, `processingState=VALID`, `buildAudienceType=APP_STORE_ELIGIBLE`, `expired=false`
- 내부 그룹 `Taption Encoder Internal`에 build 37이 이미 포함됨을 readback. 내부 그룹은 유효 빌드가 자동 연결되어 POST 수동 추가 요청은 Apple API에서 `Cannot add internal group to a build`로 거부됨.
- 내부 그룹 테스터 1명(`axony99@gmail.com`) 상태 `INSTALLED` readback.

## REV29N7C3A

- 리뷰 완료. 코드 수정은 하지 않음.

### 백그라운드 audio 판정 정정 — FIX06R8K2A 재검토

- 기존 리뷰에서 audio 선언만으로 동일 사유 재반려 가능성이 높다고 한 결론은 철회함.
- 현재 `QueuePreviewViews.swift`에는 `PiPVideoView`, PiP 시작·유지, `.playback` / `.moviePlayback` 오디오 세션 및 실제 미디어 오디오 재생이 구현되어 있음.
- Apple은 PiP를 사용하려면 background audio playback 설정이 필요하다고 명시함: https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller
- 2026-10-06 App Store Connect 실시간 readback: 1.1.5 `READY_FOR_SALE`. 현재 반려 중이라는 전제로 audio를 제거하는 것은 부적절함.
- `UIBackgroundModes/audio`는 유지한다. 차후 심사에서 필요하면 실제 기기에서 오디오가 있는 영상의 재생 → PiP → 홈 화면 이동을 녹화하여 기능을 설명해야 함. 시뮬레이터 재생 증거를 실제 기기 심사 녹화로 대신하지 않음.

## FIX06R8K2A

- 외부 파일 자동 재생은 재생용 검사·계획만 준비하며 인코딩 저장공간 검사를 하지 않도록 수정함. `requiresEncodingPreparation`으로 표시하고 인코딩 시작 시 저장공간 확인을 포함한 정상 준비 경로를 반드시 다시 수행함. 별 차감은 이 준비가 성공한 뒤에만 가능함.
- iCloud downloader를 주입 가능한 서비스로 분리하여 모든 미디어 검사(단일 파일·폴더·미리보기·검사 캐시 재사용) 이전에 로컬 이용 가능 상태를 보장함.
- `.current`와 `.downloaded`를 모두 로컬 이용 가능 상태로 인정하고, 매번 URL resource cache를 비워 최신 다운로드 상태를 조회함. 최대 120초 대기, 취소 전파, provider 오류 및 타임아웃별 안내를 추가함.
- 실제 iCloud 폴더의 `DJI_20261003113630_0001_D_자막.mov` 확인: 78,871 bytes, 720×720 HEVC Alpha, 106.373333초, 32개 sparse video frame, 오디오 트랙 없음. 기존 미리보기 codec gate가 HEVC Alpha를 거절하여 자동 플레이어를 열지 않았음. MOV의 HEVC Alpha는 `AVPlayer` / `AVPlayerViewController`로 재생하고, 일반 영상은 기존 VLC 플레이어를 유지함. 전체 화면·미니 플레이어, native PiP 콜백, 오디오 세션·광고 억제의 수명 관리를 추가함. 인코딩의 alpha 보존·라우팅 정책은 변경하지 않음.
- 수정 전 clean generic iOS Debug build, 최종 수정본의 signed generic iOS Debug build 및 unsigned generic iOS Release build, arm64 simulator build-for-testing 모두 통과함.
- 검증 산출물: `/tmp/TaptionEncoder-FIX06R8K2A.qsicl6`. 기존 업로드된 TestFlight 1.1.6 (37) 바이너리와 현재 로컬 수정의 증거를 구분한다.

### 최종 검증 — 2026-10-06

- `FinalVerified.xcresult`: 핵심 회귀 테스트 **20/20 통과**, 실패·건너뜀·runtime warning 없음. iPhone 17e / iOS 27.0 / arm64, 자체 검증용 simulator `D54B5939-D9E3-4815-A572-53A6423A61B8`에서 실행함. 외부 파일 자동 미리보기, 저장공간 검사 지연, 시작 전 재준비, 별 차감 안전성, busy 상태의 소스 보존, HEVC Alpha native 경로, iCloud 상태·최종 poll·타임아웃·provider 오류·취소, 기존 앨범/파일/플레이리스트 동작을 확인함.
- 최종 빌드 로그: `verified-final-ios-build.log` (Debug, signing 포함), `verified-release-ios-build.log` (Release, compilation/link 확인), `final-native-seek-build.log` (arm64 build-for-testing). 새 native preview 코드의 compiler warning/error 없음. 기존 codec API deprecation 및 종속 라이브러리 경고는 남아 있음.
- 원본과 검증용 MOV의 SHA-256 동일: `797c8cf12f1a4de7565ccecdd7e189aa88e762d348f1998f9cf2b99d4b02004b`. 원본 iCloud 파일은 변경하지 않음.
- 실제 파일 4초 지점의 자막 `일단 커피를 한잔 먹고 시작해야겠다` 표시를 육안 확인함: iPad Air 11-inch (M4) / iOS 27 simulator (`ipad-subtitle-verified.png`), iPhone 17e / iOS 27 simulator (`iphone-subtitle-verified.png`), **iPhone 11 Pro / iOS 27.0.1 실제 기기** (`physical-subtitle-verified.png`, `physical-final-alpha.log`). 화면 캡처를 위해 DEBUG 전용 seek 후 일시정지했으며, 이는 전체 영상 재생 완료 테스트가 아님.
- 파일의 Apple BGRA decode 검사: 32 frame 중 21 frame에 정상 자막, 11 frame은 빈 투명 구간. 처음 0~3.07초는 자막이 없으며 중간에도 빈 구간이 있음. 10초의 image-generator 실제 sample time은 9.476666초의 빈 frame인 반면 FFmpeg `-ss` 추출은 뒤의 frame을 잡을 수 있었음. 검은 캡처만으로 파일 손상·투명 채널 호환 문제라고 추정한 중간 판정은 철회함.
- Apple HEVC Alpha encoder로 만든 독립 fixture `valid-alpha.mov`도 iPad simulator 및 실제 iPhone에서 표시됨 (`ipad-valid-alpha-playing.png`, `physical-valid-alpha.png`). 이 fixture의 정상 표시와 실제 자막 파일 캡처를 함께 검증하여 output-ready 로그만으로 성공 판정하지 않음.
- H.264 + AAC 영상은 기존 VLC 경로에서 실제 iPhone PiP `active=true`, `possible=true`, `simulator=false` 확인. `physical-pip.png`에서 재생 위치 14.833초 및 PiP 뒤의 **앱 메인 화면**이 보이며, 전체 검은 preview 화면이 메인을 가리지 않음. player mute=false, volume=1.00 및 playback 오디오 세션 활성화 로그 확인. 실제 청취·iOS 홈 화면에서의 연속 오디오 녹화까지 확인한 증거는 아니므로 심사용 오디오 증명으로 대신하지 않음.
- 제한: iCloud 실제 신규 다운로드/네트워크 장애는 상태 주입 테스트로 검증했고 실제 파일은 이미 로컬 이용 가능 상태였음. 전체 120개 codec physical regression과 native HEVC Alpha PiP 버튼의 실제 터치 테스트는 실행하지 않음. Intel x86_64 simulator 링크는 기존 FFmpeg bridge의 arm64-only 구성으로 실패했으며, 지원되는 arm64 simulator 검증은 통과함.
- `main` / `origin/main` 모두 `788c2961b34dc80d9d9ef106b8be6e20d0c97fd9`. 기존 사용자 버전 변경(1.1.6 / 37)을 보존했고 새 commit/push/archive/upload/심사 제출은 하지 않음. 기존 TestFlight build 37에는 이번 FIX06R8K2A 수정이 포함되지 않음. 차기 업로드 시 마케팅 버전·빌드 번호를 둘 다 새로 올려야 함.
- 실제 iPhone에 이번 수정의 확인용 Debug 앱을 설치하고 테스트 환경변수 없이 다시 시작함. 로컬 생성물은 별도 `/tmp` 경로에 두고, 정리 결과는 아래에 기록함.
- 정리 완료: 자체 임시 simulator `D54B5939-D9E3-4815-A572-53A6423A61B8` 삭제, 기존 iPad simulator에 이번 검증으로 설치한 `com.taption.encoder` 앱·검증용 데이터 제거, 자체 생성 DerivedData 약 1.9GB는 휴지통으로 이동함(복구 가능하며 휴지통을 비우지는 않음). 다른 simulator, 기존 릴리즈/Swift package cache, GitHub·로컬 소스는 삭제하지 않음. 최종 xcresult·로그·스크린샷은 `/tmp/TaptionEncoder-FIX06R8K2A.qsicl6`에 유지함.

### P1/P2 — 외부 파일 “바로 재생” 경로가 인코딩용 저장공간 검사에 결합됨

- `openExternalPlayerFile`은 `autoOpenPreviewAfterPrepare: true`로 올바르게 플레이어를 요청하지만, 내부적으로 `prepareEncodingFlow` 전체를 먼저 수행함.
- 이 흐름은 `TaptionVideoCore.prepareSingleAssetJob` 뒤에 인코딩 작업공간 저장공간 검사를 수행하고, 부족하면 `storageBlocked`에서 종료한 뒤 미리보기를 열지 않음.
- 실제 iPhone 17e 시뮬레이터 검증에서 외부 URL 전달과 `autoOpenPreview=true`까지는 확인됐지만, 1080×1920 파일은 약 311.5MB, 작은 320×180 파일도 약 285.2MB의 요구량 때문에 미리보기 전에 차단됨.
- 결론: 디스크 여유가 적은 실제 iPhone/iPad에서 “파일을 열면 바로 재생” 요구가 인코딩 가능 여부 때문에 실패할 수 있음. 플레이어 진입은 미디어 검사/재생 가능성만 확인하고, 인코딩 저장공간 검사는 사용자가 인코딩을 시작할 때로 분리하는 것이 안전함.

### P2 — iCloud 다운로드 대기 실패 메시지가 일반적인 인코딩 오류로 축약됨

- `ensureUbiquitousItemDownloaded`는 최대 30초 대기 후 `CocoaError(.fileReadUnknown)`을 던짐.
- 호출부의 일반 `catch`는 이를 “Encoding failed / could not prepare this video”로 표시하므로, 사용자는 iCloud 다운로드 지연·권한·File Provider 문제를 구분하기 어려움.
- 취소 전파(`Task.checkCancellation`)와 비동기 sleep 사용은 적절함. 다만 타임아웃 전용 오류/사용자 안내(“Files에서 먼저 다운로드 완료 후 다시 시도”)가 있으면 복구성이 좋아짐.

### 통과/제한 사항

- iPad Air 11-inch (M4) arm64 시뮬레이터: 외부 URL → 준비 완료 → `Queue preview opened` → `Queue preview video output ready` 확인.
- `git diff --check`: 통과.
- 1.1.6 (37) Release archive/export, App Store Connect validation/upload, `VALID / APP_STORE_ELIGIBLE`, 내부 그룹 build 노출: 통과.
- iPhone 실제 기기 재생과 build 37의 특정 테스터 설치 상태는 이번 증거로 확정하지 못함. iPhone 시뮬레이터는 저장공간 부족으로 재생 출력까지 진행되지 않음.
- 버전 1.1.6 (37) 변경은 프로젝트 설정의 마케팅/빌드 번호 일괄 증가이며, 그 자체의 문법·구성 오류는 발견되지 않음.

## REV06D4N8Q — 현재 작업 트리 상세 코드 리뷰 (2026-10-06)

### 범위와 증거 구분

- `main` / `origin/main` / HEAD: `788c2961b34dc80d9d9ef106b8be6e20d0c97fd9`. 현재 변경된 SourceOpening, HomeScreenState, HomeViewModel, QueuePreviewViews, 새 NativeQueueVideoPreviewView, 관련 테스트와 Xcode 등록을 검토하고 HomeView/Stars/시작·취소·오디오 세션 호출 관계를 추적함.
- 앱 소스·프로젝트·테스트를 수정하지 않음. 기록 파일만 갱신함. commit/push/upload/기기 설치/시뮬레이터 생성·정리는 하지 않음.
- 기존 최종 `FinalVerified.xcresult`를 다시 읽어 20 passed / 0 failed / 0 skipped / runtimeWarnings 없음 확인. signed generic Debug 및 unsigned generic Release 로그의 BUILD SUCCEEDED 확인. 전체 테스트를 이번에 다시 실행한 것이 아니며, 모든 codec/실기기 시나리오 통과라는 뜻도 아님.
- 별도 제어 실험 경로: `/tmp/TaptionEncoder-REV06D4N8Q.phqhn9`. Ruby가 현재 앱 파일에서 검토 대상 메서드를 그대로 추출하여 Swift로 실행함. 지갑·encoder·player·저장/광고 등 주변 서비스는 기록용 대역으로 대체한 **메서드 수준 실험**이며, 실제 AVKit/VLC decode 또는 실기기 UI 검증으로 대체하지 않음.

### P1 — 시작 요청이 예약·추적되지 않아 중복 차감 및 취소 후 재시작 가능

- 위치: HomeViewModel.swift:2229, 4587, 4602, 4610, 387, 3429.
- Start는 즉시 busy/starting 상태를 설정하지 않고, `activeTask`에 저장되지 않는 Task를 생성함. 지갑 await 이후 현재 review/operation/cancellation 검증이 없으며 `startEncoding(...allowsBusyState: true)`로 강제 진입함. Reset은 추적 중인 `activeTask`만 취소하므로 예약되지 않은 시작 요청이 남음.
- `start-race-probe.rb`는 실제 `startPreparedEncoding`, `attemptEncodingStart`, `reset`, `blockEncodingStartForInsufficientStars`를 추출함. snapshot 반환을 제어해 동시성 창을 재현함.
- 결과 (`start-race-result.log`):
  1. 두 Start: 별 잔액 3 → 1, consume 2회, encoder-start 2회.
  2. 지갑 조회 중 실제 reset() 호출: idle 이후 대기 중 시작이 encoder-start를 호출함.
  3. 별 1개로 두 Start: 첫 encoder-start 이후 두 번째 부족 처리에서 readyToStart로 되돌아가고 activeTask/activeStarCharge가 nil로 지워짐.
  4. playback-only review로 두 Start: `allowsBusyState=true` 준비 호출 2회. 실제 준비 함수는 이전 activeTask를 cancel하며, 기존 취소 catch에는 generation 검증이 없으므로 중첩 준비 경로까지 열림.
- 권고: Start를 동기적으로 한 번만 예약하고 시작 Task/operation token을 추적한다. Reset/소스 변경 시 취소·무효화하고 각 await/catch 후 소유 operation을 확인한다. 별 예약/환불은 해당 operation에 연결하여 이미 진행 중인 다른 작업의 핸들·별 정보를 지우지 않는다.
- 중복 시작/지갑 await 취소의 근본 문제는 기존 코드에도 존재하며, 신규 requiresEncodingPreparation 분기가 중복 준비 경로를 추가함. 이를 HEVC Alpha decode 자체의 회귀로 분류하지 않음.

### P2 — 일반 파일·앨범 소스 변경 시 기존 미니 플레이어가 유지됨

- 위치: HomeView.swift:194, 206, 642, 721, 796; HomeViewModel.swift:2096, 6767.
- `miniPlayerPreview`는 HomeView의 별도 @State이고 viewModel.dismissPreview()는 activePreview만 비움. 미니 정리는 Reset/외부 URL 진입/미니 Close·Expand에만 연결되어 있음. 일반 파일 picker, import browser 확정, Photos 완료 경로는 기존 미니를 지우지 않음.
- 재현 경로(호출·뷰 트리 검증): 영상 A를 미니로 축소 → Album/Files로 B를 가져옴 → B 카드 Play. A의 mini overlay와 B의 full preview 조건이 동시에 참이므로 별도 player가 함께 유지됨. 두 경로 모두 mute=false/volume=unity로 설정하고, 새 소스 접근 시작은 이전 security scope를 해제함.
- 영향: 숨겨진 이전 영상의 동시 재생/소리 혼합 및 이전 미디어 접근 수명 불일치 가능. 실제 기기에서 이 경로의 음향 재현은 이번에 하지 않음.
- 권고: 소스 전환 수락 시 공통 경로에서 미니를 종료하거나 full/mini를 동일한 재생 세션 상태로 관리한다. 기존 `testPreviewClosesOnResetSourceChangeAndEncodingStart`는 viewModel.activePreview만 검사하므로 HomeView의 mini 상태를 검증하지 못함.
- 기존 UI 수명 관리 문제이며 새 native 경로에서만 발생하는 것으로 한정하지 않음.

### P2 — VLC fallback이 취소 후에도 다음 재생을 호출함

- 위치: QueuePreviewViews.swift:1244, 1246, 1258, 1357; 미니의 동일한 fallback 패턴도 검토함.
- `try? Task.sleep`이 CancellationError를 삼키고, waitForVideoOutput은 취소를 단순 false로 반환함. fallback 루프는 false를 재시도 조건으로 처리하며 다음 stop/media/play 전에 Task.checkCancellation을 하지 않음.
- `preview-cancel-probe.rb`는 실제 previewDemuxModes/playPreviewWithFallbacks/waitForVideoOutput을 추출하고 출력이 준비되지 않는 player를 사용함. MOV의 첫 automatic 재생 후 task.cancel()을 호출했는데, `Task.isCancelled=true` 상태로 avformat 재생이 추가 호출됨. 결과는 false이며 CancellationError가 아님 (`preview-cancel-result.log`).
- 영향: 닫기/영상 전환으로 폐기된 작업이 이후에도 player와 오류/loading 상태를 건드릴 수 있음. 실험은 제어 흐름을 증명하며 실제 VLC에서 화면·소리가 다시 나타났다고 주장하지 않음.
- 권고: 취소를 fallback 실패와 구분해 throw하며 각 재시도와 player 조작 전에 cancellation/재생 generation을 확인한다. 오래된 작업의 catch·종료도 새 세션 상태를 변경하지 않도록 한다.
- 기존 fallback 코드의 문제이며 이번에 native 분기로 전환하는 경로도 추가 검토함.

### 낮은 우선순위 성능 개선 권고 — native 경로의 불필요한 VLC 생성

- QueuePreviewViews.swift:142 및 1392에서 분기 이전에 @State player를 생성함. makePreviewPlayer는 매번 별도 VLCInstance를 생성하지만 native 분기에서는 그 player를 사용하지 않음.
- native/VLC view 소유자를 분리하거나 VLC 분기에서 지연 생성하면 불필요한 초기화를 피할 수 있음. 실제 메모리·전력·시작 시간의 증가량은 프로파일링하지 않았으므로 심각도를 정량화하지 않음.

### 정상 확인 및 남은 검증

- 재생용 외부 파일 준비는 저장공간 검사를 지연하며, 인코딩 시작 전에 정상 준비로 돌아가는 구조가 유지됨. 지갑 동시성 문제와 별개로 준비 실패 전 별 차감 방지 회귀는 기존 테스트에서 통과함.
- iCloud `.current`/`.downloaded`, 최종 poll, 오류·timeout·취소 전파와 fingerprint 일치 조건을 검토함. 현재 자료에서 추가 확정 오류는 발견하지 못함. 신규 원격 다운로드/실제 네트워크 장애는 미검증임.
- native item.status callback은 currentItem identity를 확인하며 shutdown에서 item observation/player/audio session을 정리함. HEVC Alpha의 실제 자막 표시 증거는 FIX06R8K2A의 iPhone/iPad 자료를 재사용함. native PiP 버튼·홈 화면 오디오, 최소 지원 iOS 및 전체 120 codec physical regression은 미검증임.
- native HEVC Alpha 단위 테스트는 route/metadata/storageCheckCount를 확인하지만 AVPlayerViewController 재생·PiP·최소화/확대 수명 자체를 실행하지 않음. 추가 회귀는 지갑 지연 중 연속 Start/Reset/소스 변경, mini 상태의 Files/Photos 교체, fallback 대기 중 닫기·영상 전환을 포함해야 함.
- 최종 `git diff --check` 통과. 기록 변경을 제외한 앱 소스 변경 없음. 업로드된 TestFlight 1.1.6 (37)에는 현재 로컬 FIX06R8K2A 수정이 포함되지 않는다는 기존 증거 구분을 유지함.

## FIX06P3M7Q — 상세 리뷰 수정 및 Files 기본 연결 확인 (2026-10-06)

### 요청·범위·기본 연결의 남은 단계

- 사용자가 기본 플레이어의 의미를 **파일 앱에서 Taption Encoder를 기본 연결 앱으로 사용**이라고 확인함. 앱 내부의 모든 영상 decoder를 AVPlayer로 교체하지 않음. 일반 영상은 기존 VLC, HEVC Alpha MOV는 Apple native playback 경로를 유지함.
- 시작 시 `main`, `origin/main`, HEAD는 모두 `788c2961b34dc80d9d9ef106b8be6e20d0c97fd9`. 이전 FIX06R8K2A의 dirty source, native player, 프로젝트 등록 및 1.1.6 (37) 설정을 보존하며 그 위에 REV06D4N8Q 수정을 적용함.
- Info.plist의 두 영상 DocumentTypes는 이미 Viewer / Owner이고, MP4·MOV·legacy UTI, in-place 및 Files 지원 등록이 있음. `testImportableVideoTypesMatchCurrentLaunchInputContainers`로 재검증함. 이 등록만으로 기기의 파일별/유형별 기본 연결 선택이 완료됐다고 주장하지 않음.
- Apple 공식 안내: 파일 앱 → 파일 길게 터치 → 정보 가져오기 → **항상 다음으로 열기** → 앱 선택 → 해당 파일 또는 파일 유형 변경 확인. [Apple 지원](https://support.apple.com/ko-kr/guide/iphone/iphe4bff8827/ios).
- iPhone 미러링을 이름/번들 ID로 읽으려 했지만 timeout 또는 앱 해석 오류가 발생함. 재확인 시 앱은 실행 중이지만 접근 가능한 화면을 얻지 못함. 기기 기본 연결은 **미변경/미확인**이며 사용자에게 미러링 연결 또는 직접 선택을 요청함. 기본 연결 선택 후 Files에서 실제 파일을 탭하는 최종 OS UI 검증은 남아 있음.
- commit/push, archive/export, TestFlight/App Review 업로드 또는 제출은 하지 않음. 이 수정은 로컬 검증 코드이며, 기존 TestFlight build 37에 반영됐다는 뜻이 아님.

### 구현

- HomeViewModel: Start를 동기 예약하고 시작 Task 및 operation ID를 추적함. 연속 Start를 차단하고 Reset/새 소스/실패에서 무효화하며, 지갑 조회·차감·새 snapshot 반환 뒤 현재 operation/review/cancellation을 확인함.
- 차감이 완료된 뒤 오래된 요청이 취소되면 취소되지 않은 별도 Task에서 해당 차감만 환불함. 새 작업의 activeTask/activeStarCharge를 지우지 않음. 새 지갑 snapshot으로 겹친 환불·차감의 표시 잔액을 갱신함.
- 준비 작업에도 operation ID와 await/catch 소유권 검증을 추가하여 폐기된 준비 작업이 새 소스 상태를 덮어쓰지 않도록 함. 준비 완료 상태를 먼저 게시한 뒤 자동 Start를 예약함.
- 미니 플레이어를 HomeView 로컬 State에서 HomeViewModel의 읽기 전용 Published 상태로 이동함. Files/Photos/외부 열기·Reset·인코딩 시작 및 full preview 전환에서 동일한 재생 세션 정리를 사용함. 오래된 PiP callback은 현재 preview ID가 다르면 무시함.
- VLC full/mini fallback에서 취소를 삼키던 대기를 throwing 방식으로 바꿈. 공유 QueuePreviewPlaybackAttempts 및 lifetime ID로 각 재시도·player 조작·대기 결과·오류 상태 변경을 검증함. 정상 실패일 때의 두 번째 demux 재시도는 유지함.
- native/VLC view 소유자를 분리하여 native preview에서 사용하지 않는 VLC Player/Instance를 생성하지 않도록 함. 메모리·발열·fps 개선량은 프로파일링하지 않았으므로 수치로 주장하지 않음.
- 출력 HEVC / MP4·MOV, encoder backend 및 영상 geometry는 변경하지 않음. 화면 문자열은 영어를 유지함.

### 빌드·자동 회귀

- 증거 경로: `/tmp/TaptionEncoder-FIX06P3M7Q.iuynqE`. 생성물은 소스 트리 밖에 저장함. 이전 clean generic iOS build를 baseline으로 재사용한 뒤 현재 소스를 Debug/Release 및 arm64 simulator로 다시 컴파일함.
- 공통 명령: `xcodebuild -project TaptionEncoder.xcodeproj -scheme TaptionEncoder -derivedDataPath <증거>/DerivedData -clonedSourcePackagesDirPath /tmp/TaptionEncoder-TF29M8Q4L1/DerivedData/SourcePackages -disableAutomaticPackageResolution`.
- signed generic iOS Debug: `-configuration Debug -destination 'generic/platform=iOS' build`, `final-debug-ios-build.log`, **BUILD SUCCEEDED**.
- unsigned generic iOS Release: `-configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`, `final-release-ios-build.log`, **BUILD SUCCEEDED**. 배포 archive/export 검증이 아님.
- arm64 simulator test compile: iOS 27 iPhone 17e / `7924C008-2201-4182-91F6-C2BCE710F372`, `reverified-simulator-build.log`, **TEST BUILD SUCCEEDED**.
- 47개 선택 회귀: `-parallel-testing-enabled NO -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/<name> test-without-building`. 전체 명단은 `<증거>/selected-tests.txt`. 최종 `FinalVerified2.xcresult`: **47 passed / 0 failed / 0 skipped**, runtimeWarnings/testFailures 없음. `final-tests2.log`: 실행 7.443초. 전체 앱 테스트 또는 120 codec 실기기 회귀를 실행한 결과로 확대 해석하지 않음.
- 신규 11개: 동기 Start 예약·단일 차감, snapshot 중 Reset, debit commit 뒤 Reset 환불, debit 중 소스 교체 및 새 작업 보호, 외부 playback-only 중복 준비, mini Files/Photos/Reset/Start 정리, full 복원, fallback 취소·generation 교체·정상 재시도, native wrapper의 VLC 미생성을 검증함.
- 위 신규 11개를 `-test-iterations 3 -test-repetition-relaunch-enabled YES`로 실행함. 최종 `RaceVerified.xcresult`: **33 runs / 0 failed**, 11 unique tests, runtimeWarnings/testFailures 없음. `race-verified-tests.log` 세 iteration 모두 통과.
- 최초 47개 실행에서는 테스트 fixture의 AV1이 preview 불가 조건이어서 preview 전제의 3개 테스트가 실패함. fixture만 H.264로 명시하여 실제 동작 전제를 수정했으며 assertion은 삭제하지 않음. 해당 `FocusedVerified.xcresult`는 보존함.
- 최초 반복 실행 `RaceRepeated.xcresult`는 1·2회 통과, 3회에서 저장 완료 대기 2초 timeout 1회 발생함. 로그상 save completion은 2.4249초로 실제 완료됨. 새 테스트 네 곳의 대기 상한만 10초로 변경하고 차감/encoder 호출/환불/잔액 assertion을 유지한 뒤 위 47 + 33회 재검증함. 실패 결과도 보존함.
- `git diff --check`, 변경한 HomeViewModel/HomeView/QueuePreviewViews/CodecRoutePlannerTests의 `swiftc -frontend -parse` 통과. 기존 deprecated 테스트 API, SDK/캐시 경고를 새 소스 오류로 혼동하지 않음. 이전 경로에서 재사용한 DerivedData의 stale path 경고가 있으나 빌드 완료와 결과 bundle로 현재 소스 검증을 확인함.

### 런타임 증거·제한

- 같은 원본 자막 MOV를 `<증거>`의 테스트 복사본으로 사용함. iPhone 및 iPad 시뮬레이터에서 현재 native wrapper를 실행하고 4초 위치로 seek한 `iphone-native.png` / `ipad-native.png`를 육안 확인함. 두 화면에 자막 문구가 표시됨. 전체 106초 영상의 모든 frame 검증은 아님.
- 실기기: 연결된 iPhone 11 Pro / iOS 27.0.1, UDID `00008030-001628201AD2802E`. 기존 앱이 developer Debug 1.1.6 (37)임을 먼저 확인하고 현재 signed Debug를 설치함 (`physical-before-app-info.json`, `physical-install.json`). 기존 사용자 앱 데이터/지갑을 초기화하지 않음.
- 원본을 `Documents/FIX06P3M7Q-subtitle.mov`로 복사하고 DEBUG preview/seek 환경으로 열었음. `physical-native.log`: Native playback started, first video frame ready, `seconds=4 finished=true`, 375×375 video bounds 확인. 이 실기기 증거는 decode/seek 로그이며 새 실기기 screenshot이나 청취 검증으로 주장하지 않음.
- 별도 H.264/AAC 테스트 영상을 `Documents/FIX06P3M7Q-playback.mp4`로 복사함. `physical-vlc-pip.log`: automatic 첫 demux에서 `hasVideoOutput=true`, `activeVideoOutputs=1`; native PiP controller `possible=true`, `active=true`, `simulator=false` 확인.
- `physical-vlc-mini.log`: full 출력 성공 → auto minimize → full ad suppression 해제 → mini video output `hasVideoOutput=true`, `activeVideoOutputs=1` 확인. 새 ViewModel mini 상태 연결 및 mini fallback의 실제 출력 증거임. 실제 기기에서 연속 picker 교체·Reset UI 조작은 자동 회귀로 대체했으며 OS UI로 다시 눌러 본 결과라고 주장하지 않음.
- 실제 audio 청취/화면 녹화 capture, native HEVC Alpha PiP 버튼·홈 화면 오디오, 최소 지원 iOS, 최신 iPad 실기기, 전체 codec 회귀 및 새 iCloud 네트워크 장애는 이번에 미검증임. audio session preferred 설정 -50 뒤 basic playback fallback 활성화 로그는 기록되어 있고 새 발견으로 배포 심사 통과를 보장하지 않음.
- 테스트 후 실기기는 DEBUG 자동 재생/seek 환경 없이 정상 재실행함. 실기기 테스트용 두 파일은 앱 Documents에 고유 이름으로 남으며 원본 iCloud 영상은 수정하지 않음. 이번 전용 simulator 및 기존 iPad에 이번 설치한 테스트 앱/데이터만 정리하고, 다른 simulator와 기존 release/법률 기록을 보존함. 상세 정리 결과는 아래에 기록함.

### 테스트 후 정리 확인

- `physical-normal-relaunch.log`: `Launched application with com.taption.encoder bundle identifier.` 확인. 자동 재생·PiP·mini·seek 환경을 전달하지 않고 정상 실행함.
- 이번 생성 전용 `TaptionEncoder-FIX06P3M7Q` simulator `7924C008-2201-4182-91F6-C2BCE710F372`를 shutdown/delete함. 이후 `simctl list devices -j`에 없음. 테스트 전용 폐기 데이터이며 삭제한 simulator의 앱/데이터 자체는 복구되지 않음. 검증 결과 bundle, 로그, 스크린샷은 `/tmp` 증거 경로에 보존함.
- 기존 iPad `E825E51D-9EC6-439D-B5F6-A11C4A0394F0`는 그대로 유지함. 이번 설치 전 앱 부재를 확인했던 com.taption.encoder 테스트 설치만 terminate/uninstall함. 이후 get_app_container가 No such file로 앱 부재를 확인함. 다른 두 기존 iPhone simulator와 기존 iPad는 Booted 상태로 보존됨.
- 이번 사용한 DerivedData는 `/Users/u_mo_c/.Trash/TaptionEncoder-FIX06P3M7Q-DerivedData`로 이동함. 휴지통에서 복구 가능하며 영구 삭제 또는 휴지통 비우기를 하지 않음. 공유 SourcePackages, 다른 앱/작업의 cache, 보존 release 자료는 삭제하지 않음.
- 정리 후 main/origin 상태는 동일하고 기존·요청 변경 파일만 남음. 최종 `git diff --check` 통과. `temp.md`에는 미완료인 기기 기본 연결 UI 선택만 남김.

## FIX06A8V2N — 재생 전환·오디오 안정화 (2026-10-06)

### 범위와 원인

- 사용자가 기존 기능 안정화 1~3번을 진행하도록 승인했으며, 실제 iPad 연결 대신 이번에는 시뮬레이터 검증을 선택함. 다중 영상 합치기, commit/push, 버전 증가, archive/export, TestFlight/App Store 업로드·심사 제출은 이번 범위에서 제외함.
- 시작 시 main/HEAD/origin/main은 `788c2961b34dc80d9d9ef106b8be6e20d0c97fd9`로 같았음. 기존 FIX06R8K2A/FIX06P3M7Q 변경을 보존했으며 새로운 브랜치·원격 변경을 만들지 않음. App Store Connect의 현재 심사/배포 상태는 이번에 확인하지 않았으므로 로컬 결과로 이를 주장하지 않음.
- 증거 경로: `/tmp/TaptionEncoder-FIX06A8V2N.jutZsc`. 이전 전용 빌드 캐시를 휴지통에서 이 경로로 이동하여 재사용함. 공유 SourcePackages는 정확한 기존 경로 `/tmp/TaptionEncoder-TF29M8Q4L1/DerivedData/SourcePackages`만 재사용함.
- full/mini가 별도 player를 생성하며 위치와 paused/playing 상태를 전달하지 않았음. playback category에 부적합한 allowAirPlay 옵션을 설정하여 실기기 -50/basic fallback이 발생했고, 동기 오디오 활성화/비활성화를 main thread에서 수행했음.

### 구현

- `QueuePreviewPlaybackSnapshot`으로 finite/비음수 시각, 재생 의도, duration clamp를 전달함. ViewModel은 현재 full/mini ID를 검증하고 미니 복원 시 현재 미니 metadata를 사용함. 로딩 중 재전환은 요청 snapshot을 보존함.
- AVPlayer(native HEVC Alpha) 경로는 item ready 후 precise seek completion을 확인하고 이전 pause/play를 복원함. cancelPendingSeeks, task 취소 및 item/session 일치 검사로 오래된 완료를 배제함. 첫 frame과 snapshot 복원이 모두 준비돼야 로딩을 해제함.
- VLC seek는 비동기이며 currentTime은 요청 직후 optimistic 값임을 SwiftVLC 0.10.1의 `Player+Seek.swift`에서 확인함. 첫 vout/seekable만 보고 seek→pause하면 요청 6초가 0.41초로 돌아가는 실제 simulator 재현을 발견함. 별도 native time/position 구독으로 실제 입력 clock 준비를 확인한 뒤 seek함.
- paused 전환은 안정적인 pause 응답을 기다린 뒤 precise seek하여 정상 전환의 시각 밀림을 방지함. paused seek는 timeChanged를 생략할 수 있으므로 독립적인 displayedPictures 증가도 완료 근거로 사용함. 둘 다 갱신되지 않으면 음소거 상태로 한 번 재탐색하고 pause 응답을 확인함. 이 대체 경로는 프레임 단위 정밀성을 보장하지 않음. cancel/stale 오류는 재시도하지 않으며, 취소된 오래된 작업의 defer가 새 media의 mute 상태를 바꾸지 않도록 검사함. 구독은 bounded(8)이고 완료·오류·취소 시 해제함. 최종 실패/timeout은 안내 후 player를 stop함.
- audio는 `.playback / .moviePlayback / options: []`. 직렬 background queue에서 설정하고 iOS 27에서는 public asynchronous activate/deactivate, iOS 18~26에서는 background setActive를 사용함. main actor의 request/owner 체인과 player instance별 UUID lease가 full A→mini B→full C의 늦은 A 종료까지 차단함.
- 근거: SDK AVAudioSession category contract와 Apple의 [allowAirPlay](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowairplay), [allowBluetoothA2DP](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetootha2dp), [activate](https://developer.apple.com/documentation/avfaudio/avaudiosession/activate(options:completionhandler:)) 문서. Output-only playback은 AirPlay/A2DP를 이미 지원하며 allowAirPlay는 playAndRecord용임.
- decoder 분리(native Alpha / 일반 VLC), encoding codec/geometry, HEVC 출력 및 MP4/MOV 정책은 변경하지 않음. 회귀 자동 전환/seek probe는 DEBUG에서만 작동함.

### 빌드·자동 회귀

- arm64 Simulator build-for-testing: `final-probe-simulator-build.log`의 TEST BUILD SUCCEEDED. generic iOS signed Debug/Release는 아래 최종 확인에 기록함.
- 중간 선택 72개(기존 47 + 당시 신규 25): `FinalStable72.xcresult`, `selected-tests-72.txt`, `final-stable-72-tests.log`. iPad Air 11-inch (M4) / iOS 27.0 / arm64에서 **72 passed / 0 failed / 0 skipped**, runtimeWarnings/testFailures 없음. 테스트 실행 22.294초(전체 xcode 작업 wall time과 별개). 이후 paused 대체 복구 3개 회귀를 추가함.
- 신규 항목: paused/playing snapshot round-trip, stale callback, 범위 보정, seek readiness/완료/취소/timeout, seek 완료 전 pause 금지, await 이후 generation 검증, displayed frame ack, audio activation/close 직렬화 및 superseded request/동일 preview ID 재사용, 다운로드 대기 취소 후 다른 소스 열기·재시도.
- 위 중간 신규 25개 3회 반복은 `FinalStableRepeated75.xcresult`에서 75 runs / 0 failures. 최종 신규 28개 반복 결과는 아래에 기록함.
- 최초 61개 실행은 두 테스트가 실패했음(`Verified.xcresult` 보존). 다운로드 도중 새 소스 선택은 의도적으로 busy guard에 막히므로 fixture를 Cancel → cancelled 확인 → 다른 소스 → 원본 재시도로 바로잡음. production busy 정책/핵심 assertion을 삭제하지 않음. DEBUG PiP helper의 새 operationID signature에 맞춰 source assertion도 수정함. 보정한 61개, UUID 추가 후 62개 및 15×3, native seek ack 보완 후 68개 및 21×3 모두 통과한 중간 결과도 보존함.
- 실제 simulator seek 실패/이전 시각 복귀 및 paused timeline 이벤트 생략은 버리지 않고 `iphone-vlc-paused-before-seek-ack.app.log`, `iphone-vlc-paused-seek-ack.console.log`, `iphone-vlc-paused-precise.console.log` 등 실패 증거를 보존함. 최종 시간만 검사하는 optimistic 테스트로 대체하지 않고 실제 player 재실행으로 수정 확인함.
- 저장 공간이 한때 221MiB로 줄어든 시점에 `precise-paused-debug-build.log`의 CodeSign internal error가 발생함. 공간 부족과의 인과를 확정하지 않으며, 인증서/프로젝트 설정 변경 없이 최종 signed Debug 빌드가 성공함. 임시 index 삭제 시도는 실행 도구의 보호로 거절되어 삭제되지 않았음.
- `final-retry-debug-build.log`는 같은 DerivedData의 두 실제 build가 겹쳐 build.db locked로 실패함. 동시 build를 중단하고 `final-retry-debug-build2.log`에서 재실행 성공함. source/서명 오류로 확대 해석하지 않음.

### 실제 iCloud 파일 및 런타임 증거

- Mac의 실제 iCloud 원본 `Taption Encoder/DJI_20261003113630_0001_D_자막.mov`에 production SourceOpening.swift의 downloader를 사용한 probe를 실행함(AppLogger만 console shim). `icloud-probe.log`: ubiquitous=true / NotDownloaded / local=false → 실제 download 요청 → Current / readableBytes=78871. 원본 SHA-256 `797c8cf12f1a4de7565ccecdd7e189aa88e762d348f1998f9cf2b99d4b02004b`를 재확인함. 원본 내용은 수정·evict하지 않음. 이는 Mac provider 증거이며 iOS Files의 실제 네트워크/UI 검증과 동일시하지 않음.
- 다운로드 취소 unit fixture는 실제 Task cancellation을 기록하는 controlled downloader임. 대기/검사가 중지되고 재시도가 허용되는지 검증했으며, OS iCloud provider의 전송 자체가 취소됐다고 주장하지 않음.
- iPhone 17e / iOS 27 Simulator: `iphone-vlc-paused-final.console.log`에서 6.0초 → mini 6.0 / playing=false → full 6.0 / playing=false. `iphone-vlc-paused-final.png`에서 00:06, Play 아이콘 및 정상 영상 출력 확인함. 프레임에 포함된 sample timecode는 5.900으로, 이 테스트를 모든 codec의 frame-accurate 편집 보장으로 확대하지 않음.
- 동일 iPhone VLC 재생 중: `iphone-vlc-playing-final.console.log`에서 mini 요청 6.408 → 6.66 / playing=true, full 요청 6.66 → 6.901 / playing=true, 정상 clock 진행. `iphone-vlc-playing-final.png` 보존. Playing 경로의 native clock 허용 오차는 0.35초이며 전환하는 동안의 정상 시간 진행과 paused drift를 구분함.
- 동일 iPhone 원본 Alpha 자막: `iphone-native-paused-final.console.log`에서 mini/full 모두 4.0 / playing=false와 first frame ready; `iphone-native-paused-final.png` 보존. 재생 중 `iphone-native-playing-final.console.log`에서 mini 4.3967 / full 4.7933 / playing=true. 원본은 음성 없는 sparse subtitle 영상이므로 무음 자체를 audio session 실패라고 해석하지 않음.
- iPad native: `ipad-native-paused.app.log`에서 mini/full 4.0 / false, `ipad-native-playing.app.log`에서 mini 4.365 / full 4.76 / true. `ipad-native-paused.png`의 자막 문구 표시를 육안 확인함. 최종 VLC 변경 이후에도 native 구현과 worker는 이 증거의 코드와 같음.
- iPad VLC: `ipad-vlc-paused-final.console.log`에서 mini 6.0 / false 뒤 full 출력 ack timeout이 한 번 발생함. 실패를 보존하고 위 음소거 대체 복구를 구현함. 보완한 정상 재실행 `ipad-vlc-paused-retry-final.console.log`은 mini/full 모두 6.0 / false, `ipad-vlc-paused-retry-final.png` 보존. `ipad-vlc-playing-final.console.log`은 mini 6.0 / true 및 full 6.405 / true로 재생 의도와 clock 진행 확인. 이전 seek ack 구현의 runtime 출력 증거도 보존함.
- 최종 DEBUG에서 `TAPTION_FORCE_PAUSED_SEEK_RETRY=1`로 ack 누락만 강제하고 실제 player에서 복구함. `ipad-vlc-forced-retry-final.console.log`: 원래 full·mini·복원 full 세 곳에서 muted retry 수행, native clock 확인 및 pause 응답 후 mini 6.159 / false, full 6.41 / false; playback failed 없음. 각 전환의 관측 오차 약 0.16/0.25초. `ipad-vlc-forced-retry-final.png`에서 00:06 / Play 아이콘 / sample timecode 6.300의 실제 영상 표시를 육안 확인함. 실패/완료 값을 mock으로 대신한 테스트가 아니며, 강제 env 분기는 Release에 포함되지 않음.
- 실제 iPhone 11 Pro / iOS 27.0.1에서는 중간 signed Debug를 설치하고 VLC paused 전환·async audio activation을 확인함(`physical-vlc-paused.log`, `physical-install.json`). audio worker는 최종과 같은 구현이며 fallback=false, -50/AVAudioSessionHangRisk 없음. 이 결과를 마지막 VLC seek/frame 보완의 실기기 검증으로 주장하지 않음. 기존 기기 데이터/지갑은 초기화하지 않음.
- `ipad-vlc-pip.console.log`: simulator=true / possible=false / active=false / hasAVController=false. 현재 SwiftVLC simulator 경로에서 시스템 PiP가 제공되지 않으므로 백그라운드 audible/PiP 성공을 주장하지 않음. DEBUG-driven callbacks로 실제 full/mini player lifecycle을 실행한 증거이지 OS 버튼/홈 화면을 직접 조작한 결과가 아님.
- 미검증: 실제 iPad, 최저 지원 iOS 18의 runtime, 최종 실기기 청취/화면 녹화, native Alpha PiP 버튼/홈 화면, iOS 실제 cloud 네트워크 장애/취소, 전체 codec 120개 물리 회귀. codec/geometry 변경이 없는 이번 로컬 검증을 archive/export/TestFlight/App Review/법적 승인과 구분함. AdMob account form 및 simulator WebContent/telephony/deprecated 경고는 이번 player 수정으로 해결했다고 주장하지 않음.

### 최종 확인·정리

- 최종 기본 동작 전체 선택: `FinalRetry75.xcresult`, `selected-tests-75.txt`, `final-retry-75-tests.log`. iPhone 17e / iOS 27.0 / arm64에서 **75 passed / 0 failed / 0 skipped**, runtimeWarnings/testFailures 없음. 실행 8.360초. 이후 DEBUG 강제 ack 누락 probe만 추가했으며 기본/Release 동작은 변경하지 않음.
- 최종 신규 28개 × 3회: `FinalRepeated84.xcresult`, `final-84-repeated-tests.log`에서 **84 runs / 0 failed / 0 skipped**, 28 unique tests, runtimeWarnings/testFailures 없음. DEBUG probe 추가 후 빌드한 app으로 실행함. 강제 env는 자동 회귀에 전달하지 않음.
- 최종 generic iOS signed Debug: `final-proof-debug-build.log`의 BUILD SUCCEEDED. 최종 generic iOS Release: `final-retry-release-build.log`의 BUILD SUCCEEDED. archive/export/upload/심사 승인 증거가 아님.
- 최종 소스 SHA-256: QueuePreviewViews.swift `7691ccd5807dec9c6b4d2c3cfd74fa1c740685b930e7e7239ff6672258e5b49e`; NativeQueueVideoPreviewView.swift `55aa156bf6b4fbccf9bc54d1f3456f4351fd4ca47480383fa4727a9fa0028aa1`; HomeViewModel.swift `a20995db065304803ff827bc2cf6e1f477e402659d646ee112c8f48911676284`; CodecRoutePlannerTests.swift `0255167ae46c6e0186a6accd7e849359881ed1135ad2fdaa4cacc652ae74dbea`.
- 테스트용으로 새로 만든 `TaptionEncoder-FIX06A8V2N` simulator (`881F6DB6-DCB9-4B30-8763-B0002FF22FB3`)만 종료·삭제함. 해당 임시 simulator 데이터는 삭제됐지만 simulator 자체는 재생성 가능하며 모든 로그·xcresult·스크린샷은 위 증거 경로에 보존함.
- 기존 iPad simulator (`E825E51D-9EC6-439D-B5F6-A11C4A0394F0`)에는 설치 전 Taption Encoder가 없음을 확인했으므로 이번 임시 설치 `com.taption.encoder`만 종료·제거함. 제거 후 get_app_container는 No such file or directory / exit 2. 기존 iPad 및 다른 기존 iPhone simulator, 다른 앱/데이터는 보존함. 실제 iPhone의 중간 Debug 설치·테스트 파일은 삭제하지 않았으며 최종 빌드 설치로 주장하지 않음.
- 실행 중인 xcodebuild가 없음을 확인하고 이번 전용 DerivedData만 `/Users/u_mo_c/.Trash/TaptionEncoder-FIX06A8V2N-DerivedData`로 이동함. 휴지통에서 복구 가능하며 영구 삭제·휴지통 비우기는 하지 않음. 공유 SourcePackages, 다른 작업의 캐시, 기존 release 자료와 원본 영상은 건드리지 않음. 증거 경로의 FinalRetry75/FinalRepeated84 xcresult 및 iPad 스크린샷 보존을 다시 확인함.
- 마무리 시 HEAD/main/origin/main은 모두 `788c2961b34dc80d9d9ef106b8be6e20d0c97fd9`로 동일함. 기존 변경과 이번 수정은 로컬 작업 트리에 보존하며 commit/push하지 않음. 최종 `git diff --check` 통과. 완료된 FIX06A8V2N만 temp.md에서 제거하고 별도 미완료인 FIX06P3M7Q 기기 기본 연결 UI 선택은 남김.

## FIX06C9H4S — 보관 중인 자막 MOV의 로컬 복사 재생 확인 (2026-10-06)

### 요청·대상

- 사용자는 iCloud 연결 문제가 아니라 해당 폴더의 영상 자체가 재생되지 않는다고 정정하고, 영상을 복사해서 테스트하도록 요청함. 초기 cloud provider 조사에서 파일 자체 검증으로 범위를 변경했으며 downloader/codec/geometry/출력 정책은 수정하지 않음.
- 대상 폴더를 1단계 목록으로 확인했고 영상은 `DJI_20261003113630_0001_D_자막.mov` 하나였음. 원본 `/Users/u_mo_c/Library/Mobile Documents/com~apple~CloudDocs/Taption Encoder/`는 읽기만 하고 로컬 증거 폴더 `/tmp/TaptionEncoder-FIX06C9H4S.Y7zSDf/subtitle-original.mov`로 복사함.
- 원본·로컬 복사본·두 simulator의 Documents 복사본 SHA-256이 모두 `797c8cf12f1a4de7565ccecdd7e189aa88e762d348f1998f9cf2b99d4b02004b`로 일치함. 파일 내용·원본 이름은 변경하지 않음.

### 파일 분석·실제 앱 출력

- `media-probe.json`, `frame-timestamps.csv`: 78,871 bytes / MOV / 720×720 / 106.373333초 / video 1 track, audio 0 tracks / 32 frames. 첫 frame은 0초의 빈 화면이고 다음 자막 frame은 3.070000초, 이후 6.906667초 등에 다른 frame이 있음. `source-frame-01/02/03.png`를 직접 열어 빈 화면 → “일단 커피를 한잔 먹고 시작해야겠다” → “와~” 확인함. 이 파일에는 촬영 영상/오디오가 없고 sparse 자막 출력이 들어 있음. FFmpeg의 기본 HEVC probe와 별도로 실제 앱의 Apple inspector는 `hevcWithAlpha`로 식별함.
- 이전 FIX06A8V2N 최종 simulator app을 복사해 사용함. 관련 source 4개 SHA-256이 이전 최종 기록과 같음을 확인했으므로 유효한 최종 build/test를 재사용하고 이번에 새 build 또는 75개 자동 테스트 재실행을 했다고 주장하지 않음. bundle `com.taption.encoder`, 로컬 표시 버전 `1.1.6 (37)`, 실행 파일 SHA-256 `95983c28b5a533743aa89c6f2e48f62523915c222646f581a3c60aedfff08729`. 같은 표시 버전이라도 원격 배포본과 동일한 binary라는 증거는 아님.
- 새 전용 iPhone 17e (`AC832FA1-1393-4D94-833C-EDE3AAF3199C`) 및 iPad Air 11-inch (M4) (`0251295B-4290-494B-A94B-7B816596A8AB`) / iOS 27.0에만 app과 동일한 로컬 파일을 설치함. 기존 simulator와 실제 기기는 변경하지 않음.
- 강제 seek 없이 처음부터 연 normal run에서 두 기기 모두 inspector의 `hevcWithAlpha`, native playback started, first video frame ready, rate=1.0, audio activation fallback=false 확인함. `ipad-normal-first.png`에서 “와~”의 실제 표시를 육안 확인함. 두 normal app 로그는 `iphone-normal.app.log`, `ipad-normal.app.log`에 보존함. 이 결과를 전체 106초 완료/실기기/시스템 PiP 검증으로 확대하지 않음.
- 별도 재실행은 기존 DEBUG `TAPTION_PREVIEW_SEEK_SECONDS=4`만 사용하여 실제 AVPlayer를 4초에 seek·pause함. 두 기기에서 `Native queue preview debug seek completed finished=true seconds=4` 확인 후 다시 screenshot을 찍음. 최종 증거 `iphone-paused-4s-ready.png`, `ipad-paused-4s-ready.png`를 직접 열어 위 첫 자막 문구가 모두 표시되는 것을 확인함. 초기 `*-paused-4s.png`는 앱 초기화 중 캡처였으므로 4초 출력 성공 증거로 사용하지 않음.
- native playback/position/audio activation 실패 로그는 두 최종 app log에서 발견되지 않음. AdMob timeout은 별도 광고 초기화/네트워크 로그이며 이를 파일 decode 실패로 분류하지 않음. 최종 `iphone-final.app.log`, `ipad-final.app.log`, normal/seek screenshot 모두 증거 폴더에 보존함.

### 결론·제한

- 요청한 원본 복사 재생 테스트는 완료함. 동일 파일이 최신 로컬 수정본의 iPhone/iPad native 경로에서 자막을 표시하므로 이번 로컬 검증에서는 재생 불가가 재현되지 않음. 처음 3.07초의 자막 없는 구간 및 자막 외 검은 화면은 파일 내용과 부합함. 사용자의 실제 기기 문제를 단순히 이 구간 탓이라고 확정하지 않음.
- 이전 Alpha/native 미리보기 수정은 로컬 dirty 변경에 포함되어 있고 HEAD/main의 경로와 다름. 실제 사용 중인 앱의 배포 경로·binary/버전 및 해당 기기 로그는 아직 확인되지 않았으므로 사용자가 가진 설치본에서 해결됐다고 주장하지 않음. 이번에 source 변경, version bump, commit/push, TestFlight 업로드, App Review 제출 또는 실제 기기 설치를 하지 않음.
- 이번에 생성한 위 두 simulator만 종료·삭제함(모두 exit 0). 임시 simulator 데이터는 삭제됐고 재생성 가능하며, 파일 복사본·로그·screenshot은 증거 폴더에 보존함. 기존 booted iPhone 18 Pro/iPhone 17e/iPad 및 다른 작업 simulator는 그대로 둠. 임시 app 복사본은 `/Users/u_mo_c/.Trash/TaptionEncoder-FIX06C9H4S-test.app`로 이동해 복구 가능함. 이전 DerivedData/공유 패키지 및 release 자료는 건드리지 않음.
- 정리 후 원본 SHA-256을 재확인했고 동일함. HEAD/main/origin/main은 모두 `788c2961b34dc80d9d9ef106b8be6e20d0c97fd9`, 기존 dirty 소스는 보존, 최종 `git diff --check` 통과. 완료된 복사 재생 검증 FIX06C9H4S만 temp.md에서 제거했고 기존 미완료 FIX06P3M7Q는 남김.

## REL06T7M9C — main 반영·TestFlight 새 빌드·source-only 정리 (2026-10-06)

- 사용자가 main 커밋/푸시, TestFlight 빌드 업로드 및 관련 소스 외 산출물·시뮬레이터 데이터 정리를 명시적으로 요청함. App Review 제출/공개 릴리스는 이번 요청에 포함하지 않음.
- 시작 main/HEAD/origin/main은 `788c2961b34dc80d9d9ef106b8be6e20d0c97fd9`, fetch 후에도 동일. 로컬 preview/audio/source preparation/race 수정 및 새 native player를 모두 보존해 반영한다.
- ASC app은 이름/브라우저 탭에 의존하지 않고 `bundleId=com.taption.encoder`로 조회하여 `6780777838`을 확인함. 다른 앱의 열린 브라우저 탭은 릴리스 대상으로 사용하지 않음. 해당 앱 live readback: 공개 `1.1.5 / READY_FOR_SALE`, 최신 TestFlight `1.1.6 (37) / VALID / APP_STORE_ELIGIBLE`, expired=false. 신규 버전은 모든 8개 target/configuration에서 `1.1.7 (38)`로 증가함.
- 최종 preview/native/VM/test 소스 4개 SHA-256이 FIX06A8V2N 최종 기록과 동일함을 확인했고 FinalRetry75.xcresult의 75 passed/0 failed/0 skipped, FinalRepeated84.xcresult의 신규 28개×3회=84 runs/0 failed를 재확인함. summary JSON을 이번 증거 폴더에 옮겼으며 이미 유효한 자동 회귀를 새로 실행했다고 주장하지 않음. 버전 증가 후 새 Release archive/export를 별도로 검증한다.
- 다른 프로젝트의 xcodebuild가 공유 simulator에서 동시에 실행 중임을 확인함. 공유 device/runtime와 다른 프로젝트 데이터는 초기화하지 않고 Taption Encoder 앱 설치·데이터 및 Encoder 전용 생성물만 정리한다.
- 저장 공간이 약 3GB로 줄어 이전 완료 FIX06A8V2N/FIX06C9H4S/FIX06P3M7Q/FIX06R8K2A/REV06D4N8Q의 테스트·스크린샷·로그 폴더를 사용자 요청에 따라 먼저 삭제함. 상세 결과는 위 기록에 보존했지만 원래 /tmp 증거 링크는 이후 열리지 않을 수 있다. 이 생성물 삭제는 휴지통 이동이 아닌 영구 삭제이며 Git 소스·원본 iCloud 영상은 삭제하지 않는다.
- AGENTS의 보존 `1.1.3 (34)` release record는 이 작업 시작 시 정확한 경로에 존재하지 않았음. 이 작업으로 삭제하지 않았으며 이전 법적 승인 pending/source-offer gate를 승인으로 변경하지 않는다. 필수 vendor/framework, 앱 assets, codec fixtures, 라이선스/릴리스 스크립트는 재현 가능한 source 구성으로 유지한다.
- 이번 임시 증거/빌드 경로: `/tmp/TaptionEncoder-REL06T7M9C.wTXaLS`. 진행 결과는 아래에 이어 기록하고 사용자 요청에 따라 업로드 확인 후 생성물을 삭제한다.

### main 커밋·새 archive/export·Apple 전달

- 구현 및 버전 변경 커밋: `c5e5e8fb832fee4ed06dd86576f81dd9dcbb1e93` (`Fix video preview playback and audio session stability for 1.1.7`). `main`에서 생성해 `origin/main`에 push 성공했고, 이 정확한 코드 상태로 아래 배포본을 생성함. 이후 완료 기록 커밋은 AGENTS.md/temp.md/test.md만 변경하며 앱 소스는 변경하지 않음.
- 새 전용 DerivedData에서 generic iOS / Release `clean archive` 수행: `archive.log`의 **CLEAN SUCCEEDED / ARCHIVE SUCCEEDED**, exit 0. `TaptionEncoder-1.1.7-38.xcarchive`의 main app은 arm64 / `com.taption.encoder` / `1.1.7 (38)`이며 `codesign --verify --deep --strict` 통과.
- SwiftPM 고정 버전: GoogleMobileAds `13.5.0`, GoogleUserMessagingPlatform `3.1.0`, SwiftVLC `0.10.1`. 기존 75개 및 신규 28개×3회 회귀 증거를 재사용했고 이번 릴리스 작업 중 다시 실행한 테스트라고 주장하지 않음. 출력 HEVC / MP4·MOV, encoder backend 및 geometry는 변경하지 않음.
- `xcodebuild -exportArchive` **EXPORT SUCCEEDED**, exit 0. export는 `method=app-store-connect`, automatic signing, team `4FWG8XXYM7`, `manageAppVersionAndBuildNumber=false`, **`testFlightInternalTestingOnly=true`**. App Store 심사 제출이나 외부 TestFlight 배포용 빌드가 아님.
- IPA `Taption Encoder.ipa`: **26,840,799 bytes**, SHA-256 **`917692ad10043114cfc0b8185c2cfdccc385af00b90f4ce1a719e7e2e3b17c91`**. Apple Distribution 서명 및 deep/strict 서명 검사 통과. main app과 두 extension 모두 `1.1.7 (38)` 일치. Release 실행 파일에 native preview 로그 문자열이 있고 DEBUG 전용 강제 seek/retry 환경 변수 문자열 두 개는 없음.
- Apple `altool` validation: `validate.log`의 **VERIFY SUCCEEDED with no errors**, exit 0. upload: `upload.log`의 **UPLOAD SUCCEEDED with no errors**, exit 0. Delivery UUID / ASC build ID **`30e114f0-e77e-48c4-b2e2-8d35c7255fdd`**, 업로드 반영 시각 **2026-10-06 18:52:56 KST**.
- `altool --build-status --delivery-id … --wait` exit 0: **processingState=VALID**, build/import status=VALID, audience=INTERNAL_ONLY, is-on-app-store-connect=true, uses-non-exempt-encryption=false. 업로드 receipt와 처리 완료를 별도 확인함.

### App Store Connect / 내부 TestFlight readback

- 공식 API `GET /v1/builds?filter[app]=6780777838&filter[version]=38`에서 한 빌드를 조회함: `version=38`, preReleaseVersion=`1.1.7`, platform=IOS, **processingState=VALID**, **buildAudienceType=INTERNAL_ONLY**, expired=false.
- 같은 build의 buildBetaDetail: **internalBuildState=IN_BETA_TESTING**, externalBuildState=NOT_APPLICABLE, autoNotifyEnabled=true. 자동 알림 설정을 확인한 것이며 테스터의 실제 알림 수신/설치 완료 증거는 아님.
- 기존 내부 그룹 **`Taption Encoder Internal`** (`10a4640f-864b-4952-bb94-cd2ea87a96c0`, hasAccessToAllBuilds=true)의 `GET /v1/betaGroups/<id>/builds` 목록에 위 build 38 / 동일 UUID / VALID / INTERNAL_ONLY가 포함됨. 새 테스터를 초대하거나 다른 앱·그룹을 변경하지 않음.
- 이번 범위는 내부 TestFlight 전달 완료까지임. App Review 제출/공개 릴리스, 사용자 실기기 설치·재생·시스템 PiP/가청 background audio 및 법적 승인 완료로 확대 해석하지 않음. `legal-approval.pending.json`과 public distribution gate는 그대로 비승인 상태임.

### source-only 정리·보존 확인

- 사용자 요청에 따라 이전 proof 디렉터리 `/tmp/TaptionEncoder-FIX06A8V2N.jutZsc`, `FIX06C9H4S.Y7zSDf`, `FIX06P3M7Q.iuynqE`, `FIX06R8K2A.qsicl6`, `REV06D4N8Q.phqhn9`를 영구 삭제함. 위 과거 작업의 원래 screenshot/xcresult/log는 더 이상 로컬에 보존되지 않으며, 남은 기기 기본 연결 UI 요청 FIX06P3M7Q 자체는 완료로 처리하지 않음.
- 이전 `/tmp/TaptionEncoder-TF29M8Q4L1` 약 1.5GB의 archive/export/패키지 체크아웃과 동일 ID의 flat export-options/log/API 생성 파일, `/Users/u_mo_c/Library/Developer/Xcode/DerivedData/TaptionEncoder-cppuipnwyznujvabarpyvzevtqvq`, 작업 트리의 ignored `.DS_Store`를 영구 삭제함. private API key·서명 인증서·프로비저닝 및 다른 프로젝트의 공유 캐시는 삭제하지 않음.
- 기존 iPhone 17e (`DBF0A437-57FB-44A4-BDCC-80A0C2A74CF8`)의 **`com.taption.encoder`만 uninstall** exit 0, 이후 get_app_container는 No such file or directory / exit 2. 전체 available simulator의 bounded bundle/data plist inventory에서 `com.taption.encoder`, `.tests`, `.liveactivity`, `.thumbnail`에 일치하는 항목은 최종 **[]**. 다른 앱이 사용하는 generic simulator 또는 OS runtime은 erase/delete하지 않음.
- 원본 iCloud 자막 MOV를 삭제·수정하지 않았고 최종 SHA-256을 다시 확인함: **`797c8cf12f1a4de7565ccecdd7e189aa88e762d348f1998f9cf2b99d4b02004b`**, FIX06C9H4S 기록과 동일. Git source, 필수 vendor/framework/assets/fixtures/licenses 및 compact 검증 기록은 보존함.
- 처리 완료와 그룹 연결을 확인한 뒤 이번 `/tmp/TaptionEncoder-REL06T7M9C.wTXaLS` 약 555MB 전체(새 DerivedData/archive/IPA/dSYMs/추출 앱/업로드 임시물/API·테스트 요약·로그)를 **영구 삭제**, `rm -r` exit 0. `com.taption.encoder`가 포함된 배포 로그로 확인한 `/var/folders/q1/0p9tcvnx7yx5l12y55zm4tdm0000gn/T/TaptionEncoder_2026-10-06_13-16-45.289.xcdistributionlogs` 및 `TaptionEncoder_2026-10-06_18-45-47.948.xcdistributionlogs`도 같은 방식으로 삭제함.
- 위 새/이전 증거·패키지·DerivedData·배포 로그의 정확한 경로는 모두 최종 **ABSENT**. `/tmp`, 해당 macOS 임시 폴더, Xcode DerivedData/Archives, Downloads, Trash의 Encoder 이름 한정 목록에서도 추가 일치 항목이 없음. `git ls-files --others --ignored --exclude-standard` 결과도 빈 목록임. 공유 simulator OS 자체를 모두 삭제했다는 뜻은 아님.
- 삭제한 raw proof/IPA/archive/dSYMs는 휴지통에서 복구할 수 없음. 소스는 GitHub/main으로 보존되지만 동일 업로드 빌드의 디버그 심볼 재생성·복구는 보장하지 않음. 다음 빌드는 패키지 resolve와 derived 산출물 재생성이 필요함.
- 완료 기록 전 `git diff --check` 통과, build source 커밋 이후 차이는 기록 파일뿐임. 추가 worktree는 없고 유일한 worktree는 프로젝트의 main checkout. 이번 REL06T7M9C만 temp.md에서 제거하며 별도 미확인인 FIX06P3M7Q는 유지함.

## PUB06V8N2R — 출시 초안·수정사항 등록 및 공개 배포 차단 확인 (2026-10-06)

### 상태·범위·차단 조건

- 사용자는 앱 출시 및 수정사항 작성을 요청함. 시작 HEAD/main/origin/main은 모두 `ed17d666df085bfd08df1648a07ee907d0e0e53f`, 작업 트리는 clean. 릴리스 코드 source commit은 `c5e5e8fb832fee4ed06dd86576f81dd9dcbb1e93`이며 이번에 앱 소스·프로젝트 버전은 변경하지 않음.
- 공식 ASC API로 app `6780777838`의 `bundleId=com.taption.encoder`, name=`taption encoder`, primaryLocale=`en-US`를 재확인함. 공개 버전 `1.1.5 / READY_FOR_SALE`; 새 출시 초안은 처음에 없었음. latest uploaded build는 `1.1.7 (38) / VALID / INTERNAL_ONLY / IN_BETA_TESTING`이며 expired=false. 이전 `1.1.6 (37)`의 APP_STORE_ELIGIBLE 상태를 최신 preview/audio 수정 포함 증거로 쓰거나 대신 제출하지 않음.
- 내부 테스트 전용 빌드가 App Store 제출을 방지하는 선택임은 [Apple 배포 안내](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)로 확인함. 기존 38을 App Store용으로 바꿨다고 주장하지 않음. 새 업로드를 진행하려면 프로젝트 지침에 따라 marketing/build를 함께 증가한 일반 App Store 배포본이 필요함.
- `Vendor/OpenSourceCompliance/README.md`, `LEGAL_REVIEW_PACKET.md`, gate script 및 `legal-approval.pending.json`을 확인함. 승인 status와 네 가지 결정 모두 pending, approvalID/reviewer/approvedAt 및 release/digest 필드가 비어 있음. gate는 정확한 archive/Distribution IPA/대응 source/relink/size-report와 외부 승인 digest를 요구함. 지난 정리에서 생성물을 영구 삭제한 상황이며, 공개 배포 gate를 실행·PASS한 것으로 기록하지 않음. 소스 수정이나 pending → approved 임의 변경은 하지 않음.
- 승인 자료가 없는 현재 범위에서는 공개 build 생성·업로드·심사 제출·공개 출시를 수행하지 않음. 외부 승인 기록의 경로 또는 승인용 자료 준비 방향을 사용자에게 요청해야 하며 PUB06V8N2R는 미완료로 temp.md에 유지함. 이 로컬 gate 차단을 Apple의 새로운 rejection 또는 법률적 불법 확정으로 표현하지 않음.

### App Store Connect 초안·문구·보존 검증

- 현재 등록 locale는 **ko / en-US 두 개**임. 요청의 짧고 기능 중심인 작성 방향에 맞춰 실제 수정된 자막 영상 preview/playback, seek/player 전환, file opening/encoding Start·Reset 안정화만 작성함. 이미 공개 1.1.5에서 소개한 iPad landscape를 새 변경으로 반복하지 않고, 측정하지 않은 성능 향상 수치를 쓰지 않음.
- 올바른 app 관계로 `POST /v1/appStoreVersions`: version **1.1.8**, platform IOS, releaseType **AFTER_APPROVAL**. 생성한 version ID **`0649aa64-cc2d-4e5c-b95c-129053c487ad`**. 최종 API readback은 **PREPARE_FOR_SUBMISSION**, releaseType=AFTER_APPROVAL, selected build relationship **null**. 설정만 준비했으며 심사 승인 또는 실제 출시 완료라는 뜻이 아님.
- Apple는 새 version 생성 시 기존 metadata가 이전됨을 안내함([새 버전 생성](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/)). 실제 비교에서도 두 locale의 description/keywords/marketingUrl/promotionalText/supportUrl이 공개 버전과 동일함을 확인한 뒤, 새 초안의 whatsNew만 PATCH함. 공개 1.1.5의 수정사항·메타데이터를 덮어쓰지 않음.
- 한국어 등록 문구: `일부 자막 영상의 미리보기와 재생을 개선했습니다.\n재생 위치 이동과 플레이어 전환의 안정성을 개선했습니다.\n파일 열기와 인코딩 시작·초기화 처리의 안정성을 개선했습니다.` (실제 값은 세 줄).
- 영어 등록 문구: `Improved previews and playback for certain subtitle videos.\nImproved stability when seeking and switching players.\nImproved stability when opening files and starting or resetting encoding jobs.` (실제 값은 세 줄).
- 두 PATCH 성공 후 공식 GET으로 다시 읽은 whatsNew가 locale별 작성값과 정확히 일치함. 다른 metadata 다섯 필드도 작성 전/후 일치. screenshot signature(display type·파일명·크기·source checksum·image dimensions·delivery state 및 관계의 순서)를 공개 버전, 새 초안 작성 전, 작성 후에 비교해 동일함을 확인함.
- 스크린샷은 locale마다 **APP_IPHONE_65 5개 + APP_IPAD_PRO_3GEN_129 10개**, 총 **30개**로 유지됨. 이번에 새 이미지를 생성/업로드하거나 기존 이미지를 삭제하지 않음.
- 임시 API/helper/검증 JSON 위치는 `/tmp/TaptionEncoder-PUB06V8N2R.VyAdty`; private P8는 서명 내부에서만 사용하고 값/JWT를 출력·저장하지 않음. 새 archive/IPA/DerivedData/시뮬레이터 데이터는 만들지 않음. commit/push는 이번 요청으로 수행하지 않으며 기록 파일만 로컬 변경으로 남김.
- 검증 결과를 위 compact 기록으로 남긴 뒤 이번에 생성한 해당 임시 API/helper/JSON 폴더만 source-only 유지 방향으로 삭제함(`rm -r` exit 0, 정확한 경로 최종 ABSENT). 소스·private key·원본 영상 및 기존 다른 작업 데이터는 삭제하지 않음. 최종 `git diff --check` 통과, 앱 source/build configuration diff 없음. AGENTS.md/temp.md/test.md만 이번 요청의 로컬 기록 변경으로 남으며 출시 요청은 미완료 상태임.

## LAW06N5K8T — 1.1.8 (39) 외부 승인 검토 자료 준비·출시 문구 정정 (2026-10-06)

### 요청·범위·소스

- 사용자는 PUB06V8N2R의 차단 조건에 대해 승인 검토 자료 준비를 요청함. 이후 기존 자막/미리보기 표현을 빼고 일부 영상 재생 불가 개선으로 정정하도록 요청함. 이번 작업은 로컬 검토 자료 및 해당 ASC 문구 변경까지이며 Apple 업로드/심사 제출·외부 검토자 발송·commit/push를 수행하지 않음.
- 시작 및 최종 확인 HEAD/main/origin/main은 `ed17d666df085bfd08df1648a07ee907d0e0e53f`. 기존 dirty AGENTS.md/temp.md/test.md를 보존함. 실제 runtime 수정 commit은 `c5e5e8fb832fee4ed06dd86576f81dd9dcbb1e93`이며, 8개 target/configuration의 marketing/build를 함께 `1.1.8 (39)`로 증가해 새 후보를 만듦. 앱 Swift/C 코드·library binary·encoder/output 정책은 변경하지 않음.
- 라이브러리 대조에서 기존 출처 JSON의 FFmpeg bridge device/simulator hash가 이전 바이너리에 해당함을 발견함. 현재 두 바이너리가 Git HEAD 및 마지막 변경 commit `94a5294c5f93d9ae670d416a1832f4cf8baaacb6`과 동일함을 확인하고, 비번들 `libvlc-ios-provenance.json`의 hash와 검증 날짜·binary source commit만 수정함. 현재 arm64 SHA-256 `9ef599100adf0972f766d0ad86239db6ba705e8d27037fd67d827e4a99515704`, simulator arm64 `2ebd28e4c02c3dd730c6decb1ec83ba7a3b76c68d561c8988fb0b2ef4963df17`. 이 JSON은 Xcode의 컴파일/리소스 입력이 아니며 archive 뒤 이 기록 수정으로 앱 binary는 바뀌지 않음.
- BaseSource 스냅샷(`git archive`로 앱/프로젝트/두 extension/테스트/Vendor/.gitignore만 포함, 비공개 자료)에 CandidateVersion.patch와 CandidateComplianceMetadata.patch를 순서대로 적용해 **119개 구성 파일 전부**가 현재 작업 트리와 일치함을 확인함. 새 후보가 이미 commit된 소스라고 표현하지 않음.

### 새 Release archive·Distribution export·기술 검증

- 새 전용 `/tmp/TaptionEncoder-LAW06N5K8T.RF8id0`에서 SwiftPM resolve 후 generic iOS / Release `clean archive`: **CLEAN SUCCEEDED / ARCHIVE SUCCEEDED**, exit 0. SDK/Xcode는 27.0 / 27A266a. 고정 GoogleMobileAds 13.5.0, UMP 3.1.0, SwiftVLC 0.10.1을 유지함. archive는 소스 폴더 밖의 새 `1.1.8-39-LAW06N5K8T` record로 생성했고 부재한 역사적 1.1.3 record를 덮어쓰거나 재구성하지 않음.
- `app-store-connect` / `destination=export`, automatic signing, `manageAppVersionAndBuildNumber=false`, **testFlightInternalTestingOnly=false**, `uploadSymbols=false`로 **EXPORT SUCCEEDED**, exit 0. IPA **23,347,059 bytes**, SHA-256 **`302a267ebbc28c21546da17a7713b1ec39a5043b896113d977811e5c2ac32b2b`**. 이는 로컬 일반 배포 export이며 Apple 서버 validate/upload/processing/App Store eligibility 확인이 아님.
- archive 및 추출 IPA의 앱·Live Activity extension·Thumbnail extension 모두 `1.1.8 (39)` / iphoneos / 최소 OS 18.0 일치. `codesign --verify --deep --strict` 통과, IPA Apple Distribution 및 get-task-allow=false 확인. 세 실행 파일 각각 archive dSYM UUID와 일치함. 전체 archive 앱 bytes **45,986,620**; __TEXT bytes는 main **36,913,152**, Live Activity **98,304**, Thumbnail **49,152**.
- 같은 archive의 별도 **release-testing / thin-for-all-variants export**도 exit 0으로 성공해 실제 Xcode `App Thinning Size Report.txt`를 수집함. iPhone/iPad 각 **20.9 MB compressed / 43.5 MB uncompressed**, universal **23.3 MB / 46 MB**, ODR 없음. 이 보고서의 provenance는 같은 archive의 별도 export이며 App Store IPA와 동일한 byte의 Apple 서버 크기 보고서로 주장하지 않음. [Apple 크기 규격](https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes/)도 확인함.
- preview/native/VM/test 주요 소스 4개의 SHA-256이 FIX06A8V2N/REL06T7M9C의 최종 값과 모두 일치함. 기존 75개 unique tests와 신규 28개×3=84 runs / 실패 0 compact 기록을 재사용함. 이전 raw proof는 소유자 요청으로 삭제되어 있으므로 새 test 실행 또는 raw result 재검사로 표현하지 않음. 이번에 simulator/실기기/minimum OS/PiP/background audio 회귀를 새로 수행하지 않음.

### 고정 대응 소스·정확한 재링크·승인 gate

- 제공된 source bundle 도구를 사용해 SwiftVLC/VLC/FFmpeg 8.1.1의 고정 SHA-256, **contrib source 56건의 SHA-512**, SwiftVLC의 local patch 4건 SHA-256을 확인함. VLC revision의 실제 contrib recipe는 FFmpeg **8.0**이며 mirror의 새 버전으로 대체하지 않음. mirror에서 받지 못한 6건은 고정 upstream URL에서 동일 checksum으로 확보하고, FluidLite는 고정 Git commit의 upstream `git archive` + xz recipe로 재현해 매니페스트 SHA-512와 일치시킴. 예상 hash를 낮추거나 변경하지 않음.
- 최종 대응 소스는 **377,927,008 bytes**, SHA-256 **`0ba94db56f6c237f1eef0a56e4c946eeabfa860b59cd303ed13714d3cddc8ab6`**. 수정한 출처 JSON과 최신 bridge source/build recipe가 포함됨. generated contrib 고지 **54항목**이 실제 앱의 `libVLC-Contrib-Licenses.txt`와 byte 단위로 동일함. 2건 순수 host build inputs도 source 묶음에는 포함됨. source inventory의 2026-07-14와 provenance의 기존 2026-07-28은 역사적 capture 기준이며 새 생성일로 위장하지 않음.
- 실제 archive LinkFileList/clang link command에서 Mach-O arm64 앱 객체 **76개**를 수집하고 내부 checksum을 검증함. relink **4,096,716 bytes**, SHA-256 **`c75745ca0e94b1ee269b67fc81d2a03988aa151fdb8a2192c87e0a16241b2164`**. 정규화 명령을 원래 release의 **수정하지 않은** libVLC/FFmpeg/Google SDK 입력으로 실행해 exit 0, unsigned arm64 executable을 생성함. 변경 라이브러리 재빌드·서명·설치·runtime 또는 Apple 플랫폼에서의 실용적인 modified-library 배포를 입증한 결과는 아님.
- 크기 보고서 **12,312 bytes**, SHA-256 **`5cc8914ed66be3cd7452bf32c4ed030d889865bc446aea1e40958ea774f5abd1`**. exact version/build 및 위 source/relink/size-report/IPA 4 digest를 `legal-approval.pending-1.1.8-39.json`에 채웠지만 status와 네 판단은 **pending**, reviewer/approvalID/approvedAt은 빈 값으로 유지함. 저장소 원래 pending template도 비승인 상태 그대로임.
- `verify_public_distribution_gate.sh` 실행은 **exit 1 / PUBLIC_DISTRIBUTION_GATE=BLOCKED / Legal status is not approved.**. archive·IPA 서명/dSYM/로컬 경로 노출·compiler artifact/필수 고지/size, source/relink metadata·내부 checksum·Mach-O object 검사를 모두 지나 외부 status 확인까지 도달함. 이후 승인 ID·날짜·승인 판단 검사까지 실행된 것으로 주장하지 않음. pending record의 4 digest는 별도 프로그램으로 실제 파일/manifest와 일치함을 검증함. 이 차단은 프로젝트 외부 승인 요건이며 Apple rejection이나 법적 위반 확정이 아님.

### ASC 정정 문구·외부 검토 안내

- 올바른 app `6780777838`, 1.1.8 version `0649aa64-cc2d-4e5c-b95c-129053c487ad`의 ko/en-US **첫 whatsNew 항목만** 정정함. 현재 한국어 첫 줄은 **`일부 영상이 재생되지 않는 문제를 개선했습니다.`**, 영어는 **`Fixed an issue that prevented some videos from playing.`**. 자막/미리보기 표현을 해당 항목에서 제거하고 나머지 두 줄은 그대로 보존함.
- 최종 공식 GET 재조회 **2026-10-06 20:06:32 KST**: 두 locale 정정 값 일치, description/keywords/marketingUrl/promotionalText/supportUrl 불변, draft **PREPARE_FOR_SUBMISSION / AFTER_APPROVAL / selectedBuild=null**. 이전 PUB의 30 screenshot 보존 검증을 재사용하며 이번에 screenshot API write/업로드/삭제하지 않음. 공개 1.1.5와 내부 TF 38은 변경하지 않음.
- ASC custom EULA resource는 **data=null**. Apple 안내와 함께 Standard EULA 적용 구성으로 추론하되, 포함된 오픈소스 예외의 충분성은 외부 검토 질문으로 남김. [Apple Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/), [FFmpeg 공식 legal/compliance](https://ffmpeg.org/legal.html), [VideoLAN 공지](https://images.videolan.org/press/lgpl-libvlc.html)를 확인해 라이선스 출처와 법적 승인·특허·서명/설치 가능성을 분리함. GNU 웹 접속 오류는 기록하고, 실제 앱에 포함된 전체 LGPL-2.1 text를 검토 자료로 제공함.
- 작성 스타일 지침을 읽고 요청·확인 결과·외부 판단을 구분한 중립적 한국어 검토 안내를 작성함. 허용 범위의 관련 sent-email reference 검색 결과는 0건이었으므로 글쓰기 샘플을 임의 생성하거나 검색 범위를 넓히지 않음. **No suitable writing references found in the returned results.** 이메일 draft/send나 외부 자료 전송은 하지 않음.
- `REVIEW_REQUEST-ko.pdf` **3쪽 전부 렌더·육안 확인**, 필수 상태/버전/4 digest/정정 문구 text 검사 통과. DOCX ZIP 비손상·필수 문구/해시 확인(Word layout 육안 검증은 별도 미수행). TXT 편집본, 버전 결속 pending 승인 양식, 제공된 영문 검토 template, 고정 manifest/Package.resolved, 실제 앱 notices, compact/raw 기술 로그와 ASC readback을 함께 보관함. source-offer의 help@taption.com 수신/장기 운영, 사업자·배포 국가·수익 모델 등은 미확인 외부 입력으로 명시함.

### 전달 파일·보존

- 보관 폴더: `/Users/u_mo_c/Documents/TaptionEncoderReleases/1.1.8-39-LAW06N5K8T` (약 466 MiB). 문서·exact archive/IPA/dSYM/source/relink를 보존하며 일반 캐시로 삭제하지 않음. 검토용 proprietary source/객체도 포함되어 있으므로 공개 게시와 source-offer delivery 범위는 별도 판단 대상임.
- 전달용 ZIP: `/Users/u_mo_c/Documents/TaptionEncoderReleases/TaptionEncoder-1.1.8-39-ReviewPacket.zip`, **445,508,827 bytes**, SHA-256 **`2977fe8c3f2bbba1cc22358bf1de628373f067351f8e1079431b423886a654a8`**. ZIP CRC 비손상 및 내부 `SHA256SUMS`의 **104개 파일 전부**를 ZIP stream에서 재검증함. SHA256SUMS 자체 SHA-256은 **`85d1746f8ea397cac24db850d7546b64bdc094c934638215d2178088c8fda6b4`**. API helper/private P8/PEM/KEY/JWT는 전달 자료에 포함하지 않음. sibling verification JSON도 보관함.
- 소스 snapshot SHA-256 **`97ce839a687a0c304cfcfc598de143f51ef138559d6e0c4066011925c82f37eb`**, version patch **`747e0acfa23540ebb4dd88a9bd620ea82dfcd8e77ec76a08f8399b919e99bada`**, provenance-only patch **`201ec5a858d55ff4d6bfe28952a4f8622e33ff2972a09e7bf6541627f897590e`**. 검토 대상은 base+두 patch이며 새 source commit 또는 새 TestFlight 업로드 완료로 표현하지 않음.
- PDF 패널 open 요청은 queued로 반환됨. 실제 앱 내 표시 완료를 주장하지 않고 영구 local file link로 제공한다. 이 자료 준비 LAW06N5K8T는 검증·정리 완료 후 temp.md에서 제거하되, 외부 승인·공개 출시 PUB06V8N2R 및 기기 기본 연결 UI FIX06P3M7Q는 계속 남긴다.
- 완성 ZIP의 CRC/104-file checksum 검증 후 이번 owned scratch **약 2.4 GiB**(DerivedData, package checkout, 중복·이전 source bundle, source 복원/test relink 복사본, size-report variant IPAs, 문서 runtime/preview/API helper) 및 같은 39의 export에서 생성한 위 두 xcdistributionlogs **약 6.5 MiB**만 영구 삭제함(`rm -r`, exit 0). 정확한 세 경로는 최종 모두 ABSENT. 삭제한 임시 캐시는 휴지통 복구 대상이 아니며 재생성 가능함. 요청한 review record/ZIP/dSYM/객체/대응 소스, Git 원본·private key·서명 자료·원본 사용자 영상과 다른 프로젝트 데이터는 보존함.
- 새 simulator/device/runtime는 생성·설치·초기화·삭제하지 않음. 최종 ignored/untracked 목록은 빈 값, 여유 공간 **4.1 GiB**. HEAD/main/origin/main은 기존 ed17d66이며, 남은 변경은 AGENTS.md/project.pbxproj/provenance JSON/temp.md/test.md 다섯 파일임. 최종 `git diff --check` 통과. LAW06N5K8T 자료 준비는 완료, PUB06V8N2R 공개 출시는 실제 외부 승인 입력을 기다리는 미완료 상태로 유지함.

## PUB06V8N2R 재개 — 심사 제출 재요청·승인 기록 미충족 재확인 (2026-10-06)

- 검토 자료 준비 완료 후 사용자가 ‘제출해’라고 요청해 기존 공개 출시 작업을 재개함. 현재 사용자 AGENTS.md 및 파일을 다시 읽고 main/HEAD/origin/main이 모두 `ed17d666df085bfd08df1648a07ee907d0e0e53f`인 것을 확인함. 기존 다섯 dirty 파일과 exact-release 검토 자료를 보존함.
- **2026-10-06 21:18:42 KST**, 공식 ASC API **GET만** 실행함. bundleId 조회에서 app **6780777838 / com.taption.encoder**를 확인하고, 1.1.8 version **0649aa64-cc2d-4e5c-b95c-129053c487ad**를 재조회함. 상태 **PREPARE_FOR_SUBMISSION**, releaseType **AFTER_APPROVAL**, selected build **null**. 이 설정은 승인 후 자동 출시를 위한 초안 설정이지 실제 제출/승인이 아님.
- `GET /v1/builds?filter[app]=6780777838&filter[version]=39`의 결과 **0건**. 최신 build는 **1.1.7 (38) / VALID / INTERNAL_ONLY** / ID **30e114f0-e77e-48c4-b2e2-8d35c7255fdd**. 37/36의 APP_STORE_ELIGIBLE 상태를 최신 preview/audio 수정 포함 자료로 대체하거나 제출하지 않음. 현재 39의 Apple upload/processing 완료라고 주장하지 않음.
- ko/en-US whatsNew를 공식 GET으로 재조회해 LAW06N5K8T의 최종 등록 값과 전체 일치를 확인함. ‘일부 영상이 재생되지 않는 문제를 개선했습니다.’와 같은 의미의 영어 첫 줄 및 기존 두 안정화 항목을 보존하며 이번에 metadata를 PATCH하지 않음.
- 후보 source/relink/size-report/IPA의 SHA-256을 실제 파일에서 다시 계산해 RELEASE_MANIFEST.json 및 exact-release pending 양식의 4 digest와 모두 일치함을 확인함. archive/export의 기존 LAW06N5K8T 서명·dSYM·56 source·76 object 및 gate 증거를 재사용함. full build/test 또는 full gate를 새로 실행했다고 주장하지 않음.
- `legal-approval.pending-1.1.8-39.json`의 status, lgplStaticLinking, appStoreEULACarveout, libvlcContribMap, hevcDistribution은 여전히 **pending**이며 **approvalID/reviewer/approvedAt은 빈 값**. 저장소 원래 pending template도 비승인 상태임. ‘제출해’는 App Store 제출 권한 요청이지만 현재 프로젝트가 요구하는 실제 외부 법률 검토 기록으로 간주하거나 승인자를 대신 작성하지 않음.
- 차단 사유는 프로젝트의 공개 배포 승인 요건 미충족임. Apple의 새로운 rejection, 제출 불가능하다는 일반 법률 판단 또는 위법 확정으로 표현하지 않음. 버전/digest 결속 실제 외부 승인 기록의 파일 경로를 사용자에게 요청하며, 업로드·심사 제출·commit/push·외부 검토 자료 발송을 하지 않음. PUB06V8N2R는 temp.md에 미완료로 남김.
- API private key와 JWT는 인증 내부 메모리에만 사용했고 내용/token을 출력·파일 저장하지 않음. 임시 helper 파일 생성이 실패하여 파일 수정 없이 읽기 전용 in-memory CLI로 재조회함. 빈 owned 임시 디렉터리 외 빌드·시뮬레이터·새 배포 산출물을 생성하지 않고 기존 검토 폴더/ZIP을 수정·삭제하지 않음. 필요한 compact 근거는 이 항목에 남김.

## HIS06G2N8P — 내부 외부승인 조건 도입·이전 배포 적용 이력 확인 (2026-10-06)

- 사용자 질문 ‘이전에는 그런거 없었는데?’에 대해 이력 확인과 설명만 진행함. `git status --short --branch`에서 main...origin/main 및 기존 다섯 dirty 파일을 확인하고 보존함. 신규 제출·규칙 변경 권한으로 해석하지 않음.
- `git log --diff-filter=A` 결과 공개 배포 gate, pending 승인 양식, LEGAL_REVIEW_PACKET은 **2026-07-14 13:14:24 KST / 76769a9c162378290de7aaa7ea47b4c460601133 / Prepare 1.1.2 build 33 compliance release candidate**에서 최초 추가됨. gate의 `status == approved` 조건은 현재와 도입 당시 모두 존재하며 현재 파일 322행에서 `Legal status is not approved.`를 발생시킴. 이번 자료 준비에서 새로 만든 Apple 제출 요건이 아님.
- AGENTS의 `external legal` 및 `public-distribution` 문구 도입은 **2026-07-17 01:39:14 KST / 1fab2e446ce2d0f6a19774bc8c4568fe9226925a / Document maintenance handoff for 1.1.3**임. 동일 commit은 1.1.3 (34)의 owner-reported App Review 제출, Apple VALID / APP_STORE_ELIGIBLE 및 delivery UUID 0c043b6a-f0f6-4014-9d2d-07c3c7911c3f를 기록하면서도 대응소스/외부 법률승인 미비로 내부 gate가 blocked라고 기록함. 과거 제출과 내부 규칙 적용·기록이 일관되지 않았다는 근거이며, 과거 법적 승인 존재/부재나 법적 적합성을 확정하는 증거로 사용하지 않음.
- project.pbxproj에 gate/승인 JSON/external counsel 참조가 없음을 scoped rg로 확인함. 이 저장소의 자체 배포 절차 조건이며 Xcode의 자동 빌드 단계나 Apple 검증 서버의 필수 승인 JSON으로 표현하지 않음. commit Author/Committer 이름만으로 사람과 agent 중 도입 주체를 구분할 수 없으므로 사용자 또는 이번 작업자가 새로 만들었다고 단정하지 않음.
- Apple 공식 일반 제출 안내 https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/ 에서 필수 metadata/build 선택 및 Add for Review/Submit for Review 절차를 확인함. 확인한 안내에는 이 프로젝트의 외부 법률승인 JSON 단계가 없음. Apple App Review Guidelines 5.2/5.2.1 https://developer.apple.com/app-store/review/guidelines/#intellectual-property 의 권리·라이선스 준수 책임과, FFmpeg 공식 https://ffmpeg.org/legal.html 의 라이선스/대응소스/고지 요건은 별도로 유지되는 사항임. 외부 승인서가 Apple 일반 필수 제출 서류가 아니라는 사실을 법적 위험 없음이나 라이선스 의무 면제로 확대하지 않음.
- 현재 질문에 대한 설명만 완료함. 내부 필수 외부승인 규칙을 변경하려면 사용자 지시를 확인해야 하며, pending을 approved로 조작하거나 gate를 우회하지 않음. gate 재실행, build/test, 업로드, App Review 제출, metadata 수정, commit/push 또는 외부 packet 전송을 수행하지 않음. 기존 PUB06V8N2R 및 FIX06P3M7Q는 미완료로 보존함.

## RULE06V2Q8 — 외부 승인서 의무 규칙 변경·공개 제출 재개 (2026-10-06)

- 사용자는 HIS06G2N8P 설명 뒤 내부 외부승인서 필수 규칙 변경에 ‘ㅇㅇ’로 동의하고 별도 승인서 제출이 이전에도 필요하지 않았다고 설명함. 별도 외부승인서는 제출하지 않는다는 뜻으로 사용자에게 명시하고, 기존 앱 심사 제출 요청은 계속 진행함. Apple 일반 필수 제출 자료와 프로젝트 자체 요구를 구분함.
- main/HEAD/origin/main은 기존 ed17d666df085bfd08df1648a07ee907d0e0e53f이며 기존 dirty 다섯 파일을 보존함. 사용자 지시에 따라 AGENTS/README/LEGAL_REVIEW_PACKET과 gate/향후 relink metadata 문구를 변경함. mandatory external approval만 opt-in으로 바꾸며 pending 승인 양식·과거 exact-release 자료/ZIP·app runtime code·library binaries·공지/EULA·private credentials는 변경하지 않음.
- 기본 gate는 승인 JSON 없이 서명/dSYM/version/IPA entitlements/크기/notice/내부 source·relink checksum/76개 Mach-O object 검사와 4 digest 계산을 모두 실행함. 기존 historical relink status를 보존해서 받을 수 있으며 새 packet은 technical-relink-materials로 표시함. PASS는 기술 검사 통과이며 법적 검토가 이루어진 것으로 표현하지 않도록 LEGAL_REVIEW_STATUS=NOT_VERIFIED를 출력함. --legal-approval 또는 --require-legal-approval은 원래 strict version/digest-bound 검사를 켬.
- 실제 보관 1.1.8 (39) 자료로 기본 gate **exit 0 / PUBLIC_DISTRIBUTION_GATE=PASS / TECHNICAL_RELEASE_CHECKS=PASS / EXTERNAL_LEGAL_APPROVAL=NOT_REQUIRED_BY_PROJECT_POLICY / LEGAL_REVIEW_STATUS=NOT_VERIFIED**. archive app 45,986,620 bytes, IPA 23,347,059 bytes, 앱/두 extension의 __TEXT 36,913,152/98,304/49,152 bytes. source/relink/size/IPA SHA-256은 LAW06N5K8T의 0ba94db56f6c237f1eef0a56e4c946eeabfa860b59cd303ed13714d3cddc8ab6 / c75745ca0e94b1ee269b67fc81d2a03988aa151fdb8a2192c87e0a16241b2164 / 5cc8914ed66be3cd7452bf32c4ed030d889865bc446aea1e40958ea774f5abd1 / 302a267ebbc28c21546da17a7713b1ec39a5043b896113d977811e5c2ac32b2b와 모두 일치함.
- scoped 검증: bash -n(두 script), --help exit 0, require-without-record exit 1, missing archive exit 1, missing option value/unknown option 각각 exit 64, 실제 preserved pending 양식을 명시한 strict 실행 exit 1 / Legal status is not approved. 모두 예상대로임. 실제 외부 승인 record를 만들어 통과시킨 테스트는 수행하지 않음. 기존 기술 fail-closed 조건을 삭제하지 않음.
- 기존 browser의 다른 앱 TestFlight 탭을 변경하지 않고, 신규 read-only API key 설정 탭에서 기존 issuer/key ID만 확인함. private p8/JWT는 인증 내부에서만 사용하고 출력/저장하지 않음. browser 키 생성/다운로드/권한 변경 없음. official App Store Connect API로 bundleId=com.taption.encoder → app 6780777838 확인.
- **21:44:06 KST** 제출 전 GET: 1.1.8 / PREPARE_FOR_SUBMISSION / AFTER_APPROVAL / selectedBuild=null, uploaded build 39 0건. 기존 iOS review submission 다섯 건은 모두 COMPLETE이며 새 submission 없음. ko/en-US first line과 기존 두 안정화 문구 전체 일치. App Review 연락처 필드는 존재, demoAccountRequired=false. metadata/contact/release notes를 새로 변경하지 않음. 새로운 Apple 검증/업로드/심사 결과는 후속 항목으로 분리하여 기록함.
- 추가 negative 검증: 승인 기록을 생략한 모드에서 잘못된 size-report 입력은 exit 1 / The supplied file is not an App Thinning Size Report., 일반 Markdown을 source archive로 지정하면 exit 1 / Could not extract source bundle. 기존 기술 검사 차단 유지. 최초 size negative fixture인 README에는 검사 marker 자체가 포함되어 예상 실패가 발생하지 않았으므로, 해당 fixture는 invalid-report 증거로 사용하지 않고 marker가 없는 기존 pending JSON으로 바꿔 검증함. report validator는 기존 marker/크기 경고 검사이며 새 정밀 report-format parser를 구현했다고 주장하지 않음. 실제 배포 report는 보관된 exact digest와 일치함.
- **21:47:49 KST** ASC screenshot readback: ko/en-US 각각 iPhone 5개 + iPad 10개, 총 **30개**, 네 screenshot set과 모든 assetDeliveryState=COMPLETE. 기존 screenshot/localization IDs를 보존하며 재업로드/수정하지 않음.
- Apple altool 27.0.5의 실제 후보 IPA validation **2026-10-06 21:46:45 KST / exit 0 / VERIFY SUCCEEDED with no errors**. 이어 upload **21:50:12 KST / exit 0 / UPLOAD SUCCEEDED with no errors**, delivery UUID **141b3cb7-e2ca-4584-a8f4-4c8fb875cbcb**, 전송 23,347,059 bytes. 동일 source/relink/IPA candidate를 사용하며 내부-only build 38이나 옛 build 37로 대체하지 않음. 업로드 receipt는 서버 processing 완료나 App Review 제출로 확대하지 않음. 21:50:33 GET의 build39 결과는 아직 0건이며 --build-status --delivery-id … --wait로 Apple 처리 완료를 별도 대기함.
- Apple `--build-status --delivery-id … --wait` **exit 0**: build 39의 **processingState=VALID / import-status=VALID / APP_STORE_ELIGIBLE / is-on-app-store-connect=true / usesNonExemptEncryption=false**. 공식 GET **21:53:32 KST**에서도 같은 build ID 141b3cb7-e2ca-4584-a8f4-4c8fb875cbcb / version 39 / expired=false 및 preReleaseVersion **411b2700-6f3f-4879-a11a-3c3dd8773148 / 1.1.8 / IOS**를 확인함.
- 올바른 App Store version 0649aa64-cc2d-4e5c-b95c-129053c487ad에 build39를 PATCH 연결(HTTP 204)하고 GET selectedBuild의 동일 ID/version/state/audience를 확인함. 기존 다른 build 선택이 없는 것을 먼저 검사했으며 기존 사용자 변경을 덮어쓰지 않음. 새 review 생성 직전 active iOS review 없음, 전체 ko/en-US whatsNew 일치 및 AFTER_APPROVAL 설정을 다시 검사함.
- 공개 App Review submission **f0a2e763-efe5-4396-bb34-429a8d90ba0b** 생성, 정확한 1.1.8 version을 review item **ZjBhMmU3NjMtZWZlNS00Mzk2LWJiMzQtNDI5YThkOTBiYTBifDZ8ODkyNjE5NDU5**으로 추가한 뒤 `submitted=true` PATCH 성공. Apple 응답 submittedDate **2026-10-06T12:54:54.382Z (21:54:54 KST)**, platform IOS, **WAITING_FOR_REVIEW**. 외부 법률승인서나 검토 ZIP을 제출한 것이 아니라 사용자가 요청한 앱 심사 제출임.
- **21:54:57 KST final 공식 readback**: submission WAITING_FOR_REVIEW, appStoreVersionForReview=정확한 1.1.8 version ID, item total=1, version **1.1.8 / WAITING_FOR_REVIEW / AFTER_APPROVAL / earliestReleaseDate=null**, selectedBuild=정확한 39/VALID/APP_STORE_ELIGIBLE. 심사 승인/READY_FOR_SALE/새 public release 완료로 표현하지 않음. Apple 심사를 법적 검토 승인으로 사용하지 않음. 현재 공개 1.1.5는 새 승인 후 자동 전환 예정이며 별도 승인서 필수 입력은 없음.
- 새 runtime/library binary 변경·새 simulator/device 실행·commit/push·평점 초기화·스크린샷 교체·source/객체의 공개 게시·외부 법률 packet 전송·private credentials 출력/저장은 없음. 준비된 immutable 1.1.8-39-LAW06N5K8T/ZIP/pending 기록과 원래 source/proof를 보존함. RULE06V2Q8 구현·검증 및 앱 심사 제출은 완료; PUB06V8N2R는 Apple 심사/실제 공개 출시 후속 확인만 남김.
- App Store Connect 해당 앱 배포 페이지를 새로 읽어 UI에서도 **1.1.8 심사 대기 중 / 선택 build 39, version 1.1.8 / 자동으로 버전 출시 checked / 기존 평가 유지 checked**를 확인함. 사용자의 다른 앱 탭은 그대로 두고 이 앱 결과 탭만 deliverable로 남김. UI를 통한 제출/승인서 첨부/계약 수락은 없음. 최종 bash syntax 및 git diff --check 통과, 기존 다섯 dirty 파일에 추가된 네 개 compliance 문서/스크립트 변경만 포함하는 총 아홉 변경 파일이며 untracked 생성 파일 없이 로컬 미커밋 상태를 보존함.

## LIC06P2K8T — 현재 구성의 라이선스 의무·미확인 위험 설명 (2026-10-06)

- 사용자 요청은 라이선스 문제 설명임. AGENTS를 읽고 main/HEAD/origin/main=ed17d666df085bfd08df1648a07ee907d0e0e53f 및 기존 아홉 dirty 파일을 확인함. 답변 근거 기록용 temp/test만 수정하고 runtime code·gate 정책·공지·EULA·심사/출시 설정·기존 artifact를 변경하지 않음. 외부 법률승인서 필수 입력을 다시 요구하지 않음.
- 제출된 정확한 1.1.8 (39) IPA에서 libVLC-LGPL-Notice.txt와 FFmpeg-LGPL-Decode-Bridge.txt를 unzip -p로 직접 읽음(추출 파일 생성 없음). libVLC는 LGPL 2.1-or-later / Static, FFmpeg decode bridge는 LGPL 2.1-or-later / GPL 및 nonfree 비활성 / H.265 출력은 AVAssetWriter. 둘 모두 help@taption.com으로 library source/수정사항/build script/재링크 자료를 요청하는 최소 3년 written offer와 LGPL 역공학 권리 보존 문구가 실제 포함돼 있음.
- LGPL-2.1.txt 6항(271행 이후)을 직접 읽어 고지·license text, 고객의 개인용 수정/수정 디버깅 역공학 허용, 6a의 library corresponding source와 앱 object/source 형태 재링크 자료, 6c의 최소 3년 written offer 대안을 확인함. 이는 LGPL 사용 자체가 앱 전체 독점 source 공개를 자동 요구한다는 뜻이 아님. 정적 연결도 조건을 갖추면 가능한 대안이며 정적 연결 자체를 위법으로 표현하지 않음. GNU 공식 html 조회는 timeout, 공식 GNU search의 동일 2.1 license 본문과 실제 번들 전문으로 보완함. GPLv3의 Installation Information 조건을 LGPL2.1에 그대로 적용하지 않음.
- 현재 bridge BUILD/config/provenance 기록을 필요한 구간만 확인함: --disable-shared/--enable-static, --enable-gpl 및 --enable-nonfree 없음. libVLC embedded FFmpeg에서도 두 enable flag 부재가 기존 provenance에 기록됨. FFmpeg 공식 https://ffmpeg.org/legal.html 의 LGPL 기본/optional GPL parts/별도 patent 문제를 읽음. FFmpeg checklist는 유일한 준수 경로가 아니라 upstream이 제안하는 쉬운 경로라고 명시하므로, dynamic linking·공개 웹 다운로드가 없다는 이유만으로 이번 written-offer/static-link 방식을 위반으로 확정하지 않음. 설정 검사는 전체 제삼자 라이선스 법률검토 완료를 뜻하지 않음.
- 기존 LAW06N5K8T의 candidate/source verification JSON과 version-bound test 근거를 재사용함. **56 contrib source archives**, **54 in-app contrib notice entries**, **76 app objects**, 생성 upstream notice=shipped exact match. unmodified pinned library technical relink는 성공했지만 signed=false/installed=false/userModifiedLibraryTested=false임. 이것은 자료 구성/재링크 기술 검사 증거이며 실제 수정 라이브러리의 최종 signing/installation 가능성을 입증한 것이 아님. 새 library 교체·install test를 실행하지 않았으며 이를 확정된 LGPL 위반으로 표현하지 않음.
- 실제 source request 수신 주소의 소유/운영, mailbox 수신, 이용자 요청 응답/전달 및 최소 3년 운영 가능 여부는 미검증. 이번 작업은 이메일·외부 요청을 보내지 않음. local source/relink archive 보관과 이용자에게 실질적으로 제공 가능한 운영은 구분해야 하며, 현재 가장 구체적인 후속 확인 항목은 source offer 이행 가능성임. 공개 다운로드 URL 부재만으로 written offer가 부적법하다고 판단하지 않음.
- Apple Standard EULA https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ 33행에는 open-source terms/law가 허용하는 modification/reverse engineering에 대한 예외가 존재함. 따라서 Apple 표준 EULA가 무조건 LGPL과 충돌한다거나 custom EULA가 반드시 필요하다고 주장하지 않음. LAW 준비 시 ASC custom EULA data=null 기록과 당시 검토 질문을 재사용하되 이번에 새 ASC 조회/설정 변경 또는 법적 sufficiency 결론을 내리지 않음.
- HEVC/H.264 등의 codec patent license는 library copyright license와 별도임. FFmpeg patent mini-FAQ 및 HEVC patent pool의 https://accessadvance.com/topic-what-do-we-license/ 를 확인함. 후자는 pool 운영자의 encoder/decoder/device/software/cloud 범위 설명이지 Taption의 침해·별도 license료를 확정하는 판결/계약 증거가 아님. Apple-native encoder 사용만으로 모든 별도 배포 국가/사업모델 patent 문제의 면제를 확정하지 않으며, 이번 확인으로 Taption의 fee/license 필요 또는 불필요를 단정하지 않음.
- 제한: 이번 bounded 기술·문서 대조에서 확정된 위반이라고 단정할 증거는 확인하지 못했으며, 포괄적 법률 승인/모든 권리 clearance 또는 모든 위험 부재로 확대하지 않음. 내부 외부승인서 의무 규칙 변경과 실제 LGPL/third-party/patent 의무는 별개임. runtime/release 변경·새 simulator/build/test·업로드/심사 취소/외부 packet 전송·commit/push 없음. 기존 공개 출시 및 실제 기기 Files UI 후속 항목은 보존함.

## AUT0908A36 — Taption Down Shorts 활용 코덱·실행 경계 감사 (2026-10-06)

### 결론

- 이 저장소에는 Shorts 생성·업로드용 CLI나 서버 export target이 없다. Xcode app target의 iOS `TaptionVideoCore`/`AVFoundationHEVCEncoderService`가 실제 실행 경계이며, 출력 계약은 H.265/HEVC와 MP4/MOV로 고정되어 있다. `Shorts`, YouTube, 자막 burn-in, 9:16 crop/pad, Shorts duration 정책은 scoped source에서 확인되지 않았다.
- Down이 직접 재사용할 수 있는 완성 알고리즘은 확인되지 않았다. 아래 3개는 iOS 앱 내부에서 실제 연결된 코덱 경로 또는 좁은 통합 후보이며, 소스 존재를 Down 연동 완료로 해석하지 않는다.

### 후보 1 — Apple native HEVC writer (가장 낮은 배포 위험)

- 근거: `TaptionEncoder/Core/Codecs/HW_AppleHEVCCodecAlgorithm.swift:93-170,232-269`가 AVAssetExportSession의 HEVC preset을 고르고 MP4/MOV writer를 구성한다. performance 조건에서는 H.264/HEVC/ProRes의 AVAssetReader/AVAssetWriter fast path를 먼저 시도하며 실패 시 native export로 돌아간다.
- 입력/출력: Apple이 읽을 수 있는 소스 → H.265/HEVC MP4 또는 MOV; resize, frame rate, rotation, 색상, 오디오 보존 옵션은 `TaptionCodecTranscodeRequest`를 통해 전달된다.
- Down 통합 계획: Down이 iOS 기기에서 최종 파일을 만들 때만 `TaptionVideoCore.prepareSingleAssetHEVCJob(sourceURL:temporaryOutputURL:)` 후 `encodePreparedJob(_:progress:)`를 호출한다(`TaptionEncoder/Core/VideoCore/TaptionVideoCore.swift:45-125,128-210`). 서버/컨테이너에서 Swift/AVFoundation을 실행하는 경로는 존재하지 않으므로 Down 서버로의 직접 이식이 아니다.

### 후보 2 — SwiftVLC decode → AVAssetWriter HEVC (현재 broad iOS software path)

- 근거: `TaptionEncoder/Core/Codecs/AV1/SW_AV1HEVCCodecAlgorithm.swift:307-325,1625-1785`가 AV1/H.264/HEVC/VP 계열과 다수 legacy route를 software descriptor로 등록하고, `TaptionEncoder/Core/Codecs/AV1/SW_AV1HEVCTranscodePipeline.swift:1-8`에서 `CLibVLC`와 AVFoundation writer를 결합한다. 영상은 decoded pixel buffer, 오디오는 packed S16 PCM을 AAC/Apple-native output으로 writer에 넣는다.
- 실행 경계: `TaptionEncoder/App/AppEnvironment.swift:77`의 `AVFoundationHEVCEncoderService`가 production service로 등록되고, `EncoderService.swift:345-397`가 registry 또는 software command path를 선택한 뒤 output verifier를 실행한다.
- Down 통합 계획: 이 경로의 정책만 Down의 별도 worker로 포팅하려면 `source probe → decode frames/audio → Shorts용 9:16 framing/scene/subtitle 단계 → HEVC MP4/MOV writer → output verification`을 새 서비스로 구현해야 한다. 현재 저장소에는 framing/subtitle/upload 계약이 없으므로 후보 2만으로 Shorts 생성 완료를 주장할 수 없다.

### 후보 3 — source-built FFmpeg decode bridge → Apple HEVC writer (VC-1/Y41P/ProRes RAW 한정)

- 근거: `TaptionEncoder/Core/Codecs/CodecAlgorithm.swift:359-399`와 `CodecTranscodingRegistry.swift:34-128`은 VC-1, Y41P, ProRes RAW route를 bundled bridge descriptor로 연결한다. `SW_FFmpegDecodeBridgeFallbackTranscoder`는 `SW_FFmpegCommandExecutor.swift:830-875`에서 입력을 probe하고 bridge runner로 decoded video/audio를 받아 HEVC output을 확인한다. bridge C API는 `Vendor/FFmpegLGPLDecodeBridge/Sources/TaptionFFmpegDecodeBridge.h:96-138`의 video/audio probe·decode 함수와 `SW_FFmpegCommandExecutor.swift:1075-1147,1329-1447`의 NV12/BGRA/PCM writer 연결로 구성된다.
- 범위: 일반 Shorts용 범용 encoder가 아니라 선택된 legacy/RAW decode 보완책이다. notice는 FFmpeg 8.1.1, GPL/nonfree 비활성, CLI executable 미번들, HEVC MP4/MOV 출력은 AVAssetWriter라고 명시한다(`TaptionEncoder/OpenSourceNotices/FFmpeg-LGPL-Decode-Bridge.txt:3-31`).
- 재현 명령(이번 감사에서는 실행하지 않음):

```sh
OUTPUT_XCFRAMEWORK=/tmp/TaptionFFmpegDecodeBridge.xcframework \
WORK_DIR=/tmp/taption-ffmpeg-decode-bridge \
MIN_IOS_VERSION=18.0 \
bash Vendor/FFmpegLGPLDecodeBridge/build_ffmpeg_lgpl_decode_bridge.sh
```

  이 명령은 고정 FFmpeg 8.1.1 archive를 다운로드·SHA-256 검증하고 iPhoneOS/arm64 및 arm64 simulator XCFramework를 만드는 무거운 재빌드 경로다(`Vendor/FFmpegLGPLDecodeBridge/build_ffmpeg_lgpl_decode_bridge.sh:9-13,50-63,87-137`). 실제 앱 프로젝트에는 `TaptionFFmpegDecodeBridge.xcframework`가 Frameworks phase에 연결되어 있다(`TaptionEncoder.xcodeproj/project.pbxproj:58-63,195,234-244`).

### FFmpeg-family command/export 경계와 제약

- `SW_FFmpegCodecCommandPlanner`는 `ffmpeg` 실행 파일명과 `-i`, `-map`, `-c:v libx265`, `-movflags +faststart` 등의 argument 배열을 만들 뿐이다(`TaptionEncoder/Core/Codecs/SW_FFmpegCodecCommandPlanner.swift:95-205,550-634`). `SW_FFmpegCommandExecutor.execute`는 readiness gate가 모두 닫히지 않으면 실패하고 runner가 없으면 `runnerUnavailable`을 반환한다(`TaptionEncoder/Core/Codecs/SW_FFmpegCommandExecutor.swift:75-117`). 현재 `SW_UniversalCodecTranscodeAlgorithm.transcode`도 backend가 번들되지 않으면 `backendNotBundled`를 던진다(`TaptionEncoder/Core/Codecs/SW_UniversalCodecTranscodeAlgorithm.swift:79-90`). 따라서 command plan은 runnable CLI나 Down worker가 아니다.
- broad FFmpeg 후보의 기본 readiness는 `isBundledInCurrentBuild=false`, gate 미충족으로 생성된다(`TaptionEncoder/Core/Codecs/SW_SoftwareCodecBackendRegistry.swift:729-750`). 특히 command plan의 `libx265`/`libx264` 계열은 LGPL decode bridge와 별도의 license/patent 검토 대상이며, `Vendor/OpenSourceCompliance/README.md:7-11,28-41` 및 `legal-approval.pending.json:1-16`은 기술 검사와 법적 승인·특허 검토를 분리한다.
- SwiftVLC는 `Package.resolved`에서 0.10.1 revision `58d1f3a8...`로 고정되어 있고, bundled notice는 LGPL-2.1-or-later/static 및 54 runtime/header input의 technical inventory만 보장한다(`TaptionEncoder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:15-25`, `TaptionEncoder/OpenSourceNotices/libVLC-LGPL-Notice.txt:3-24`). 이는 Down 배포에 대한 법률 승인이나 특허 clearance가 아니다.

### 검증 경계

- 이번 항목은 read-only 소스·프로젝트·notice·manifest 대조만 수행했다. 새 build, test, simulator/device 실행, FFmpeg archive 다운로드, bridge 재빌드, 외부 API/브라우저/credentials 사용은 하지 않았다.
- 실제 runnable app path는 후보 1·2와 후보 3의 bundled bridge에 한정해 정리했으며, broad FFmpeg command path는 planning-only로 분리했다. Down 연동을 닫으려면 별도 worker/CLI target, Shorts framing·subtitle·duration 계약, output/upload proof, 그리고 각 bundled dependency의 release·license·performance 검증이 추가로 필요하다.

## COPY06M2Q8 — 지원 메일 정정 및 간결한 동영상 변환 설명 (2026-10-06)

- 사용자 지정 메일은 builday365@gmail.com이며 help@taption.com이 아님. 코덱·포맷 목록과 encoder 용어를 마케팅 설명에서 빼고 ‘쉽고 빠른 동영상 변환’ 중심으로 정리하라는 요청을 반영함. 앱 이름 taption encoder, bundle com.taption.encoder 및 실제 출력 정책은 바꾸지 않음. 요청한 짧고 직접적인 문체에 맞춰 설명을 작성하고 한국어·영어 모두 반영함.
- 시작 시 AGENTS 전체, git 상태 및 main/HEAD/origin/main=ed17d666df085bfd08df1648a07ee907d0e0e53f를 확인하고 기존 아홉 dirty 파일을 보존함. 원본 영상/자료·기존 출시 packet·private signing credentials를 수정하거나 삭제하지 않음.
- ASC live GET(22:25:05/22:26 KST): app 6780777838/com.taption.encoder, version 0649aa64-cc2d-4e5c-b95c-129053c487ad=1.1.8, build 39/141b3cb7-e2ca-4584-a8f4-4c8fb875cbcb, WAITING_FOR_REVIEW / AFTER_APPROVAL. 기존 locale은 ko와 en-US 두 개. App Review 연락처 ee58c91e-41ab-4fb8-a2fc-abb8dfe64766의 contactEmail은 이미 builday365@gmail.com이어서 불필요한 PATCH를 하지 않음.
- App Store version localization en-US 27c823c2-eec6-4613-9352-e7bc8c96618c 및 ko 808c7353-6b4b-4c62-b738-d9a55ac98ac0에 description·keywords를 PATCH하고 GET으로 정확히 일치함을 검증함. ko 키워드 52자, en-US 키워드 82자로 100자 제한 이내. 설명·부제·키워드에 encoder/encoding/codec/format, 인코더/인코딩/코덱/포맷, HEVC/H.264/H.265/MP4/MOV 등의 기술 목록이 없는지 확인함. supportUrl·marketingUrl·promotionalText·whatsNew·locale 등 다른 attributes는 모두 불변.
- 심사 중 candidate appInfo 0864a04b-3e26-45e8-85d7-56ad055fa2a2의 ko localization 94d726b8-4df2-4e54-9cef-cc3c5320c909 subtitle은 ‘쉽고 빠른 동영상 변환’(12자), en-US d704dfb4-2a6b-43d9-8fae-d11e84d3ec99는 ‘Easy, fast video conversion’(27자)으로 PATCH/GET 검증 통과. 두 부제 모두 30자 제한 이내. name·privacy URL 등 다른 attributes 불변. 기존 공개 AppInfo는 변경하지 않음.
- 저장된 한국어 description(133자):

```text
쉽고 빠른 동영상 변환

사진이나 파일에서 영상을 선택하고 간편하게 변환해 보세요.
여러 영상도 한 번에 변환하고, 원하는 위치에 저장할 수 있습니다.
아이폰과 아이패드에서 편하게 사용하세요.

문의: builday365@gmail.com
```

- 저장된 영어 description(244자):

```text
Easy, fast video conversion

Choose videos from Photos or Files and convert them in a few simple steps.
Convert multiple videos in one go and save them where you want.
Enjoy a simple experience on iPhone and iPad.

Support: builday365@gmail.com
```

- 저장된 ko keywords: 동영상,영상,변환,동영상변환,영상변환,압축,용량줄이기,일괄변환,사진,파일,재생,아이폰,아이패드. en-US keywords: video,converter,conversion,compress,batch,photos,files,player,playback,iphone,ipad.
- 로컬 TaptionEncoder/OpenSourceNotices/libVLC-LGPL-Notice.txt:30 및 FFmpeg-LGPL-Decode-Bridge.txt:39에서 메일 한 곳씩만 builday365@gmail.com으로 교체함. 각 HEAD 원본에 단 한 번의 email byte replacement를 적용한 결과가 현재 파일과 완전히 동일함을 검사함. libVLC 현재 SHA256=b58ab9816222c854d2ad02deea791bbbaa81c94834657e1b4245c6431f81501f, FFmpeg 현재 SHA256=af0dc5a8f85e11b82a913a5cb4ba15206b6b032200c957864adffd4ecc5181e2. LGPL 전문, third-party notices, 재링크/최소 3년 source offer 및 역공학 권리 문구는 보존함. git diff --check 통과.
- 최종 독립 GET(22:28:30 KST): 설명·키워드·candidate 부제 일치 PASS, 동일 version 1.1.8/build 39, submission f0a2e763-efe5-4396-bb34-429a8d90ba0b WAITING_FOR_REVIEW, submittedDate=2026-10-06T12:54:54.382Z(21:54:54 KST), AFTER_APPROVAL 유지. ko/en-US 수정사항 문구는 이전과 정확히 동일함. 심사 취소, 재제출, build 선택 변경 및 자동 출시 설정 변경 없음.
- 제한/남은 결정: 이전 LIC06P2K8T에서 직접 확인한 제출 IPA와 LAW06N5K8T의 정확한 version/digest-bound record에는 여전히 help@taption.com이 포함됨. 설명·로컬 소스 편집은 그 바이너리를 변경하지 않음. 이번 제출의 앱 내부 메일까지 반영하려면 사용자가 심사 취소 및 새 빌드 제출을 승인해야 하며, 기존 정확한 자료를 덮어쓰지 않고 별도 새 출시 자료를 만들어야 함. 새 clean build/archive/runtime regression·업로드/commit/push·외부 이메일/packet 전송은 수행하지 않음. mailbox 소유·수신·장기 운영 가능성을 실제 메일 송신으로 검증한 것은 아님. 관련 의무 고지를 삭제하거나 법률 승인을 주장하지 않음.

## NAME06Y2K8 — YYY Encoder 변경·홈 제목 제거·새 제출 준비 (2026-10-06)

- 사용자는 앱 이름을 정확히 `YYY Encoder`로 변경하고 사진에도 반영하도록 요청했다. 이후 구조화 질문에서 **심사 취소 후 새 빌드·이미지로 재제출**을 승인했고, 홈 화면의 앱 이름 텍스트는 삭제하도록 추가 지시했다. source/main/origin/main은 ed17d66이며 기존 사용자 변경을 보존했다. commit/push는 요청되지 않아 실행하지 않는다.
- 같은 앱 6780777838/com.taption.encoder의 candidate appInfo 0864a04b-3e26-45e8-85d7-56ad055fa2a2 ko/en-US 이름을 PATCH→YYY Encoder 후 22:35:40 KST GET 검증했다. 간결한 동영상 변환 설명·부제·지원 메일을 유지했다. 공개 1.1.5의 이름 변경/새 공개 출시 완료를 주장하지 않는다.
- 22:51:10 KST 기존 review f0a2e763-efe5-4396-bb34-429a8d90ba0b에 canceled=true를 PATCH했다. CANCELING→22:51:23 COMPLETE, version DEVELOPER_REJECTED를 확인했다. 22:52:20 KST 기존 build 39 선택을 해제하고 같은 version resource 0649aa64-cc2d-4e5c-b95c-129053c487ad를 **1.1.9 / PREPARE_FOR_SUBMISSION / AFTER_APPROVAL / selectedBuild=null**로 변경·재조회했다. 기존 locale/screenshot IDs와 과거 정확한 출시 자료를 보존했다.
- 앱 CFBundleDisplayName/default appName 및 사용자 노출 안내·Live Activity 이름을 수정했다. 홈 header의 제목 Text와 사용하지 않는 subtitle property를 제거했고 Menu·film.stack·별 배지는 유지했다. bundle ID/target/scheme/내부 실행 파일/기존 `Taption Encoder Outputs` 저장 폴더와 HEVC·MP4/MOV 출력 정책은 변경하지 않았다.
- plist lint 및 git diff --check 통과. 새 전용 scratch에서 고정 SwiftPM GoogleMobileAds 13.5.0/UMP 3.1.0/SwiftVLC 0.10.1 resolve, generic iOS Debug clean build, Release clean archive 및 일반 app-store-connect export 모두 exit 0이다. 신규 산출물은 소스 밖 `/Users/u_mo_c/Documents/TaptionEncoderReleases/1.1.9-40-NAME06Y2K8`에 생성했다. 기존 1.1.8-39-LAW06N5K8T를 덮어쓰지 않았다.
- iPhone 18 Pro Max/iOS 27 신규 전용 simulator **6081A497-D25A-43E4-A68D-F1F5B138E718**: focused XCTest **12 passed / 0 failed / 0 skipped**를 xcresult summary에서 직접 확인했다. 신규 이름/홈 제목 부재 계약, 기존 저장·출력 정책, 파일 탐색/일괄 저장/Live Activity/배포 hardening을 포함한다. iPad 전용 simulator ABB3AE94-752E-485C-A353-26951343D42F의 같은 테스트는 이어 실행 중이다. 다른 프로젝트의 simulator/device/runtime는 변경하지 않는다.
- 실제 새 배포 IPA ZIP 검사와 plist 확인: **1.1.9 (40) / displayName=YYY Encoder / bundleId=com.taption.encoder**, 내부 실행 파일은 의도적으로 Taption Encoder다. IPA **23,346,557 bytes**, SHA256 **9613464b9be9c345b56635db417801a8e1b6658194be9c4637511aec32bdc566**. 두 shipped notice는 현재 소스와 byte 일치하고 builday365@gmail.com을 포함하며 help@taption.com을 포함하지 않는다. libVLC notice SHA256=b7978098d613dee11b50de0ef4cfd120b1bfb0807108e10fe25aa2291b7baa78, FFmpeg notice=d0bb8725135b2ec9031a4321ab02cbdae50ee5f031330bd89a3d677e7f3e694d. 이 로컬 export 검사는 Apple validation/upload/processing/submission과 별도 증거다.
- 실제 Release xcactivitylog로 Mach-O 앱 객체 **76개**를 수집한 relink bundle SHA256 **451faa88114962ca260f093c996c5253d7dab16fadd217ec37e2c479eeb26d52**를 생성했다. 첫 시도에 일반 archive 텍스트를 xcactivitylog 대신 지정해 fail-closed 사용자 경로 오류가 발생했고, 실제 archive activitylog로 다시 실행해 통과했다. 정규화 검사 조건/앱 소스를 변경하지 않았다. 대응 소스와 같은 archive의 크기 보고서, 기술 gate/Apple upload는 후속 검증 중이다.
- ASC 기존 PNG 총 30개를 원래 순서·이름·규격과 함께 original-manifest.json으로 고정하여 `/Users/u_mo_c/Documents/YYYEncoderAppStoreScreenshots-NAME06Y2K8/originals`에 복구했다. 두 imagegen 초안은 해상도/UI/글자 가장자리 변경 때문에 최종 이미지로 채택하지 않았다. 원본의 이름/홈 제목 영역만 native 정밀 편집하는 방식의 사용자 선택을 요청했으며, 원본 이미지 및 ASC 등록 사진은 아직 변경하지 않았다. Apple 업로드·재제출·공개 승인 완료는 아직 주장하지 않는다.
- 후속 로컬 검증: iPad xcresult summary도 **12 passed / 0 failed / 0 skipped**, 총 24건 통과를 확인했다. iPhone/iPad 앱 runtime screenshot에서 home header의 앱 이름 텍스트 부재, 메뉴·영상 아이콘·별 표시 보존을 육안 확인했다. iPadOS 상태바가 자체 표시하는 YYY Encoder는 앱의 home header와 별개이며 OS 표시를 삭제했다고 주장하지 않는다. Simulator UI 접근이 불가해 새 가로 회전 screenshot은 수집하지 않았다.
- 같은 archive의 Xcode App Thinning report(기기 20.9 MB compressed/43.5 MB uncompressed, universal 23.3 MB/46 MB)와 대응 소스/재링크를 입력한 **배포 기술 gate exit 0/PASS**. LEGAL_REVIEW_STATUS=NOT_VERIFIED 유지. source SHA256=0bf092133e0e9ebe669b9b12d7c9cafe35efe31374e34a3e84a34ab98ce9b290, relink=451faa88114962ca260f093c996c5253d7dab16fadd217ec37e2c479eeb26d52, size report=12ee95b095482438669c690dc25cb58cc0fe786e0483a8322d6c82c5c5514d68, IPA=9613464b9be9c345b56635db417801a8e1b6658194be9c4637511aec32bdc566. 원래 수정하지 않은 라이브러리로 normalized link command 실행 exit 0/unsigned arm64 executable을 확인했다. modified-library 설치/법적 승인으로 확대하지 않는다.
- 앱/두 extension archive 서명과 dSYM UUID는 각각 main 5870AFB6-7AFE-3877-82BC-F9568D228133, Live Activity 3573F938-5AC6-3839-BFE7-73846242CCD7, Thumbnail 66FE1043-B167-30EC-9FBC-ECB27DF6BF09로 모두 일치했다. BaseSource-ed17d66.tar.gz+Candidate-1.1.9-40.patch를 새 scratch에 적용하여 구성 파일 **119개**를 현재 소스와 byte 비교 PASS했다. 처음 absolute /tmp 경로 방식은 macOS /tmp symbolic link 때문에 git apply가 차단했고, 실제 /private/tmp stage directory에서 적용해 검증했다. 사용자 소스/브랜치를 초기화하지 않았다.
- 23:14:06 KST upload 전 독립 ASC GET: 정확한 1.1.9/PREPARE_FOR_SUBMISSION/AFTER_APPROVAL, existing build40 count=0. 위 IPA의 Apple altool validation을 시작했으며 완료 결과와 upload/processing은 별도 후속 증거로 남긴다. 이 단계에서 사진 교체와 재제출은 아직 하지 않았다.
- Apple altool 27.0.5 validation **23:17:02 KST / exit 0 / VERIFY SUCCEEDED with no errors**를 확인했고, 동일 IPA upload도 **exit 0 / UPLOAD SUCCEEDED with no errors**. 새 delivery UUID **44ea1608-1531-462c-8345-121ee09a8d45**, 전송 bytes=23,346,557로 로컬 IPA와 일치한다. processingState/APP_STORE_ELIGIBLE와 App Review 재제출은 아직 별도 확인이 필요하다.
- 새 1.1.9 ko/en-US whatsNew를 앱 이름 변경·홈 화면 정리·일부 영상 재생 불가 개선·동영상 변환/파일 처리 안정화의 네 짧은 문장으로 수정했다. 23:19:19 KST PATCH 후 GET에서 두 locale 모두 정확한 문구를 확인했고 description/keywords/URL/promotionalText 등 **다른 localization attributes는 전부 불변**이다. 한국어: `앱 이름을 YYY Encoder로 변경했습니다.` / `홈 화면을 간결하게 정리했습니다.` / `일부 영상이 재생되지 않는 문제를 개선했습니다.` / `동영상 변환과 파일 처리의 안정성을 개선했습니다.` 영어: `Renamed the app to YYY Encoder.` / `Simplified the home screen.` / `Fixed an issue that prevented some videos from playing.` / `Improved video conversion and file handling stability.` AFTER_APPROVAL 보존, 사진 교체/새 심사 제출은 아직 하지 않았다.
- Upload 완료 시각은 **23:19:34 KST**이며 altool processing **exit 0/VALID/APP_STORE_ELIGIBLE/is-on-app-store-connect=true**를 확인했다. 23:23:05 KST 공식 API 독립 GET에서 delivery와 같은 build ID 44ea1608-1531-462c-8345-121ee09a8d45, build 40, expired=false 및 preReleaseVersion **2475fa5c-0855-4d2f-99b3-fea089d24302 / 1.1.9 / IOS**를 확인한 뒤 같은 App Store version에 선택했다. 현재 **1.1.9/PREPARE_FOR_SUBMISSION/AFTER_APPROVAL/selectedBuild=40**이며 새 WAITING_FOR_REVIEW로 확대하지 않는다.
- 23:24:08 KST 최종 checkpoint: **active iOS review 0건**, old canceled review COMPLETE, App Review contact builday365@gmail.com/demoAccountRequired=false, 네 screenshot set 5+10+10+5=30장의 원래 ID·순서 유지 및 delivery COMPLETE. 공개 심사 재제출·새 이미지 업로드/삭제는 실행하지 않았다. 원본 PNG 30장의 native dimensions와 SHA256/MD5 baseline도 모두 고정했다(총 45,652,243 bytes). 기존 비디오·기기 프레임·언어별 텍스트를 바꾸지 않는 native 정밀 편집 방식의 사용자 답변을 기다리는 단계이며 NAME06Y2K8는 temp.md에 미완료로 유지한다. 홈 이름 제거와 실제 새 바이너리/이메일 수정·업로드까지는 완료다.
- 최종 plist lint/git diff --check 통과. 새 파일/로그/이미지는 전부 소스 밖이며 23개 tracked dirty 파일을 보존하고 commit/push하지 않았다. 이전 1.1.8 record/ZIP/pending legal record/기존 사용자 동영상/다른 프로젝트 시뮬레이터를 삭제하거나 변경하지 않았다. archive/IPA/dSYMs/대응 소스/76개 재링크 객체와 compact proof는 새 exact-release record에 보존했다. 로컬 전용 simulator와 scratch는 아직 보존돼 있고 새 release 후속이 끝난 뒤 그 정확한 신규 생성 대상만 정리할 수 있다.

### NAME06Y2K8 재개 — 정밀 편집 및 심사 재제출 (2026-10-07)

- 사용자는 ‘정밀편집해서 마무리하고 제출까지 마무리해’로 원본 영역만 native 편집하는 방식을 명시 승인했다. 이전 imagegen 초안을 채택하지 않고 non-bundled `Scripts/precise_app_store_branding.swift`의 CoreGraphics/CoreText 픽셀 처리와 별도 `Scripts/verify_app_store_artwork.swift` 검증을 사용했다. 실제 앱 코드·구성 119개 및 1.1.9 (40) IPA SHA256가 기존 검증 결과와 동일함을 다시 확인했다. 이번 이미지 작업으로 앱 바이너리가 바뀌었다고 주장하지 않으며 앞서 통과한 iPhone/iPad 24개 테스트와 배포 기술/Apple 검증을 재사용한다.
- 최종 PNG **30/30 PASS**: ko/en-US 각 iPhone 5장(1242×2688), iPad 세로 5장(2064×2752), 가로 5장(2752×2064). 원래 파일명·폴더 구조·해상도를 유지했고 모두 비손상 8-bit RGB/무알파 PNG다. 원본 30개 SHA256 불변, 저장 후 lossless 픽셀 일치, 별도 비교에서도 **편집 허용 영역 밖 변경 픽셀 0**이다. 변경 영역은 상단 브랜드 글자와 홈 제목/영상 아이콘 재정렬 영역뿐이며 영상·버튼·기기 프레임·다른 설명 문구·언어별 UI는 그대로다.
- 상단 30개 wordmark의 Vision OCR 결과가 모두 **YYY Encoder**, 전체 OCR에서 이전 Taption 이름 검출 0건이다. 홈 제목이 있는 26장 모두 삭제했고, 나머지 4장은 원래 홈 헤더가 없는 전체 화면 picker/player다. OCR이 건너뛴 흐린 iPad modal 배경 8장을 육안 검수에서 발견해 같은 기기군의 확정 geometry로 처리했다. 최초 단일 색상/아이콘 탐색은 흐린 배경의 미세한 수직 gradient에서 fail-closed했고, 행별 배경색 복원과 원본 아이콘 픽셀 복사로 해결했다. 최종 연락처 시트 및 흐린 iPad master 검수에서 이전 이름·사각형 번짐·테두리·이음새가 보이지 않는다.
- 최종 ko/en-US PREVIEW 2개를 업로드 전에 이미지/링크로 제공했다. `open_in_codex`는 queued이므로 패널 표시 완료를 별도로 주장하지 않는다. 원본/미리보기/정밀 diff·OCR·체크섬은 `/Users/u_mo_c/Documents/YYYEncoderAppStoreScreenshots-NAME06Y2K8`에 보존하며 compact QA는 새 exact-release의 `Evidence/artwork-qa-summary.json`에 보존했다.
- 00:28:23 KST 공식 ASC GET에서 **1.1.9/PREPARE_FOR_SUBMISSION/AFTER_APPROVAL/build40**, active iOS review 0건 및 원래 30개 ID·순서·체크섬/COMPLETE를 재확인했다. 같은 앱의 4개 screenshot set에서 원본 백업이 있는 해당 파일만 하나씩 교체하고 완료·체크섬·native dimensions·순서를 확인한 뒤 다음 파일로 진행한다. 초기 version GET의 build linkage 미포함 검사는 외부 수정 전 종료됐고 `include=build`를 명시해 해결했다.
- 최초 이미지 교체에서 19장은 모든 검사를 완료했다. 두 resource는 COMPLETE가 체크섬 metadata보다 먼저 반영되어 `NoneType` 검사에서 해당 set 진행이 멈췄다. 기존 새 ID를 공식 GET으로 재조회해 정확한 로컬 MD5/해상도가 반영된 것을 확인하고 재업로드 없이 순서를 복구했다. 이후 polling은 COMPLETE뿐 아니라 checksum/image metadata도 준비될 때까지 확인한다. 기존 원본을 대량 삭제하거나 새 POST를 중복하지 않았다. 00:38:03 KST 기준 26장 완료, 남은 영어 iPad 가로 이미지와 최종 심사 제출은 별도 후속 기록으로 확정한다.
- 00:31:40 KST metadata GET: ko/en-US 이름 YYY Encoder, 부제·간결한 동영상 변환 설명·builday365@gmail.com 및 짧은 수정사항 정상, build40 VALID/APP_STORE_ELIGIBLE/expired=false를 확인했다. 00:33:30 KST 실제 IPA의 version/build/displayName/bundle ID와 두 bundled source-offer 고지의 올바른 메일·SHA256도 다시 확인했다. 기존 1.1.8 (39) 자료·사용자 파일·시뮬레이터 데이터는 변경/삭제하지 않으며 commit/push 및 공개 승인 완료는 아직 수행/주장하지 않는다.
- 이미지 교체 최종 결과 **30/30 COMPLETE**, 네 set의 5+10+5+10개 순서 및 각 원본 파일명·새 로컬 MD5·native dimensions·파일 크기 일치. `screenshot-upload-progress.json`은 COMPLETE/failures=[]이며 초기 transient metadata 오류와 재업로드 없는 복구 이력을 보존한다. Apple에 등록된 이전 screenshot resource 30개는 요청한 새 이미지로 교체됐고, 삭제한 이전 PNG의 로컬 원본 30개와 과거 출시 자료는 그대로 보존되어 복구할 수 있다.
- 최초 제출 명령이 사용자에 의해 중단됐다. 재개 지시 ‘ㄱㄱ’ 후 **00:41:33 KST** 공식 read-only GET에서 version PREPARE_FOR_SUBMISSION/AFTER_APPROVAL/build40, active review 0건 및 제출 receipt 부재를 확인했다. 중단된 명령을 성공으로 취급하거나 기존 제출을 중복 생성하지 않았다.
- 제출 전 독립 GET으로 30개 새 이미지의 COMPLETE·MD5·규격·순서를 다시 검사하고, 이름·부제·간결한 ko/en-US 설명/수정사항/지원 메일이 직전 확정 metadata와 동일한지 확인했다. 앱/구성 119개 source hash와 정확한 IPA SHA256도 일치했다. build40 VALID/APP_STORE_ELIGIBLE/expired=false 및 preReleaseVersion 1.1.9/IOS, AFTER_APPROVAL을 확인한 뒤 새 review **eb30a21b-6226-4d21-882e-2a99797e27af**를 생성하고 해당 version 한 건만 연결했다.
- **2026-10-07 00:42:55.710 KST** submitted=true 완료. **00:43:56 KST** 별도 GET에서 review 및 App Store version 모두 **WAITING_FOR_REVIEW**, 1.1.9 (40), build 44ea1608-1531-462c-8345-121ee09a8d45 및 **AFTER_APPROVAL**을 확인했다. 제출 item이 정확한 version resource 0649aa64-cc2d-4e5c-b95c-129053c487ad에 연결된 것도 확인했다. 제출 이후 30개 새 이미지의 체크섬·해상도·순서/COMPLETE와 ko/en-US 이름 YYY Encoder를 재확인했다. Apple 승인·실제 공개 출시 완료를 주장하지 않는다.
- 정확한 기록은 새 release `Evidence/asc-resume-after-interruption.json`, `asc-screenshots-final-readback.json`, `asc-resubmission-receipt.json`, `asc-resubmission-final-readback.json`에 보존했다. NAME06Y2K8 구현·정밀 이미지 교체·심사 재제출 및 COPY06M2Q8 실제 새 바이너리 메일 확인은 완료되어 temp.md에서 제거한다. PUB06V8N2R는 새 submission에 결속한 Apple 심사/실제 공개 출시 후속 확인만 남긴다. FIX06P3M7Q의 사용자 기기 기본 연결 미확인 상태는 유지한다. 이번 재개에서 새 빌드·시뮬레이터 실행/삭제·commit/push·외부 법률 승인서 조작은 수행하지 않았다.
- 최종 AGENTS.md/RELEASE_MANIFEST 상태를 실제 새 제출에 맞춰 갱신하고 기존 immutable 바이너리/소스/재링크와 새 증거를 포함한 SHA256SUMS를 재생성했다. **17/17 checksum OK**, `git diff --check` PASS. 완료 ID 두 개만 temp.md에서 제거했고 관련 없는 FIX06P3M7Q 내용은 byte 그대로 보존했다.

## CLN07M4Q9B — main 커밋·푸시 및 소스 중심 정리 (2026-10-07)

- 사용자는 워크트리 clean, main 커밋·push, 소스 외 관련 파일 삭제 및 새 채팅용 프롬프트를 요청했다. main/origin/main을 fetch 후 확인했고 시작 HEAD는 둘 다 ed17d666df085bfd08df1648a07ee907d0e0e53f다. Git worktree는 주 checkout 한 개뿐이며 앱에 연결된 별도 managed artifact/worktree는 없다. 별도 브랜치 삭제·이력 초기화는 하지 않는다.
- 23개 tracked 변경과 정밀 이미지 Swift 도구 2개를 범위별로 확인했다. 실제 submitted candidate의 119개 앱/구성 파일 SHA256가 current source와 일치하며 IPA SHA256=9613464b9be9c345b56635db417801a8e1b6658194be9c4637511aec32bdc566도 재확인했다. plist lint/배포 shell 두 파일 bash -n/git diff --check 통과. 새 도구의 private-key/Bearer/password/token 패턴은 발견하지 않았다. 기존 iPhone/iPad focused 24 tests 및 동일 Release/Apple 검증을 재사용하며 새 runtime 테스트를 수행했다고 주장하지 않는다.
- source 밖 삭제 후보는 /private/tmp/YYYEncoder-NAME06Y2K8.UPtGou 약 3.1 GiB, /Users/u_mo_c/Documents/YYYEncoderAppStoreScreenshots-NAME06Y2K8 약 91 MiB 및 전용 simulator 6081A497-D25A-43E4-A68D-F1F5B138E718 / ABB3AE94-752E-485C-A353-26951343D42F의 데이터다. 공용 ~/Library/Developer/Xcode/DerivedData 폴더는 현재 없다. 다른 프로젝트 시뮬레이터/공용 runtime·원본 사용자 동영상·인증 키·필수 vendor/resources/licenses는 삭제 대상이 아니다.
- TaptionEncoderReleases 약 1.3 GiB는 현재 심사 중 정확한 archive/IPA/dSYM/출시 증빙 및 LGPL 대응 소스/재링크를 포함하므로 보존 지침과 충돌하는 삭제 범위를 사용자에게 질문했다. 정확한 symbols/원본 artifact는 소스 재빌드로 복구를 보장할 수 없음을 안내했다. 소스 commit/push 및 재생성 가능한 정리는 독립적으로 진행하되 이 보존 자료의 실제 삭제/보존 선택은 후속 결과로 기록한다.
- 앱 변경/정밀 도구/compact 검증 25개 파일을 main **71d9f67e18e6e6c7f061004599ed143982ee98ae**로 commit했고 origin/main push exit 0. 독립 `git ls-remote --heads origin main`도 같은 hash다. 커밋 직후 working tree는 clean이었다. 기존 branch/remote history는 삭제하거나 force-push하지 않았다.
- 소유 이름을 재검증한 전용 simulator 두 대를 shutdown/delete했고 devices 목록에서 두 ID 및 data directory 부재를 확인했다. 원래 다른 simulator **12개 ID 모두 존재**한다. 해당 두 ID의 잔여 log directory만 제거했다. 명시 검증한 전용 /private/tmp/YYYEncoder-NAME06Y2K8.UPtGou를 일반 `rm -r -- 정확한경로`로 삭제했고 부재 확인했다. 먼저 force 형태 명령은 도구 보호 규칙이 거절했으며 실행되지 않았다. 강제 옵션 없이 안전한 일반 삭제로 완료했다. 이 build/cache/raw test 결과는 재생성할 수 있지만 삭제한 로컬 copy 자체는 보장 복구할 수 없다.
- 제출한 archive/IPA/dSYM/LGPL source/relink/이미지 원본은 아직 그대로 보존한다. 사용자 scope 답변을 받지 않아 전체 비소스 삭제 완료로 표현하지 않는다. 필수 project assets/vendor/licenses 및 키, 원본 사용자 동영상, 공용 simulator runtime/다른 프로젝트 데이터를 보존했다. 현재 APFS 여유 공간 df 보고는 60 GiB이며, 다른 시스템 활동을 포함할 수 있어 전체 변화량을 이 작업의 절감량으로 단정하지 않는다.
- 새 채팅용 NEXT_CHAT_PROMPT.txt는 현재 user 지시의 간결한 작업형 문장과 사실/제한 중심으로 작성했다. source commit·정확한 version/build/review ID·심사 대기/자동 출시·삭제 및 보존 대상·남은 CLN/PUB/FIX 항목을 명시했다. 스타일 참고로 연결 앱의 관련 capability를 확인했으나 적합한 원문 링크 reference를 새로 확보하지 않았으며 현재 대화의 사용자 제공 작업 지시를 사용했다. 프롬프트 작성은 새 thread 생성이나 메시지 전송을 의미하지 않는다.
- **00:59:24 KST** 공식 API read-only 재조회에서 같은 1.1.9/build40/review eb30a21b-6226-4d21-882e-2a99797e27af, version/review WAITING_FOR_REVIEW 및 AFTER_APPROVAL을 확인했다. cleanup 과정에서 심사 취소·재제출·Apple 등록 screenshot 삭제/변경은 하지 않았다. handoff/정리 기록은 별도 main 문서 커밋으로 반영하며 CLN07M4Q9B는 보존 자료 삭제 범위 결정만 pending으로 유지한다.
- 후속으로 사용자가 복구 제한 안내에 **‘삭제’**로 답하여 기존 exact-release 보존 지침을 해당 대상에 한해 명시적으로 변경했다. 정확한 1.1.8-39-LAW06N5K8T 및 1.1.9-40-NAME06Y2K8 디렉터리, 39 ReviewPacket ZIP/verification JSON, YYYEncoderAppStoreScreenshots-NAME06Y2K8를 실물/경로 확인 후 일반 `rm -r --`로 삭제(exit 0), 빈 TaptionEncoderReleases는 `rmdir`로 제거(exit 0)했다. 두 상위 경로 부재 확인 PASS. 크기는 사전 du 기준 약 1.3 GiB+91 MiB이며 정확한 여유 디스크 변화량으로 단정하지 않는다.
- 삭제에는 exact archive/IPA/dSYM, 대응 소스 사본/재링크 객체, 심사 패킷, 이미지 원본/수정본/PREVIEW/QA 및 raw 증거가 포함된다. 정확한 바이너리·심볼·증거 복구는 보장하지 않는다. canonical 소스/필수 의존성·리소스·라이선스/재빌드 도구/compact Git 기록, 인증 키와 사용자 원본 영상은 보존했고 소스 제공 책임이 면제됐다고 해석하지 않는다. Apple 심사나 서버에 등록된 파일은 변경하지 않았다.
- 삭제 전후 tracked 파일에서 AGENTS.md/temp.md/test.md/NEXT_CHAT_PROMPT.txt 네 기록 문서를 제외한 **121개 SHA256 전부 동일**, 변경 0건. CLN07M4Q9B를 완료 항목으로 temp.md에서 제거하고 PUB06V8N2R의 후속 근거를 compact Git 기록/공식 live 조회로 정정했다. FIX06P3M7Q는 그대로 유지한다. 문서 정정만 추가 커밋·main push하며 새 앱 빌드/런타임 테스트를 수행한 것으로 표현하지 않는다.
