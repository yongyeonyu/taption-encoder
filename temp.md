# 진행 중 작업

# CLN08P6M2Q

요청: “워크트리 클린 메인 커밋 푸쉬 후 불필요한 파일 전부 삭제. 소스만 빼고 다 지워”. 최신 앱/아이콘/버전/홈페이지·지원메일 소스를 main에 커밋·푸시한 후 이 프로젝트의 출시·검증·디자인 출력물과 종료된 빌드 임시 파일을 정리한다.

원인: 현재 main/origin/main은35d858a이고 검증·제출된 최신43 및 후속 변경33개 파일이 미커밋이다. 프로젝트 밖 출시·검증·빌드 자료도 중복 보관되어 있다.

해결 범위: 소스·편집 가능한 홈페이지 원본·필수 리소스/의존성/라이선스/재빌드 도구·인증 키·Git 및 사용자 원본을 보존한다. 삭제 경로/용량과 실행 중 프로세스·열린 파일을 확인하고 완료된 검증/제출의 작은 식별자·해시 기록을 test.md에 유지한다. 사용자의 이번 명시적 삭제 요청은 Encoder 전용41/42/43 출시 산출물의 이전 보존 지시를 대체한다. IPA/archive/dSYM·원시 검증 산출물 삭제 후 정확한 복구는 보장하지 않는다. Apple 심사/업로드 자산·실제 iPhone 앱/사용자 데이터·다른 프로젝트는 변경하지 않는다.

검증 기준: 원격main과 로컬HEAD 일치, 최종git status clean, 기존121개 canonical source SHA256 동일성, 필수 vendor/resources/licenses/인증 키 보존, 정확한 삭제 경로 부재와 전후 용량 확인. 이미 통과한 BKR19/PLY60/TRS5 검증을 재사용하고 앱 소스를 바꾸거나 새 build/upload/review를 수행하지 않는다. 실제 삭제 완료 기록을 main에 추가 커밋·푸시하고 이 완료 항목만 제거한다.

# PUB08K7N4M

남은 요청: BOKKI Encoder 1.1.12 (43)의 Apple 심사 결과 및 승인 후 실제 공개 출시 확인. BKR08N6Q2M의 대문자 이름·최신 로컬 기능·새 홈페이지/지원 이메일·실제 UI 소개 사진·새 배포/단일 심사 제출은 완료했다.

원인: 심사 제출 및 AFTER_APPROVAL 설정은 실제 승인·공개 출시와 별개다.

최종 독립 readback: 2026-10-08 13:50:41 KST. App 6780777838/com.taption.encoder, version bf3874fc-ebb5-497e-bb49-9a1b88854615 / 1.1.12, build/delivery 0eaa4e92-f6d7-4ffa-bc79-f97fccfd4b95 / 43 / VALID / APP_STORE_ELIGIBLE, review 60182eba-12c3-4f3a-aeb8-925804cc9d02 / WAITING_FOR_REVIEW, version WAITING_FOR_REVIEW / AFTER_APPROVAL. 제출 시각 13:48:35.340 KST. 정확한 한 version/build/item, ko/en-US BOKKI Encoder·새 marketing/support/privacy URL·메일 없는 설명936/1701자·새 노트/contact support@bokkiyaw.com 및30장 COMPLETE·checksum/규격/이름/순서를 확인했다. KR public lookup은 아직 YYY Encoder1.1.11. 이전42 review는 COMPLETE이고1.1.11 공개 출시를 확인했다(PUB07P4N8R 완료); 이번에는 심사를 취소하지 않았다.

검증·후속 기준: 사용자가 결과 확인을 요청하면 같은 IDs의 live ASC와 public KR lookup을 읽기 전용으로 검증하고 test.md에 남긴다. 새 review/upload/metadata/버전/Git publication/cleanup을 임의 수행하지 않는다. 자동 감시는 요청되지 않아 automation을 만들지 않았다.

