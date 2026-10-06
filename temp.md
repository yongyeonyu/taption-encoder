# 진행 중 작업

# CLN07M4Q9B

요청: 워크트리를 정리하고 main에 현재 검증된 변경사항을 커밋·푸시한 뒤 소스 외 관련 산출물을 삭제하고 새 채팅용 이어가기 프롬프트를 작성한다.

원인: 1.1.9 (40) 심사 제출까지 완료된 이름/메일/홈 화면/배포 정책 변경과 정밀 이미지 도구가 아직 로컬 변경이다. 전용 빌드 cache·시뮬레이터·이미지와 정확한 출시 자료가 소스 밖에 남아 있다.

해결 계획: main/origin 및 diff·기존 검증과 source hash를 확인하고 source-only 대상과 삭제 대상을 정확한 경로/소유 simulator ID로 분리한다. archive/IPA/dSYM/심사 증빙 삭제는 현재 보존 지침과 복구 불가 위험을 안내하여 사용자 선택을 받는다. 원래 사용자 동영상·다른 프로젝트/시뮬레이터·인증 키·필수 vendor/resources/notices는 보존한다. compact proof와 이어가기 프롬프트를 소스에 남기고 커밋·원격 main 정합성 및 정리 후 상태를 확인한다.

검증 기준: git diff --check, 현재 119개 앱/구성 source hash 및 shipped IPA hash 정합성, main=origin/main 및 clean status, 정확한 삭제 대상 부재/보존 대상 존재 확인, 새 대화 프롬프트에 심사 대기/자동 출시와 삭제로 인한 제한을 구분한다. test.md CLN07M4Q9B에 기록한다.

# PUB06V8N2R

남은 요청: YYY Encoder 1.1.9 (40)의 Apple 심사 결과 및 실제 공개 출시 후속 확인. NAME06Y2K8의 이름/홈 제목/메일 수정·정밀 이미지 30장 교체·심사 재제출은 완료됐다.

현재 검증 결과(2026-10-07 00:43:56 KST): 앱 6780777838/com.taption.encoder, version 0649aa64-cc2d-4e5c-b95c-129053c487ad / 1.1.9, build 40 / 44ea1608-1531-462c-8345-121ee09a8d45. 새 review eb30a21b-6226-4d21-882e-2a99797e27af / submittedDate 2026-10-07 00:42:55.710 KST. Review/version 모두 WAITING_FOR_REVIEW / AFTER_APPROVAL. ko/en-US 이름·간결한 설명·지원 메일·수정사항과 새 screenshot 30개의 COMPLETE·체크섬·해상도·순서 검증 완료. 이전 1.1.8 (39) 제출은 취소된 역사적 증거로 보존한다.

원인: 심사 제출과 승인 후 자동 출시 설정은 실제 Apple 승인/공개 출시 완료와 별개다. 이전 외부 법률승인서 필수 내부 규칙은 사용자 지시에 따라 opt-in으로 변경됐으며 기술 gate는 통과했다. Apple 승인을 법적 clearance로 해석하지 않는다.

남은 해결: 사용자가 후속 확인을 요청하면 동일 version/build/submission의 live ASC 상태 및 심사 메시지를 확인한다. AFTER_APPROVAL을 보존하고 새 업로드/심사 취소/metadata 변경/외부 자료 전송을 임의 실행하지 않는다. 자동 감시 automation은 요청되지 않아 생성하지 않는다.

검증 기준: 위 새 1.1.9 (40)/review의 Apple review 결과와 READY_FOR_SALE/READY_FOR_DISTRIBUTION 및 실제 공개 배포 상태를 별도로 확인한다. 새 exact-release /Users/u_mo_c/Documents/TaptionEncoderReleases/1.1.9-40-NAME06Y2K8와 screenshot 원본/검증 자료, 이전 1.1.8 기록을 후속 확인 동안 보존한다. 근거는 test.md NAME06Y2K8 및 release Evidence/asc-resubmission-final-readback.json에 있다.

# FIX06P3M7Q

남은 요청: 파일 앱에서 Taption Encoder를 기본 연결 앱으로 선택하고 실제 파일 탭으로 확인한다. REV06D4N8Q 코드 수정과 로컬 빌드·회귀 검증은 완료되어 test.md의 FIX06P3M7Q에 기록함.

원인: iPhone 미러링의 앱 화면 읽기가 timeout/해석 오류로 실패함. Info.plist의 Viewer/Owner 및 UTI 연결 등록은 검증했지만, 기기의 ‘항상 다음으로 열기’ 선택 완료를 입증하지는 않음.

남은 해결: 사용자가 미러링을 연결하면 Files → 영상 길게 터치 → 정보 가져오기 → 항상 다음으로 열기 → Taption Encoder → 해당 파일 유형에 적용을 선택·확인한다. 또는 사용자가 기기에서 직접 선택한다. 사용자에게 연결/직접 설정을 요청했으며 아직 설정 완료 답변은 없음. 앱 내부 전체 decoder를 AVPlayer로 바꾸지 않는다.

검증 기준: 해당 기기의 MP4/MOV 기본 연결 메뉴에서 Taption Encoder 선택을 확인하고 Files에서 파일 탭 시 바로 플레이어로 진입하는지 확인한다. 기본 연결 UI와 앱 코드/test 결과는 분리 기록한다. 명시되지 않은 commit/push/upload는 하지 않는다.
