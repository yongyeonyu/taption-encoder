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
