import Foundation

/// Quality gate: normal is not verification. Every interruption revokes explicit validation.
public struct TrackingGate: Sendable {
    public private(set) var normalSince: Double?
    public private(set) var lastTime: Double?
    public private(set) var verified=false
    public let maxAge: Double=0.5
    public let stableDuration: Double=1.0
    public init() {}
    @discardableResult public mutating func observe(time: Double, normal: Bool, anchorsPresent: Bool) -> Bool {
        guard time.isFinite, lastTime.map({time > $0}) ?? true else { return false }
        if let lastTime, time-lastTime > maxAge { invalidate() }
        lastTime=time
        if normal && anchorsPresent { if normalSince == nil { normalSince=time } }
        else { invalidate() }
        return true
    }
    public func canVerify(now: Double) -> Bool {
        guard let lastTime, let normalSince, now.isFinite,
              now >= lastTime, now-lastTime <= maxAge else { return false }
        return lastTime-normalSince >= stableDuration
    }
    @discardableResult public mutating func verify(error: Double, tolerance: Double, now: Double) -> Bool {
        verified = canVerify(now: now) && error.isFinite && error >= 0 && tolerance.isFinite &&
            tolerance > 0 && tolerance <= 0.5 && error <= tolerance
        return verified
    }
    public func isReady(now: Double) -> Bool { verified && canVerify(now: now) }
    public mutating func expire(now: Double) {
        if let lastTime, !now.isFinite || now < lastTime || now-lastTime > maxAge { invalidate() }
    }
    public mutating func invalidate() { verified=false; normalSince=nil }
}
