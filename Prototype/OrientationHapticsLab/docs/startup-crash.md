# 실기기 첫 실행의 흰 화면 크래시

## 확인한 원인

2026-10-07 실기기에서 빌드는 성공했지만 앱이 흰 화면으로 남았다. Xcode의 노란 경고는 `Update to recommended settings`였고, 실제 실패는 실행 중의 Swift 실행 영역 검사였다.

디버거에서 확인한 호출 경로:

```text
OrientationHapticsLab.motion
EXC_BREAKPOINT
_dispatch_assert_queue_fail
dispatch_assert_queue
_swift_task_checkIsolatedSwift
swift_task_isCurrentExecutorWithFlagsImpl
closure #2 in MotionFeed.start
```

리셋 지연 개선 중 방향 자료를 별도 OperationQueue에서 받도록 변경했지만, `@MainActor` 안에서 만든 Objective-C SDK 콜백은 여전히 MainActor 실행을 기대했다. 실제 기기의 첫 센서 자료가 별도 큐에서 전달되자 Swift 6의 실행 영역 검사가 실패했다. 이는 폴더 경로나 빌드 실패가 아니라 이전 수정에서 놓친 실행 시점의 결함이다.

## 수정

- 방향·걸음 SDK 콜백을 `nonisolated` 팩터리에서 생성하고 반환 함수를 `@Sendable`로 명시
- SDK 객체는 콜백 안에서 값으로 변환하고, 값만 AsyncStream 또는 actor로 전달
- Core Haptics의 시작·중단·리셋·완료 콜백도 `@Sendable`로 명시하고 actor 상태 변경은 `await`로 수행
- 시스템 알림을 받는 진동·오디오 구독도 UI 실행 영역을 암묵적으로 상속하지 않도록 명시
- 실행 영역 검사를 끄거나 센서 콜백을 UI 큐로 되돌리는 방식은 사용하지 않음

## 검증

기존 테스트는 가짜 HeadingFeed를 통해 측정 값을 전달했기 때문에 실제 SDK 콜백 경계를 거치지 않았다. 이번에는 앱이 실제 등록하는 콜백을 메인 실행 영역에서 생성한 뒤 별도 큐에서 직접 호출하는 테스트 3개를 추가했다.

- 센서 오류 콜백이 별도 큐에서 실행되어도 검사 실패 없이 전달되는지 확인
- 빈 자료를 무시하고 최신 이벤트만 보관하는지 확인
- 걸음 센서의 오류 콜백도 별도 큐에서 전달되는지 확인
- 앱 테스트 35개 통과, 계산 모듈은 변경 없이 기존 30개 통과 결과 유지
- Xcode에서 선택된 실제 아이폰용 빌드와 실행을 진행

실제 화면 표시·리셋 확인 결과는 이슈 #19에서 추적한다. 이 검증은 허리 착용 시 각도 오차나 7걸음 인식률 검증을 대신하지 않는다.

## 참고

시작 로그의 `.debug.dylib`와 진입점 탐색 메시지는 Xcode의 디버그 실행 구조에 해당한다. 해당 문구만으로 앱의 시작점이 없다고 판단하면 안 된다. [Apple의 디버그 빌드 구조 설명](https://developer.apple.com/documentation/xcode/understanding-build-product-layout-changes)을 참고한다.
