# AirPods 공간 음향으로 앞뒤까지 구분하게 하는 방법

작성 2026-09-29 · 목적: 좌우는 되는데 앞뒤가 안 되는 문제(1번 테스트)를 푼다.

## 한 줄 결론

앞뒤 혼동은 공간 음향의 오래된 약점이고, 푸는 방법은 이미 정리돼 있다. **효과가 큰 순서는 ① 고개 움직임 ② 내 귀에 맞춘 공간 음향 ③ 뒤쪽 높은 음 깎기 ④ 정답을 알려 주는 연습**이다.
그리고 ①②는 **Apple이 iOS 18부터 AVAudioEngine에 공식으로 열어 뒀다.** 우리 앱이 이미 AVAudioEngine을 쓰므로 바로 붙일 수 있다.

## 왜 앞뒤가 헷갈리나

좌우는 두 귀에 닿는 시간·크기 차이로 안다. 정면과 정후면은 그 차이가 둘 다 0이라 좌우 단서로는 못 가른다. 앞뒤를 가르는 단서는 두 가지뿐이다.
- **귓바퀴가 만드는 높은 음역(약 3~7 kHz) 차이** — 사람마다 귀 모양이 달라서, 남의 귀로 만든(일반형) 공간 음향이면 이 단서가 틀어진다
- **고개를 돌렸을 때 소리가 움직이는 방향** — 오른쪽으로 10° 돌리면 앞 소리는 왼쪽으로, 뒤 소리는 오른쪽으로 10° 움직인다

## 방법

### ① 고개 움직임 (가장 강력) `[연구]` `[Apple 공식 API]`
- Wightman & Kistler (1999, JASA 105:2841): 고개를 움직이면 앞뒤 혼동이 사라진다. 고개를 못 움직여도 **본인이 소리를 움직이면** 혼동이 사라졌다
- 우리 테스트에서도 “고개를 돌리면 잘 들린다”는 관찰이 나왔다
- **Apple 공식 API**: `AVAudioEnvironmentNode.isListenerHeadTrackingEnabled` (iOS 18+). 호환 AirPods를 끼면 **시스템이 머리 방향에 맞춰 청취자를 돌려 준다.** 지금 앱은 이걸 CMHeadphoneMotionManager로 직접 하고 있고, 부호 버그를 한 번 냈다. 공식 경로로 바꾸면 그 위험이 없어진다
- 필요한 권한: `com.apple.developer.coremotion.head-pose` 엔타이틀먼트 (Apple 문서 “Personalizing spatial audio in your app”)
- ⚠️ 무대 제약: 고개를 움직여야 효과가 난다. 고개가 안무의 일부라면 쓸 수 있는 순간이 제한된다 — 무용수 확인 필요

### ② 내 귀에 맞춘 공간 음향 (개인 맞춤형 공간 음향) `[Apple 공식 API]`
- iPhone 설정에서 TrueDepth 카메라로 귀·머리를 스캔해 만든 프로필이다
- **엔타이틀먼트 `com.apple.developer.spatial-audio.profile-access` (iOS 18+)** 를 넣으면 이 프로필이 **AVAudioEngine · AUSpatialMixer · PHASE 의 출력에 적용된다**(Apple 문서 원문: “applies the personalized spatial audio profile someone makes in Settings to your app’s audio output”). Xcode에서 **Spatial Audio Profile** capability를 켠다
- 연구상 개인 귀에 맞추면 앞뒤 혼동이 준다(Frank & Zotter 2018 서론에서 정리)
- ⚠️ 2025-01 Apple 개발자 포럼에 “iOS 앱에 이 엔타이틀먼트를 넣었더니 서명에서 거부됐다”는 글이 있다(답변 없음). **우리 팀 계정으로 실제로 서명되는지 해 봐야 안다**
- ⚠️ 무용수 본인이 자기 폰에서 프로필을 만들어야 한다. 운영자 폰의 AirPods로 듣는 구조면 운영자 프로필이 적용된다

