import Foundation

/// Spoken lines for the signal design decided on 10/17: short, four directions, no distances.
public enum SignalCopy {
    public static let turnLeft="왼쪽으로"
    public static let turnRight="오른쪽으로"
    public static let turnBack="뒤로 도세요"
    public static let stepDown="내려갑니다"
    public static func stepUp(stairs: Bool) -> String { "앞에 \(stairs ? "계단" : "단상"), 올라갑니다" }
    public static func escape(toRight: Bool) -> String { "멈추세요. \(toRight ? "오른쪽" : "왼쪽")으로 비켜서세요" }
}
