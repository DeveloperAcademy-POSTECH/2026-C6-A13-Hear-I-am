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
