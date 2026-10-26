import Foundation

/// Spoken lines for the signal design decided on 10/17: short, four directions, no distances.
public enum SignalCopy {
    public static let left="왼쪽"
    public static let right="오른쪽"
    public static let turnLeft="왼쪽으로"
    public static let turnRight="오른쪽으로"
    public static let turnBack="뒤로 도세요"
    /// Where the next point's chair or stairs lies from the body: 「앞에 의자」 · 「오른쪽에 계단」 (#72).
    /// 「에」 keeps it apart from the turn words 「오른쪽」 · 「왼쪽」. What to do there is not said: the performer knows.
    public static func place(bearing: Double, stairs: Bool) -> String {
        let side=abs(bearing) <= 45 ? "앞에" : abs(bearing) > 135 ? "뒤에" : bearing > 0 ? "오른쪽에" : "왼쪽에"
        return "\(side) \(stairs ? "계단" : "의자")"
    }
    public static func escape(toRight: Bool) -> String { "멈추세요. \(toRight ? "오른쪽" : "왼쪽")으로 비켜서세요" }
    /// Spoken point name on reaching a target spot (#74): 「피일」 · 「피이」 · 「피삼」.
    public static func point(_ index: Int) -> String {
        let words=["피영","피일","피이","피삼","피사","피오","피육","피칠","피팔","피구","피십",
                   "피십일","피십이","피십삼","피십사","피십오","피십육","피십칠","피십팔","피십구","피이십"]
        return words.indices.contains(index) ? words[index] : "피\(index)"
    }
    /// A DistanceGate mark: 「3미터」 · 「1미터」 · 「50센티」.
    public static func distance(_ meters: Double) -> String {
        meters < 1 ? "\(Int((meters*100).rounded()))센티" : "\(Int(meters.rounded()))미터"
    }
}
