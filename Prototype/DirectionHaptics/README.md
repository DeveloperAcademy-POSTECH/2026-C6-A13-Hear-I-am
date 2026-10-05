# 방향 햅틱 · DirectionHaptics

공연하는 시각장애인 예술인이 iPhone의 진동으로 몸 기준 앞·뒤·왼쪽·오른쪽을 익히는 네이티브 프로토타입입니다. `HapticLab`과 독립된 프로젝트이며 iOS 17 이상에서 실행합니다.

## 실행

1. `DirectionHaptics.xcodeproj`를 열고 `DirectionHaptics` scheme을 선택합니다.
2. 실제 iPhone을 연결하고 Signing & Capabilities에서 사용할 Team을 선택합니다.
3. iPhone에서 Run 합니다. 개발·검증 환경은 Xcode 26.6입니다.

시뮬레이터에는 진동과 회전 센서가 없습니다. Debug 실행 인자에 `--ui-preview`를 추가하면 시간 진행과 회전값 입력만 확인할 수 있습니다. **미리보기의 회전 버튼은 센서 입력을 흉내 내는 개발 도구이며 실제 iPhone에는 표시하지 않습니다.** 정답·오답 알림음은 설정의 미리 듣기로 확인할 수 있습니다.

## 세 가지 탭과 상단 설정

| 화면 | 기능 |
| --- | --- |
| 탐색 | 8종 기본 패턴과 사용자 패턴, 방향별 재생, 즐겨찾기, 패턴 JSON 공유 |
| 랜덤 체험 | 진동을 느끼고 몸과 휴대폰을 함께 회전 → 1초 정지 → 정답·오답 알림 → 다음 진동 자동 진행 |
| 편집 | 그래프를 보며 강도·촉감·길이·쉼·반복·개별 블록 수정, 수정 전후 재생 |

비교 탭과 A/B·정답률 화면은 앱 내 탐색에서 제거했습니다. 상단 톱니바퀴에서 전체 진동 세기, 준비 시간, 정답·오답 알림음, 자동 잠금 방지, 화면 모드를 조절합니다. 체험에는 시작 당시 설정과 패턴을 고정해서 사용합니다.

## 눈 감고 회전 체험

1. 패턴을 선택하고 `네 방향 미리 익히기`에서 각 방향의 진동을 익힙니다.
2. 휴대폰 **화면을 위로**, 윗부분을 몸 앞쪽으로 향하게 들고 `회전 체험 시작`을 누릅니다.
3. 먼저 센서와 휴대폰 자세가 준비될 때까지 기다린 뒤 준비 시간(기본 3초)을 셉니다. 준비 시간이 끝나면 무작위 방향의 진동이 나옵니다. 진동 직전의 휴대폰 방향을 이번 회전의 기준으로 잡습니다.
4. 진동이 끝난 뒤 **몸과 휴대폰을 함께** 돌립니다.

| 느낀 방향 | 동작 |
| --- | --- |
| 앞 | 현재 방향 그대로 1초 유지 |
| 오른쪽 | 오른쪽으로 90° 돌린 뒤 1초 정지 |
| 왼쪽 | 왼쪽으로 90° 돌린 뒤 1초 정지 |
| 뒤 | 어느 쪽이든 180° 돌린 뒤 1초 정지 |

어느 각도든 1초간 가만히 유지하면 답을 확정합니다. 정답 각도 ±20° 안이면 정답, 다른 방향 또는 네 방향 사이의 각도는 오답입니다. 빠르게 지나가는 동작, 10°를 넘는 느린 회전, 화면을 세워 드는 동작, 센서 데이터가 끊긴 시간은 유지 시간을 초기화합니다. 회전 응답은 진동 종료 0.5초 후부터 확인합니다. 따라서 앞 응답은 진동이 끝난 뒤 계속 정지해 있으면 약 1.5초 후 확정됩니다.

