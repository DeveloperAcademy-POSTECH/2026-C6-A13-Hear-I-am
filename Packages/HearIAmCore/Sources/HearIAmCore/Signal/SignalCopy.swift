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
    /// Sino-Korean number words used for spoken point names (#74, #76).
    public static func koreanNumber(_ index: Int) -> String {
        let words=["영","일","이","삼","사","오","육","칠","팔","구","십",
                   "십일","십이","십삼","십사","십오","십육","십칠","십팔","십구","이십"]
        return words.indices.contains(index) ? words[index] : "\(index)"
    }
    /// Spoken point name on reaching a floor target spot (#74): 「피일」 · 「피이」 · 「피삼」.
    public static func point(_ index: Int) -> String {
        "피\(koreanNumber(index))"
    }
    /// Spoken point name on reaching a chair or stairs target spot (#76): 「의자일」 · 「계단일」.
    public static func stepPoint(stairs: Bool, number: Int) -> String {
        "\(stairs ? "계단" : "의자")\(koreanNumber(number))"
    }
    /// A DistanceGate mark: 「3미터」 · 「1미터」 · 「50센티」.
    public static func distance(_ meters: Double) -> String {
        meters < 1 ? "\(Int((meters*100).rounded()))센티" : "\(Int(meters.rounded()))미터"
    }
}
