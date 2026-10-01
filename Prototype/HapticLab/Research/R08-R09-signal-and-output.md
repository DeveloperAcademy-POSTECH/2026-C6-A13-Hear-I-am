# R08 · R09 통합 기술 리서치
## 이동 안내의 신호 설계와 출력 장치의 실제 범위

작성일 2026-09-23 · 우선순위 P0 · 무대 위 목표 위치 안내 프로젝트

확인 상태 표기 — `[문서]` Apple 공식 문서 확인 · `[선행]` 외부 연구·제품 사례 · `[추론]` 앞의 둘에서 끌어낸 설계 판단 · `[미확인]` 실기기·현장 검증이 필요한 것

**이 문서의 수치는 전부 공식 문서와 외부 연구에서 옮긴 것이다. 우리 기기에서 돌려 본 결과는 하나도 없다.** 실기기 검증은 Part C의 실험 계획으로 남긴다.

## 이 문서의 차례

| | 내용 |
|---|---|
| **0. 요약** | 세 줄 결론과 즉시 바로잡아야 할 팀 내 가정 |
| **0.5 먼저 알아야 할 것** | 기기가 막아 놓은 세 가지. R08부터 읽어도 이해되도록 앞에 뺀 요약 |
| **Part A · R08** | 신호에 뜻을 싣는 법 — 선행 연구(A1~A3), 설계안 세 가지(A4), 안전 규칙(A5) |
| **Part B · R09** | 출력 장치가 실제로 낼 수 있는 것 — Watch 햅틱(B1), AirPods 공간 음향(B2), 착용 조건(B3), 비교와 우선순위(B4) |
| **Part C** | 실험 계획 E1~E9 |
| **Part D** | 아직 모르는 것과 물어야 할 것 |
| **Part E** | 참고 자료 |

---

# 0. 요약

## 0.1 R08 — 어떤 뜻을 어떻게 실을 것인가

몸의 여러 위치를 못 쓰고(Watch 두 대는 동시에 통신하지 못한다) 세기도 쓸 수 있다는 보장이 없으므로, **방향은 리듬으로 표현하는 것이 기본이다.** Apple 지도 앱은 참고가 되지만 그대로 빌릴 수는 없다 — 공식 문서가 설명하는 구분은 **음높이**이고, 우리는 무음 모드를 써야 하므로 소리를 못 쓴다(§A1.1).

설계안 세 가지를 비교해 **통로형(Corridor, 안 C)** 을 첫 검증 후보로 제안한다. 방향이 맞으면 침묵하고, 벗어나면 벗어난 쪽으로 울린다. 무용 중 지속 진동은 촉각 둔감과 피로를 부르므로 "정상일 때 침묵"이 유리하다.

**이 안의 유일한 치명 약점은 침묵이 고장과 구분되지 않는다는 것이다.** 생존 신호와 Watch 측 자체 감시로 막는다.

## 0.2 R09 — 기기는 무엇을 낼 수 있는가

**Apple Watch에서는 임의 파형과 이어지는 진동을 만들 수 없다.** `CHHapticEngine`(Core Haptics)의 플랫폼 목록에 watchOS가 없다. 연속 호출에는 100ms의 최소 지연이 강제된다. 다만 **세기는 지정할 수 있다** — SwiftUI `SensoryFeedback.impact(weight:intensity:)` 가 watchOS 10부터 있고 `intensity` 를 0~1로 받는다. ⚠️ 문서가 *"모든 플랫폼이 서로 다른 무게와 세기에 대해 다른 피드백을 재생하지는 않는다"* 고 경고하므로 **실기기로 재봐야 한다**(§B1.2, 실험 E6-2). 확실한 표현 차원은 **리듬 하나**다.

**AirPods의 공간 음향은 iPhone에서만 만들 수 있고, 기본 설정으로는 3D가 아니다.** `AVAudioEnvironmentNode` 역시 watchOS 미지원이며, 기본 렌더링 알고리즘은 좌우 팬(`equalPowerPanning`)이다. HRTF를 명시적으로 켜야 공간 음향이 된다. 그리고 **모노 입력만 공간화된다.**

**지연은 오디오 쪽이 훨씬 크다.** AirPods의 블루투스 출력 지연은 모델에 따라 80~220ms로 보고된다. 여기에 위치 추정과 전송 지연이 더해진다.

**결론**: 두 장치 모두 심각한 제약이 있지만 종류가 다르다. **햅틱은 표현력이 좁고, 오디오는 느리고 음악을 가린다.** 공연 중 주 출력은 Watch 햅틱, AirPods는 학습·리허설·비상 음성으로 두는 것을 제안한다.

## 0.3 즉시 바로잡아야 할 팀 내 가정

| 기존 가정 | 확인 결과 |
|---|---|
| "500m부터 진동이 점점 강해진다"를 Watch에서 구현 | **끊기지 않는 곡선으로는 불가능**(Core Haptics 없음). 단계별 세기는 `SensoryFeedback` 으로 지정 가능하나 ⚠️ 반영 여부 미확인 `[문서]` |
| AirPods 공간 음향이면 방향을 알려 줄 수 있다 | 기본 설정은 좌우 팬이다. HRTF를 명시해야 하고, 그래도 앞뒤 혼동이 남는다 `[문서]` `[선행]` |
| 양 손목에 Watch를 하나씩 채워 좌우를 만든다 | **불가능.** iOS 앱은 한 번에 한 대의 Watch와만 통신한다 `[문서]` |
| 공연 음원은 스피커로, 안내음은 AirPods로 동시에 | **한 대의 iPhone으로는 불가능.** iOS는 서로 다른 스트림을 여러 출력으로 나누지 못한다 `[선행]` |
| 손목을 내려도 진동은 나간다 | 나가지 않는다. 확장 런타임 세션이 필요하고 그 한도는 1시간이다 `[문서]` |

---

---

# 0.5 먼저 알아야 할 것 — 기기가 막아 놓은 세 가지

R08(신호 설계)을 먼저 읽을 수 있도록, R09에서 확인한 제약 중 설계를 가르는 것만 앞에 뺀다. 근거는 전부 뒤의 **Part B · R09**에 있다.

| 막힌 것 | 그래서 어떻게 되나 |
|---|---|
| **이어지는 진동·임의 파형을 못 만든다** — Core Haptics가 watchOS에 없다. 세기는 지정할 수 있으나 ⚠️ 반영 미확인 `[문서]` | "멀리서 약하게 → 가까이서 강하게"를 **끊기지 않는 곡선으로는** 못 만든다. 기본은 **간격(리듬)**, 세기는 단계로만 가능할 수 있다 |
| **연속 호출에 100ms 하한이 있다** — 이미 울리는 중에 부르면 끊고 100ms를 기다린다 `[문서]` | 패턴 문법이 `[탭] [간격] [탭]` 으로 고정된다. 간격은 100ms 아래로 못 내려간다 |
| **시계 두 대를 동시에 못 쓴다** — WatchConnectivity로는 한 대와만 통신한다 `[문서]` (로컬 네트워크 경로는 별도, §B1.6) | "왼쪽 시계가 울리면 왼쪽"이 안 된다. **좌우도 리듬으로** 구분한다 |

> 남는 표현 차원은 **리듬 하나뿐이다.** Part A의 설계는 전부 이 한 줄에서 출발한다.

# Part A · R08 — 신호에 뜻을 싣는 법

## A1. 한 손목, 한 진동기로 방향을 전한다

### A1.1 Apple 지도는 어떻게 좌우를 구분하나 — 자료가 갈린다 `[문서]` `[선행]`

> **이 문서의 첫 버전은 "우회전 = 탭 12회, 좌회전 = 2탭 3쌍"이라고 단정했다.** 그건 2차 자료(기사)의 설명이고, **Apple 공식 지원 문서는 다르게 적고 있다.**

| 출처 | 우회전 | 좌회전 |
|---|---|---|
| **Apple 공식 지원 문서** | 저음 다음 고음 (*tock tick*) | 고음 다음 저음 (*tick tock*) |
| 2차 자료 (CIO 등) | 일정한 탭 12회 | 2탭을 3쌍 |

공식 문서는 *"Apple Watch는 **소리와 햅틱**을 써서 언제 회전할지 알려 준다"* 고 한 뒤, 실제 구분은 **음높이**로 설명한다. 그리고 *"무음 모드에서는 소리가 나지 않는다"* 고도 적는다.

**이것이 우리에게 중요한 이유** `[추론]` — Apple의 선례가 음높이에 기대고 있다면, **우리는 그걸 그대로 빌려 쓸 수 없다.** 공연 중에는 무음 모드가 필수이고(§B1.4), 무음에서는 소리가 사라진다. **진동만 남았을 때도 좌우가 구분되는지는 우리가 직접 재봐야 한다.**

그래도 남는 교훈은 있다. 어느 설명을 따르든 **Apple은 세기를 연속으로 올리는 방식을 쓰지 않는다.** 음높이든 박자 수든 **서로 다른 패턴 두 개**를 쓴다. 그리고 12탭이 맞다면 **그 패턴은 길다** — 최소 간격 100ms로도 1.2초가 넘어 **무대 위 몇 초짜리 이동 안내로는 늦다.**

