# 진행 중 작업

# REL06T7M9C

요청: 로컬 수정 검증 후 main 커밋·푸시, 새 TestFlight 빌드 업로드, source-only 정리(관련 빌드/테스트/시뮬레이터 산출물 삭제)를 수행한다.

원인: 현재 미리보기/오디오/소스 열기 수정이 dirty 로컬 상태이며 배포본과 다르다. 완료 검증 증거와 저장 용량을 구분해 커밋/릴리스 후 정리한다.

해결: main/origin과 live App Store Connect 상태 확인, 변경 리뷰 및 회귀 재사용/필요 실행, marketing/build 동시 증가, 커밋·푸시한 정확한 상태에서 archive/export/upload한다. 처리 상태·TestFlight 공유는 읽어 확인하고 심사 제출/공개 배포는 요청 범위에 넣지 않는다. 관련 생성물만 정확히 식별해 복구 가능한 정리부터 수행하고, 필수 source/vendor/resources 및 원본 영상·다른 작업·기존 릴리스 법적 기록은 보존한다.

검증 기준: clean main == origin/main, source 포함 새 버전 일치, archive/export 및 Apple 업로드 receipt, App Store Connect processing/TestFlight 실제 상태, 명시한 정리 targets의 삭제·보존 확인. 기록은 test.md에 남기고 완료 항목만 여기서 제거한다.

# FIX06P3M7Q

남은 요청: 파일 앱에서 Taption Encoder를 기본 연결 앱으로 선택하고 실제 파일 탭으로 확인한다. REV06D4N8Q 코드 수정과 로컬 빌드·회귀 검증은 완료되어 test.md의 FIX06P3M7Q에 기록함.

원인: iPhone 미러링의 앱 화면 읽기가 timeout/해석 오류로 실패함. Info.plist의 Viewer/Owner 및 UTI 연결 등록은 검증했지만, 기기의 ‘항상 다음으로 열기’ 선택 완료를 입증하지는 않음.

남은 해결: 사용자가 미러링을 연결하면 Files → 영상 길게 터치 → 정보 가져오기 → 항상 다음으로 열기 → Taption Encoder → 해당 파일 유형에 적용을 선택·확인한다. 또는 사용자가 기기에서 직접 선택한다. 사용자에게 연결/직접 설정을 요청했으며 아직 설정 완료 답변은 없음. 앱 내부 전체 decoder를 AVPlayer로 바꾸지 않는다.

검증 기준: 해당 기기의 MP4/MOV 기본 연결 메뉴에서 Taption Encoder 선택을 확인하고 Files에서 파일 탭 시 바로 플레이어로 진입하는지 확인한다. 기본 연결 UI와 앱 코드/test 결과는 분리 기록한다. 명시되지 않은 commit/push/upload는 하지 않는다.
