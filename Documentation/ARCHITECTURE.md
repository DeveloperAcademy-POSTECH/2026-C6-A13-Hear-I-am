# 코드 구조 (MVVM)

이슈 [#14](https://github.com/DeveloperAcademy-POSTECH/2026-C6-A13-Hear-I-am/issues/14)에서 정한 구조다. 새 코드를 넣을 때 이 문서의 자리를 따른다.

## 층

| 층 | 자리 | 하는 일 |
|---|---|---|
| 도메인 | `Packages/PoC4Core` | 무대 좌표, 경로 검사, 안내 판정, 파일 저장. UIKit·ARKit을 모른다. 테스트는 여기에 붙인다. |
| 공용 서비스 | `PoC4/Core` | 여러 기능이 함께 쓰는 AR 세션, 음성, 실험 로그, 목록 저장소, 디자인 요소 |
| 기능 | `PoC4/Features/<기능>` | 화면 하나의 Model · View · ViewModel |
| 앱 | `PoC4/App/Source` | 진입점, 탭 루트, AppDelegate |

화살표는 한 방향이다. View → ViewModel → Core → PoC4Core. Core와 PoC4Core는 기능 폴더를 참조하지 않는다.

## 폴더

```text
PoC4/PoC4/
├── App/Source/            PoC4App · HearRootView · HearAppDelegate
├── Core/
│   ├── AR/                ARSessionController(+Lifecycle · +Samples · +References · +Save · +Logging)
│   │                      ARSceneRenderer(+Annotations) · SessionBridge · CameraSample · CameraView
│   ├── Audio/             GuidanceSpeech
│   ├── Logging/           TrialLogger
│   ├── Store/             StageLibrary
│   └── DesignSystem/      색 · 버튼 · StageMap · 선택 상태와 선택 바
├── Features/
│   ├── Home/              홈, 무대 이름 변경·삭제
│   ├── Preparation/       가로 무대 준비 (스캔 → 범위 → 기물 → 경로 → 확인점 → 저장)
│   ├── Guidance/          세로 안내 (선택 → 복원·확인점 → 착용 → 출발 → 안내 → 완료)
│   ├── Planning/          공연 사전 저장 (도면 편집)
│   ├── Records/           완료 기록
│   └── StagePreview/      저장 스캔 3D 보기
└── Resources/

Packages/PoC4Core/Sources/PoC4Core/
├── Geometry/   Point3 · FloorPoint · StageFrame · StageArea · FrontEdgeGuide
├── Stage/      StageObstacle · StageRoute · PreparationDraft · WorldObstacle
├── Guidance/   GuideSettings · RouteGuide · GuidanceCue · GuidanceCopy · NarrationQueue · DepartureGate · TrackingGate · GuidanceRun
├── Storage/    MeshSnapshot · ScanManifest · ScanStore · PerformancePlan(+Store) · LibraryPins · GuidanceRecord(+Store) · TrialRecord · TrialLog
└── LabError
```

## 기능 폴더 안

```text
Features/<기능>/
├── Model/        그 화면에서만 쓰는 값·문구 (예: PreparationStep, GuidanceHeadline)
├── View/
│   ├── Screen/   화면 뼈대. 하위 뷰를 배치하고 생명주기·알림만 다룬다
│   ├── Parts/    화면 안의 조각 뷰
│   └── Sheet/    덮어 띄우는 카드·안내
└── ViewModel/    화면 상태와 동작
```

- **Model**: 도메인 모델(경로·무대·기록)은 PoC4Core에 둔다. 기능 Model에는 그 화면 전용의 표시용 값과 문구만 둔다. 같은 개념을 두 곳에 만들지 않는다.
- **View**: 한 파일에 한 타입. 150줄 안팎을 넘으면 Parts로 나눈다. View는 `@State`로 화면 상태를 들지 않고 ViewModel의 값을 읽는다.
- **ViewModel**: 클래스 하나로 두고, 상태(단계)마다 `extension` 파일로 나눈다. 그 상태에서 하는 일만 그 파일에 넣는다.
  - `PreparationViewModel` +Scan · +Boundary · +Objects · +Route · +Checkpoint · +Review
  - `GuidanceViewModel` +Selection · +Restore · +Wear · +Departure · +Guiding · +Interruption · +Finish
- 비어 있는 Model · ViewModel 폴더는 `.gitkeep`으로 자리만 잡아 두었다. project.yml이 `.gitkeep`을 빌드 대상에서 뺀다.

## AR 세션

`ARSessionController`가 ARKit 세션 하나를 맡는다. 준비와 안내는 `Purpose`(.preparation / .guidance)로 구별한다.

- 준비: `PreparationViewModel`이 입력(`PreparationDraft`)의 주인이다. 입력이 바뀔 때마다 `applyPreparation`으로 세션에 사본을 넘기고, 세션은 그 사본으로 앵커·표식·저장 가능 여부를 계산한다. 새 세션이 시작되면 `onReset`으로 ViewModel 입력을 비운다.
- 안내: `GuidanceViewModel`이 `restore` · `verifyCheckpoint`를 부르고, 0.1초마다 `position` · `heading` · `ready`를 읽어 판정한다.
- 그리기는 `ARSceneRenderer`, 실험 로그(`Documents/Trials`)는 `TrialLogger`가 맡는다.

## 새 파일을 만들 때

1. 저장 형식이나 판정 규칙이면 PoC4Core에 넣고 테스트를 붙인다.
2. 두 기능 이상이 쓰면 Core, 한 화면만 쓰면 그 기능 폴더에 넣는다.
3. 파일을 더하거나 옮긴 뒤 `PoC4`에서 `xcodegen generate`를 실행한다. 프로젝트 파일은 손으로 고치지 않는다.

## 다음 작업

- `ObservableObject`를 `@Observable`로 바꾸기. 지금은 ViewModel이 `ARSessionController`의 `objectWillChange`를 그대로 넘겨서, 추적 값이 바뀔 때마다 화면 전체가 다시 계산된다.
- 위치 입력(ARKit · 외부 카메라 · UWB)과 출력(음성 · 진동)을 프로토콜로 바꿔 끼울 수 있게 하기.
