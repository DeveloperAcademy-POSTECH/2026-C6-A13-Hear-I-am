import Foundation

/// The three parts of the temporary sound test tab. Titles and descriptions say what each one checks.
enum SoundTestSection: Int, CaseIterable, Identifiable {
    case signals=1, buzz, direction
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .signals: return "① 신호 하나씩 듣기"
        case .buzz: return "② 에어팟 부르르 소리"
        case .direction: return "③ 톡톡톡 vs 고개로 방향 찾기"
        }
    }
    var detail: String {
        switch self {
        case .signals: return "안내에 쓸 경고음 · 띵 · 음성을 하나씩 틀어요. 겹침은 경고음과 음성을 같이 틀어 말이 묻히는지 봐요."
        case .buzz: return "진동처럼 들리는 낮은 소리예요. 몸이 떨리는 게 아니라 귀로 듣는 소리예요. 높은 소리를 섞으면 저음이 약한 이어폰에서도 들려요."
        case .direction: return "시작하면 앱이 정한 목표 방향을 찾아요. 톡톡톡: 안내와 같이 목표에서 벗어나면 「왼쪽」·「오른쪽」 한 번과 톡톡톡이 나고, 가까워질수록 빨라지다가 ±n° 안에서 멈춰요. 고개: 고개가 목표를 향하면 에어팟에서 부르르. 목표를 1초 바라보면 끝나요."
        }
    }
}