보존: exact43 기록 /Users/u_mo_c/Documents/TaptionEncoderReleases/1.1.12-43-BKR08N6Q2M/RELEASE_MANIFEST.json부터 읽는다. 이전41/42 기록과 새 source/relink/IPA를 섞거나 rewrite하지 않는다. 현재main/origin/main35d858a와 미커밋 source patch를 보존한다. iPhone18ProMax에 Release-derived developer43 설치/독립 이름·버전 확인 완료(실행/물리UI/codec검증 아님), iPhone11Pro는 최근 잠금 해제 없음으로 pre-install read가 거부돼 이번 설치를 수행하지 않았다(마지막 확인 설치본은 BNM의 Bokki1.1.11(42), 이번 live 앱 상태 조회 불가).11 Pro 설치-only 선호 유지. 사용자 source/Stars/data 초기화나 삭제를 하지 않았다. BNM/WEB의 앱·스토어 이전은 새43에서 완료됐고 옛Notion 이메일만 EML08K3P9R로 별도 유지한다.

# EML08K3P9R

남은 요청: Notion 공개 지원 페이지(3835583c1e20813cb611e96411180eda)와 개인정보 페이지(3835583c1e208186a727d1f377539fa8)의 support@taption.app 텍스트 및 mailto 링크를 사용자가 지정한 support@bokkiyaw.com으로 변경한다.

완료: 로컬 고지 두 곳의 이메일만 교체, 나머지 119 source hash 보존, 실제 signed 앱 번들 확인, 두 iPhone 설치/독립 readback과 18 Pro Max 실행 완료. ASC 현행 App Review contactEmail도 교체/독립 GET 통과. 2026-10-08 01:14:56 KST 1.1.11/42 WAITING_FOR_REVIEW / AFTER_APPROVAL, build/review/items/설명 보존. 빈 beta 이메일은 채우지 않았다. test.md EML08K3P9R 및 /Users/u_mo_c/Documents/YYYEncoderValidation/EML08K3P9R/VALIDATION_MANIFEST.json 참고.

원인: Notion connector 인증 만료(UNAUTHORIZED). BNM8C2R5D7에서 fresh fetch 두 건과 public reload를 다시 실행해 두 페이지의 이전 이름/이메일·mailto 및 편집 권한 부재를 재확인했다. 재연결 요청에 사용자는 ‘지금 만들고 있어’라고 답했으며 인증 완료는 확인하지 않았다.

추가 지시: 사용자는 홈페이지 주소도 변경할 예정이며 새 도메인 구매·사이트 제작 중이라고 밝혔다(WEB08D6K2R). 새 사이트 URL이 준비되면 홈페이지 이전과 함께 지원/개인정보/연락처 링크를 확인한다. 이를 Notion 재인증 완료로 간주하지 않는다.

남은 해결·검증 기준: 사용자의 준비/재연결이 완료되면 두 페이지를 fetch하고 정확한 이메일 텍스트와 mailto만 교체한다. 공개 페이지 readback으로 새 주소와 나머지 내용 보존을 검증한다. 새 제목/정책 문구·날짜·공유 권한은 바꾸지 않는다. 완료 전 이 항목을 지우지 않는다.

범위: 정확한 제출 42와 과거 기록은 고치지 않는다. Apple 심사 취소/신규 binary 업로드/재제출, 메일 송신/메일 계정 생성, commit·push/자료 삭제는 요청되지 않았다. 메일 수신/소유 확인은 수행하지 않았다.

# FIX06P3M7Q

남은 요청: 파일 앱에서 Taption Encoder를 기본 연결 앱으로 선택하고 실제 파일 탭으로 확인한다. REV06D4N8Q 코드 수정과 로컬 빌드·회귀 검증은 완료되어 test.md의 FIX06P3M7Q에 기록함.

원인: iPhone 미러링의 앱 화면 읽기가 timeout/해석 오류로 실패함. Info.plist의 Viewer/Owner 및 UTI 연결 등록은 검증했지만, 기기의 ‘항상 다음으로 열기’ 선택 완료를 입증하지는 않음.

남은 해결: 사용자가 미러링을 연결하면 Files → 영상 길게 터치 → 정보 가져오기 → 항상 다음으로 열기 → Taption Encoder → 해당 파일 유형에 적용을 선택·확인한다. 또는 사용자가 기기에서 직접 선택한다. 사용자에게 연결/직접 설정을 요청했으며 아직 설정 완료 답변은 없음. 앱 내부 전체 decoder를 AVPlayer로 바꾸지 않는다.

검증 기준: 해당 기기의 MP4/MOV 기본 연결 메뉴에서 Taption Encoder 선택을 확인하고 Files에서 파일 탭 시 바로 플레이어로 진입하는지 확인한다. 기본 연결 UI와 앱 코드/test 결과는 분리 기록한다. 명시되지 않은 commit/push/upload는 하지 않는다.
