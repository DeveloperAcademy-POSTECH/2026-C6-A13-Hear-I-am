import Foundation
import simd

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
    public static let minimumHeadingHorizontalRatio = 0.25
    /// Nil identifies an invalid direction vector, not a recoverable camera tilt.
    public static func horizontalForwardRatio(_ cameraForward: Point3) -> Double? {
        let v=cameraForward.vector
        let length=simd_length(v)
        guard cameraForward.valid, length.isFinite, length > 0.001 else { return nil }
        return hypot(v.x,v.z)/length
    }
    public func heading(cameraForward: Point3) -> Double? {
        let v=cameraForward.vector
        let horizontal=SIMD3(v.x,0,v.z)
        guard let ratio=Self.horizontalForwardRatio(cameraForward), ratio >= Self.minimumHeadingHorizontalRatio else { return nil }
        let h=simd_normalize(horizontal)
        return atan2(-simd_dot(h,right), -simd_dot(h,back))*180 / .pi
    }
}
