# HapticLab — R08·R09 실험용 프로토타입

무대 위 이동 안내 프로젝트의 **신호 설계(R08)** 와 **출력 장치(R09)** 를 실기기에서 재기 위한 앱이다.
리서치 문서 `Research/R08-R09-signal-and-output.md` 의 실험 계획 E1~E9 중 **여덟 개를 담았다**.

이 앱은 제품이 아니다. **숫자를 얻기 위한 도구**다. 처음에는 카메라 없이 신호 자체를 알아듣는지부터 쟀고,
2026-10-01에 카메라(LiDAR) 위치 추적과 소리 안내를 합친 화면(S2)을 더했다.

## 지금 상태 (2026-10-01)

앱을 켜면 **카메라 + 소리 따라 걷기(S2)** 화면 하나만 뜬다. 세워 둔 iPhone(LiDAR 기종, 16 Pro Max로 시험)이
사람 위치를 잡고, 바닥에 찍은 목표 자리에서 AirPods 3D 소리가 나며, 그 소리를 따라 걸어가 도착하는지 본다.
단계(카메라 켜기 → 사람 인식 → 목표 정하기 → 정면 맞추기 → 걷기)를 차례로만 진행할 수 있다.
다른 실험 화면의 코드는 남아 있다 — `Sources/iOS/PhoneApp.swift` 의 루트를 `TestListView()` 로 바꾸면 돌아온다.
실기기 테스트 기록은 `Research/test-log.md`.

## 구성

| | 무엇 | 어디서 |
|---|---|---|
| **iPhone 앱** | 운영자가 쓴다. 시계 없이 하는 1~4도 여기서 | 테스트 목록 · 결과 |
| **Watch 앱** | 무용수·피험자가 찬다. 첫 화면 목록에서 번호를 눌러 들어간다 | 간격 하한(E6-1) · 세기 구분(E6-2) · 신호 식별(E1·E2·E3) · 수신 · 지속 실행(E5) |

## 여는 법

```bash
cd prototype/HapticLab
xcodegen generate          # project.yml 에서 HapticLab.xcodeproj 를 만든다
open HapticLab.xcodeproj
```

`xcodegen` 이 없으면 `brew install xcodegen`.

빌드 확인은 이미 끝났다 (Xcode 27 / iOS 27 SDK / watchOS 27 SDK).
다만 **실기기에서 돌려 본 적은 없다.** 서명 설정(팀 선택)은 Xcode 에서 직접 해야 한다.

```bash
# 빌드만 확인하려면
xcodebuild -project HapticLab.xcodeproj -scheme HapticLabWatch -destination 'generic/platform=watchOS' build
xcodebuild -project HapticLab.xcodeproj -scheme HapticLab     -destination 'generic/platform=iOS'     build
```

## 실험 순서

각 테스트는 앱 안에서 **설명 → 진행 → 결과** 순서로 안내된다. 조건(간격·세기·렌더링)은 앱이 차례로 바꾸고,
사람은 느낀 대로 답 버튼만 누른다. 번호는 테스트 안내 페이지의 번호와 같다.

| 번호 | 화면 | 기기 | 실험 | 무엇을 가르나 |
|---|---|---|---|---|
| 1 | 폰 `1 소리 방향` | iPhone + AirPods | E7 | 8방향 정위. 좌우 팬(기본값) 16번 → HRTF 고품질 16번. 오차 중앙값 22° 기준, 앞뒤 혼동 |
| 2 | 폰 `2 소리 신호 맞히기` | iPhone + AirPods | E1 소리판 | 다섯 뜻을 소리(짧은 음, 좌우는 한쪽 귀)·말(음성)로 맞히는가. 통과 90% |
| 3 | 폰 `3 AirPods 빼 보기` | iPhone + AirPods | E9 일부 | 한쪽·양쪽을 뺐을 때 안내음이 멈추는가, 폰 스피커로 새는가. 출력 경로 변화를 같이 기록 |
| 4 | 폰 `4 소리로 목표까지` | iPhone + AirPods, 두 사람 | E4 소리판 | 걷는 사람이 운영자 폰의 AirPods 를 끼고, 소리 신호만으로 목표에 가는가 |
| 5 | 시계 `5 진동 간격` | Watch | E6-1 | 진동 9종 중 또렷한 것을 고른 뒤, 간격 500→80ms 에서 5번이 따로 느껴지는가 |
| 6 | 시계 `6 진동 세기` | Watch | E6-2 | `SensoryFeedback.impact(intensity:)` 세기 5단계·무게 3단계를 손목이 구분하는가 |
| 7 | 시계 `7 신호 맞히기` | Watch | E1 · E2 | 다섯 뜻을 진동으로 맞히는가(통과 90%). 가만히/걸으며/춤추며를 따로 기록 |
| 8 | 시계 `8 계속 울리나` | Watch | E5 | 손목을 내려도 5초 주기 톡이 계속 나가는가. 그냥 → 워크아웃 세션 |
| 9 | 폰 `9 전달 속도` + 시계 `폰 신호 받기` | iPhone + Watch | E8 | 시험 신호 100번의 왕복 시간. 보통 100ms 미만, 느린 5% 200ms 이하 |
| 10 | 폰 `10 진동으로 목표까지` + 시계 `폰 신호 받기` | iPhone + Watch, 두 사람 | E4 | 4번과 같은 과제를 진동으로 |
| 11 | 2번·7번을 걸으며·춤추며 | Watch + AirPods | E2 · E3 · E9 | 움직임·음악 속 식별, 착용 견고성 |

