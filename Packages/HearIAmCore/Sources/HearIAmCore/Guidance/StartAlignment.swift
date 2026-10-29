import Foundation

/// After reaching p0: face the exact p0→p1 bearing, then wait before an optional automatic start.
/// A pause cancels automatic start; construct a fresh preparation on explicit retry.
public struct StartAlignment: Sendable {
    public enum State: Equatable, Sendable { case aligning, waiting, ready, paused }
    public private(set) var state: State = .aligning
    public private(set) var remaining: Double
    public let automaticallyStarts: Bool
    public let headingDegrees: Double
    private let start: FloorPoint
    private let radius: Double
    private var gate=DepartureGate()
    private var lastTime: Double?

    public init(route: StageRoute, settings: GuideSettings) throws {
        try route.validate();try settings.validate()
        guard route.points[0].distance(to:route.points[1]) >= 0.05 else { throw LabError.invalid("출발점과 첫 경로점이 너무 가까워 방향을 정할 수 없어요.") }
        start=route.points[0];radius=settings.startRadius
        headingDegrees=StageHeading.bearing(from:route.points[0],to:route.points[1],headingDegrees:0)
        automaticallyStarts=route.startDelaySeconds != nil
        remaining=Double(route.startDelaySeconds ?? 0)
    }
    public func bearing(headingDegrees: Double) -> Double { HeadingMath.wrapDegrees(self.headingDegrees-headingDegrees) }
    public func matches(position: FloorPoint, headingDegrees: Double) -> Bool {
        position.valid && headingDegrees.isFinite && position.distance(to:start) <= radius && abs(bearing(headingDegrees:headingDegrees)) <= RouteGuide.facingToleranceDegrees
    }
    public mutating func pause() { state = .paused;gate.reset();lastTime=nil }
    public mutating func observe(time: Double, position: FloorPoint, headingDegrees: Double, trackingValid: Bool, allowsAdvance: Bool = true) {
        guard state != .paused, state != .ready else { return }
        guard time.isFinite, position.valid, headingDegrees.isFinite, trackingValid,
              position.distance(to:start) <= radius,
              lastTime.map({time > $0 && time-$0 <= 0.5}) ?? true else { pause();return }
        let elapsed=lastTime.map {time-$0} ?? 0
        lastTime=time
        let aligned=matches(position:position,headingDegrees:headingDegrees)
        if state == .waiting {
            if !aligned { state = .aligning;gate.reset();return }
            guard allowsAdvance else { return }
            remaining=max(0,remaining-elapsed)
            if remaining == 0 { state = .ready }
        } else if gate.observe(time:time,eligible:aligned && allowsAdvance) {
            state = remaining > 0 ? .waiting : .ready
        }
    }
}
