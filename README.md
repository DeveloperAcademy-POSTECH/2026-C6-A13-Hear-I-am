# Hear I am 히얼아이엠

LiDAR로 스캔한 무대에 동선을 저장해 두면, 허리에 찬 iPhone이 그 동선을 따라 소리와 음성으로 방향 · 거리 · 장애물을 알려 주는 iOS 앱입니다. 공연자는 「Hear I am」 하고 불러 말로 연습을 시작하고, 조력자는 화면으로 무대를 스캔하고 공연을 관리합니다.

> Apple Developer Academy @ POSTECH · 2026 Challenge 6 · A13

## 팀

<table>
  <tr>
    <th colspan="1" align="center"><br>🧭&nbsp; PM<br><br></th>
    <th colspan="2" align="center"><br>🎨&nbsp; Designer<br><br></th>
    <th colspan="3" align="center"><br>💻&nbsp; Developer<br><br></th>
  </tr>
  <tr>
    <td align="center" width="16%"><br><img src=".github/assets/team/tom.png" width="120" alt="TOM"></td>
    <td align="center" width="16%"><br><img src=".github/assets/team/kyeozo.png" width="120" alt="KYEOZO"></td>
    <td align="center" width="16%"><br><img src=".github/assets/team/claire.png" width="120" alt="CLAIRE"></td>
    <td align="center" width="16%"><br><img src=".github/assets/team/nana.png" width="120" alt="NANA"></td>
    <td align="center" width="16%"><br><img src=".github/assets/team/jace.png" width="120" alt="JACE"></td>
    <td align="center" width="16%"><br><img src=".github/assets/team/ian.png" width="120" alt="IAN"></td>
  </tr>
  <tr>
    <td align="center"><h3>TOM</h3>(우상영)<br><br></td>
    <td align="center"><h3>KYEOZO</h3>(조원경)<br><br></td>
    <td align="center"><h3>CLAIRE</h3>(김경민)<br><br></td>
    <td align="center"><h3>NANA</h3>(김나영)<br><br></td>
    <td align="center"><h3>JACE</h3>(김재원)<br><br></td>
    <td align="center"><h3>IAN</h3>(김지원)<br><br></td>
  </tr>
</table>

## 앱 흐름

앱을 열면 **공연자**와 **조력자** 중 하나를 고릅니다. 역할은 그 실행 동안만 유지되고, 앱을 새로 열면 다시 고릅니다.

### 조력자

| 탭 | 하는 일 |
|---|---|
| 스캔 | 공간 스캔 → 무대 범위(네 모서리) → 기물(장애물 · 의자 · 계단) → 동선 → 확인점 1 · 2 → 저장 |
| 공연 관리 | 공연 폴더(참고 씬 · 공연 및 연습 공간 폴더), 사전 동선 편집, 무대 카드의 「안내 시작」으로 실전 준비 |
| 기록 | 끝까지 마친 안내의 이동 궤적과 걷는 인물을 재생 |

설정에서 소리 출력(폰 스피커 고정)과 신호 연습을 다룹니다.

### 공연자

1. 홈에서 「Hear I am」 하고 부릅니다. 화면 버튼으로도 시작할 수 있습니다.
2. 공연 → 공연장 · 저장 무대 → 사용 방식을 말로 고릅니다. 화면에 보이는 번호로 말해도 됩니다.
3. **연습용**: 저장한 실제 공간에서 휴대폰을 들고 제자리에서 한 바퀴 돌면 공간을 다시 찾습니다. 허리 앞쪽에 세로로 착용하고(후면 카메라는 몸 바깥쪽) 「착용 완료」 → 「출발」이라고 하면 지금 자리에서 P1부터 안내합니다.
4. 걷는 중에는 「Hear I am」 하고 부른 뒤에만 말을 받습니다. 연습 중에는 「P2로 다시 가 줘」처럼 원하는 지점으로 돌아갈 수 있습니다.
5. 마지막 지점에 닿으면 기록을 저장하고 홈으로 돌아갑니다.

실전용은 공연자가 말로 고르면 아직 연습용으로 진행합니다. 실전 준비(확인점 1 · 2 맞추기 → 저장 출발점에서 시작)는 조력자가 공연 관리에서 시작합니다.

### 자주 쓰는 말

| 말 | 하는 일 |
|---|---|
| Hear I am | 부르기. 대화가 열리고, 조용히 10초가 지나면 다시 닫힙니다 |
| 연습용 · 실전용 | 사용 방식 고르기 |
| 착용 완료 · 다음 | 다음 단계로 |
| 출발 | 안내 시작 |
| 멈춰 · 계속 | 안내 일시정지 · 다시 이어서 |
| 다시 말해 줘 | 방금 안내 다시 듣기 |
| P2로 다시 가 줘 | (연습용, 안내 시작 뒤) 그 지점으로 다시 안내 |
| 취소 · 이전 · 무대 다시 선택 | 한 단계 뒤로 · 무대 고르기로 |
| 닫기 | 대화 닫기 |

## 안내 중 들리는 것