정답이면 올라가는 두 음, 오답이면 내려가는 두 음을 재생하고 화면에 **정답 / 내 응답**을 표시합니다. 정답·오답 모두 2초 쉬고 준비 시간 뒤 다음 진동으로 자동 진행합니다. **새 진동 직전의 방향이 다음 기준**이므로 처음 방향으로 돌아올 필요가 없습니다. 계속 움직여 답을 확정하지 못하면 같은 기준으로 10초 후 같은 진동을 반복합니다. 정답 버튼·스와이프·다음 버튼은 없습니다.

하단 `체험 일시 정지`로 멈춥니다. 앱을 벗어나거나 잠그면 센서·진동·소리·자동 진행도 중지합니다. 다시 시작하면 현재 방향으로 기준을 새로 잡습니다. 센서를 사용할 수 없거나 응답이 끊기면 오류를 표시하고 자동 진행을 멈춥니다.

이 기능은 진동을 해석한 방향을 1초간 유지해 정답·오답을 확인하는 **연습**입니다. 화면의 완료 횟수에는 정답과 오답이 모두 포함되며, 체험을 닫으면 사라집니다. 방위각·위치·무대 목적지를 측정하는 기능은 없습니다.

## 정답·오답 알림음과 저장 범위

- **TTS·음성 읽기는 없습니다.** 햅틱은 Core Haptics의 haptic 이벤트만 사용하고 `playsHapticsOnly = true`로 재생합니다.
- 정답·오답 알림음을 별도 WAV로 재생합니다. 설정에서 함께 끄거나 각각 미리 들을 수 있습니다. 기존 성공음 설정값은 그대로 이어집니다.
- 알림음은 `AVAudioSession.playback + mixWithOthers`를 사용하므로 다른 음악과 함께 **무음 모드에서도 재생**됩니다. 기기 음량이 0이거나 연결한 이어폰으로 출력 중이면 iPhone 스피커에서 들리지 않을 수 있습니다. 눈 감고 연습하기 전에 설정에서 두 알림음을 확인하세요.
- 체험 완료 횟수·응답·결과는 저장하지 않습니다. 닫거나 앱이 종료되면 사라집니다.
- 사용자 패턴·즐겨찾기·앱 설정만 기기에 저장합니다. 기존 사용자 패턴과 사용자가 변경한 전체 세기는 덮어쓰지 않습니다.

## 기본 세기

전체 진동 세기의 기본값과 새로 추가하는 진동 블록은 **100%**입니다. A/B/C/D/G/H 기본 세트의 모든 진동도 100%입니다. E는 최대 세기 100%에서 강도 흐름을 적용하고, F는 30/50/75/100%의 방향별 차이를 유지합니다. %는 API 설정값이며 물리적인 진동 세기 측정값이 아닙니다.

## 비교할 8종 패턴

숫자는 기본 설정입니다. `짧음=100ms`, `김=350ms`, 길이 조합의 진동 사이 쉼은 `200ms`입니다. `탭`은 Core Haptics transient 이벤트이며 길이를 직접 지정하지 않습니다.

| 세트 | 앞 | 뒤 | 왼쪽 | 오른쪽 | 확인할 가설 |
| --- | --- | --- | --- | --- | --- |
| A 길이 조합 | 짧음·짧음 | 김·김 | 김·짧음 | 짧음·김 | 순서가 다른 두 진동을 기억하기 쉬운가 |
| B 횟수 | 1탭 | 4탭 | 2탭 | 3탭 | 단순한 횟수 차이를 동작 중에도 셀 수 있는가 |
| C 리듬 묶음 | 균등 4탭 | 2+2 | 3+1 | 1+3 | 같은 횟수에서 묶음만으로 구별되는가 |
| D 속도 변화 | 빠른 3탭 | 느린 3탭 | 점점 빠르게 | 점점 느리게 | 간격 변화의 방향을 구별하는가 |
| E 강도 변화 | 약→강 | 강→약 | 약→강→약 | 강→약→강 | 연속 진동의 강도 흐름이 구별되는가 |
| F 강도 단계 | 30% | 50% | 75% | 100% | 네 단계 세기만으로 충분한가 |
| G 촉감 단계 | 0% | 33% | 67% | 100% | 둥근 느낌과 날카로운 느낌의 단계가 구별되는가 |
| H 복합 | 날카로운 2탭 | 둥근 긴 진동 | 둥근 김→날카로운 짧음 | 날카로운 짧음→둥근 김 | 여러 특성을 함께 쓰면 혼동이 줄어드는가 |

