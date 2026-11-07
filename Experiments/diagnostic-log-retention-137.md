# 진단 로그 보관과 개인정보처리방침 대조 (#137)

확인일: 2026-11-08 (KST). 기준은 [개인정보처리방침](https://xrpjwk8.github.io/heariam-help/privacy/#retention)의 2026-11-06 시행 내용이다. 법률 적합성 전체를 보증하는 검토가 아니라, 해당 설명과 현재 앱의 파일 처리 동작을 대조한 구현 기록이다.

## 작업 범위

- 기준: `origin/develop` / `a180344a9324bcdbb3786db66277cded2b4f908f`.
- 작업: `feat/#137-diagnostic-log-retention`, 바탕화면 저장소의 `.worktrees/diagnostic-retention-137`.
- 원격 작업 브랜치까지 푸시하며 PR·develop 병합은 이번 범위에 없다.
- 다른 작업 폴더의 Xcode 서명·scheme 설정과 실제 iPhone 데이터는 변경하지 않는다.

## 저장 구조와 적용 대상

| 위치 | 내용 | 방침에 맞춘 보관 |
| --- | --- | --- |
| `Documents/VoiceLogs/voice-YYYY-MM-DD.jsonl` | 인식된 말, 명령 해석, 대화 및 오류 | 기록일 + 달력상 3개월 |
| `Documents/Trials/trial-UUID.jsonl` | AR 추적, 상대 좌표·방향, 오류, 일부 안내 음성·음성 이벤트 | 기록일 + 달력상 3개월 |
| `Documents/SoundTests/trial-UUID.jsonl` | 소리·몸/고개 방향 시험 진단 | 기록일 + 달력상 3개월 |
| `Documents/Scans/` | 공간 지도, 메시, 경로, 현장 사진·썸네일 | 사용자 삭제까지, 이번 자동 삭제 제외 |
| `Documents/Performances/`, `PerformancePlans/`, `PlaceFolders/` | 공연·씬·장소·주소·사진·분류 | 사용자 삭제까지, 이번 자동 삭제 제외 |
| `Documents/GuidanceRecords/` | 완료한 연습·안내 기록과 다시 보기 | 사용자 삭제까지, 이번 자동 삭제 제외 |
| `Documents/stage-pins.json`, `UserDefaults` | 고정 무대·설정 | 사용자 삭제까지, 이번 자동 삭제 제외 |
| `Library/Caches/VoiceLanguageModel/` | 저장된 무대·장소 이름을 이용한 인식 모델 | 진단 로그가 아님, 후속 캐시 정리 검토 |
| `tmp/HearIAm-photos-*` | 저장 전 사진 작업물 | 진단 로그가 아님, 이번 기간 삭제 제외 |
| `Documents/VoiceTest/inbox.txt` | DEBUG에서 외부 도구가 넣는 시험 입력 | 앱이 작성하는 진단 결과가 아님, 이번 자동 삭제 제외 |

OSLog는 iOS가 관리하는 시스템 로그다. 앱이 직접 저장하는 JSONL과 다른 저장 영역이며, 이번 정리에서 시스템 로그를 지울 수 있다고 주장하지 않는다. 인식 음성 원본과 합성 PCM은 앱의 녹음 파일로 저장하지 않는다.

## 실행 기준

1. `time`(음성 로그) 또는 `wallTime`(추적·소리 로그)의 실제 기록 시각에 Gregorian 달력 3개월을 더해 만료를 계산한다. 90일로 환산하지 않는다. 계산 시간대는 UTC로 고정하여 기기의 시간대 변경으로 보관 기한이 흔들리지 않게 한다.
2. 만료된 행과 최근 행이 섞인 파일에서는 만료된 행만 제거한다. 파일 수정 시각만으로 로그 전체의 기한을 연장하지 않는다.
3. 기존 헤더·잘린 행처럼 기록일을 복원할 수 없는 경우에는 파일 생성일, 생성일이 없으면 수정일을 사용한다. 날짜 자체를 얻을 수 없으면 원본을 보존하고 실패로 보고한다.
4. 알려진 세 폴더와 정확한 파일명에만 적용한다. 다른 파일·하위 폴더·심볼릭 링크는 정리하지 않는다.
5. 앱 시작, 전경 복귀, 실행 중 주기 점검에서 정리한다. 음성 로그 작성도 주기 점검을 요청한다. 쓰고 있는 TrialLog는 건드리지 않으며 닫은 후 정리한다.
6. 큰 파일은 행 단위로 읽고 임시 파일에 결과를 준비한 뒤 교체한다. 읽기·쓰기·교체 실패 시 원본을 보존하고 다음 실행에서 재시도한다. 정리 오류 자체에는 인식 텍스트를 다시 저장하지 않는다.
7. 큰 파일의 읽기·정리본 준비는 쓰기 잠금 밖에서 수행한다. 마지막 삭제/교체 직전에 활성 여부와 파일 식별자·크기·수정시각을 다시 확인한다. 새 행이 추가됐으면 원본을 보존하고 다음 점검으로 넘긴다. 정리 작업들끼리는 별도로 직렬화하여 서로의 임시 파일을 삭제하지 않는다.
8. 비정상 종료로 남은 정확한 `.retention-UUID.tmp` 임시 복사본은 다음 점검에서 회수한다. 다른 숨김 파일은 건드리지 않는다.

앱이 종료되거나 iOS에 의해 실행이 멈춘 동안에는 정확한 만료 시각에 코드를 실행할 수 없다. 다음 실행/복귀에서 누락된 정리를 수행한다. 이미 사용자가 외부로 복사한 파일이나 iCloud·컴퓨터 백업은 앱의 원본 정리로 삭제되지 않는다. 방침에 실행 시점 설명을 보완하는 것을 권한다.

파일 날짜를 읽는 새 동작에 맞춰 `PrivacyInfo.xcprivacy`의 FileTimestamp 사용 사유 `C617.1`을 추가한다. 이는 앱 컨테이너 안의 파일 메타데이터 처리 사유다. [Apple 공식 문서](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)

## 추가 제안 — 이번에는 구현하지 않음

### 1. 이전 장소 자료의 삭제·정정 경로 (우선)

`StageLibrary.loadLibrary`는 최초 이전 시 `PlaceFolders`를 읽은 뒤 원본을 남긴다. `PerformanceCatalog.migrate`는 주소·사진 ID 등을 `legacyPlaces`에도 복제한다. 현재 V3에는 구 장소 관리 화면으로 들어가는 경로가 없고, 공연·공간·스캔 삭제는 구 JSON/JPEG와 `legacyPlaces`를 지우지 않는다. `legacyPath`도 남아 삭제·이름 변경 전 명칭이 음성 검색에 사용될 수 있다.

공연/공간 폴더를 삭제해도 스캔을 보관하는 현재 동작은 UI에 설명돼 있으므로 그대로 존중한다. 대신 사용자에게 남은 구 장소 자료를 확인·삭제할 경로를 제공하고, 자료 삭제/정정 시 원본 JSON·사진, `legacyPlaces`, `legacyPath`를 일관되게 처리하는 것을 제안한다. 자료가 중복 저장돼 있다는 이유만으로 자동 삭제하지 않는다.

관련: `Core/Store/StageLibrary.swift`, `Storage/PerformanceCatalog.swift`, `Storage/PerformanceCatalogStore.swift`, `Places/PlaceFolderStore.swift`.

### 2. 무대·장소 이름이 포함된 음성 모델 캐시

`VoiceLanguageModelBuilder.prepare`는 문구 목록의 해시마다 `VoiceLanguageModel/<hash>`에 모델을 저장한다. 무대/장소 삭제 후 이전 해시 폴더의 이름 정보가 남을 수 있다. 관련 자료 삭제 시 사용 중 모델을 안전하게 해제한 뒤 이전 캐시를 정리하거나, 현재 모델을 제외한 구 모델을 지우는 방식을 제안한다. 3개월 진단 로그와는 별도 수명 관리가 필요하다.

관련: `Voice/Recognition/VoiceSpeechAnalyzer.swift`, `Voice/Agent/GuidanceViewModel+VoiceRehearsal.swift`, `Voice/VoiceVocabulary.swift`.

### 3. 앱 안에서 연습·안내 기록을 직접 삭제

`GuidanceRecordStore`와 기록 화면은 저장·목록·상세 조회를 제공하지만 개별 삭제 기능은 없다. 방침의 파일 앱 관리 설명과 바로 충돌하는 것은 아니지만, 앱 내 개별/전체 삭제를 제공하면 특히 공연자에게 더 접근하기 쉽다. 무대 삭제와 안내 기록 삭제가 별개라는 안내도 함께 제안한다.

관련: `Storage/GuidanceRecordStore.swift`, `Features/Records/View/Screen/GuidanceRecordsView.swift`.

### 4. 운영자가 받은 고객지원 자료의 6개월 보관

방침은 문의 처리 완료 후 6개월 삭제를 명시한다. 이메일·Google Forms·첨부파일의 삭제 일정은 앱 로컬 파일 정리로 이행할 수 없다. 운영 계정의 실제 보관/삭제 상태는 이번 코드 검토에서 확인하지 않았다. 문의 종료일 기록과 해당 시스템의 정기 삭제 절차를 별도로 마련해야 한다.

### 5. 방침 문구와 선택권 보완

자동 정리 시점(실행/복귀, 쓰기 중 파일 종료 후)과 시스템 로그/백업의 범위를 구체적으로 설명하는 것을 제안한다. 개발용으로 모든 인식 문구를 장기 보관할 필요가 없다면 진단 저장 끄기와 텍스트 최소화도 별도 검토할 수 있다. 이는 현재 방침에서 허용한 진단 저장과 별개인 제품 개선 제안이다.

## 코드에서 확인한 기존 일치 사항

- 기기 내 음성 인식을 요구하고 사용할 수 없을 때 서버 인식으로 자동 전환하지 않는 경로가 있다.
- 앱이 백그라운드로 이동하면 음성 입력을 중지한다.
- 사진 선택은 시스템 PhotosPicker를 사용하며 앱은 선택한 사진을 받는다.
- 주요 자료는 앱 Documents에 저장하고 파일 앱 접근을 제공한다.
- 사용자 직접 공유 및 외부 Google Forms 지원 링크는 자동 서버 수집과 분리돼 있다.

## 검증

- Core 전체 XCTest **390개 통과**, 실패 0·skip 0. 신규 보관 테스트 13개 포함.
- 월말·윤년·밀리초 경계·시간대, 오래된 헤더/불완전 행, 재작성 후 날짜 보존, 허용된 파일만 삭제, 심볼릭 링크 제외, 사용자 자료 보존, 임시 복사본 회수, 활성 파일/동시 append 보호, 쓰기 실패 원본 보존을 검증했다.
- 50,000행 + 큰 JSON 행 fixture 처리: Mac 테스트에서 0.521초. 최초 구현의 18.073초에서 개선했으며 iPhone 실측 성능을 의미하지 않는다.
- Xcode 27.1: Debug iOS Simulator 및 Release generic iOS **서명 제외 빌드 성공**.
- 새 iOS 26.5 테스트 기기에서 실제 앱 시작/전경 복귀를 검증했다. 오래된 VoiceLogs/Trials/SoundTests와 중단된 정리 임시 파일은 제거됐고, 혼합 파일의 최근 행·최근 로그·알 수 없는 파일·5종 사용자 자료 폴더의 검사 파일은 바이트 단위로 보존됐다.
- 빌드된 앱의 `PrivacyInfo.xcprivacy`에 FileTimestamp/C617.1이 포함된 것을 확인했다.
- 기존 `CameraView.Coordinator`의 `ARCoachingOverlayViewDelegate` main-actor 적합성 경고가 남아 있다. 이번 변경 파일의 새 경고나 빌드 오류는 없었다. 카메라 경고 수정은 이번 범위에 포함하지 않았다.
- 독립 코드 검토에서 만료 헤더와 중단된 정리 임시 파일의 잔존을 보완했고, 최종 차단 이슈는 발견되지 않았다.
- 실제 사용자 iPhone 자료에는 정리를 실행하지 않았다. 아직 배포하지 않았으며, 테스트는 임시 디렉터리와 새 테스트 기기의 합성 자료만 사용했다.

재검증은 Xcode 개발 도구를 선택한 환경에서 `swift test --package-path Packages/HearIAmCore`로 실행할 수 있다. 앱 빌드는 `Hear-I-am` scheme을 사용한다.
