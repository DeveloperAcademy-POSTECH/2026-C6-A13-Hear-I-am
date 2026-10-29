import Foundation

enum VoiceUsageMode: String, CaseIterable, Identifiable {
    case practice, performance
    var id: String { rawValue }
    var title: String { self == .practice ? "연습용" : "실전용" }
    var detail: String { self == .practice ? "말로 지점 이동 · 반복" : "안내 중 마이크 꺼짐" }
    var symbol: String { self == .practice ? "figure.walk" : "mic.slash.fill" }
}