- B의 탭 사이 쉼은 200ms입니다.
- C의 쉼은 앞 `[200,200,200]`, 뒤 `[80,440,80]`, 왼쪽 `[80,80,440]`, 오른쪽 `[440,80,80]`ms입니다.
- D의 쉼은 앞 `[120,120]`, 뒤 `[500,500]`, 왼쪽 `[500,120]`, 오른쪽 `[120,500]`ms입니다.
- E/F/G와 H의 뒤 방향 연속 진동은 700ms입니다.
- 강도·촉감의 %는 API 설정값이며 물리적 진동 세기·주파수의 측정값이 아닙니다. 타임라인도 설계값의 시각화입니다.

이 패턴들은 비교를 위한 출발점입니다. F/G처럼 미세한 차이에 의존하는 방식은 기종·케이스·고정 위치·동작에 따라 구별이 어려울 수 있습니다. 특정 세트를 효과가 검증된 방식으로 표시하지 않습니다.


## 그래프를 보며 편집

편집 화면 상단에 **방향 선택·그래프·수정 전후 재생 버튼을 고정**했습니다. 아래 Form만 스크롤하므로 간편 조절이나 상세 블록을 수정하면서 같은 화면에서 그래프를 확인할 수 있습니다.

- 강도는 높이, 촉감은 색의 진하기, 시간은 가로 길이로 즉시 갱신됩니다.
- 그래프는 한 주기를 표시합니다. 기본 시간축은 0–2초이며, 긴 패턴은 정수 초 단위로 확장합니다. 전체 길이와 반복 횟수는 별도로 표시합니다.
- 간편 조절은 선택한 방향의 해당 블록 전체에 같은 값을 적용합니다. 블록별 차이는 상세 편집에서 조절하세요.
- 탭은 Core Haptics transient이며 길이를 지정하지 않습니다. 스케줄에서는 70ms 슬롯을 사용합니다.
- 연속 진동·쉼은 30–2000ms, 강도 10–100%, 촉감 0–100%, 반복 1–5회, 최대 16블록·총 12초입니다.
- 기본 세트는 복제하여 저장하고, 기존 사용자 세트를 수정하면 버전이 증가합니다. 패턴 JSON만 공유할 수 있습니다.

## 구현과 접근성

