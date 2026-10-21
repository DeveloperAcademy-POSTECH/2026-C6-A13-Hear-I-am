import Foundation

/// The two parts of the sound test tab: every tone and every spoken line guidance uses, nothing else (10/21).
enum SoundTestSection: Int, CaseIterable, Identifiable {
    case sounds=1, speech
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .sounds: return "① 신호음"
        case .speech: return "② 음성"
        }
    }
    var detail: String {
        switch self {
        case .sounds: return "안내 중에 나는 소리를 같은 크기로 하나씩 틀어요."
        case .speech: return "안내 중에 나오는 말을 같은 크기로 하나씩 틀어요."
        }
    }
}