### A1.2 촉각 아이콘 연구 — 리듬이 가장 잘 구분된다 `[선행]`

Brewster·Brown 계열 Tacton 연구의 인식률:

| 조건 | 인식률 |
|---|---|
| 리듬 단독 | **93%** |
| 거칠기(진폭 변조) 단독 | 80% |
| 두 차원을 동시에 실은 촉각 아이콘 | 약 70~71% |
| 공간 단서가 없을 때 평균 | **57%** (항목별 30~83%) |

**설계로 옮기면** `[추론]` — 우리는 몸의 여러 위치를 못 쓰고(B1.6), 거칠기를 쓸 수 있다는 보장도 없다(B1.2). **확실한 것은 리듬 한 차원이고, 그것이 마침 가장 잘 구분되는 차원이다.**

주의할 것이 하나 있다. 나중에 세기를 쓸 수 있다고 확인되더라도, **의미를 두 차원에 나눠 싣는 순간 인식률이 93%에서 70%로 떨어진다.** 세기는 새 의미를 싣는 데 쓰기보다 **같은 의미를 더 잘 들리게 하는 데** 쓰는 편이 안전하다. 그리고 **동시에 구분할 의미는 4~5개를 넘기지 않는다.**

### A1.3 통로형 설계 — 맞으면 침묵한다 `[선행]`

HapticNav의 Haptic Corridor는 목적지로 향하는 가상 통로를 만든다.

- 방향이 맞으면 **진동 없음**
- 조금 벗어나면 부드러운 펄스
- 크게 벗어나면 강한 진동

시각장애 러너가 뉴욕 마라톤 24km를 시각 보조·음성 없이 완주한 사례로 소개된다. 제품 측은 SDK 응답 50ms 미만을 주장한다(제3자 검증 아님).

**우리 조건으로 번역하면** 세기 대신 간격으로 바꾼다 — 맞으면 침묵 / 조금 벗어나면 느린 펄스 / 많이 벗어나면 빠른 펄스. `[추론]`

### A1.4 스마트워치로 실제 해 본 사례 — RunPacer `[선행]`

