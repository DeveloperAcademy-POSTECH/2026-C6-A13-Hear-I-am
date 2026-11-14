import Foundation

/// Spoken lines for the signal design decided on 10/17: short, four directions, no distances.
public enum SignalCopy {
    public static var start: String { L("출발") }
    public static var holdStart: String { HearLanguage.current.isEnglish ? "Wait" : "대기" }
    public static var holdEnd: String { L("대기 끝") }
    public static var left: String { L("왼쪽") }
    public static var right: String { L("오른쪽") }
    public static var turnLeft: String { L("왼쪽으로") }
    public static var turnRight: String { L("오른쪽으로") }
    public static var turnBack: String { L("뒤로 도세요") }
    /// Where the next point's chair or stairs lies from the body: 「앞에 의자」 · 「오른쪽에 계단」 (#72).
    public static func place(bearing: Double, stairs: Bool) -> String {
        let side=abs(bearing) <= 45 ? L("앞에") : abs(bearing) > 135 ? L("뒤에") : bearing > 0 ? L("오른쪽에") : L("왼쪽에")
        let object=stairs ? L("계단") : L("의자")
        // English names the object first: "Chair ahead".
        return HearLanguage.current.isEnglish ? "\(object) \(side)" : "\(side) \(object)"
    }
    /// Short object hint spoken once after aligning toward a chair or stairs before distance marks (#76): 「의자」 · 「계단」.
    public static func stepHint(stairs: Bool) -> String { stairs ? L("계단") : L("의자") }
    /// Spoken orientation cue when aligning with the green `facingEdge` on a chair or stairs (#76): 「오른쪽 봐」 · 「왼쪽 봐」.
    public static func look(toRight: Bool) -> String { L("%@ 봐", (toRight ? right : left).lowercased()) }
    public static func escape(toRight: Bool) -> String { L("멈추세요. %@으로 비켜서세요", (toRight ? L("오른쪽") : L("왼쪽")).lowercased()) }
    /// Sino-Korean number words used for spoken point names (#74, #76).
    public static func koreanNumber(_ index: Int) -> String {
        // The English voice reads digits by itself.
        if HearLanguage.current.isEnglish { return "\(index)" }
        let words=["영","일","이","삼","사","오","육","칠","팔","구","십",
                   "십일","십이","십삼","십사","십오","십육","십칠","십팔","십구","이십"]
        return words.indices.contains(index) ? words[index] : "\(index)"
    }
    /// Spoken point name on reaching a floor target spot (#74, #88): 「피원」 · 「피투」 · 「피쓰리」.
    public static func point(_ index: Int) -> String {
        // The Hangul spellings make the Korean voice say "P one"; the English voice reads "P 1" as it is.
        if HearLanguage.current.isEnglish { return "P \(index)" }
        let words=["피제로","피원","피투","피쓰리","피포","피파이브","피식스","피세븐","피에잇","피나인","피텐",
                   "피일레븐","피트웰브","피써틴","피포틴","피피프틴","피식스틴","피세븐틴","피에이틴","피나인틴","피트웬티"]
        return words.indices.contains(index) ? words[index] : "피\(index)"
    }
    /// Spoken point name on reaching a chair or stairs target spot (#76): 「의자일」 · 「계단일」.
    public static func stepPoint(stairs: Bool, number: Int) -> String {
        let object=stairs ? L("계단") : L("의자")
        return HearLanguage.current.isEnglish ? "\(object) \(number)" : "\(object)\(koreanNumber(number))"
    }
    /// A DistanceGate mark: 「3미터」 · 「1미터」 · 「50센티」.
    public static func distance(_ meters: Double) -> String {
        if meters < 1 { return L("%@센티", Int((meters*100).rounded())) }
        let whole=Int(meters.rounded())
        return whole == 1 && HearLanguage.current.isEnglish ? "1 meter" : L("%@미터", whole)
    }
}
