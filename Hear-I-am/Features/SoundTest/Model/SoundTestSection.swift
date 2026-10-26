import Foundation

/// Sections of the signal tutorial tab (#74): active tones and spoken lines for the user to learn.
enum SoundTestSection: Int, CaseIterable, Identifiable {
    case sounds=1, speech
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .sounds: return "① 신호음 익히기"
        case .speech: return "② 음성 안내 익히기"
        }
    }
    var detail: String {
        switch self {
        case .sounds: return "목표 지점의 방향을 맞출 때와 출발·마지막 지점에서 들리는 소리예요."
        case .speech: return "지점 도착, 다음 지점 방향, 남은 거리, 의자·계단 위치를 알려주는 말이에요."
        }
    }
}
