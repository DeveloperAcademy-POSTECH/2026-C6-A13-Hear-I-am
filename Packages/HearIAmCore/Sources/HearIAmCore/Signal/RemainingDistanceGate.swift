import Foundation

/// Explicit Korean pronunciation avoids the synthesizer choosing a unit or decimal convention.
public struct DistanceAnnouncement: Equatable, Sendable {
    public let meters: Double
    public let tenths: Int
    public init?(meters: Double) {
        guard meters.isFinite, meters >= 0, meters < 1000 else { return nil }
        self.meters=meters;tenths=Int((meters*10).rounded())
    }
    public var line: String {
        let digits=["영","일","이","삼","사","오","육","칠","팔","구"]
        let whole=tenths/10, fraction=tenths%10
        var integer=""
        for (unit,name) in [(1000,"천"),(100,"백"),(10,"십"),(1,"")] {
            let digit=(whole/unit)%10
            if digit > 0 { integer += (digit == 1 && unit > 1 ? "" : digits[digit])+name }
        }
        if integer.isEmpty { integer="영" }
        return integer+(fraction > 0 ? "점"+digits[fraction] : "")
    }
}

/// Reads the latest remaining distance, never a backlog of crossed thresholds.
/// Commit only when playback starts. Preserve this state across pauses/realignment of the same leg.
public struct RemainingDistanceGate: Sendable {
    private var last: DistanceAnnouncement?
    public var hasAnnounced: Bool { last != nil }
    public init() {}
    public mutating func reset() { last=nil }
    public func candidate(meters: Double) -> DistanceAnnouncement? {
        guard let next=DistanceAnnouncement(meters:meters) else { return nil }
        guard let last else { return next }
        let spacing=meters <= 2 ? 0.5 : 1.0
        guard last.meters-meters >= spacing-1e-6, next.tenths != last.tenths else { return nil }
        return next
    }
    public mutating func didSpeak(_ announcement: DistanceAnnouncement) { last=announcement }
}
