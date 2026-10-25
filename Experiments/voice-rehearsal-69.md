# #69 음성 안내 준비·연습 제어 기술 검증

- 갱신: 2026-10-25, 사용자 요청에 따라 자동 선택·안내 중 끼어들기·흑백 UI로 개편
- 이슈: [#69](https://github.com/DeveloperAcademy-POSTECH/2026-C6-A13-Hear-I-am/issues/69)
- 작업 브랜치: `feat/#69-voice-rehearsal-poc`
- 분기 기준: `origin/develop`의 `293dae021f8d3273e07e7ceccae6ae598d8310f9`
- 생성 시각: 2026-10-25 14:18:26 +0900, 브랜치 생성 reflog로 확인
- 작업 위치: `/Users/sangyoung/Desktop/2026-C6-A13-Hear-I-am/.worktrees/voice-rehearsal-69`
- 이번 세션에서 생성한 최신 작업 브랜치는 #69다. 저장소 전체의 다른 브랜치 분기 순서는 확정하지 않는다.
- 커밋·원격 푸시까지만 진행하며 PR은 생성하지 않는다. 기존 #48 실험은 가져오지 않는다.

## 1. 현재 구현과 검증 수준

| 항목 | 상태 |
| --- | --- |
| 코어 테스트 | 212개 통과. 기존 명령·복귀 검사에 무대 검색 시나리오 6개 추가 |
| iOS Simulator Debug | 개편된 전체 앱 빌드 통과 |
| iPhone Release | 최종 Release 서명 제외 빌드 통과 (`CODE_SIGNING_ALLOWED=NO`) |
| 실제 화면 | 전용 iPhone 17 Pro / iOS 26.5 시뮬레이터 실행 및 홈 흑백 버튼 캡처 확인 |
| 선택 화면 조작 | Device Hub 접근 지연으로 터치·권한·모드 전환의 자동 UI 확인은 미완료 |
| 실제 마이크·AR 이동 | 미실시. 기기 내 한국어 인식, 끼어들기, 에코, 이어폰, P2 복귀 현장 검증 필요 |

기준 develop의 방향음·도착음·기물 경고·현장 확인·착용·출발 조건을 유지한다. 삭제된 8초 카운트다운은 복원하지 않는다. 기존 사용자 Xcode 서명 설정은 변경하거나 커밋하지 않는다.

## 2. 사용자 흐름

`홈 → 무대 검색·선택 → 연습용/실전용 → 현장 확인 → 착용 → 출발`

무대와 모드를 선택할 때는 별도 확인 버튼이나 ‘다음’을 요구하지 않는다. 현장·착용·출발 단계에는 기존 위치 확인 조건과 사용자의 진행 요청이 필요하다.

| 단계 | 사용자 입력 | 앱 응답 |
| --- | --- | --- |
| 홈 | ‘말로 안내 시작’ | 권한·인식 준비 후 띠링, ‘어느 무대를 사용할까요?’ |
| 검색 | ‘효자아트홀과 관련된 무대 열어줘’ | 저장된 이름에서 관련 무대를 찾고 번호·이름을 읽음 |
| 결과 선택 | ‘효자아트홀 I believe’, ‘1번’, 화면 누르기 | 사용 방식 화면으로 즉시 이동 |
| 선택 알림 | 이어서 듣거나 말로 끼어들기 | ‘효자아트홀 I believe가 선택되었습니다’ 후 연습용·실전용 질문 |
| 모드 선택 | ‘연습용’ 또는 ‘실전용’ | 확정과 동시에 공간 복원·현장 확인 단계로 이동 |
| 취소 | ‘취소’ 또는 ‘취소 · 이전 선택’ | 사용 방식→직전 무대 목록, 검색 결과→전체 목록, 안내 시작 전 준비→사용 방식 선택 |

검색 대상은 이 iPhone에 저장된 무대 이름이다. 외부 공연장 검색이나 자유로운 AI 추천은 포함하지 않는다. 검색 결과가 1개여도 검색 요청만으로 선택하지 않는다. 정확한 이름이 하나로 일치할 때만 자동 선택하며, 중복 이름은 결과 목록의 번호로 구분한다. 번호는 항상 현재 보이는 목록을 기준으로 한다.

무대 선택 화면에서는 모드 버튼을 먼저 보여주지 않는다. 모드 화면에는 선택된 무대와 연습용·실전용만 표시한다. 음성 대신 버튼으로 선택해도 동일하게 자동 진행한다.

## 3. 안내 중 끼어들기

초기 버전의 ‘TTS가 끝난 뒤 듣기’ 정책을 제거했다.

1. 안내를 읽는 중에도 음성 인식을 유지한다.
2. 발화가 감지되면 읽던 안내와 뒤에 예약된 설명을 멈추고 띠링을 재생한다.
3. 이동 중이면 안내를 일시정지하고 사용자에게 잠시 멈추도록 표시한다.
4. 첫 음절을 포함한 같은 인식 턴을 계속 사용한다. 부분 결과는 화면에 표시하고, 확정 문장만 실행한다.
5. 선택·취소에 따른 화면 전환 시 이전 인식 턴을 폐기해 늦은 결과가 다음 화면에서 실행되지 않도록 한다.

`AVSpeechSynthesizer.write`로 만든 PCM을 마이크 입력과 같은 voice-processing 엔진의 `AVAudioPlayerNode`로 재생한다. 앱의 음성 출력을 에코 제거의 참조 경로에 연결하기 위한 구성이다. 합성 완료 시점이 아니라 마지막 버퍼의 실제 재생 완료를 안내 완료 기준으로 삼는다.

발화 감지와 에코 제거는 착용자만 식별하는 기술이 아니다. 자체 낭독·주변 대화·음악으로 잘못 듣기가 시작되는지 실제 기기에서 확인해야 한다. VoiceOver는 앱 TTS와 별개이므로 함께 사용하는 시험도 필요하다.

- [Apple voice processing과 출력 경로](https://developer.apple.com/videos/play/wwdc2023/10235/)
- [AVSpeechSynthesizer PCM 출력](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:))
- [AVAudioEngine voice processing](https://developer.apple.com/videos/play/wwdc2019/510/)

## 4. 연습 복귀와 실전 모드

### 연습 중 P2 복귀

`발화 감지 → 일시정지·띠링 → 명령 확정 → 역방향 경로 검사 → P2 복귀 → 도착 알림·대기 → ‘계속’ → P3 재개`

- 이미 지나온 내부 지점으로만 복귀한다. 출발점·최종점·미방문점·복귀 중 다른 복귀 요청은 제외한다.
- 현재 위치가 최신이며 저장 동선 위에 있는지, 역방향 모든 구간에서 기물 통과가 가능한지 검사한다.
- 현재 위치에서 P2로 직선 지름길을 만들지 않고 저장 경로를 되짚는다.
- P2 도착은 기존 반경·유지 시간 조건으로 판정하며 전체 공연 완료로 처리하지 않는다.
- ‘계속’ 전에는 자동으로 다음 지점으로 이동하지 않는다. 재개 시 위치 조건을 다시 확인한다.

### 실전 입력 차단

- 준비 중에는 음성 선택·취소·진행이 가능하다.
- 시작 단계 진입 시 마이크 입력 tap·엔진·인식 task·예약 재시작을 종료한다.
- 입력 차단 상태를 별도로 유지하므로 시작 설명의 수동 일시정지·위치 추적 중단·재개로 마이크가 다시 켜지지 않는다.
- 안내 시작 전 선택을 명시적으로 취소해 모드 선택으로 돌아온 경우에만 차단 상태를 초기화한다.

## 5. 기술 후보와 선택 근거

VAD는 말소리 존재 감지, ASR은 말소리를 글자로 바꾸는 역할이다. 아래 표는 실제 기기 성능 순위가 아니라 공식 자료로 확인한 기능·제약 비교다.

| 후보 | 역할·확인 내용 | 판단 |
| --- | --- | --- |
| Apple SFSpeechRecognizer | 한국어 로케일, 부분·최종 전사, 최초 발화 감지 delegate, 기기 내 인식 지원 조회 | 현재 적용. 기기별 실제 가용성 확인 필요 |
| SpeechAnalyzer + SpeechTranscriber | iOS 26 이상 기기 내 스트리밍 전사와 모델 관리 | 최소 iOS 17과 병행하는 후속 비교 후보 |
| SpeechDetector | SpeechAnalyzer의 VAD 모듈 | `results`는 오류 외 비어 있으므로 단독 발화 시작 UI 콜백으로 사용하지 않음 |
| SoundAnalysis | 실시간 소리 분류, 내장 또는 Core ML 모델 | 내장 분류 창 최소 0.5초. 감지 지연·오탐 실측 필요 |
| Silero VAD | 스트리밍 음성 존재 확률, 8/16kHz, MIT 라이선스 | iOS 런타임·모델·입력 변환 추가 필요 |
| WhisperKit / Argmax Swift SDK | Swift·Core ML 기기 내 전사 | 모델 준비·메모리·발열·AR 동시 실행 성능 검증 필요 |
| Google Cloud Speech-to-Text | 한국어 스트리밍 전사와 발화 시작·끝 이벤트 | 모델·지역별 기능, gRPC·인증·네트워크·비용 검토 필요. 미연결 |

공식 근거:

- [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer), [delegate](https://developer.apple.com/documentation/speech/sfspeechrecognitiontaskdelegate), [기기 내 인식 지원](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- [SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/), [SpeechDetector results](https://developer.apple.com/documentation/speech/speechdetector/results)
- [SoundAnalysis](https://developer.apple.com/videos/play/wwdc2021/10036/)
- [Silero VAD](https://github.com/snakers4/silero-vad), [Argmax Swift SDK](https://github.com/argmaxinc/argmax-oss-swift)
- [Google 발화 이벤트](https://docs.cloud.google.com/speech-to-text/docs/voice-activity-events), [지원 언어·모델](https://cloud.google.com/speech-to-text/v2/docs/speech-to-text-supported-languages)

현재는 `AVAudioEngine → SFSpeechRecognizer(ko-KR) → 확정 문장 → 이름 검색/제한된 명령 해석 → 기존 상태·경로 검사` 구조다. 경로 판단은 생성형 AI에 맡기지 않는다.

## 6. 권한·타이밍·오류

- 최초 마이크·Speech 권한을 요청하고 `isAvailable`, `supportsOnDeviceRecognition`을 확인한다.
- 모든 요청에 `requiresOnDeviceRecognition=true`를 지정한다. 미지원·권한 거절 시 서버로 자동 전환하지 않고 이유와 버튼 대체 흐름을 제공한다.
- `contextualStrings`는 저장 이름과 명령을 돕는 힌트이며 강제 문법이나 정확도 보장이 아니다. [Apple contextualStrings](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings)
- 인식 오류가 앱으로 전달되면 입력을 종료하고 수동 재시도를 요구한다.
- 전화·오디오 장치 변경·백그라운드에서 입력을 종료한다. 앱 복귀 후 자동으로 마이크를 다시 켜지 않는다.
- 수동 재청취는 진행 중 안내를 먼저 멈춘다. 위치 추적·기물 문제의 기존 복구 절차는 유지한다.
- HFP와 A2DP의 입력·출력 차이 때문에 이어폰 음질과 실제 오디오 경로를 별도로 확인한다. [Apple Bluetooth 경로](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetootha2dp)

| 설정 | 초기 값 | 의미 |
| --- | --- | --- |
| 대기 작업 교체 | 48초 | 장시간 단일 Speech 작업을 교체 |
| 마지막 부분 결과 뒤 입력 마감 | 1.1초 | 종료 후보 판단. 실제 무음 검출과 동일하지 않음 |
| 발화 최대 입력 | 12초 | 끝나지 않는 입력 제한 |
| 최종 결과 대기 | 3초 | 부분 결과를 임의 실행하지 않음 |
| 확정 명령 뒤 다음 턴 | 0.05초 | 다음 선택 안내 중에도 듣도록 재시작 |

위 값은 구현 상수이며 측정한 반응 속도가 아니다.

## 7. 기록과 UI 범위

- 기존 위치·시간·방향·목표 지점·상태 샘플과 `voice_listening`, `voice_command`, `rehearsal_return_requested`, `rehearsal_return_arrived`, `rehearsal_forward_resumed` 로그를 유지한다. 마이크 원본 녹음 파일은 저장하지 않는다.
- 기존 리플레이 도착·구간 분석에는 순방향 전제가 남아 있다. 복귀를 별도 연습 회차로 분리한 평가·점수·AI 코칭은 미구현이다.
- 홈 음성 버튼, 검색·무대 선택, 모드 선택, 듣기·취소·안내 UI는 흑백·회색이다. 실제 AR 공간의 지점·경고 렌더링은 기존 상태를 유지한다.
- 초기 녹색 시안 2장은 이전 흐름의 기획 자료이며 현재 구현과 동일하지 않다. 이력은 이 문서의 이전 커밋과 `outputs/voice-rehearsal-69`의 이미지에서 확인한다.

## 8. 실제 기기 검증 순서

1. 같은 iPhone에 저장된 무대 3개를 준비한다. 예: ‘효자아트홀 I believe’, ‘효자아트홀 입장 동선’, ‘연습실 A’.
2. 홈에서 음성 시작·권한·띠링을 확인한다. 정확한 이름을 말하면 별도 확인 없이 모드 화면으로 이동해야 한다.
3. ‘효자아트홀과 관련된 무대 열어줘’로 2개 결과와 번호를 확인하고, 결과 번호로 선택한다.
4. 선택 알림을 읽는 도중 ‘취소’로 결과 목록에 돌아간다. 다시 취소하면 전체 목록이어야 한다. 취소한 화면의 늦은 결과가 실행되면 안 된다.
5. 다시 선택한 뒤 안내 중 ‘연습용’을 말한다. 자동으로 현장 확인에 진입하되 확인점·착용·출발 조건은 건너뛰지 않아야 한다.
6. P2를 지난 후 안내 도중 ‘P2로 다시 안내해줘’를 말한다. 띠링 뒤 멈추고, 복귀·도착 대기·‘계속’ 후 P3 재개를 확인한다.
7. 실전으로 새로 시작해 시작 설명·일시정지·추적 중단·재개 내내 마이크가 꺼져 있는지 확인한다.

추가 검증표:

| 조건 | 확인 항목 |
| --- | --- |
| 권한 거절·기기 내 인식 미지원 | 오류 이유, 마이크 꺼짐, 버튼 대체, 반복 팝업 없음 |
| 중복 이름·없는 키워드·범위 밖 번호 | 임의 선택 없음, 결과 목록과 음성 번호 일치 |
| 설명 중 짧은 답변 | ‘취소’, ‘연습용’, ‘실전용’, ‘1번’ 첫 음절 보존·중복 실행 없음 |
| 앱 낭독만 재생 | 자기 목소리로 선택·취소·복귀가 실행되지 않음 |
| 스피커·유선·AirPods·VoiceOver | 에코·오탐·안내 음량·입력 경로·중복 음성 확인 |
| 박수·음악·주변 대화 | 잘못된 듣기 시작과 명령 실행 횟수 기록 |
| 10분 이상 반복 | 작업 교체 전후 입력, 메모리·발열·AR 동시 실행 확인 |
| 미방문점·단상 역방향·추적 실패 | 기존 경로를 손상하지 않고 거절·복구 |
| 전화·이어폰 해제·배경 이동·종료 경쟁 | 입력·예약 작업 종료, 이전 결과 실행 없음 |
| 실전 시작 설명을 수동 일시정지 | 안내 시작 전의 상태로 보여도 마이크 자동 재활성 없음 |
| 복귀 후 기록 저장·재생 | 원본 샘플·이벤트 보존, 연습 회차 분석 한계와 오류 구분 |

기록할 값: 기기·iOS·커밋·입출력 장치·환경, 실제 발화와 최종 문장, 발화 시작→띠링 및 발화 종료→동작 지연, 첫 음절 누락·오탐·잘못된 선택·중복 실행 횟수, AR 추적 상태와 마이크 종료 여부. 한 번의 성공을 일반적인 인식률로 표현하지 않는다.
