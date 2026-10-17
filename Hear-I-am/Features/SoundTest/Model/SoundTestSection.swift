import Foundation

/// The four parts of the temporary sound test tab. Titles and descriptions say what each one checks.
enum SoundTestSection: Int, CaseIterable, Identifiable {
    case signals=1, haptics, buzz, direction
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .signals: return "① 신호 하나씩 듣기"
        case .haptics: return "② 허리 진동 느끼기 (PoC1)"
        case .buzz: return "③ 에어팟 부르르 소리"
        case .direction: return "④ 몸 vs 고개로 방향 찾기"
        }
    }
    var detail: String {
        switch self {
        case .signals: return "안내에 쓸 경고음 · 띵 · 음성을 하나씩 틀어요. 겹침은 경고음과 음성을 같이 틀어 말이 묻히는지 봐요."
        case .haptics: return "허리에 찬 폰으로 45° 눈금 진동을 느껴요. 0°·180° 길게 한 번, 45° 한 번, 90° 두 번, 135° 세 번. 위치 추적을 켜면 진동하는 동안 위치가 흔들리는지 함께 보여요. 폰을 가만히 둔 채로 재요."
        case .buzz: return "진동처럼 들리는 낮은 소리예요. 몸이 떨리는 게 아니라 귀로 듣는 소리예요. 높은 소리를 섞으면 저음이 약한 이어폰에서도 들려요."
        case .direction: return "시작하면 앱이 정한 목표 방향을 찾아요. 몸: 몸을 돌리면 허리 진동이 45°마다 울려요. 고개: 고개가 목표를 향하면 에어팟에서 부르르, 몸까지 돌리면 허리 진동 '앞'. 목표를 1초 바라보면 끝나요."
        }
    }
}
