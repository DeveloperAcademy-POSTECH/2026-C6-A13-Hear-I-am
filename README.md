# Hear I am

> **TestFlight 검증용 브랜치** · `testflight/1-ux-refinement`
>
> PoC4-2를 기반으로 무대 준비·음성 안내 UX를 검증합니다. 실제 공연장 검증과 배포 서명·업로드는 별도로 진행합니다.

Xcode에서 **[Hear-I-am.xcodeproj](Hear-I-am.xcodeproj)** 하나를 열고 **Hear-I-am** scheme을 선택하세요. 앱 표시 이름은 **Hear I am**입니다.

## 현재 구현

- 홈: 무대 준비하기·안내 사용하기, 고정한 무대와 최근 저장한 무대, 스캔 공간 3D 미리보기.
- 가로 무대 준비: 공간 스캔 → 무대 범위 → 기물 → 경로 → 확인점 → 검토·저장.
- 세로 안내: 저장 무대 선택 → 공간 복원·확인점 확인 → 허리띠 착용 → 출발 준비 → TTS 안내.
- 완료 기록: 마지막 도착 음성을 마친 뒤 종료 버튼으로 저장. 중간 종료는 기록하지 않습니다.
- 공연 사전 저장: 실제 스캔과 독립한 도면 편집·저장 프로토타입. 설정은 진입 버튼만 제공합니다.

## 실행과 검증

- iOS 17 이상. 실제 스캔·공간 복원은 LiDAR를 지원하는 iPhone에서 확인하세요.
- Xcode의 Signing & Capabilities에서 개발 팀을 선택합니다.
- 시뮬레이터에서는 홈·목록·도면 편집 등을 확인할 수 있습니다. 실제 AR 스캔과 이동 안내는 실기기 검증이 필요합니다.
- 코어 테스트: 저장소 루트에서 `sh scripts/test-core.sh`.

## 폴더 구조

```text
PoC4/
├── PoC4.xcodeproj/       # 실행할 유일한 Xcode 프로젝트
├── PoC4/                # 앱 소스 (MVVM)
│   ├── App/Source/      #   앱 진입점·탭 루트
│   ├── Core/            #   여러 기능이 함께 쓰는 AR·음성·로그·저장소·디자인 요소
│   ├── Features/        #   기능별 Model / View(Screen·Parts·Sheet) / ViewModel
│   └── Resources/       #   이미지 자산·개인정보 매니페스트
├── Packages/PoC4Core/    # 화면과 무관한 도메인 로직과 테스트 (Geometry·Stage·Guidance·Storage)
├── scripts/             # 검증 스크립트
├── project.yml          # 동일 프로젝트의 XcodeGen 설정
└── README.md            # 상세 사용 안내
Documentation/           # 기획·검증·자산 문서
└── Archive/             # 이전 PoC 문서와 코드 이력 안내
```

- [상세 사용 안내](PoC4/README.md) · [코드 구조(MVVM)](Documentation/ARCHITECTURE.md)
- [UX 구현 계획](Documentation/UX-REFINEMENT-PLAN.md) · [세로 안내 계획](Documentation/GUIDANCE-UX-PLAN.md)
- [검증 결과 및 실기기 체크리스트](Documentation/UX-VALIDATION.md)
- [이미지 자산과 앱 아이콘](Documentation/IMAGE-ASSETS.md)
- [이전 실험 자료](Documentation/Archive/README.md) · [기여 규칙](CONTRIBUTING.md)
