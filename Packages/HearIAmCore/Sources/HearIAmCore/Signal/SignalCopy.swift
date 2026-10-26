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
    /// Spoken point name on reaching a target spot (#74): 「피원」 · 「피투」 · 「피쓰리」.
    public static func point(_ index: Int) -> String {
        let words=["피제로","피원","피투","피쓰리","피포","피파이브","피식스","피세븐","피에잇","피나인","피텐",
                   "피일레븐","피트웰브","피써틴","피포틴","피피프틴","피식스틴","피세븐틴","피에이틴","피나인틴","피트웬티"]
        return words.indices.contains(index) ? words[index] : "피\(index)"
    }
    /// A DistanceGate mark: 「3미터」 · 「1미터」 · 「50센티」.
    public static func distance(_ meters: Double) -> String {
        meters < 1 ? "\(Int((meters*100).rounded()))센티" : "\(Int(meters.rounded()))미터"
    }
}
