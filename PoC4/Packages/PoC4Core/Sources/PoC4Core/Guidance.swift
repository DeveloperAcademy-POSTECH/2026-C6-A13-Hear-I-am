import Foundation

extension FloorPoint {
    public func distance(toSegmentFrom a: FloorPoint, to b: FloorPoint) -> Double {
        let dx=b.x-a.x, dy=b.y-a.y, n=dx*dx+dy*dy
        let t=n > 0 ? max(0,min(1,((x-a.x)*dx+(y-a.y)*dy)/n)) : 0
        return hypot(x-a.x-t*dx,y-a.y-t*dy)
    }
}

public enum GuidanceCopy {
    public static let completed="마지막 지점에 도착했습니다. 안내를 종료합니다."
    public static func target(_ index: Int, last: Int) -> String {
        if index == last { return "마지막 지점" }
        let ordinals=["출발점","첫 번째 지점","두 번째 지점","세 번째 지점","네 번째 지점"]
        return ordinals.indices.contains(index) ? ordinals[index] : "\(index)번째 지점"
    }
}

public struct GuidanceCue: Equatable, Sendable {
    public let sector: Int
    public let distance: Double
    public var direction: String { ["앞","오른쪽 앞","오른쪽","오른쪽 뒤","뒤","왼쪽 뒤","왼쪽","왼쪽 앞"][sector] }
    public var symbol: String { ["arrow.up","arrow.up.right","arrow.right","arrow.down.right","arrow.down","arrow.down.left","arrow.left","arrow.up.left"][sector] }
    public var speech: String { String(format:"%@, %.1f미터.",direction,distance) }
    public init?(position: FloorPoint, goal: FloorPoint, headingDegrees: Double, sector: Int? = nil) {
        guard position.valid, goal.valid, headingDegrees.isFinite else { return nil }
        let r=headingDegrees * .pi/180
        let forward=FloorPoint(-sin(r),-cos(r)), right=FloorPoint(-cos(r),sin(r))
        let dx=goal.x-position.x, dy=goal.y-position.y
        let angle=atan2(dx*right.x+dy*right.y,dx*forward.x+dy*forward.y)*180 / .pi
        let normalized=(angle+360).truncatingRemainder(dividingBy:360)
        self.sector=sector.flatMap { (0..<8).contains($0) ? $0 : nil } ?? Int(floor((normalized+22.5)/45))%8
        distance=position.distance(to:goal)
    }
}

/// Platform-independent sequencing. Late finish callbacks can never finish a replacement message.
public struct NarrationQueue: Sendable {
    public struct Line: Equatable, Sendable {
        public let id: UUID
        public let text: String
    }
    public private(set) var current: Line?
    private var pending: [Line] = []
    public private(set) var protectsCompletion=false
    public init() {}
    @discardableResult public mutating func replace(_ texts: [String], completion: Bool = false) -> Line? {
        guard !protectsCompletion else { return nil }
        pending=texts.filter { !$0.isEmpty }.map { Line(id:UUID(),text:$0) }
        current=pending.isEmpty ? nil : pending.removeFirst()
        protectsCompletion=completion && current != nil
        return current
    }
    @discardableResult public mutating func offerDirection(_ text: String) -> Line? {
        guard current == nil else { return nil }
        return replace([text])
    }
    /// Returns false for a canceled/old utterance. True means this line actually finished.
    @discardableResult public mutating func finish(_ id: UUID) -> Bool {
        guard current?.id == id else { return false }
        current=pending.isEmpty ? nil : pending.removeFirst()
        if current == nil { protectsCompletion=false }
        return true
    }
    public mutating func cancel() { current=nil; pending=[]; protectsCompletion=false }
}

/// Readiness requires fresh, consecutive samples; a single matching frame never starts guidance.
public struct DepartureGate: Sendable {
    private var since: Double?
    private var last: Double?
    public init() {}
    public mutating func reset() { since=nil; last=nil }
    public mutating func observe(time: Double, eligible: Bool) -> Bool {
        guard time.isFinite, eligible else { reset(); return false }
        if let last, time <= last { return false }
        if let last, time-last > 0.5 { since=nil }
        last=time
        if since == nil { since=time }
        return time-(since ?? time) >= 1.0
    }
}
