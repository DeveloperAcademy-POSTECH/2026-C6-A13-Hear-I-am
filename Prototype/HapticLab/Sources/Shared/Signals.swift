import Foundation

/// 문서 §A4 "안 C · 통로 유지"의 신호 네 개 + 뒤 + 생존 신호.
/// 방향은 모두 **무용수 몸 기준**이다(2026-09-26 결정). 앞은 신호가 없다 — 침묵이 "지금 방향대로"다.
/// "뒤"는 목표가 몸 뒤쪽에 있다는 뜻이다. 돌아설지 뒷걸음질할지는 아직 정하지 않았다.
enum GuideSignal: String, CaseIterable, Codable, Identifiable, Sendable {
    case left, right, back, arrive, stop, heartbeat

    var id: String { rawValue }

    var korean: String {
        switch self {
        case .left:      return "왼쪽"
        case .right:     return "오른쪽"
        case .back:      return "뒤"
        case .arrive:    return "도착"
        case .stop:      return "정지"
        case .heartbeat: return "작동 신호"
        }
    }

    /// 손목에서 어떻게 느껴지는지. 화면에 그대로 보여 준다.
    var feel: String {
        switch self {
        case .left:      return "톡톡 (두 번)"
        case .right:     return "톡 (한 번)"
        case .back:      return "아래로 내려가는 진동"
        case .arrive:    return "성공 진동"
        case .stop:      return "실패 진동 세 번"
        case .heartbeat: return "약한 톡, 4.5초마다"
        }
    }

    /// 신호 맞히기에서 묻는 신호. 작동 신호는 명령이 아니라 배경이라 뺀다.
    static let commands: [GuideSignal] = [.left, .right, .back, .arrive, .stop]

    var symbol: String {
        switch self {
        case .left:      return "arrow.left"
        case .right:     return "arrow.right"
        case .back:      return "arrow.down"
        case .arrive:    return "checkmark.circle"
        case .stop:      return "exclamationmark.octagon"
        case .heartbeat: return "heart"
        }
    }

    /// 문서 §A5.2의 우선순위. 숫자가 작을수록 높다.
    /// 낮은 순위는 높은 순위가 울리는 동안 버린다 — 쌓아 두지 않는다.
    var priority: Int {
        switch self {
        case .stop:      return 1
        case .arrive:    return 2
        case .left,
             .right,
             .back:      return 3
        case .heartbeat: return 4
        }
    }
}

/// 한 번의 탭. `kind` 는 watchOS 의 WKHapticType 이름에 대응한다.
struct HapticTap: Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case click, success, failure, start, stop, retry
        case notification, directionUp, directionDown
    }
    var kind: Kind
    /// 이 탭 **전에** 기다릴 시간(ms). 문서 §B1.3 — 100ms 아래로는 내려갈 수 없다.
    var gapMs: Int
}

/// 탭의 나열. 이것이 우리가 쓸 수 있는 문법의 전부다(§0.5).
struct HapticPattern: Codable, Sendable, Hashable {
    var taps: [HapticTap]

    /// 패턴 하나를 끝까지 재생하는 데 걸리는 최소 시간(ms).
    /// 문서 §A1.1 — 패턴이 길면 그만큼 지시가 늦는다.
    var minimumDurationMs: Int { taps.reduce(0) { $0 + max($1.gapMs, 0) } }

    static func repeated(_ kind: HapticTap.Kind, count: Int, gapMs: Int) -> HapticPattern {
        HapticPattern(taps: (0..<count).map { HapticTap(kind: kind, gapMs: $0 == 0 ? 0 : gapMs) })
    }
}

/// 통로에서 벗어난 정도. 세기를 못 쓰므로 **반복 간격**으로 표현한다(§A4 안 C).
enum Deviation: Int, CaseIterable, Codable, Sendable, Identifiable {
    case slight = 1200, moderate = 600, severe = 300
    var id: Int { rawValue }
    var korean: String {
        switch self {
        case .slight:   return "조금 벗어남"
        case .moderate: return "벗어남"
        case .severe:   return "많이 벗어남"
        }
    }
    /// 반복 주기(ms)
    var repeatMs: Int { rawValue }
}

enum SignalBook {
    /// 문서가 정한 기본 어휘. 실험으로 바뀔 수 있는 값이므로 한 곳에 모아 둔다.
    static let tapGapMs = 140          // 한 패턴 안에서 탭 사이 간격. 100ms 하한 + 여유
    static let heartbeatPeriodSec = 4.5

    static func pattern(for signal: GuideSignal) -> HapticPattern {
        switch signal {
        case .left:
            // 왼쪽 = 탭 두 번
            return .repeated(.click, count: 2, gapMs: tapGapMs)
        case .right:
            // 오른쪽 = 탭 한 번
            return .repeated(.click, count: 1, gapMs: tapGapMs)
        case .back:
            // 뒤 = directionDown 1회. 탭 개수가 아니라 종류로 좌우와 가른다 — 3탭은 2탭(왼쪽)과 뭉개질 수 있다.
            return HapticPattern(taps: [HapticTap(kind: .directionDown, gapMs: 0)])
        case .arrive:
            return HapticPattern(taps: [HapticTap(kind: .success, gapMs: 0)])
        case .stop:
            return HapticPattern(taps: [
                HapticTap(kind: .failure, gapMs: 0),
                HapticTap(kind: .failure, gapMs: 300),
                HapticTap(kind: .failure, gapMs: 300)
            ])
        case .heartbeat:
            return HapticPattern(taps: [HapticTap(kind: .click, gapMs: 0)])
        }
    }
}
