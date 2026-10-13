# 진행 중 작업

## TF13B4K9Q2 — main 커밋·푸시 및 TestFlight 빌드 업로드

- 원인: 승인된 미리보기 UI 수정이 아직 로컬 변경이며, TestFlight에는 새 동작이 배포되지 않았습니다.
- 해결: 현재 App Store Connect 빌드를 확인하고 다음 빌드 번호를 적용합니다. 검증된 변경을 main에 커밋·푸시한 뒤 배포 서명 archive/IPA를 생성하여 TestFlight에 업로드합니다. 산출물과 인증 키는 소스 저장소 밖에 유지합니다.
- 검증 기준: 기존 최종 UI 4개·단위 20개 통과 결과와 소스 일치 확인, 배포 archive/IPA 버전·서명 확인, Apple 업로드 수신 및 처리 결과 확인, main과 origin/main 일치 및 워크트리 clean. 근거는 test.md에 기록합니다.
