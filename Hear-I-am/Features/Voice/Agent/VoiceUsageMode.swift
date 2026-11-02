import Foundation
import HearIAmCore

enum VoiceUsageMode: String, CaseIterable, Identifiable {
    case practice, performance
    var id: String { rawValue }
    var title: String { self == .practice ? "연습용" : "실전용" }
    var detail: String { self == .practice ? "말로 지점 이동 · 반복" : "안내 중 마이크 꺼짐" }
    var symbol: String { self == .practice ? "figure.walk" : "mic.slash.fill" }
}

/// One line of the performer's conversation with the agent (Figma 495:5096–5481): what the performer said,
/// what the app answered, or the performances it found.
struct VoiceChatEntry: Identifiable {
    enum Kind {
        case user(String)
        case app(String)
        /// A line of text followed by the cards it is about (Figma 495:5160).
        case stages(String,[VoiceChatStage])
    }
    let id=UUID()
    let kind: Kind
    let date=Date()
}

/// A performance or stage card in the conversation: a small plan of its route with the name and place tags.
struct VoiceChatStage: Identifiable {
    let id: UUID
    let number: Int
    let name: String
    let tags: [String]
    let width: Double
    let depth: Double
    let points: [FloorPoint]
    let objects: [StageObstacle]
}