Apple [탭 바](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [툴바](https://developer.apple.com/design/human-interface-guidelines/toolbars), [접근성](https://developer.apple.com/design/human-interface-guidelines/accessibility) 지침을 참고해 SwiftUI List/Form, 시스템 버튼, Dynamic Type, 의미 기반 색상, 다크 모드를 사용합니다.

회전은 [Core Motion의 처리된 기기 동작](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data)을 50Hz로 읽습니다. `xArbitraryZVertical`의 yaw를 기준 각도와 비교하고 ±180° 경계를 처리합니다. 화면이 위를 향한 자세에서 수평 회전을 인식하며, 기울어진 자세나 끊긴 샘플은 성공 판정에 사용하지 않습니다. 센서는 체험을 끝내거나 중지할 때까지 계속 유지하고, 방향 기준만 매 회차 갱신합니다. 최초 센서 준비에는 최대 5초를 기다리며 준비 전에 카운트다운을 시작하지 않습니다. 샘플 수신 시각과 센서 타임스탬프를 분리해 서로 다른 시간 기준을 직접 비교하지 않습니다. 위치 권한·나침반·서버는 사용하지 않습니다.

소리 정책: [AVAudioSession.playback](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback), [mixWithOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers). 정답음은 직접 합성한 0.335초 상승음(`Sources/Resources/success.wav`), 오답음은 0.405초 하강음(`Sources/Resources/incorrect.wav`)이며 외부 음원을 사용하지 않았습니다.

## 검증

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project DirectionHaptics.xcodeproj -scheme DirectionHaptics \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

UI 테스트는 `--ui-testing --ui-reset --ui-preview`로 별도의 데이터 저장소를 사용합니다. `--rotation-test-sequence`는 Debug UI 테스트에서만 고정된 방향 순서를 제공합니다.

햅틱 엔진 생성·시작·패턴 재생·중지는 전용 직렬 큐에서 실행합니다. 엔진 작업 전에 4초 시작 제한을 걸고, 실제 플레이어 시작 응답 뒤 패턴 길이+2초의 완료 제한을 적용합니다. 시작/완료 응답이 없으면 체험을 중단하고 다시 시작할 수 있게 하며, 실패를 성공으로 집계하지 않습니다. 취소된 요청의 늦은 콜백은 다음 재생에 적용하지 않고, 중단된 엔진은 다시 생성합니다.

코어 테스트는 회전 부호·180° 경계·유지 시간·잘못된 방향·움직임·센서 공백, 기본 세기, 기존 설정 마이그레이션, 패턴 컴파일과 저장 범위를 검증합니다. UI 테스트는 자동 진행·정지·백그라운드 중단·결과 폐기·고정 그래프 갱신·설정 유지를 확인합니다. 센서가 2초 늦게 준비되는 경우, 햅틱 시작/완료 콜백이 누락된 경우의 제한 시간·오류 표시·재시작 복구도 검증합니다.

실기기 개발 진단은 Debug 실행 인자 `--hardware-diagnostics`에서만 동작합니다. 센서 수신, 8종 앞 방향 햅틱의 엔진 완료, 성공음 재생 요청, 체험 상태를 콘솔로 확인하며 기기에 결과를 저장하지 않습니다. `--ui-testing --hardware-test-front`는 실제 센서를 사용하되 앞 방향을 고정해, 정지 상태에서 두 회차 자동 진행을 검증하는 테스트 전용 인자입니다. `--rotation-test-sequence`는 오른쪽→뒤→앞→왼쪽 순서로 재생해, 실기기에서 가만히 있을 때 오답 처리와 다음 회차 진행도 검증합니다.

**실제 iPhone에서는 별도로 확인해야 합니다:** 좌우 회전 부호와 각도, 손에 든 자세에서의 안정성, 케이스·기종별 진동 구별, 무음 모드·음량별 정답·오답 알림음, 잠금·전화 후 재시작. 시뮬레이터 성공은 센서나 촉각·소리의 실기기 검증을 대신하지 않습니다.

## 앱 아이콘

`Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`를 앱 타깃의 AppIcon으로 연결했습니다. [Apple 앱 아이콘 지침](https://developer.apple.com/design/human-interface-guidelines/app-icons)을 참고해 단순한 방향 화살표와 진동 곡선, 파랑 배경을 사용했습니다. 1024×1024 불투명 PNG이며 모서리는 미리 둥글게 자르지 않고 시스템 마스크에 맡깁니다.

제작: 내장 `image_gen` 도구, 아래 프롬프트. 생성 후 앱 아이콘 규격으로 리사이즈했습니다.

```text
Use case: logo-brand. Create one final production iPhone app icon asset for Direction Haptics, an app that teaches front/back/left/right using vibration. Square 1024 x 1024 opaque full-bleed artwork, not a phone mockup. Simple memorable white directional needle pointing upward, centered inside two open concentric circular tactile ripple arcs. Bold geometric silhouette, generous negative space, readable at very small sizes. Rich system-blue to indigo background with restrained smooth gradient and only very subtle depth. No letters, words, digits, tiny details, border, outer drop shadow, or pre-rounded icon corners; iOS will apply its own mask. The motif should convey direction and touch, not audio or a speaker. One icon filling the image, not an options grid.
```
