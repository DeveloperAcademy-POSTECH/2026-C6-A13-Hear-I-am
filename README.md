# Hear I am

LiDAR로 스캔한 무대에 경로를 저장하고, 그 경로를 따라 음성으로 방향과 거리를 안내하는 iOS 앱입니다.

Xcode에서 **[Hear-I-am.xcodeproj](Hear-I-am.xcodeproj)** 를 열고 **Hear-I-am** scheme을 선택하세요. 앱 표시 이름은 **Hear I am 히얼아이엠**입니다.

## 현재 구현

- 홈: 무대 준비하기·안내 사용하기, 고정한 무대와 최근 저장한 무대, 스캔 공간 3D 미리보기.
- 가로 무대 준비: 공간 스캔 → 무대 범위 → 기물 → 경로 → 확인점 → 검토·저장.
- 세로 안내: 저장 무대 선택 → 공간 복원·확인점 확인 → 허리띠 착용 → 출발 준비 → TTS 안내.
- 완료 기록: 마지막 도착 음성을 마친 뒤 종료 버튼으로 저장합니다. 중간 종료는 기록하지 않습니다.
- 공연 사전 저장: 실제 스캔과 독립한 도면 편집·저장 프로토타입. 설정은 진입 버튼만 제공합니다.

## 실행과 검증

- iOS 17 이상. 실제 스캔·공간 복원은 LiDAR를 지원하는 iPhone에서 확인하세요.
- Xcode의 Signing & Capabilities에서 각자 개발 팀을 선택합니다. 이 설정 변경은 커밋하지 않습니다.
- 시뮬레이터에서는 홈·목록·도면 편집 등을 확인할 수 있습니다. 실제 AR 스캔과 이동 안내는 실기기 검증이 필요합니다.
- 코어 테스트: 저장소 루트에서 `sh scripts/test-core.sh`.
- 파일을 더하거나 옮긴 뒤에는 저장소 루트에서 `xcodegen generate`를 실행합니다. 프로젝트 파일은 손으로 고치지 않습니다.

## 폴더 구조

```text
2026-C6-A13-Hear-I-am/
├── Hear-I-am.xcodeproj/          # 실행할 Xcode 프로젝트 (project.yml에서 생성)
├── Hear-I-am/                    # 앱 소스 (MVVM)
│   ├── App/Source/               #   앱 진입점
│   │   ├── HearIAmApp            #     @main
│   │   ├── HearRootView          #     홈 / 공연 사전 저장 / 기록 탭
│   │   └── HearAppDelegate       #     화면 방향 제어
│   ├── Core/                     #   여러 기능이 함께 쓰는 것
│   │   ├── AR/                   #     ARKit 세션 하나를 준비·안내가 함께 씀
│   │   │   ├── ARSessionController (+Lifecycle · +Samples · +References · +Save · +Logging)
│   │   │   ├── ARSceneRenderer (+Annotations)    # 스캔 메시·표식 그리기
│   │   │   ├── SessionBridge · CameraSample · CameraView
│   │   │   └── MeshSnapshot+SceneKit
│   │   ├── Audio/                #     GuidanceSpeech (한국어 TTS)
│   │   ├── Logging/              #     TrialLogger (Documents/Trials 실험 로그)
│   │   ├── Store/                #     StageLibrary (저장 무대 목록·고정)
│   │   └── DesignSystem/         #     Color+Hear · ActionButton · BrandMark · StageMap · ScreenOrientation
│   │                             #     LibrarySelectionBar · LibrarySelectionState · View+LibrarySelection
│   ├── Features/                 #   기능별 Model / View / ViewModel
│   │   ├── Home/                 #     홈, 무대 이름 변경·삭제
│   │   ├── Preparation/          #     가로 무대 준비 (스캔 → 범위 → 기물 → 경로 → 확인점 → 저장)
│   │   ├── Guidance/             #     세로 안내 (선택 → 복원·확인점 → 착용 → 출발 → 안내 → 완료)
│   │   ├── Planning/             #     공연 사전 저장 (도면 편집)
│   │   ├── Records/              #     완료 기록
│   │   └── StagePreview/         #     저장 스캔 3D 보기
│   └── Resources/                #   Assets.xcassets · PrivacyInfo.xcprivacy
├── Packages/HearIAmCore/         # 화면과 무관한 도메인 로직과 테스트 (UIKit·ARKit을 모름)
│   ├── Sources/HearIAmCore/
│   │   ├── Geometry/             #   Point3 · FloorPoint · StageFrame · StageArea · FrontEdgeGuide
│   │   ├── Stage/                #   StageObstacle · StageRoute · PreparationDraft · WorldObstacle
│   │   ├── Guidance/             #   GuideSettings · RouteGuide · GuidanceCue · GuidanceCopy
│   │   │                         #   NarrationQueue · DepartureGate · TrackingGate · GuidanceRun
│   │   ├── Storage/              #   ScanManifest · ScanStore · MeshSnapshot · LibraryPins · TrialRecord · TrialLog
│   │   │                         #   PerformancePlan(+Store) · GuidanceRecord(+Store)
│   │   └── LabError
│   └── Tests/HearIAmCoreTests/   #   Core · Preparation · StageRoute · Guidance · GuidanceRecord
├── scripts/test-core.sh          # 코어 테스트 실행
├── project.yml                   # XcodeGen 설정
├── CONTRIBUTING.md               # 이슈·브랜치·PR 규칙
└── .github/                      # 이슈·PR 템플릿
```

