# 진행 중 작업

## RF14T0P10A — iPad 실기기 터치 검사 대기
- 원인: iPad Pro의 XCTest automation mode 연결이 시간 초과되어 실기기 터치 검사는 실행되지 않았습니다. 잠금 해제 요청의 응답을 기다립니다.
- 해결: 잠금 해제 후 작업 전용 `DeviceHarness/PreviewInteractionUITests.swift`로 설치된 최종 빌드 48의 하단 스와이프·정보·공유·Add를 검사합니다. 근거/도구는 `/private/tmp/BOKKIEncoder-RF14T0P10A-5nan1f74`에 보존했습니다.
- 검증 기준: 실제 iPad14,6의 해당 XCTest가 실행되어 성공하고 현재 설치 버전 1.1.13(48)이 확인되어야 합니다. 앱 설치·실행 및 시뮬레이터 검사와 구분합니다.
