import Foundation

/// Row-major rotation from the Core Motion reference frame into device coordinates.
/// Copy the nine fields from `CMAttitude.rotationMatrix`.
public struct ReferenceToDeviceRotation: Equatable, Sendable {
    public let m11: Double, m12: Double, m13: Double
    public let m21: Double, m22: Double, m23: Double
    public let m31: Double, m32: Double, m33: Double
    public init(m11: Double, m12: Double, m13: Double, m21: Double, m22: Double, m23: Double,
                m31: Double, m32: Double, m33: Double) {
        self.m11=m11; self.m12=m12; self.m13=m13; self.m21=m21; self.m22=m22; self.m23=m23
        self.m31=m31; self.m32=m32; self.m33=m33
    }
    /// Orthonormal rows and determinant 1, within sensor noise.
    var isRotation: Bool {
        let rows=[[m11,m12,m13],[m21,m22,m23],[m31,m32,m33]]
        guard rows.joined().allSatisfy(\.isFinite) else { return false }
        let tolerance=0.02
        for row in rows where abs(row.reduce(0) { $0+$1*$1 }-1) > tolerance { return false }
        for a in 0..<3 { for b in (a+1)..<3 where abs(zip(rows[a],rows[b]).reduce(0) { $0+$1.0*$1.1 }) > tolerance { return false } }
        let determinant=m11*(m22*m33-m23*m32)-m12*(m21*m33-m23*m31)+m13*(m21*m32-m22*m31)
        return abs(determinant-1) <= tolerance
    }
}