**1~4는 시계 없이 된다.** 5~10은 시계 진동의 한계를 재는 것이라 iPhone 진동으로 대신하지 않는다 —
iPhone 에는 watchOS 에 없는 Core Haptics 가 있고 착용 위치도 달라서, 결과가 옮겨지지 않는다.

방향 버튼·신호의 뜻은 "그쪽으로 가라"(무용수 몸 기준)이고, 방향 신호는 `조용히` 를 누를 때까지 반복된다.

🔴 **시계 테스트 중에서는 8번이 가장 중요하다** — `play()` 문서는 *"HealthKit 심박 수집 중 햅틱을 치지 말라"* 고 하고,
워크아웃 세션 문서는 *"워크아웃 중 햅틱을 제공하면"* 을 전제한다. **문서끼리 말이 다르다.**

⚠️ 1번 전에 제어 센터의 **공간 음향** 설정을 기록하고 고정한다. 시스템이 따로 공간화를 걸 수 있다.

🔴 3번에서 **AirPods 를 빼면 안내음이 iPhone 스피커로 나가는지 본다.** 나가면 객석으로 새는 사고다.

## 기록 꺼내기

결과는 기기에 저장된다(앱을 꺼도 남는다). 시계는 첫 화면 `지난 결과`, iPhone 은 `결과` 탭.
iPhone `결과` 탭 → **기록 파일로 보내기** 로 TSV 를 뽑는다. 시계 기록은 아직 iPhone 으로 넘어가지 않는다.
쉼표 대신 탭으로 나눈다 — 설명에 쉼표가 들어가면 표가 깨지기 때문이다.

컬럼: `experiment · at · condition · expected · answered · correct · reaction_ms · note`

**표 파일은 커밋하지 않는다.**

## 코드에서 설계를 바꾸는 자리

| 바꿀 것 | 어디 |
|---|---|
| 신호 패턴 (왼쪽=2탭, 오른쪽=1탭, 뒤=directionDown …) | `Sources/Shared/Signals.swift` 의 `SignalBook.pattern(for:)` |
| 탭 사이 간격 · 생존 신호 주기 | 같은 파일 `SignalBook` 위쪽 상수 |
| 이탈 정도별 반복 간격 (1200/600/300ms) | 같은 파일 `Deviation` |
| 우선순위 | `GuideSignal.priority` |
| 유효 시간 (늦은 지시 버리기) | `GuideCommand.validForMs` 기본값 |
| 생존 신호 끊김 판정 시간 | `Watchdog.timeoutSec` |

## 지금 상태에서 분명히 해 둘 것

- 빌드는 확인했고 iPhone·Watch 실기기에 설치·실행까지 했다. **실험 숫자는 아직 하나도 없다**
- watchOS 시뮬레이터 런타임이 이 기계에 없어 **Watch 앱은 시뮬레이터에서도 못 띄웠다.** 빌드만 확인했다
- E7의 머리 방향 추적은 **AirPods Pro·3세대 이상·Max·Beats Fit Pro** 에서만 된다. 시뮬레이터에서는 동작하지 않는다
- 워크아웃 세션(E5)은 실기기 Watch + HealthKit 권한이 있어야 한다
- 서명·프로비저닝은 Xcode 에서 팀을 골라야 한다