### 기능 폴더 안

```text
Features/<기능>/
├── Model/            # 그 화면에서만 쓰는 값·문구 (예: PreparationStep, GuidanceHeadline)
├── View/
│   ├── Screen/       # 화면 뼈대. 하위 뷰를 배치하고 생명주기·알림만 다룸
│   ├── Parts/        # 화면 안의 조각 뷰
│   └── Sheet/        # 덮어 띄우는 카드·안내
└── ViewModel/        # 화면 상태와 동작
```

- **의존 방향**은 한쪽입니다. View → ViewModel → Core → HearIAmCore. Core와 HearIAmCore는 기능 폴더를 참조하지 않습니다.
- **Model**: 경로·무대·기록 같은 도메인 모델은 HearIAmCore에 둡니다. 기능 Model에는 그 화면 전용 표시 값과 문구만 둡니다.
- **View**: 한 파일에 한 타입. 150줄 안팎을 넘으면 Parts로 나눕니다.
- **ViewModel**: 클래스 하나를 단계마다 `extension` 파일로 나눕니다.
  - `PreparationViewModel` +Scan · +Boundary · +Objects · +Route · +Checkpoint · +Review
  - `GuidanceViewModel` +Selection · +Restore · +Wear · +Departure · +Guiding · +Interruption · +Finish
- 비어 있는 폴더는 `.gitkeep`으로 자리만 잡아 두었습니다. project.yml이 빌드 대상에서 뺍니다.

### 새 파일을 둘 자리

1. 저장 형식이나 판정 규칙이면 HearIAmCore에 넣고 테스트를 붙입니다.
2. 두 기능 이상이 쓰면 `Core/`, 한 화면만 쓰면 그 기능 폴더에 넣습니다.
3. 넣은 뒤 `xcodegen generate`를 실행합니다.

## 저장 형식

- 스캔: `Documents/Scans/<UUID>/`에 지도·메시·manifest를 둡니다. `StageRoute.version=2`가 양 끝의 무대 밖 배치를 표현하고, version 1과 manifest v1/v2도 계속 읽습니다.
- 즐겨찾기: `Documents/stage-pins.json`. 고정 목록과 최근 목록은 겹치지 않고, 각각 저장 날짜 내림차순입니다.
- 사전 저장: `Documents/PerformancePlans/<UUID>.json`. 실제 공간 지도와 연결하지 않습니다.
- 완료 기록: `Documents/GuidanceRecords`에 세션별 JSON. 같은 세션을 중복 저장하지 않습니다.
- 번들 ID(`org.heariam.poc4.scanlab`)와 앵커 이름 접두사(`PoC4.reference.`)는 기존 TestFlight 앱과 저장된 무대를 잇기 위해 이전 이름을 유지합니다.

