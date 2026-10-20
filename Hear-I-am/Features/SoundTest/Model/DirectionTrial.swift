import Foundation

/// One run of section ④: find a target direction by body or by head.
struct DirectionTrial {
    enum Mode: String { case tick="톡톡톡", head="고개" }
    let mode: Mode
    /// Target relative to the facing direction at start. Positive is right.
    let target: Int
    let bodyStart: Double
    let headStart: Double?
    let startedAt: Double
    var headFoundAt: Double?
    var headLatched=false
    var steadySince: Double?
}

struct DirectionTrialResult: Identifiable {
    let id=UUID()
    let mode: DirectionTrial.Mode
    let target: Int
    let found: Bool
    let seconds: Double
    let bodyError: Double?
    let headError: Double?
    let headFoundSeconds: Double?

    var summary: String {
        var parts=["\(mode.rawValue) · 목표 \(target)°",found ? String(format:"%.1f초",seconds) : "중단 "+String(format:"%.1f초",seconds)]
        if let bodyError { parts.append(String(format:"몸 %+.0f°",bodyError)) }
        if let headError { parts.append(String(format:"고개 %+.0f°",headError)) }
        if let headFoundSeconds { parts.append(String(format:"고개로 찾음 %.1f초",headFoundSeconds)) }
        return parts.joined(separator:" · ")
    }
}
