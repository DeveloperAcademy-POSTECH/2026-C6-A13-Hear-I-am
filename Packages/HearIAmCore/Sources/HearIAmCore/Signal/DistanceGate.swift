import Foundation

/// Remaining distance, spoken at marks on the way to a target (decided 10/19): every metre while more
/// than 1 m away, then 1 m and 0.5 m. A walk of 0.5 m takes about a second, so every 0.5 m all the way
/// would talk almost without pause; near the target 「50센티」 doubles as the "about to arrive" cue
/// (on 10/19 the performer walked 0.3–0.8 m past two points).
/// Each mark is said at most once per leg, so swaying across a mark does not repeat it. Marks at or
/// above the starting distance (less `startMargin`) are never said.
public struct DistanceGate: Sendable {
    public static let marks: [Double]=[0.5]+(1...10).map(Double.init)
    public static let startMargin=0.1
    private var target: FloorPoint?
    private var pending: [Double]=[]
    public init() {}
    public mutating func reset() { target=nil;pending=[] }

    /// The mark just reached, or nil. When a jump passes several marks only the nearest one is returned.
    public mutating func update(position: FloorPoint, target goal: FloorPoint) -> Double? {
        guard position.valid, goal.valid else { return nil }
        let distance=position.distance(to:goal)
        if target != goal {
            target=goal;pending=Self.marks.filter { $0 < distance-Self.startMargin };return nil
        }
        let due=pending.filter { distance <= $0 }
        guard let nearest=due.min() else { return nil }
        pending.removeAll { distance <= $0 }
        return nearest
    }
}
