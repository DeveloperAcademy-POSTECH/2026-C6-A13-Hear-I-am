# Hear I am · UX refinement

이슈 [#10](https://github.com/DeveloperAcademy-POSTECH/2026-C6-A13-Hear-I-am/issues/10) · `testflight/1-ux-refinement`

`PoC4.xcodeproj`는 이 TestFlight 검증용 브랜치의 유일한 Xcode 프로젝트다. **PoC4** scheme을 실행하며 앱 표시 이름은 **Hear I am**이다.

## 실행

- iOS 17 이상. Xcode에서 `PoC4/PoC4.xcodeproj`를 열고 PoC4 scheme을 선택한다.
- 실제 스캔은 ARKit 메시 재구성을 지원하는 LiDAR iPhone이 필요하다. Signing Team을 지정하고 카메라 권한을 허용한다.
- 시뮬레이터에서는 홈·사전 편집·저장 목록을 확인할 수 있으며 스캔 완료를 모사하지 않는다.
- 코어 검증: 저장소 루트에서 `sh PoC4/scripts/test-core.sh`.
- 프로젝트 소스 목록과 `project.yml`을 함께 관리한다. XcodeGen 사용 시 `PoC4`에서 `xcodegen generate`.

## 구현한 흐름

- 세로 홈: 브랜드·질문 문구·큰 기능 카드, 고정한 무대, 최근 저장순 목록, 별 토글, 저장 메시의 3D 미리보기.
- 기본 TabView: 홈 / 공연 사전 저장 / 기록. 설정은 진입 버튼만 제공한다.
- 가로 무대 준비: 전체 카메라 배경, 중심 십자선, 반투명 안내(접기 가능), 하단 동작 버튼, 5단계 표시와 중앙 설명.
- 스캔 확정은 확인창을 거친다. 이후 스캔 단계 복귀는 차단하고 추적은 계속 유지한다.
- 객석 기준 앞오른쪽 → 앞왼쪽 → 뒤왼쪽 → 뒤오른쪽을 지정한다. 네 점을 자동 연결하고 직사각형·바닥 높이를 검사한다.
- 기물은 이름과 종류(장애물/단상), 바닥 둘레 3~8점을 수동 등록한다. 모두 통과 금지. 수정 취소 시 기존 기물을 보존한다.
- 경로는 출발 + 내부 1~4개 + 도착, 총 3~6점이다. 출발·도착은 동일 높이의 무대 밖도 허용한다. 내부점은 경계에서 1cm 이상 안쪽, 모든 경로 선분은 기물 둘레에서 35cm 여유를 검사한다. 이 수치는 실험 기준이며 정확도 보증이 아니다.
- 확인점은 무대 안 바닥에 한 개, 모서리에서 0.5m 이상 떨어진 곳에 둔다. 기물과 겹치면 저장할 수 없다.
- 이전 단계 수정은 후속 데이터의 세계 좌표를 유지하고 새 무대 범위에 재투영·재검사한다. 높이·경계·충돌 오류를 수정한 뒤 저장한다.
- 저장 성공 후 홈으로 돌아간다. 지도 요청 지연과 저장 실패는 입력을 유지하고 다시 시도한다. 앱 복귀 후에는 같은 공간에서 추적을 명시적으로 재개한다.
- 공연 사전 저장: 실제 스캔과 독립한 고정 3:2 도면. 점 연결·최신점 삭제·최소 3점 완료(마지막 점→도착), 삼각형 장애물/사각형 단상 배치·이동·삭제, 이름·저장·재편집. 도면 단위는 실측 미터가 아니다.

## 저장과 호환성

- 스캔: 기존 `Documents/Scans/<UUID>/`의 지도·메시·manifest 형식을 유지한다. 새 경로는 `StageRoute.version=2`로 양 끝의 무대 밖 배치를 표현한다.
- 기존 `StageRoute.version=1`과 스캔 manifest v1/v2는 계속 읽는다. 기존 실험 안내는 새 경로를 시작하지 않는다.
- 즐겨찾기: `Documents/stage-pins.json`. 고정 목록과 최근 목록은 서로 중복되지 않는다. 각 목록은 저장 날짜 내림차순이다.
- 사전 저장: `Documents/PerformancePlans/<UUID>.json`, 원자적 쓰기. 실제 공간 지도와 연결하지 않는다.
- 생성 그림 세 개와 프롬프트는 [IMAGE-ASSETS.md](../Documentation/IMAGE-ASSETS.md)에 기록했다. 카메라 화면은 실제 ARKit 영상이다.

## 이번 범위 밖

설정 세부 기능과 실제 공연장 검증은 후속 작업이다. 기존 PoC4-2 동작 설명은 [POC4-2-LEGACY.md](../Documentation/Archive/POC4-2-LEGACY.md)에 보존했다. 검증 결과와 실제 기기 체크리스트는 [UX-VALIDATION.md](../Documentation/UX-VALIDATION.md)에 있다.


### 세로 안내와 완료 기록

홈의 **안내 사용하기**에서 실제 스캔한 무대를 선택하고, 저장 공간 복원 → 확인점 검증 → 허리띠 착용(8초) → 출발 준비 → 순차 안내를 진행한다. 모든 단계는 기존 한국어 AVSpeechSynthesizer로 읽으며 이어폰을 요구하지 않는다. 마지막 도착 안내가 끝난 뒤 **종료하고 기록 저장**을 누르면 기록 탭에 저장된다. 중간 종료는 완료 기록을 만들지 않는다.

검증 단계에서는 방향/거리 아래에 실시간 카메라와 저장 지점·연결선·현재 목표를 표시한다. 추적이나 오디오가 중단되면 현재 목표를 보존하고 현장 확인 후 명시적으로 재개한다. 완료 기록은 Documents/GuidanceRecords에 세션별 JSON으로 저장하며 같은 세션을 중복 저장하지 않는다.

자세한 흐름과 제한은 [GUIDANCE-UX-PLAN.md](../Documentation/GUIDANCE-UX-PLAN.md), 검증 결과는 [UX-VALIDATION.md](../Documentation/UX-VALIDATION.md)를 참고한다.
