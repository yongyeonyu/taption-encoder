# 진행 중 작업

# FIX06P3M7Q

남은 요청: 파일 앱에서 Taption Encoder를 기본 연결 앱으로 선택하고 실제 파일 탭으로 확인한다. REV06D4N8Q 코드 수정과 로컬 빌드·회귀 검증은 완료되어 test.md의 FIX06P3M7Q에 기록함.

원인: iPhone 미러링의 앱 화면 읽기가 timeout/해석 오류로 실패함. Info.plist의 Viewer/Owner 및 UTI 연결 등록은 검증했지만, 기기의 ‘항상 다음으로 열기’ 선택 완료를 입증하지는 않음.

남은 해결: 사용자가 미러링을 연결하면 Files → 영상 길게 터치 → 정보 가져오기 → 항상 다음으로 열기 → Taption Encoder → 해당 파일 유형에 적용을 선택·확인한다. 또는 사용자가 기기에서 직접 선택한다. 사용자에게 연결/직접 설정을 요청했으며 아직 설정 완료 답변은 없음. 앱 내부 전체 decoder를 AVPlayer로 바꾸지 않는다.

검증 기준: 해당 기기의 MP4/MOV 기본 연결 메뉴에서 Taption Encoder 선택을 확인하고 Files에서 파일 탭 시 바로 플레이어로 진입하는지 확인한다. 기본 연결 UI와 앱 코드/test 결과는 분리 기록한다. 명시되지 않은 commit/push/upload는 하지 않는다.