진동은 쓰지 않습니다. 소리는 연결된 에어팟으로(없으면 폰 스피커로) 나갑니다.

| 언제 | 소리 |
|---|---|
| 출발 | 「현재 위치에서 P1으로 안내합니다」 → 첫 지점 쪽 「오른쪽」 · 「왼쪽」 |
| 방향이 틀림 (목표 ±30° 밖) | 「오른쪽」 · 「왼쪽」 한 번 → 톡톡톡(목표에 가까워질수록 빨라짐) |
| 방향이 맞음 | 확인음 한 번, 그 뒤 조용함 |
| 걷는 중 | 남은 거리 「1미터」, 마지막에 「50센티」 |
| 지점에 닿음 | 지점 이름(「피원」 · 「피투」) → 다음 지점 쪽 좌우 |
| 마지막 지점 | 띵 → 「마지막 지점 도착」 |
| 장애물 접근 | 1m · 0.6m · 0.35m 세 단계 경고음 |
| 다음 지점이 의자 · 계단 위 | 방향이 맞은 뒤 「의자」 · 「계단」 한 번. 올라선 뒤 바라볼 쪽은 「오른쪽 봐」 · 「왼쪽 봐」 |
| 바라볼 방향이 정해진 지점 | 「그 자리에서 ○○ 방향을 바라봐주세요」 → 맞출 때까지 좌우 안내 |
| 장애물에 막히거나 동선 밖으로 벗어남 | 「멈추세요. 오른쪽(왼쪽)으로 비켜서세요」 |

- 도착은 지점 0.35m 안에 0.8초 머무르면 인정합니다. 출발점은 0.45m 안입니다.
- 경로점마다 도착 뒤 대기 시간(0~3600초)과 바라볼 방향(8방위)을 저장 무대에서 정할 수 있습니다.

## 개발

- iOS 17 이상. 스캔 · 공간 복원 · 안내는 LiDAR가 있는 iPhone 실기기에서 확인합니다. 시뮬레이터로는 화면 흐름 정도만 볼 수 있습니다.
- Xcode에서 [Hear-I-am.xcodeproj](Hear-I-am.xcodeproj)를 열고 **Hear-I-am** scheme으로 빌드합니다.
- Metal Toolchain이 없다는 오류가 나면 `xcodebuild -downloadComponent MetalToolchain` 을 한 번 실행합니다.
- 파일을 더하거나 옮긴 뒤에는 저장소 루트에서 `xcodegen generate` 를 실행합니다.
- Signing & Capabilities의 개발 팀 · 번들 ID 변경은 각자 로컬에만 두고 커밋하지 않습니다.
- 번들 ID(`org.heariam.poc4.scanlab`)는 기존 TestFlight 앱의 저장 무대를 잇기 위해 예전 이름을 그대로 씁니다.
- 코어 테스트: `sh scripts/test-core.sh`
- 이슈 · 브랜치 · PR 규칙은 [CONTRIBUTING.md](CONTRIBUTING.md)를 따릅니다.

### 기록 파일

앱 Documents에 저장되고 파일 앱에서 볼 수 있습니다.

| 경로 | 내용 |
|---|---|
| `Scans/<UUID>/` | 공간 지도 · 메시 · manifest(무대 · 동선 · 기물) · 현장 사진 |
| `Performances/` | 공연 폴더 · 참고 씬 · 공간 폴더 연결 |
| `PerformancePlans/` | 사전 저장 동선 |
| `GuidanceRecords/<UUID>.json` | 끝까지 마친 안내의 완료 기록 |
| `Trials/trial-<UUID>.jsonl` | 안내마다 위치와 소리 · 음성 신호 기록 |
| `VoiceLogs/voice-<날짜>.jsonl` | 음성 대화 기록(들은 말 · 앱 답 · 단계 변화) |

### 폴더 구조

```text
Hear-I-am/
├── App/Source/       # @main · 역할 선택과 화면 전환(HearRootView)
├── Core/             # 여러 기능이 함께 쓰는 것: AR 세션 · 오디오 · 로그 · 저장 · 디자인 시스템
├── Features/         # 기능별 Model / View / ViewModel
│   ├── Onboarding                         # 시작 로고와 역할 선택
│   ├── Home · Voice                       # 공연자 홈과 음성 대화
│   ├── Preparation · Guidance             # 무대 준비(스캔)와 안내
│   ├── Performances · Places · Planning   # 공연 관리 · 공간 폴더 · 사전 동선
│   ├── Records · StagePreview             # 완료 기록 · 공간 다시보기
│   └── SoundTest                          # 설정의 신호 연습
└── Resources/        # Assets · 다시보기 인물 · 기물 모델

Packages/HearIAmCore/ # 화면과 무관한 규칙과 테스트(도착 · 이탈 판정, 신호, 음성 명령 해석, 저장 형식)
```

- 의존 방향은 View → ViewModel → Core → HearIAmCore 한쪽입니다.
- 판정 규칙과 저장 형식은 HearIAmCore에 두고 테스트를 붙입니다.
- 기능별 실험 기록과 자세한 동작은 [Experiments/](Experiments/)에 있습니다.