## 모서리 가이드와 카메라 기울기 복구 (#26)

- 무대 모서리는 객석 기준 **앞 오른쪽(E2) → 앞 왼쪽(E1) → 뒤 왼쪽(E4) → 뒤 오른쪽(E3)** 순서로 지정합니다. E4를 찍으면 E4에서 E3 방향으로 앞 변과 같은 길이의 청록색 점선이 나타납니다. 방향을 돕는 임시 선이며 E3은 실제 바닥에서 직접 찍어야 합니다. 모서리를 수정하면 선도 다시 계산합니다.
- 카메라 정면 벡터의 수평 성분 비율이 `0.25` 미만이면 방향을 계산하지 않습니다. 수평에서 약 ±75.5°보다 더 위·아래로 향하는 상태입니다. 몸의 이동 방향이나 휴대폰의 세로·가로 화면 회전을 측정하는 조건은 아닙니다.
- 안내 중 **위치 추적과 C 검증이 유지된 기울기 문제**는 별도의 교정 상태로 들어갑니다. AR 세션·현재 목표·C 검증을 유지하고 교정 음성을 즉시, 이후 최소 6초 간격으로 재생합니다. 음성을 겹치지 않게 합니다.
- 새 표본의 유효 방향과 현재 경로 구간의 위치 조건이 1초 연속 유지되고 교정 음성이 끝나면 같은 목표로 자동 재개합니다. 출입 구간의 무대 밖 위치도 해당 구간 안이면 허용합니다. 교정 시간은 도착 체류 시간이나 안내 진행 시간에 포함하지 않습니다.
- 교정 중 경로 이탈·등록 기물 접근은 명시적 재개로 전환합니다. 수동 일시정지, 나가기 확인, 음성 실패는 자동 재개를 취소합니다. 추적 제한·앵커 유실·0.5초를 넘긴 표본 만료·앱 비활성화·오디오 중단은 기존 중단/확인점 재검증 경로를 따릅니다. 출발 음성 중 기울어지면 출발 준비로 돌아갑니다.
- `guide_paused`(unclearHeading, 수평 비율), `guide_alignment_prompt`, `guide_auto_resumed`, `guide_alignment_cancelled`를 기존 Trials 로그에 기록합니다.
- 여러 수동 확인점을 저장하는 기능이나 자동 마커 관측은 이번 변경에 포함하지 않습니다. 수동 확인점 개수만 늘려도 공연 중 자동 재검증이 이루어지지는 않습니다.

실기기 확인 항목 (아직 미실시):

- [ ] E2 → E1 → E4 지정 후 청록색 점선이 실제 E3 방향을 가리키고, E3을 찍기 전에는 무대가 확정되지 않는지 확인합니다. E4 수정·잘못된 높이/앞쪽 선택도 확인합니다.
- [ ] 안내 중 카메라를 바닥·천장 쪽으로 기울여 즉시 교정 음성과 반복을 확인합니다. 다시 전방으로 향하면 확인점을 다시 찍지 않고 같은 목표로 자동 재개되는지 확인합니다.
- [ ] 교정 도중 수동 정지/나가기 취소, 경로 이탈, 기물 접근, 렌즈 가림, 앱 전환, 오디오 중단을 각각 시험하여 잘못된 자동 재개가 없는지 확인합니다.
- [ ] 실제 안무·조명·착용 상태에서 자세와 추적 유실을 구분하는지, 음성이 안무를 방해하는지, 허리띠 안에서 폰이 돌아가지 않는지 확인합니다.

## 다음 작업

- `ObservableObject`를 `@Observable`로 바꾸기. 지금은 추적 값이 바뀔 때마다 화면 전체가 다시 계산됩니다.
- 위치 입력(ARKit · 외부 카메라 · UWB)과 출력(음성 · 진동)을 바꿔 끼울 수 있게 하기.
