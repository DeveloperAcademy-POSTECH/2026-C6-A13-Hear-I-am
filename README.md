# Hear I am

LiDAR로 스캔한 무대에 경로를 저장하고, 그 경로를 따라 음성으로 방향과 거리를 안내하는 iOS 앱입니다.

Xcode에서 **[Hear-I-am.xcodeproj](Hear-I-am.xcodeproj)** 를 열고 **Hear-I-am** scheme을 선택하세요. 앱 표시 이름은 **Hear I am 히얼아이엠**입니다.

## 현재 구현

- 홈: 무대 준비하기·안내 사용하기, 고정한 무대와 최근 저장한 무대, 스캔 공간 3D 다시보기.
- 공간 다시보기: 기물·인물 임시 모형, 전체/동선 위/구간 가까이 시점, 준비 중 수동 촬영한 현장 사진. [구현 범위·에셋 규격·실기기 확인](Experiments/stage-replay-49.md).
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

## 무대 변별 위험 구역 (#31)

무대 준비에서 네 모서리를 지정한 뒤 **위험 구역**을 누릅니다. 객석 기준 앞·뒤·왼쪽·오른쪽 중 원하는 변을 켜고 각 변의 **0.5m / 1m**를 선택합니다. 기본값은 전부 꺼짐이며, 새로 켠 변은 0.5m입니다. 여러 변에 서로 다른 거리를 지정하거나 다시 꺼서 해제할 수 있습니다.

선택한 변에서 무대 안쪽으로 주황색 띠를 표시합니다. 준비 AR, 미니맵, 검토 화면, 저장 목록과 저장 3D 보기에서 확인할 수 있습니다. 무대 모서리를 수정하면 새 무대 크기·방향에 맞춰 다시 그립니다. 작은 무대는 띠가 무대 안에서 잘리며, 여러 띠가 겹치거나 무대 전체를 덮을 수 있습니다.

- `StageRoute.dangerZones`에 변(`front/back/left/right`)과 거리(`0.5/1.0`, m)를 저장합니다. 기존 route v1/v2의 추가 필드이며, 필드가 없는 저장본은 미설정으로 읽습니다. 잘못된 거리·변·중복 변은 거부합니다.
- `StageDangerZone.vertices(width:depth:)`는 무대 평면 좌표를 반환합니다. AR 표시에는 `StageArea.world`를 적용합니다. 변별 거리는 장애물과 별도로 저장합니다.
- 카메라 AR에서는 스캔 메시의 깊이에 가려지지 않는 주황색 면과 테두리로 표시합니다. 실물 장애물 뒤의 구역도 겹쳐 보일 수 있는 주석 표시입니다.
- 시작점·이동점·종료점이 위험 구역에 포함되면 화면 하단에 해당 점 이름과 작은 주의 문구를 표시합니다. 경계선 위도 포함하고 무대 밖은 제외합니다. 점 삭제·구역 변경 시 문구도 갱신되며 점 선택·저장을 차단하지 않습니다.
- 위험 구역은 이번 버전에서 **시각적 주의 표시**입니다. 구역 진입 음성, 자동 중단, 경로 차단은 연동하지 않았습니다. 출입 동선이 위험 구역을 통과해도 저장할 수 있습니다. 안내 담당자는 저장된 변별 설정을 사용해 추후 연동할 수 있습니다.
- 설정 변경만으로 AR 기준 앵커를 다시 만들거나 공간 지도 저장 준비 상태를 초기화하지 않습니다.
- #28 다중 확인점·자동 마커 구현은 대기 상태를 유지합니다.

실기기 확인 항목 (미실시):

- [ ] 직사각형 무대를 스캔하고 앞 0.5m·뒤 1m·왼쪽 0.5m·오른쪽 1m를 선택해 실제 바닥의 방향과 폭을 확인합니다.
- [ ] 변 해제·거리 변경·모서리 수정 후 표시가 즉시 갱신되는지 확인합니다.
- [ ] 장애물·동선·확인점을 추가한 뒤 저장하고, 앱 재실행 후 저장 3D 보기에서 설정이 유지되는지 확인합니다.
- [ ] 가로 iPhone에서 설정 목록을 스크롤하고 네 변의 토글·거리 선택·완료 버튼을 조작합니다.
## 음성 중 단계 이동 설정 (#34)

홈 오른쪽 위 **설정(톱니바퀴)** → **음성 안내 중 다음 단계 진행**을 켜면 무대 선택, 확인점 확인, 착용 준비 시작, 안내 시작/재개 버튼을 설명이 끝나기 전에도 누를 수 있습니다. 기본값은 꺼짐이며 기기에 저장되어 다음 안내 세션과 앱 재실행 후에도 유지됩니다.

이동 시 이전 설명과 완료 콜백을 취소합니다. 공간 복원이 완료되면 확인점 단계로도 음성을 기다리지 않고 진행합니다. 무대 선택 여부·확인점 검증·추적 상태·출발 위치 안정 조건과 음성 오류 처리는 계속 적용됩니다. 8초 착용 카운트다운, 시작 신호 후 이동 안내, 마지막 종료 음성·기록 저장 조건은 유지합니다.

실기기 확인 (미실시):

- [ ] 기본 꺼짐 상태에서 설명 중 버튼 잠금과 음성 종료 후 활성화 확인
- [ ] 켠 상태에서 각 단계의 설명 중 버튼을 눌러 이전 음성이 멈추고 다음 단계 설명만 재생되는지 확인
- [ ] 앱 재실행 후 토글 유지, 다시 끈 뒤 대기 동작 복원 확인
- [ ] 확인점 불일치·추적 유실·출발 준비 미완료·음성 오류에서 조건을 건너뛰지 않는지 확인
## E4 방향 가이드 (#26)

- 무대 모서리는 객석 기준 **앞 오른쪽(E2) → 앞 왼쪽(E1) → 뒤 왼쪽(E4) → 뒤 오른쪽(E3)** 순서로 지정합니다. E4를 찍으면 E4에서 E3 방향으로 앞 변과 같은 길이의 청록색 점선이 나타납니다. 방향을 돕는 임시 선이며 E3은 실제 바닥에서 직접 찍어야 합니다. 모서리를 수정하면 선도 다시 계산합니다.

실기기 확인 항목 (아직 미실시):

- [ ] E2 → E1 → E4 지정 후 청록색 점선이 실제 E3 방향을 가리키고, E3을 찍기 전에는 무대가 확정되지 않는지 확인합니다. E4 수정·잘못된 높이/앞쪽 선택도 확인합니다.

## 다음 작업

- `ObservableObject`를 `@Observable`로 바꾸기. 지금은 추적 값이 바뀔 때마다 화면 전체가 다시 계산됩니다.
- 위치 입력(ARKit · 외부 카메라 · UWB)과 출력(음성 · 진동)을 바꿔 끼울 수 있게 하기.

추가 실기기 확인: 메시 표시를 켜고 끈 상태에서 카메라 AR 위험 구역을 확인하고, 위험 구역에 시작점·이동점·종료점을 찍어 주의 문구와 선택 유지·삭제 후 갱신을 확인합니다. (미실시)
