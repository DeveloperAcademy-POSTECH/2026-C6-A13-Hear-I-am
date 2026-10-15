import Foundation
import simd

public struct Point3: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double; public var z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x=x; self.y=y; self.z=z }
    public init(_ p: SIMD3<Float>) { self.init(Double(p.x), Double(p.y), Double(p.z)) }
    public var vector: SIMD3<Double> { SIMD3(x,y,z) }
    public var valid: Bool { [x,y,z].allSatisfy { $0.isFinite && abs($0) <= 500 } }
    public func distance(to p: Point3) -> Double { simd_length(vector-p.vector) }
}

/// +X map right, +Y backstage, Z up. Facing the audience, body right is map -X.
public struct StageFrame: Codable, Equatable, Sendable {
    public let origin: Point3
    public let front: Point3
    public init(origin: Point3, front: Point3) throws {
        self.origin=origin; self.front=front
        try validate()
    }
    public func validate() throws {
        let delta=front.vector-origin.vector
        guard origin.valid, front.valid, hypot(delta.x,delta.z) >= 0.5,
              abs(delta.y) <= 0.15 else { throw LabError.invalid("기준 O와 정면 F는 같은 바닥에서 0.5m 이상 떨어져야 합니다.") }
    }
    private var back: SIMD3<Double> {
        let d=front.vector-origin.vector
        return -simd_normalize(SIMD3(d.x,0,d.z))
    }
    private var right: SIMD3<Double> { simd_cross(back, SIMD3(0,1,0)) }
    public func position(_ world: Point3) -> Point3 {
        let d=world.vector-origin.vector
        return Point3(simd_dot(d,right), simd_dot(d,back), d.y)
    }
    /// Rear camera optical forward (-Z) faces away from abdomen; no walking-direction inference.
    public func heading(cameraForward: Point3) -> Double? {
        let v=cameraForward.vector
        let horizontal=SIMD3(v.x,0,v.z)
        guard cameraForward.valid, simd_length(v)>0.001,
              simd_length(horizontal)/simd_length(v) >= 0.25 else { return nil }
        let h=simd_normalize(horizontal)
        return atan2(-simd_dot(h,right), -simd_dot(h,back))*180 / .pi
    }
}

public enum LabError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(s)=self { return s }; return nil }
}

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