Apple Watch Series 7 기반, 시각장애 러너와 가이드의 보폭 동기화(ASSETS '25).

- **단일 탭 펄스**를 여러 탭 대안보다 선호했다.
- **펄스 길이 100~200ms** 가 동작 중 명료성에 최적이라고 기술한다.
- **지연 100ms 미만**을 리듬 인지 유지의 필수 조건으로 잡았다.
- 참가자들은 속도에 따른 **세기 조절**을 요청했으나 Watch API로는 불가능한 요구다(B1.2).
- 한계 — 통제된 200m 트랙, 참가자 10명.

**펄스 100~200ms, 종단 지연 100ms 미만**을 우리 실험의 초기 목표값으로 채택한다. `[추론]`

## A2. 움직이는 몸은 진동을 덜 느낀다 `[선행]`

- **촉각 억제(tactile suppression / movement-related gating)** — 움직이는 팔다리의 촉각 민감도는 정지 상태보다 떨어진다. 말초의 마스킹뿐 아니라 운동 명령이 감각 예측을 통해 입력을 깎는 중추 기전이 주된 설명이다. 다만 **과제에 촉각이 필요할 때는 억제가 줄어든다** — 신호를 기다리고 있으면 덜 깎인다.
- **신체 위치별 민감도** — 손가락·손목·귀·목·발의 인지도와 선호도가 높다. 몸통은 사지보다 둔하다. 손목 최대 민감 대역은 안쪽 100~275Hz(200Hz 정점), 바깥쪽 75~250Hz(125Hz 정점)로 보고된다.
- **보행 중** — 시간적으로 떨어진 이산 진동은 보행 위상 게이팅의 영향을 받지 않았고, 허리가 보행 중 선호 부위로 제시되었다. 발은 부적합하다.

**설계로 옮기면** `[추론]`

1. **정지 상태에서 잰 식별률을 안무 중 성능으로 일반화하면 안 된다.** 실험은 정지 / 보행 / 실제 안무 세 조건으로 나눈다.
2. **이산 펄스가 연속 진동보다 유리하다.** 보행 위상 게이팅의 영향이 적다는 보고와 지속 진동의 둔감화가 같은 방향을 가리킨다.
3. 손목은 나쁘지 않은 부위다. **Watch를 손목 안쪽으로 착용**하면 민감도가 올라갈 여지가 있다. 무용 동작·의상과 함께 확인한다. `[미확인]`

## A3. 가장 가까운 선행 시스템 `[선행]` `[미확인]`

- **시각장애인 포용 무용 지원 시스템** (ROBOMECH Journal, 2025) — 모션캡처가 무용 구역을 덮고 사용자·파트너·벽의 위치를 잡아 **햅틱 조끼로 세 패턴(위치 신호 / 정지 신호 / 무용 동작 신호)** 을 전달한다. 파트너에게 접근시킨 뒤 일정 거리에서 정지시킨다. **우리 프로젝트와 구조가 가장 가깝다.** 본문 전문을 확보하지 못해 진동 파라미터·거리 임계값·정확도는 미확인이다.
- **Dance Haptics** (Deakin Motion.Lab) — 무용을 볼 수 없는 관객에게 8×8 = 64개 진동자를 깐 좌석 쿠션으로 전달. 목적은 다르지만 **다중 액추에이터가 있으면 공간 인코딩이 가능하다**는 대조군이다.
- **열 촉각 지팡이 특허** (US11684537B2) — 4방향 펠티어 모듈. 보행 정확도 91.66%, 냉자극 응답 시간 **2.54초.** 열 자극은 우리에게 느리다는 근거로 쓴다.

**공통 관찰** `[추론]` — 앞선 시스템은 거의 전부 **다중 진동자**를 쓴다. Apple Watch 한 대만 쓰는 우리 구성은 선행 사례보다 출력 대역이 좁다. 이 격차를 리듬 설계와 신호 개수 축소로 메울 수 있는지가 R08의 실질적 질문이다.

## A4. 설계안 세 가지

공통 표기 — `·` 는 탭 1회, 간격은 B1.3에 따라 100ms 이상.

### 안 A · 이산 방향 지시 (Discrete Turn)

| 의미 | 패턴 |
|---|---|
| 왼쪽 | `··  ··  ··` (2탭 3쌍) |
| 오른쪽 | `· · · · · ·` (균일 연타) |
| 직진·계속 | 없음 |
| 정지 | `failure` 계열 단일 |
| 도착 | `success` 계열 단일 |

**장점** — 기존 사용자가 아는 문법. 신호가 드물어 피로가 적다.
**단점** — **패턴이 길다.** 좌우 판정에 1초 내외가 들고 그만큼 지시가 늦는다. 이동 중 오차를 실시간으로 보정하지 못한다.

### 안 B · 근접 박동 (Proximity Pulse)

거리를 반복 간격으로 표현한다. 세기를 쓸 수 있다고 확인되면(E6-2) 간격 대신 세기로 표현하는 변형도 가능하다.

| 남은 거리 | 간격 |
|---|---|
| 멀다 | 1500ms마다 1탭 |
| 중간 | 800ms마다 1탭 |
| 가깝다 | 300ms마다 1탭 |
| 도착 | 전용 패턴, 반복 중단 |

**장점** — 거리감이 연속적으로 전해지고 학습이 쉽다.
**단점** — **방향을 못 싣는다.** 별도 좌우 신호와 섞으면 두 층이 서로를 가린다. **계속 울린다** — 촉각 둔감(A2)과 배터리(B1.3) 양쪽에 불리하다.
**치명적 문제** — 원문 R08이 지적한 **"강한 신호 하나가 목표 근접과 위험 근접을 동시에 뜻하는"** 함정에 정확히 빠진다. 빠른 박동이 "다 왔다"인지 "낭떠러지다"인지 구분되지 않는다.

### 안 C · 통로 유지 (Corridor / Null-zone) — **첫 검증 후보**

목표를 향하는 방향에 허용각 통로를 두고 **통로 안이면 침묵한다.**

| 상태 | 패턴 |
|---|---|
| 통로 안(정상 진행) | **무진동** |
| 왼쪽으로 벗어남 | `··` 를 벗어난 정도에 따라 1200 / 600 / 300ms 간격 반복 |
| 오른쪽으로 벗어남 | `·` 를 같은 간격 체계로 반복 |
| 도착 | `success` 1회, 반복 중단 |
| 정지·안내 불가 | `failure` 계열 긴 단일 + 반복 |
| 생존 신호 | 4~5초마다 아주 약한 `click` 1회 |

**장점** — 정상 상태에서 아무것도 울리지 않아 **피로·둔감·배터리 모두 유리하다.** 벗어난 정도가 곧 긴급도가 되어 의미가 하나로 맞아떨어진다. 좌우가 탭 개수(1 대 2)로만 갈려 판정이 빠르다.
**단점** — **"침묵"이 "정상"과 "고장"을 동시에 뜻한다.** 유일한 치명 약점이며 생존 신호로 막아야 한다(A5.3).

### 권고 `[추론]`

**안 C를 주 설계로, 안 A의 도착·정지 신호를 그대로 빌려 쓴다.** 안 B는 통로 안쪽 근거리에서만(예: 도착 3m 이내) 보조적으로 검토한다.

무용수가 외울 의미는 **왼쪽 / 오른쪽 / 도착 / 정지 네 가지**다. A1.2의 4~5개 상한 안에 들어온다.

## A5. 신호를 안전하게 만드는 규칙

### A5.1 목표 근처에서 좌우가 뒤집히지 않게 한다

목표에 가까워지면 위치 추정의 작은 흔들림만으로 좌·우 판정이 계속 뒤집힌다. 제어공학의 **불감대(deadband)** 와 **이력(hysteresis)** 이 표준 대응이다. 불감대는 출력을 바꾸지 않는 입력 구간이고, 이력은 진입 임계와 이탈 임계를 다르게 두는 것이다.

우리 설계로는 세 겹이다. `[추론]`

1. **각도 불감대** — 통로 반각 이내면 침묵. 반각은 위치 추정 오차(R02)와 함께 정한다.
2. **도착 이력** — 도착 판정 반경(들어갈 때)보다 이탈 판정 반경(나갈 때)을 크게 잡는다. 경계에서 도착 신호가 반복되는 것을 막는다.
3. **최소 유지 시간** — 방향 지시를 바꾸기 전에 새 판정이 일정 시간 이상 유지되어야 한다. 100ms 하한과 무관하게, 사람이 반응할 시간을 감안해 훨씬 길게 잡는다.

### A5.2 신호 사이에 우선순위를 정한다 `[추론]`

한 번에 하나만 내보낸다.

```
1순위   정지 · 위험 (제외 구역 접근, 추적 상실, 통신 상실)
2순위   도착
3순위   방향 보정 (좌 / 우)
4순위   생존 신호
```

순위가 낮은 신호는 높은 신호가 울리는 동안 **버린다. 큐에 쌓아 두었다가 나중에 내보내지 않는다.** 100ms 하한 때문에 쌓인 신호는 반드시 늦게 도착하고, **늦은 지시는 틀린 지시다**(R10의 유효 시간 항목과 같은 원칙).

### A5.3 침묵이 안전을 뜻하지 않게 한다

안 C의 약점이자 R11이 이미 지적한 문제다 — *"아무 신호가 없다는 사실이 안전하다는 뜻이 되지 않도록 한다."*

- **생존 신호** — 정상 상태에서도 4~5초에 한 번 아주 약한 탭을 낸다. 무용수는 이것이 끊기면 시스템이 죽은 것임을 안다.
- **Watch 쪽 자체 감시** — iPhone에서 오는 갱신이 일정 시간 없으면 **Watch가 스스로** 안내 중단 신호를 낸다. 연결이 끊긴 뒤 iPhone이 보내는 정지 신호는 도착하지 않는다.
- **AirPods를 보조로 쓴다면 같은 문제가 더 나쁘다** — 자동 귀 감지로 한쪽이 빠지면 안내가 조용히 멈춘다(B2.6). 착용 상태를 앱이 감지해 운영자에게 알려야 한다.
- 생존 신호의 주기와 강도는 실험으로 정한다. 너무 잦으면 둔감해지고 너무 드물면 고장 감지가 늦다. `[미확인]`

### A5.4 목표는 큐가 정한다

가장 가까운 저장 지점을 자동으로 고르면 공연 순서와 어긋난다. 신호 계층은 "현재 큐가 지정한 목표"만 본다. 목표 선택은 R05·R06 소관이고, **R08은 주어진 목표와 현재 위치의 차이만 신호로 바꾼다.**

---

# Part B · R09 — 출력 장치의 실제 범위

## B1. Apple Watch 햅틱

### B1.1 쓸 수 있는 패턴 목록 `[문서]`

`WKHapticType` 전체 (watchOS 2.0 도입, 이후 추가분 포함):

| 케이스 | 도입 | 문서상 의미 | 우리 앱에서의 가용성 |
|---|---|---|---|
| `notification` | watchOS 2.0 | 앱이 포그라운드가 아닐 때 도착한 알림 | 의미 충돌 위험 |
| `directionUp` | 2.0 | 값 상승·임계 초과 | 가용 |
| `directionDown` | 2.0 | 값 하강·임계 미만 | 가용 |
| `success` | 2.0 | 작업의 성공적 완료 | **도착 신호 후보** |
| `failure` | 2.0 | 작업의 실패 | **중단·위험 신호 후보** |
| `retry` | 2.0 | 일시 실패, 재시도 | 재안내 후보 |
| `start` | 2.0 | 동작의 시작 | 출발 신호 후보 |
| `stop` | 2.0 | 동작의 끝 | 정지 신호 후보 |
| `click` | 2.0 | 경로 위 고정 지점 표시 | **패턴 구성의 기본 단위** |
| `navigationGenericManeuver` | 7.0 | 새 내비게이션 단계 | 조건부 |
| `navigationLeftTurn` | 7.0 | 좌회전 | 조건부 |
| `navigationRightTurn` | 7.0 | 우회전 | 조건부 |
| `underwaterDepthPrompt` | 9.0 | (문서에 설명 없음) | 해당 없음 |
| `underwaterDepthCriticalPrompt` | 9.0 | (문서에 설명 없음) | 해당 없음 |

**navigation 3종의 조건**: 세 케이스 모두 문서에 같은 문장이 붙는다 — *"You can only use this haptic type when your app is running a continuous background location session."* 실내 무대에서 지속 위치 세션을 유지하는 것은 우리 구조(고정 iPhone이 위치를 계산하고 Watch는 받기만 한다)와 맞지 않는다. **좌·우 전용 패턴은 기본 설계에서 빼고, 쓰려면 위치 세션 조건부터 검증한다.**

**`click` 의 설명이 중요하다** — *"Use this haptic to mark fixed points along a path. Space out the intervals at which you play the haptic rather than playing it several times in quick succession."* 경로 위 지점 표시용으로 설계된 유일한 케이스이면서, 동시에 "빠르게 연속으로 치지 말라"는 경고가 붙어 있다.

### B1.2 세기 — 첫 버전의 서술을 정정한다 `[문서]`

> **이 문서의 첫 버전은 "세기를 전혀 못 바꾼다"고 적었다. 과한 서술이었다.** Core Haptics가 watchOS에 없다는 사실만 보고 내린 결론이었고, SwiftUI `SensoryFeedback` 에 세기 파라미터가 있다는 것을 빠뜨렸다.

| 무엇 | 확인된 사실 |
|---|---|
| **Core Haptics** (`CHHapticEngine`) — 임의 파형·이어지는 진동·세기 곡선 | 지원 플랫폼은 iOS 13 / iPadOS 13 / Mac Catalyst 13 / macOS 10.15 / tvOS 14 / visionOS 1. **watchOS가 없다.** 이건 그대로다 |
| **SwiftUI `SensoryFeedback.impact(weight:intensity:)`** | **watchOS 10.0부터 있다.** `intensity: Double = 1.0` 을 받고, 무게(`light`·`medium`·`heavy`)와 재질(`rigid`·`soft`·`solid`)도 고를 수 있다. 문서가 *"Only plays feedback on iOS and watchOS"* 라고 명시한다 |
| 그 값이 **실제로 세기를 바꾸는가** | ⚠️ **문서가 보장하지 않는다** — *"Not all platforms will play different feedback for different weights and intensities of impact."* |
| `SensoryFeedback` 의 범위 | `WKHapticType` 보다 넓다. watchOS 전용 케이스(`.increase`·`.decrease`)가 따로 있고, 무게×재질×세기 조합이 가능하다 |

**정확한 진술은 이렇다** — 임의 파형과 이어지는 진동은 못 만든다. **세기는 지정할 수 있으나, 손목이 그 차이를 구분하는지는 재봐야 안다.**

#### "애플 지도는 거리에 따라 진동이 강해진다"는 이야기 `[미확인]`

**아직 근거를 못 찾았다.** Apple 지원 문서가 적는 것은 좌/우를 가르는 탭 패턴과 *"마지막 구간에서 진동을 느끼고, 도착할 때 다시 느낀다"* 뿐이다. **거리에 따라 세기가 자동으로 변한다는 서술은 Apple 문서에 없다.**

그렇다고 사실이 아니라는 뜻은 아니다. 세 가지가 가능하다.

1. **문서화되지 않은 시스템 앱 동작이다.** Apple 자사 앱은 공개 API 밖의 것을 쓸 수 있다 — 그런 경우 **우리가 따라 만들 수 없다**
2. **세기가 아니라 알림이 오는 시점·횟수의 차이다.** 예고 알림 한 번 → 회전 직전 알림 한 번이 점점 강해지는 것처럼 느껴질 수 있다
3. **실제로 `SensoryFeedback` 이 하는 일을 지도도 하고 있다.** 그러면 우리도 같은 것을 할 수 있다

**어느 쪽인지는 눈으로 확인할 수 있다.** 실험 **E6-2**로 올렸다.

참고로 watchOS 10부터 iPhone의 Watch 앱 → 지도 → **Turn Alerts** 에서 이동 수단별(운전 · CarPlay 운전 · 걷기 · 자전거)로 회전 알림을 조절할 수 있다. 다만 이건 사용자가 미리 고르는 것이지 주행 중에 자동으로 변하는 것이 아니다.

### B1.3 연속 호출에는 100ms 하한이 있다 `[문서]`

`WKInterfaceDevice.play(_:)` 문서의 요지:

- *"Do not call this method multiple times in quick succession."*
- 이미 햅틱이 울리는 중에 호출하면 **시스템이 현재 피드백을 중단하고, 새 피드백 전에 최소 100밀리초의 지연을 강제한다.**
- 햅틱 엔진 사용은 전력을 소모하며 과용하면 배터리와 사용자 경험 모두에 나쁘다.
- *"Do not call this method while gathering heart rate data using HealthKit."* — 햅틱 엔진이 돌면 HealthKit의 심박 수집이 멈춘다.

**설계로 옮기면** — 우리가 쓸 수 있는 패턴 문법은 `[탭] [간격] [탭] [간격] …` 이고 간격의 하한은 100ms다. "빠른 2탭"과 "아주 빠른 2탭"은 구분되지 않는다. 패턴 사이의 최소 구별 간격은 실기기에서 재야 한다. `[추론]` `[미확인]`

심박 경고는 B1.5의 워크아웃 세션 안과 정면으로 충돌한다. 백그라운드 실행을 워크아웃 세션으로 얻으면 심박 수집이 따라오고, 그 위에서 햅틱을 계속 치게 된다. 어느 쪽이 밀리는지 실기기 확인이 필요하다. `[미확인]`

### B1.4 세기는 사용자 설정이 정한다 `[문서]`

- 설정 → 소리 및 햅틱 → **햅틱: 기본 / 강하게(Prominent) / 끔.** "강하게"는 일부 알림 앞에 **예고 탭을 하나 더 붙인다** — 즉 우리 패턴의 탭 개수가 달라질 수 있다.
- **햅틱 강도 슬라이더**로 세기를 조절한다.
- **무음 모드에서도 손목 탭은 남는다** — Apple 지원 문서: *"You can still receive haptic notifications."*
- **손바닥으로 화면을 덮으면 알림이 무음 처리된다(Cover to Mute).** 제스처 설정에서 켜고 끈다.

**설계로 옮기면** `[추론]`

1. 공연 전 운영 절차에 **"햅틱 = 기본, 강도 = 고정값, 무음 모드 = 켬"** 설정 확인이 들어가야 한다. 설정이 다르면 같은 신호가 다르게 느껴진다.
2. **무음 모드는 선택이 아니라 필수다.** HIG는 watchOS가 햅틱에 소리를 결합한다고 적는다 — *"the Taptic Engine generates haptics for a number of built-in feedback patterns, which watchOS combines with an audible tone."* 안내음이 객석으로 새면 안 된다.
3. **Cover to Mute는 위험 요소다.** 무용 동작 중 손바닥이 화면을 스치면 알림이 꺼질 수 있다. 우리 앱 햅틱에도 적용되는지 확인이 필요하다. `[미확인]`

### B1.5 손목을 내리면 멈춘다 `[문서]`

`play(_:)` 는 앱 상태가 비활성·백그라운드면 **아무 효과가 없다.** 문서가 인정하는 예외는 활성 워크아웃 세션뿐이다.

대안은 `WKExtendedRuntimeSession` — *"your app continues to run after the user stops interacting with it … or play sounds or haptics, even after the watch's screen turns off."*

| 세션 종류 | 실행 방식 | 예약 가능 | **시간 제한** |
|---|---|---|---|
| Self care | 최전면(frontmost) | 아니오 | **10분** |
| Mindfulness | 최전면 | 아니오 | **1시간** |
| Physical therapy | **백그라운드** | 아니오 | **1시간** |
| Smart alarm | 백그라운드 | 예 | 30분 |

**설계로 옮기면** `[추론]`

- 확장 실행 세션 중 무대에 맞는 것은 **Physical therapy(백그라운드, 1시간)** 하나다. 최전면 세션은 무용수가 팔을 움직이는 동안 앱이 앞에 떠 있어야 하므로 취약하다.
- 세션 재시작은 앱이 포그라운드일 때만 가능하다(`start()` 는 포그라운드 전용).
- 문서는 **CPU 사용이 높으면 시스템이 세션을 취소할 수 있다**고 경고한다. Watch는 받아서 울리기만 하고 계산은 iPhone이 하는 구조가 맞다.
- 세션 종류를 "앱의 의도된 용도에 맞춰" 고르라는 지시가 있다. 무대 안내 앱이 physical therapy를 선언해 심사를 통과하는지는 미확인이다. `[미확인]`

#### 그런데 길이 하나 더 있다 — 워크아웃 세션 `[문서]`

> **이 문서의 첫 버전은 "1시간 제한이 공연 길이의 상한을 정한다"고 적었다.** 확장 실행 세션만 보고 내린 결론이었고, **워크아웃 세션이라는 별도 경로를 빠뜨렸다.**

Apple 공식 문서(Running workout sessions)가 적는 것:

- *"Apps with an active workout session can run in the background."*
- *"Workout sessions require the Workout processing background mode. **If your app plays audio or provides haptic feedback during the workout session, you must also add the Audio background mode.**"*
- *"Workout apps can use the AVFoundation framework to play **short audio clips in the background**, such as coaching or notifications."*

즉 **워크아웃 세션 중에는 백그라운드 햅틱과 짧은 안내음이 둘 다 공식적으로 가능하다.** 문서에 시간 제한이 명시되지 않는다(2차 자료는 8시간을 언급한다 `[선행]` `[미확인]`).

대신 대가가 넷이다. `[문서]`

| 대가 | 내용 |
|---|---|
| **심박 수집이 따라온다** | 문서: *"All workout sessions generate high-frequency heart rate samples."* 그런데 `play()` 문서는 **심박 수집 중 햅틱을 치지 말라**고 경고한다 → 🔴 **이 충돌이 진짜 쟁점이다. E5에서 가장 먼저 잰다** |
| **운동 기록이 남는다** | 무용수의 활동 링과 건강 기록이 공연마다 오염된다. 당사자 동의가 필요하다 |
| **사용자에게 알려야 한다** | 문서: *"The app must clearly indicate when a workout session is in progress."* → 심사 문제 소지 |
| **한 번에 하나뿐** | 다른 앱이 워크아웃을 시작하면 우리 세션이 끝난다 |

**정리하면** `[추론]` — 공연이 1시간을 넘어도 **길이 막힌 것은 아니다.** 다만 워크아웃 경로는 심박·기록·심사 세 부담을 다 지고 간다. **먼저 공연 길이를 물어보고, 1시간 안이면 확장 실행 세션을 쓰는 것이 깔끔하다.**

### B1.6 Watch 두 대로 좌우를 만들 수는 없다 `[문서]`

`WCSession` 문서 — *"When automatic switching is enabled, only one Apple Watch at a time actually communicates with the iOS app."*

iPhone 하나에 여러 Watch를 페어링할 수는 있어도(iOS 9.3+ / watchOS 2.2+), **iOS 앱과 실제로 통신하는 Watch는 한 번에 하나**다. 전환이 일어나면 iOS 앱 세션이 비활성·해제 상태를 거친다.

**따라서 좌우는 공간이 아니라 시간(리듬)으로 표현한다.** R08 설계의 가장 큰 제약이다.

> **다만 첫 버전은 여기서 한 걸음 더 나가 "여러 무용수에게 각각 다른 신호를 보내는 것도 같은 제약에 걸린다"고 적었다. 그건 과했다.** WatchConnectivity가 아닌 경로가 있다.

**Watch 앱은 `URLSession` 으로 직접 네트워크 통신을 할 수 있다.** watchOS 2부터 Wi-Fi로, Series 3 셀룰러부터는 셀룰러로도 된다. 고정 iPhone이 로컬 네트워크로 여러 Watch에 각각 다른 신호를 뿌리는 구조는 **원리적으로 가능하다.** `[선행]`

⚠️ 그런데 개발자 보고가 좋지 않다 — **iPhone이 범위 안에 있으면 요청이 iPhone을 거쳐 프록시되고**, 그 과정에서 연결이 안 된다는 사례가 여럿 올라와 있다. 무대처럼 iPhone이 바로 옆에 있는 환경이 딱 그 조건이다.

**정확한 결론은** `[추론]` — 한 명은 WatchConnectivity로 충분하다. **여러 명은 로컬 네트워크로 가야 하고, 그건 별도 설계와 실측이 필요한 일이다**(R10과 함께 볼 것).

---

## B2. AirPods · 공간 음향

### B2.1 공간 음향은 iPhone에서만 만들 수 있다 `[문서]`

`AVAudioEnvironmentNode` 플랫폼: **iOS 8.0 / iPadOS 8.0 / Mac Catalyst 13.1 / macOS 10.10 / tvOS 9.0 / visionOS 1.0.** watchOS는 없다.

즉 **Watch가 직접 공간 음향을 만들어 AirPods로 보낼 수 없다.** 오디오 안내를 쓰려면 iPhone이 소리를 만들고 AirPods로 내보내는 경로가 된다. 무용수가 iPhone을 지녀야 하는지, 아니면 고정 iPhone이 직접 AirPods와 연결되는지는 R10의 연결 구조 문제와 묶인다.

### B2.2 기본 설정은 3D가 아니다 `[문서]`

`AVAudio3DMixingRenderingAlgorithm` 의 선택지:

| 알고리즘 | 문서상 설명 | CPU |
|---|---|---|
| `equalPowerPanning` | 믹서 버스를 스테레오 필드로 패닝. 믹싱 콘솔의 팬 노브와 같다 | 가장 쌈 |
| `sphericalHead` | 양이 시간차 등 공간 단서를 모사 | HRTF보다 쌈 |
| `HRTF` | 필터링으로 헤드폰에서 3D 공간을 모사 | 비쌈 |
| `HRTFHQ` | HRTF 대비 주파수 응답과 정위 개선 | 가장 비쌈 |
| `auto` (iOS 13+) | 현재 재생 하드웨어에서 가능한 최고 품질을 자동 선택 | — |

**기본값은 `equalPowerPanning` 이다.** 즉 아무 설정도 하지 않으면 우리가 얻는 것은 3D가 아니라 **좌우 팬**이다. "공간 음향을 쓴다"는 말이 저절로 방향 안내가 되지 않는다.

두 가지 제약이 더 있다. `[문서]`

- **모노 입력만 공간화된다.** 문서 원문 — *"Spatialization applies only to inputs with a mono channel connection format. This class doesn't spatialize stereo inputs."* 안내 음원은 반드시 모노로 준비해야 한다.
- **청취자의 위치와 방향은 앱이 직접 넣어야 한다.** `listenerPosition` 과 `listenerAngularOrientation` 을 우리가 갱신하지 않으면 음원은 고정된 가상 위치에 머문다. 기본 방향은 −z축을 바라보는 상태이며 yaw·pitch·roll 모두 0이다.

#### 그런데 시스템이 따로 공간화를 걸 수도 있다 `[선행]`

iOS 15부터 **공간 음향 변환(Spatialize Stereo)** 이 있다. 돌비 애트모스가 아닌 평범한 스테레오 소리도 **시스템이 공간화하고 헤드 트래킹까지 입힌다.** 즉 우리가 `AVAudioEnvironmentNode` 를 쓰지 않아도 공간감이 생길 수 있다.

이건 양날의 검이다. `[추론]`

- 좋은 면 — 공짜로 공간감을 얻을 수도 있다
- 나쁜 면 — **우리가 의도한 방향과 시스템 처리가 부딪힐 수 있다.** 그리고 이건 **사용자가 제어 센터에서 켜고 끄는 것**이라 앱이 고정할 수 없다

**실험 E7에서는 이 설정을 반드시 기록하고 고정한다.** 안 그러면 어느 쪽이 낸 방향감인지 모른다.

**설계로 옮기면** — 무대 좌표의 목표 지점에 소리를 "고정"하려면 세 가지가 동시에 맞아야 한다. ① 무용수의 무대 위 위치(R02·R04) ② 무용수의 머리 방향 ③ 이 둘을 환경 노드의 청취자 좌표계로 옮기는 정렬. **하나라도 틀리면 소리는 엉뚱한 쪽에서 들린다.** `[추론]`

### B2.3 머리 방향은 받을 수 있지만 몸 방향은 아니다 `[문서]`

`CMHeadphoneMotionManager` — **iOS 14.0 / iPadOS 14.0 / Mac Catalyst 14.0 / macOS 14.0 / watchOS 7.0.**

- 사용 전 `isDeviceMotionAvailable` 확인이 필요하다.
- **`NSMotionUsageDescription` 키가 Info.plist에 없으면 시스템이 앱을 크래시시킨다.** 문서가 IMPORTANT로 명시한다.
- `CMHeadphoneMotionManagerDelegate` 로 헤드폰 연결·해제를 감지한다. 원격 기기에서 스트리밍되므로 연결 상태 추적이 필수다.

지원 기기와 갱신 주기 `[선행]` — AirPods Pro(1·2세대), AirPods(3세대 이상), AirPods Max, Beats Fit Pro. 갱신은 초당 약 25회로 보고된다(비공식). Apple의 공간 음향 설정은 **끔 / 고정(Fixed) / 헤드 트래킹(Head Tracked)** 세 모드이며, 지원 모델로 AirPods 3·4·5, AirPods Pro, AirPods Max가 안내된다.

**백그라운드 제약** `[선행]` `[미확인]` — 앱이 백그라운드로 가면 헤드폰 모션 갱신이 멈춘다는 개발자 보고가 있다. Motion & Fitness 백그라운드 모드가 필요하다는 언급이 있으나 공식 문서에서 확인하지 못했다.

**가장 중요한 구분** `[추론]` — 헤드폰이 주는 것은 **머리의 자세**다. 이것은 다음 어느 것과도 같지 않다.

- 무대 위의 **절대 위치** — 헤드폰은 위치를 모른다.
- **몸통의 방향** — 무용수는 몸은 그대로 두고 고개만 돌릴 수 있다. 무용에서는 오히려 흔한 동작이다.
- **이동 방향** — 옆걸음·뒷걸음에서는 셋이 모두 다르다.

R04의 방향 기준 문제와 정확히 같은 지점이며, **공간 음향을 쓰는 순간 이 문제가 필수 선결 조건이 된다.** 햅틱은 "무대 기준 학습된 신호"로 이 문제를 우회할 수 있지만 공간 음향은 우회할 수 없다.

### B2.4 정위 정확도에는 한계가 있다 `[선행]`

⚠️ **먼저 밝혀 둘 것** — 아래 수치는 **AirPods를 가지고 잰 것이 아니다.** 일반적인 HRTF 공간 음향 연구의 값이다. Apple의 개인화 프로파일과 H칩 처리가 들어간 AirPods가 이보다 나을 수도, 못할 수도 있다. **우리 조건의 값은 E7로 직접 잰다.**

- **비개인화 HRTF는 정위 오차가 크고 앞뒤 혼동이 늘어난다.** 특히 정중면에서 그렇다.
- 실제 음원을 머리 움직임과 함께 정위할 때의 평균 각도 오차가 연구에 따라 **16.3° ~ 21.6°** 로 보고된다.
- 앞뒤 혼동은 보통 기준선에서 **40~45° 이내 편차**를 기준으로 판정한다.
- **동적 청취(머리를 움직이며 듣기)는 정위 정확도를 크게 높이고 앞뒤 혼동을 줄인다.** 동시에 개인화 HRTF의 이점을 줄인다.
- 최적화된 비개인화 HRTF로 정위 오차가 22% 줄고 청취자의 65%가 앞뒤 혼동을 줄였다는 보고가 있다.

Apple은 iOS 16부터 **개인화 공간 음향**을 제공한다 — iPhone 카메라로 얼굴과 양 귀를 스캔해 HRTF 프로파일을 만들고 같은 Apple 계정의 기기에 동기화한다. `[선행]`

**설계로 옮기면** `[추론]`

1. **무대 이동 안내에 앞뒤 구분이 필요하면 공간 음향만으로는 위험하다.** 20° 내외의 오차는 무대 몇 미터 거리에서 상당한 위치 오차가 된다.
2. 무용수는 춤추며 머리를 계속 움직이므로 동적 청취 조건이 저절로 만족된다. 이는 유리한 점이다.
3. **개인화 프로파일 설정을 운영 절차에 넣는다.** 당사자별로 한 번 하면 되는 일이다.
4. 좌·우만 구분하면 되는 설계라면 오차 20°는 감당할 만하다. **앞·뒤를 소리로 구분하려 들지 않는 것이 안전하다.**

### B2.5 오디오는 느리다 `[선행]` `[문서]`

⚠️ 아래 수치는 **Apple 공식 발표가 아니라 제3자 측정 사이트의 값**이다. 통신 환경·OS 버전·마이크 사용 여부에 따라 달라진다고 적혀 있다. 범위를 가늠하는 데만 쓰고, **우리 숫자는 E8로 잰다.**

블루투스 출력 지연 보고값:

| 기기 | 보고된 지연 |
|---|---|
| AirPods Pro 2 / Pro 3 (AAC, iPhone) | 80 ~ 160 ms |
| AirPods Max (AAC) | 100 ~ 180 ms |
| AirPods 3세대 | 180 ~ 220 ms |

`AVAudioSession.outputLatency` 로 조회할 수 있으나 `[문서]`, 개발자 포럼에는 **실제 지연이 예측값과 다르고 시간에 따라 변한다**는 보고가 있다 `[선행]` `[미확인]`.

이것은 **출력 단계만의 지연**이다. 전체 경로는 촬영 → 위치 추정 → 판단 → 전송 → 출력이며, AirPods를 쓰면 마지막 단계에서만 0.1~0.2초가 더해진다. `[추론]`

### B2.6 한쪽이 빠지면 안내가 조용히 멈춘다 `[선행]`

**자동 귀 감지(Automatic Ear Detection)** — AirPods 한쪽을 빼면 재생이 일시정지되고, 양쪽을 빼면 정지한다.

무용 중 한쪽이 빠지면 **안내가 소리 없이 사라진다.** 무용수는 "안내가 없다"를 "가만히 있으라"로 오해할 수 있다.

**더 나쁜 시나리오가 있다.** `[선행]` 양쪽을 다 빼면 AirPods가 연결을 끊고 **오디오가 iPhone 스피커로 넘어간다는 보고가 있다.** 그러면 조용히 멈추는 것이 아니라 **안내음이 객석으로 터져 나온다.** 공연 중에는 이쪽이 훨씬 심각하다.

⚠️ 위 동작은 음악·영상 같은 **미디어 재생**에 대해 알려진 것이다. 우리가 직접 만드는 **짧은 안내음에도 같이 적용되는지는 확인하지 못했다** → 실험 E9.

설정에서 끌 수 있지만, 그러면 빠진 AirPods에서 소리가 계속 나가 객석에 샐 수 있다. **어느 쪽으로도 깔끔하지 않다.** 이것이 공연 중 주 출력을 AirPods로 두기 어려운 가장 실제적인 이유다. `[추론]`

### B2.7 공연 음원과 안내음 나누기 — 서술을 정정한다 `[문서]` `[선행]`

> **이 문서의 첫 버전은 "iOS는 서로 다른 스트림을 여러 출력으로 동시에 라우팅하지 못한다"고 단정했다. 틀렸다.** 그런 카테고리가 있다.

`AVAudioSession.Category.multiRoute` 의 문서 설명 — *"The category for routing distinct streams of audio data to different output devices at the same time."* iOS 6부터 있었다.

다만 조건이 까다롭다.

| 조건 | 내용 |
|---|---|
| 적격 출력 포트 | USB 오디오 · 라인아웃 · **유선** 헤드폰 · HDMI · 내장 스피커. ⚠️ **블루투스는 이 목록에 없다** → AirPods에는 안 될 가능성이 높다 (2차 자료 기준, 확인 필요) |
| 내장 스피커 | 다른 적격 포트가 연결되지 않았을 때만 쓸 수 있다 |
| 구현 난이도 | 문서가 *"사용 가능한 오디오 경로에 대한 더 상세한 지식과 상호작용이 필요하다"* 고 적는다. 경로가 바뀌면 설정이 무효화되므로 `routeChangeNotification` 을 반드시 관찰해야 한다 |

**그래서 무엇이 달라지나** `[추론]`

- **AirPods로는 여전히 어렵다.** 블루투스가 적격 포트 목록에 없다
- **그러나 유선 이어폰이나 USB 오디오 인터페이스라면 가능할 수 있다.** 공연장 음향 장비와 연동하는 경로가 오히려 열려 있다는 뜻이다
- R06 후보 B(앱이 공연 음원을 직접 재생)는 **불가능한 것이 아니다.** 출력 장치 조합에 따라 갈린다

**R06 담당에게 넘길 것** — "불가능"이 아니라 **"출력 장치가 무엇인가에 달렸다"** 가 맞는 결론이다. 현장에 **USB 오디오 인터페이스나 유선 경로가 있는지** 먼저 물어야 한다.

### B2.8 AirPods는 무용수가 들어야 할 소리를 가린다 `[추론]`

가장 근본적인 문제다. 무용수는 음악·대사·다른 공연자의 소리를 들으며 춤춘다. 귀를 막는 장치는 그 채널을 놓고 다툰다.

AirPods Pro의 주변음 허용(투명) 모드가 완화책이지만, 안내음과 음악이 같은 귀로 들어오는 상황 자체는 변하지 않는다. **햅틱의 최대 장점이 여기서 나온다 — 촉각은 청각과 다투지 않는다.** `[선행]` 시각장애 내비게이션 비교 연구에서 참가자들이 음성 안내보다 햅틱을 신뢰하게 되었다는 보고와도 방향이 같다.

---

## B3. 착용과 공연 조건 `[미확인]`

| 항목 | Apple Watch | AirPods |
|---|---|---|
| 빠짐 위험 | 낮음(스트랩) | **높음.** 격렬한 동작·머리 흔들기 |
| 빠졌을 때 | 즉시 드러남 | **조용히 안내가 멈춤**(B2.6) |
| 의상 간섭 | 소매, 착용 손목 | 머리 장식, 가발 |
| 파트너 접촉 | 손 맞잡기 동작에서 걸림 | 없음 |
| 땀·습기 | 접촉 저하 가능 | 빠짐 유발 |
| 소리 유출 | 무음 모드로 차단 | 빠지면 유출 |
| 음악 청취 방해 | **없음** | **있음** |

전부 당사자·선생님께 확인해야 하는 항목이다. 특히 **파트너와 손을 맞잡는 안무가 있는지**는 손목 착용 가부를 가른다.

---

## B4. 출력 장치 비교와 우선순위 제안

| | **Apple Watch 햅틱** | **AirPods 오디오** | (참고) iPhone Core Haptics |
|---|---|---|---|
| 세기·파형 제어 | 파형 불가. 세기는 ⚠️ 지정 가능하나 반영 미확인 | 가능 | 가능 (transient/continuous, sharpness/intensity) |
| 방향 표현 | 시간 패턴만 | 공간 음향으로 연속 가능(HRTF 명시 필요) | 시간 패턴만 |
| 방향 정확도 | 미확인 | 각도 오차 16~22°, 앞뒤 혼동 있음 | 미확인 |
| 출력 지연 | 미확인(전송 지연 별도) | **80~220 ms 추가** | 미확인 |
| 음악·대사 방해 | **없음** | **있음** | 없음 |
| 빠짐·이탈 | 낮음 | 높고, **조용히 멈춘다** | — |
| 백그라운드 지속 | 확장 런타임 세션 1시간 | 오디오 세션 | 앱 상태 제약 |
| 몸 방향 추정 필요 | **불필요**(무대 기준 학습 신호로 가능) | **필수** | 불필요 |
| 결론 | **주 출력 후보** | **보조**(학습·리허설·비상 음성) | 대안으로만 기록 |

### 제안 `[추론]`

**주 출력 = Apple Watch 햅틱. 보조 = AirPods 음성.**

근거는 네 가지다.

1. **음악을 가리지 않는다.** 공연이라는 맥락에서 이것이 가장 크다.
2. **몸 방향 추정 없이 시작할 수 있다.** 공간 음향은 R04의 방향 추정이 먼저 풀려야 쓸 수 있지만, 햅틱은 "무대 기준 학습된 신호"로 그것을 우회한다. **첫 통합 실험의 의존 항목이 하나 줄어든다.**
3. **빠짐이 조용한 실패로 이어지지 않는다.**
4. **지연이 한 단계 적다.**

AirPods를 버리는 것이 아니다. 다음 용도로는 오히려 낫다.

- **연습·학습 단계**: 신호의 뜻을 음성으로 설명하며 익히게 한다.
- **리허설**: 조력자의 말과 안내를 같이 듣는다.
- **비상 정지**: 촉각 신호를 놓쳤을 때의 이중화. 공연 중에는 아주 드물게만 울린다.

**메인 CS의 "AirPods 공간 음향"은 유지된다.** 다만 이번 조사 결과는 **공연 중 실시간 이동 안내의 주 채널로는 햅틱이 먼저**임을 가리킨다. 이 판단은 Part C의 E7·E8 실험 결과로 뒤집힐 수 있다.

---

# Part C · 실험 계획

모든 실험은 **카메라 없이** 시작한다. 운영자가 수동으로 신호를 보내 **신호 자체의 이해도만** 먼저 잰다. 기술 오차와 신호 이해 문제를 섞지 않기 위해서다.

## R08 계열

### E1 · 패턴 식별 (정지 상태)
- **조건** 무용수 착석 또는 기립 정지. 후보 신호 4종(좌·우·도착·정지) + 생존 신호.
- **절차** 짧은 학습(각 신호 5회 제시) → 무작위 순서 40회 제시.
- **측정** 식별 정확도, 반응 시간(신호 시작부터 구두 응답까지), 혼동 행렬.
- **통과 기준 초안** 식별 정확도 90% 이상. A1.2의 리듬 단독 93%를 참고한 값이며 당사자 요구로 다시 정한다.

### E2 · 동작 중 식별
- **조건** 같은 신호를 **정지 / 보행 / 실제 안무 동작** 세 조건에서 제시.
- **측정** 조건별 식별 정확도 하락폭, 놓친 신호 수.
- **목적** 촉각 억제(A2)의 실제 크기 측정. **E1 결과를 그대로 믿지 않기 위해 반드시 한다.**

### E3 · 음악 동반 조건
- **조건** E2의 안무 조건에 실제 공연 음원을 더한다. Watch 무음 모드 켬·끔 양쪽.
- **측정** 식별 정확도, **안내음이 객석 거리에서 들리는지**(무음 끔 조건), 음악 놓침 보고.

### E4 · 목표 도달 과제
- **조건** 평평한 연습실, 테이프로 표시한 목표 3개, 운영자가 통로 판정을 수동으로 대신한다(Wizard of Oz).
- **측정** 도착 오차(m), 도착 소요 시간, 안내 재요청 횟수, 조력자 개입 횟수, **좌우 지시 뒤집힘 횟수.**
- **목적** A5.1의 불감대·이력 값을 실제로 정한다.

## R09 계열

### E5 · 기기 상태·지속성 (Watch)
- **조건** 손목 내림 / 화면 꺼짐 / 앱 백그라운드 전환 / 확장 런타임 세션 사용·미사용 / Cover to Mute 켬·끔 / 햅틱 설정 기본·강하게 / 공연 길이 연속 운영(최소 20분, 목표 1시간).
- **측정** 상태별로 **실제로 햅틱이 나오는지 여부.** 배터리 소모, 발열, 세션 만료 시점, 세션 취소 발생.
- **가장 먼저 잴 것** 🔴 **워크아웃 세션의 심박 수집과 햅틱이 정말 충돌하는가.** `play()` 문서는 충돌한다고 경고하고 워크아웃 문서는 햅틱을 써도 된다고 한다(§B1.3, §B1.5). **어느 쪽이 맞는지가 공연 길이의 상한을 가른다.**

### E6-1 · 실기기 패턴 하한 측정
- **절차** `click` 을 간격 100 / 150 / 200 / 300 / 500ms로 n회 연속 호출하고 **실제로 몇 번 울리는지** 센다.
- **목적** 문서의 100ms 하한이 실기기에서 어떻게 나타나는지, 설계한 패턴이 재현되는지 확인.
- **주의** **이 결과가 나오기 전까지 §A4의 모든 패턴은 종이 위의 안이다.**

### E6-2 · 세기가 정말 달라지는가
- **절차**
  1. `SensoryFeedback.impact(intensity:)` 를 0.2 / 0.4 / 0.6 / 0.8 / 1.0 으로 무작위 제시하고 참가자가 강약을 맞힌다.
  2. 무게(`light`·`medium`·`heavy`)와 재질(`rigid`·`soft`·`solid`)도 같은 방식으로.
  3. **애플 지도로 실제 주행하며** 회전 전 진동이 거리에 따라 달라지는지 귀와 손목으로 확인한다. 달라진다면 세기인지 시점·횟수인지 구분해 기록한다.
- **측정** 구분 가능한 단계 수(0이면 세기는 못 쓰는 것) · 정지/보행/안무 조건별 차이 · 지도 진동의 변화 양상.
- **왜 중요한가** 세기를 쓸 수 있으면 **안 B(근접 박동)를 세기로 표현할 수 있고, 안 C의 이탈 정도를 간격과 세기 두 축으로 줄 수 있다.** 설계안이 바뀐다.

### E7 · 공간 음향 방향 정위 (AirPods)
- **조건** `AVAudioEnvironmentNode` + HRTF 명시. 모노 음원. 청취자 방향은 `CMHeadphoneMotionManager` 로 갱신. 개인화 공간 음향 프로파일 설정 전·후 비교.
- **절차** 무대 평면의 정해진 방향 8곳에 가상 음원을 두고 참가자가 손으로 방향을 가리킨다.
- **측정** **방향 지목 각도 오차**(중앙값·95백분위), **앞뒤 혼동률**, 정지 / 보행 / 안무 조건별 차이.
- **비교 기준** B2.4의 16~22° 보고값. 우리 결과가 이보다 나쁘면 공간 음향은 주 출력에서 제외한다.

### E8 · 종단 지연 실측 (햅틱 경로 대 오디오 경로)
- **절차** iPhone에서 고정 주기로 시험 명령을 내고, 각 경로의 실제 출력 시각을 기록한다. 카메라 처리 부하가 없는 조건과 있는 조건 양쪽.
- **측정** 경로별 **평균 지연과 최대 지연**, 지연의 흔들림, 누락 횟수, 재연결 뒤 밀린 신호의 출력 여부.
- **목적** B4의 우선순위 제안을 실제 숫자로 확인하거나 뒤집는다. **이 실험이 R09의 최종 판단 근거다.**

### E9 · 착용 견고성
- **조건** 실제 안무 동작 중 AirPods 착용 유지, Watch 착용 손목·안쪽 착용 비교, 의상 착용 상태.
- **측정** AirPods 이탈 횟수와 그때 안내가 멈춘 시간, Watch 신호 인지율의 착용 조건별 차이, 당사자의 불편 보고.
- **반드시 확인** 🔴 AirPods를 일부러 뺐을 때 **우리 안내음이 멈추는가, 아니면 iPhone 스피커로 나가는가**(§B2.6). 후자면 객석으로 새는 사고다.

## 공통 기록

리서치 카드 양식을 따른다. 시험 횟수·참가자·조건을 함께 남기고, **정지 상태에서만 잰 수치를 안무 중 성능으로 적지 않는다.** 평균만으로 판단하지 않고 95백분위와 최대값을 같이 남긴다.

---

# Part D · 아직 모르는 것 · 물어야 할 것

## D1. 실기기로만 알 수 있는 것 `[미확인]`

1. `play()` 연속 호출의 실제 최소 간격과 패턴 재현성 (E6-1)
1. **`SensoryFeedback.impact(intensity:)` 의 세기 차이를 손목이 구분하는가** — 문서가 보장하지 않는다 (E6-2). **이 답에 따라 설계안이 바뀐다**
1. 애플 지도의 회전 진동이 거리에 따라 달라지는지, 달라진다면 세기인지 시점인지
2. Cover to Mute가 우리 앱의 햅틱도 끄는지
3. 확장 런타임 세션 종류 선택이 App Store 심사를 통과하는지
4. 워크아웃 세션 사용 시 심박 수집과 햅틱의 충돌 양상
5. Watch를 손목 안쪽에 차면 식별률이 오르는지
6. `CMHeadphoneMotionManager` 가 앱 백그라운드에서 계속 동작하는지, 어떤 백그라운드 모드가 필요한지
7. AirPods 한쪽 착용 시 공간 음향의 동작
8. `AVAudioSession.outputLatency` 의 보고값이 실제 지연과 얼마나 다른지
9. 1시간 세션 한도에 걸리는 공연이 실제로 있는지, 있다면 중간 재시작이 무대 위에서 가능한지

## D2. 당사자·선생님께 물을 것

1. 공연 중 손목에 시계를 차는 것이 안무·의상상 가능한가. **파트너와 손을 맞잡는 동작이 있는가.**
2. 외워서 쓸 수 있는 신호 개수는 몇 개인가. 네 개(좌·우·도착·정지)가 많은가 적은가.
3. **정상일 때 아무 진동도 없는 것이 불안한가, 편한가.** (안 C의 수용성이 여기서 갈린다.)
4. 생존 신호(4~5초마다 약한 탭)가 안무 집중을 방해하는가.
5. 공연 중 AirPods를 낄 수 있는가. **음악을 귀로 직접 들어야 하는가, 스피커 소리만으로 되는가.**
6. 개인화 공간 음향 프로파일 설정(얼굴·귀 스캔)에 동의하는가.

## D3. 공연·음향 담당자께 물을 것

1. 공연 음원을 재생하는 기기와 프로그램은 무엇인가.
2. **안내음을 무용수 개인에게만 보내려면 별도 기기가 필요하다**(B2.7). 현장에 여분 기기를 둘 수 있는가.
3. 인이어 모니터 등 기존 개인 음향 장비가 이미 있는가. 있다면 그쪽이 AirPods보다 나은 경로일 수 있다.

## D4. 멘토께 물을 것

1. TrackPot의 햅틱 출력은 **어떤 API로 무엇을 시연했는가.** Core Haptics인가 `WKHapticType` 인가. 시연 기기가 iPhone인가 Watch인가.
2. "500m부터 진동이 점점 강해진다"는 사례의 실제 기기와 구현. Apple Watch에서 **끊기지 않는 세기 곡선은 만들 수 없지만 단계별 세기는 지정할 수 있다**(§B1.2). 어느 쪽을 본 것인지 확인이 필요하다.
3. AirPods 공간 음향의 기준 설정을 어떤 방법으로 했는가. 머리 방향과 무대 좌표를 어떻게 정렬했는가(B2.3).
4. 제안한 전체 흐름에서 실제로 돌려 본 부분과 아이디어인 부분의 경계.

---

# Part E · 참고 자료

## 공식 문서 — Watch 햅틱

- [WKHapticType](https://developer.apple.com/documentation/WatchKit/WKHapticType) — 케이스 전체 목록, navigation 3종의 지속 백그라운드 위치 세션 조건, `click` 의 간격 권고
- [WKInterfaceDevice.play(_:)](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:)) — 100ms 최소 지연, 백그라운드 제약, HealthKit 심박 경고
- [CHHapticEngine](https://developer.apple.com/documentation/corehaptics/chhapticengine) — 플랫폼 목록에 watchOS 없음
- [Core Haptics](https://developer.apple.com/documentation/corehaptics)
- [Using extended runtime sessions](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions) — 세션 종류별 시간 제한표
- [WKExtendedRuntimeSession](https://developer.apple.com/documentation/watchkit/wkextendedruntimesession)
- [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions) — 워크아웃 세션 중 백그라운드 햅틱·짧은 오디오 가능
- [SensoryFeedback](https://developer.apple.com/documentation/swiftui/sensoryfeedback) · [impact(weight:intensity:)](https://developer.apple.com/documentation/swiftui/sensoryfeedback/impact(weight:intensity:)) — watchOS 10부터, 세기 지정 가능하나 반영은 보장하지 않음
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession) — 다중 Watch 페어링 시 한 번에 하나만 통신
- [Playing haptics — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) — 표준 패턴을 문서상 의미대로 쓸 것, 과용 금지, 햅틱에 오디오 톤 결합
- [Adjust volume and haptics on Apple Watch](https://support.apple.com/guide/watch/adjust-brightness-text-size-sounds-haptics-apd62807a9f3/watchos) — 기본·강하게·끔, 햅틱 강도 슬라이더
- [Change the volume, audio, and haptic settings on your Apple Watch](https://support.apple.com/en-us/108368) — 무음 모드에서도 햅틱 유지, Cover to Mute

## 공식 문서 — 오디오·공간 음향

- [AVAudioEnvironmentNode](https://developer.apple.com/documentation/avfaudio/avaudioenvironmentnode) — watchOS 미지원, 모노 입력만 공간화, 암묵적 청취자
- [AVAudio3DMixingRenderingAlgorithm](https://developer.apple.com/documentation/avfaudio/avaudio3dmixingrenderingalgorithm) — HRTF · HRTFHQ · sphericalHead · equalPowerPanning · auto
- [AVAudio3DMixing.renderingAlgorithm](https://developer.apple.com/documentation/avfaudio/avaudio3dmixing/renderingalgorithm) — **기본값은 equalPowerPanning**
- [AVAudioEnvironmentNode.listenerAngularOrientation](https://developer.apple.com/documentation/avfaudio/avaudioenvironmentnode/listenerangularorientation) — 기본 방향과 각도 단위
- [CMHeadphoneMotionManager](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager) — iOS 14 / watchOS 7, `NSMotionUsageDescription` 누락 시 크래시
- [CMHeadphoneMotionManagerDelegate](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanagerdelegate) — 연결·해제 감지
- [AVAudioSession.Category.multiRoute](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/multiroute) — 서로 다른 스트림을 동시에 여러 출력으로
- [AVAudioSession.outputLatency](https://developer.apple.com/documentation/avfaudio/avaudiosession/outputlatency)
- [Control Spatial Audio and head tracking on AirPods](https://support.apple.com/guide/airpods/control-spatial-audio-and-head-tracking-dev00eb7e0a3/web) — 끔 · 고정 · 헤드 트래킹 세 모드
- [Listen with Personalized Spatial Audio for AirPods and Beats](https://support.apple.com/en-us/102596) — 귀·얼굴 스캔 기반 개인화

## 선행 연구·사례

- [How Can Haptic Feedback Assist People with Blind and Low Vision (BLV): A Systematic Literature Review](https://arxiv.org/abs/2412.19105)
- [Navigation Assistance Via Haptic Technology for Blind or Low-Vision Users: A Scoping Review (2025)](https://journals.sagepub.com/doi/10.1177/10711813251360706)
- [RunPacer: A Smartwatch-Based Vibrotactile Feedback System (ASSETS '25)](https://arxiv.org/abs/2507.04241) — Apple Watch Series 7, 펄스 100~200ms, 지연 100ms 미만
- [Multidimensional Tactons for Non-Visual Information Presentation in Mobile Devices (Brown, Brewster)](http://www.cs.columbia.edu/~coms6998-11/papers/Brown_MobHCI06.pdf) — 리듬 93%, 거칠기 80%, 전체 약 70%
- [Towards Identifying Distinguishable Tactons for Use with Mobile Devices (ASSETS 2009)](https://userpages.umbc.edu/~rkuber/pubs/ASSETS2009.pdf) — 공간 단서 없을 때 평균 57%
- [Robotic wheelchair system for inclusive dance support for the visually impaired people with haptic feedback (ROBOMECH Journal, 2025)](https://robomechjournal.springeropen.com/articles/10.1186/s40648-025-00294-6) — 모션캡처 + 햅틱 조끼. **본문 전문 미확보**
- [Haptic Feedback: Feeling the Dance You Cannot See (AMT Lab)](https://amt-lab.org/blog/2022/4/haptic-feedback-feeling-the-dance-you-cannot-see) — Deakin Motion.Lab, 8×8 진동자 좌석
- [US11684537B2 — Human-interface device and guiding apparatus for a visually impaired user](https://patents.google.com/patent/US11684537B2/en) — 열 촉각 4방향, 정확도 91.66%, 응답 2.54초
- [Tactile suppression stems from specific sensorimotor predictions (PNAS)](https://www.pnas.org/doi/full/10.1073/pnas.2118445119)
- [Temporal modulation of tactile perception during balance control (Scientific Reports, 2025)](https://www.nature.com/articles/s41598-025-99006-8) — 보행 중 이산 진동은 위상 게이팅 영향 적음
- [Vibrotactile Threshold Measurements at the Wrist Using Parallel Vibration Actuators (ACM TAP)](https://dl.acm.org/doi/10.1145/3529259) — 손목 민감 주파수 대역
- [Impact of HRTF individualisation and head movements in a real/virtual localisation task](https://arxiv.org/abs/2510.09161) — 정위 각도 오차, 동적 청취의 효과
- [A Front-Back Confusion Metric in Horizontal Sound Localization: The FBC Score (ACM)](https://dl.acm.org/doi/fullHtml/10.1145/3385955.3407928) — 앞뒤 혼동 판정 기준
- [Toward orthogonal non-individualised HRTFs for forward and backward directional sound (Ergonomics)](https://www.tandfonline.com/doi/abs/10.1080/00140131003675117) — 정위 오차 22% 감소, 청취자 65%의 앞뒤 혼동 감소
- [HapticNav / Haptic Corridor](https://haptic.works/) — 정상 시 무진동, 이탈 시 진동 증가. 제품사 주장이며 제3자 검증 아님
- [Apple Watch: How to understand haptic feedback in Maps (CIO)](https://www.cio.com/article/242788/apple-watch-how-to-understand-haptic-feedback-in-maps.html) — 우회전 12탭, 좌회전 2탭 3쌍
- [AirPods Pro 2 Latency & Codec Guide](https://onlineaudiotest.com/devices/airpods-pro-2/) · [AirPods Max](https://onlineaudiotest.com/devices/airpods-max/) — 블루투스 출력 지연 측정값
- [How to play sound to AirPods and other speakers at the same time](https://brandonkboswell.com/blog/How-to-play-sound-to-AirPods-and-other-speakers-at-the-same-time) — iOS의 동시 다중 출력 제약
- [Deadband (Wikipedia)](https://en.wikipedia.org/wiki/Deadband) — 불감대·이력의 정의


---

## 정정 이력

| 날짜 | 무엇을 고쳤나 |
|---|---|
| 2026-09-23 (1차) | 첫 버전은 **"Apple Watch는 진동 세기를 전혀 못 바꾼다"** 고 적었다. Core Haptics가 watchOS에 없다는 것만 보고 내린 결론이었고, **SwiftUI `SensoryFeedback.impact(weight:intensity:)` 가 watchOS 10부터 있다는 것을 빠뜨렸다.** 지적받아 §B1.2를 다시 쓰고 실험 E6-2를 추가했다. 애플 지도의 거리별 진동 변화는 공식 문서로 확인되지 않아 미확인으로 남긴다 |
| 2026-09-23 (2차, 전수 재검토) | 같은 종류의 오류를 찾으라는 요청으로 전체를 다시 훑어 **다섯 개를 더 고쳤다.** ① "iOS는 소리를 여러 출력으로 나눠 보내지 못한다" → **`multiRoute` 카테고리가 있다**(§B2.7) ② "백그라운드 1시간이 공연 길이의 상한" → **워크아웃 세션 경로를 빠뜨렸다**(§B1.5) ③ "Apple 지도는 12탭/2탭3쌍으로 좌우를 나눈다" → **공식 문서는 음높이로 설명한다**(§A1.1) ④ "여러 무용수에게 각각 보내는 것도 불가능" → **Watch는 `URLSession` 으로 직접 통신할 수 있다**(§B1.6) ⑤ "AirPods가 빠지면 조용히 멈춘다" → **iPhone 스피커로 넘어가 객석으로 샐 수도 있다**(§B2.6). 공통 원인은 하나다 — **한 경로가 막혔다고 그 일이 전부 불가능하다고 결론낸 것.** 출처 신뢰도 표시(§B2.4·§B2.5)도 함께 보강했다 |
