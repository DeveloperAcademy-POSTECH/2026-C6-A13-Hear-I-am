import Foundation

/// Spoken lines for the signal design decided on 10/17: short, four directions, no distances.
public enum SignalCopy {
    public static let left="왼쪽"
    public static let right="오른쪽"
    public static let turnLeft="왼쪽으로"
    public static let turnRight="오른쪽으로"
    public static let turnBack="뒤로 도세요"
    public static let stepDown="내려갑니다"
    public static func stepUp(stairs: Bool) -> String { "앞에 \(stairs ? "계단" : "단상"), 올라갑니다" }
    public static func stepOver(stairs: Bool) -> String { "앞에 \(stairs ? "계단" : "단상"), 올라갔다 내려갑니다" }
    public static func escape(toRight: Bool) -> String { "멈추세요. \(toRight ? "오른쪽" : "왼쪽")으로 비켜서세요" }
    /// A DistanceGate mark: 「3미터」 · 「1미터」 · 「50센티」.
    public static func distance(_ meters: Double) -> String {
        meters < 1 ? "\(Int((meters*100).rounded()))센티" : "\(Int(meters.rounded()))미터"
    }
    /// Positive bearing is right. Past ±135° the way out is behind: on 10/19 the line said 「오른쪽」
    /// while the vibration said 「뒤」, because the sign of a bearing near 180° is arbitrary.
    public static func escape(bearing: Double) -> String { abs(bearing) > 135 ? "멈추세요. "+turnBack : escape(toRight:bearing > 0) }
}