### ③ 뒤쪽 높은 음 깎기 (단서 과장) `[연구]`
- Frank & Zotter (2018, DAGA): **3 kHz 하이셸프 필터**로 앞은 높은 음을 +3~6 dB, 뒤는 −3~6 dB. 계산 부담 없음
  - 1차 앰비소닉스 렌더링에서 앞뒤 혼동이 **41% → 27.5%(3 dB) → 15%(6 dB)**. 정후면(180°)에서는 모든 설정이 유의하게 좋아졌다
  - 앞을 6 dB 올리면 “부자연스럽게 날카롭다”는 평, 뒤를 깎는 건 티가 덜 났다
- YouTube·VLC 같은 360° 영상 플레이어도 뒤쪽 소리를 줄이거나(약 6 dB) 높은 음을 깎는(약 7 dB) 방식을 쓴다고 같은 논문이 측정했다
- 우리 앱: AVAudioUnitEQ 하이셸프를 방향에 따라 걸면 된다(아직 없음)

### ④ 정답을 알려 주며 연습 `[연구]`
- Zahorik 외 (2006, JASA 120:343): 일반형 공간 음향으로 **30분 연습 2번**(맞힌 뒤 정답을 보여 줌)만으로 앞뒤 뒤집힘이 5명 중 4명에게서 크게 줄었고, **연습 안 한 방향에도 옮겨 갔고, 4개월 뒤에도 유지**됐다
- 무용수는 어차피 몇 달 연습한다(안무 익히는 데 약 3개월) — 연습 모드가 자연스럽게 들어갈 자리가 있다
- 우리 앱: 1번 테스트에 “답하면 정답 알려 주기” 모드를 넣으면 된다(아직 없음)

### ⑤ 넓은 대역 소리 `[연구]` `[우리 테스트]`
- 한 음짜리 소리(“삐”)엔 3~7 kHz 단서가 없다. 넓은 대역(“쏴”)이어야 ②③이 효과를 낸다
- 우리 테스트(비장애인 1명, 고개 고정, 3D 소리): 정면·정후면만 보면 `삐` 1/4 → `쏴` 4/5. 판 수가 적어 경향으로만 본다

## 우리 앱에 붙이는 순서 (제안)

1. **소리를 `쏴`로** (완료)
2. **공식 머리 추적으로 교체**: `isListenerHeadTrackingEnabled = true` + head-pose 엔타이틀먼트. 직접 만든 부호 계산을 버린다
3. **개인 맞춤 프로필 켜기**: profile-access 엔타이틀먼트. 서명이 되는지부터 확인
4. **뒤쪽 3 kHz 하이셸프 −6 dB, 앞쪽 +3 dB**
5. **정답 알려 주는 연습 모드**
6. 테스트는 **4방향 모드(앞 5 · 뒤 5 · 좌 3 · 우 3)**로 각 단계마다 잰다 — 무엇이 효과를 냈는지 가르려면 한 번에 하나씩 켠다

## 출처

- Wightman & Kistler (1999) Resolution of front–back ambiguity in spatial hearing by listener and source movement. JASA 105(5):2841–2853 — https://www.semanticscholar.org/paper/Resolution-of-front-back-ambiguity-in-spatial-by-Wightman-Kistler/92d5c76079540a608c6492b8db2fdc3504a0fad5
- Zahorik, Bangayan, Sundareswaran, Wang, Tam (2006) Perceptual recalibration in human sound localization: learning to remediate front-back reversals. JASA 120:343–359 — https://pubmed.ncbi.nlm.nih.gov/16875231/
- Frank & Zotter (2018) Simple Reduction of Front-Back Confusion in Static Binaural Rendering. DAGA 2018 — https://pub.dega-akustik.de/DAGA_2018/data/articles/000294.pdf
- Apple · Personalizing spatial audio in your app (PHASE) — https://developer.apple.com/documentation/phase/personalizing-spatial-audio-in-your-app
- Apple · com.apple.developer.spatial-audio.profile-access (iOS 18.0+) — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.spatial-audio.profile-access
- Apple · AVAudioEnvironmentNode.isListenerHeadTrackingEnabled (iOS 18.0+) — https://developer.apple.com/documentation/avfaudio/avaudioenvironmentnode/islistenerheadtrackingenabled
- Apple 개발자 포럼 · 엔타이틀먼트 서명 거부 사례 (2025-01, 답변 없음) — https://developer.apple.com/forums/thread/772104
