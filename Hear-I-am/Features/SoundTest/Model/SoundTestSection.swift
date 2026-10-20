import Foundation

/// The four parts of the temporary sound test tab. Titles and descriptions say what each one checks.
enum SoundTestSection: Int, CaseIterable, Identifiable {
    case signals=1, haptics, buzz, direction
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .signals: return "① 신호 하나씩 듣기"
        case .haptics: return "② 허리 진동 + 방향 비프 (PoC1)"
        case .buzz: return "③ 에어팟 부르르 소리"
        case .direction: return "④ 몸 vs 고개로 방향 찾기"
        }
    }
    var detail: String {
        switch self {
        case .signals: return "안내에 쓸 경고음 · 띵 · 음성을 하나씩 틀어요. 겹침은 경고음과 음성을 같이 틀어 말이 묻히는지 봐요."
        case .haptics: return "허리에 찬 폰으로 45° 눈금 진동을 느껴요. 0°·180° 길게 한 번, 45° 한 번, 90° 두 번, 135° 세 번. 같은 순간에 에어팟으로 방향 비프도 나요(왼쪽 낮게 · 오른쪽 높게 · 앞 1번 · 뒤 2번). 진동만 · 비프만 · 둘 다 선택은 이 비교 테스트에만 적용해요. 현재 안내는 왼쪽 높은 음·오른쪽 낮은 음의 3·2·1 비프와 정렬 띠링을 사용해요. 위치 추적을 켜면 진동하는 동안 위치가 흔들리는지 함께 보여요. 폰을 가만히 둔 채로 재요."
        case .buzz: return "진동처럼 들리는 낮은 소리예요. 몸이 떨리는 게 아니라 귀로 듣는 소리예요. 높은 소리를 섞으면 저음이 약한 이어폰에서도 들려요."
        case .direction: return "지속음과 3·2·1 비프를 몸·고개로 비교해요. 비프는 왼쪽 높은 음, 오른쪽 낮은 음이며 맞으면 띠링 후 무음이에요. 지속음은 정렬 후에도 작은 60Hz가 이어져요."
        }
    }
}
