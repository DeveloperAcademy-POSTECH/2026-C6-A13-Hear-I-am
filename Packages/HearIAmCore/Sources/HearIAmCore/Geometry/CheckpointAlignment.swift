import Foundation

/// Rigid horizontal transform from saved AR world to this session's observed world.
/// Experimental limits; passing two landmarks does not establish accuracy elsewhere.
public struct CheckpointAlignment: Equatable, Sendable {
    public static let minimumSeparation = 1.0
    public static let maximumTranslation = 0.50
    public static let maximumYawDegrees = 10.0
    public static let maximumLengthDifference = 0.15
    public static let maximumResidual = 0.15
    public static let maximumHeightError = 0.15
    public let savedCenter: Point3
    public let observedCenter: Point3
    /// Positive yaw follows AR's right-handed rotation about +Y.
    public let yaw: Double
    public let lengthDifference: Double
    public let residual: Double
    public var translation: Double { hypot(observedCenter.x-savedCenter.x,observedCenter.z-savedCenter.z) }
    public var yawDegrees: Double { yaw * 180 / .pi }

    public init(saved: [Point3], observed: [Point3]) throws {
        guard saved.count == 2, observed.count == 2,
              (saved+observed).allSatisfy({$0.valid}) else {
            throw LabError.invalid("확인점 1번과 2번을 순서대로 측정해주세요.")
        }
        let a=saved[0], b=saved[1], u=observed[0], v=observed[1]
        let sx=b.x-a.x, sz=b.z-a.z, ox=v.x-u.x, oz=v.z-u.z
        let sl=hypot(sx,sz), ol=hypot(ox,oz)
        guard sl >= Self.minimumSeparation, ol >= Self.minimumSeparation else {
            throw LabError.invalid("두 확인점은 수평으로 1m 이상 떨어져야 합니다.")
        }
        guard abs(a.y-u.y) <= Self.maximumHeightError, abs(b.y-v.y) <= Self.maximumHeightError else {
            throw LabError.invalid("저장한 바닥 높이와 맞지 않아요. 두 확인점을 다시 측정해주세요.")
        }
        savedCenter=Point3((a.x+b.x)/2,0,(a.z+b.z)/2)
        observedCenter=Point3((u.x+v.x)/2,0,(u.z+v.z)/2)
        yaw=atan2(sz*ox-sx*oz,sx*ox+sz*oz)
        lengthDifference=abs(sl-ol)
        residual=max(hypot(lengthDifference/2,a.y-u.y),hypot(lengthDifference/2,b.y-v.y))
        guard translation <= Self.maximumTranslation else {
            throw LabError.invalid("위치 보정량이 50cm를 넘어요. 공간을 다시 불러오고 표식을 확인해주세요.")
        }
        guard abs(yawDegrees) <= Self.maximumYawDegrees else {
            throw LabError.invalid("회전 보정량이 10도를 넘어요. 확인점 1·2의 순서와 공간 복원을 확인해주세요.")
        }
        guard lengthDifference <= Self.maximumLengthDifference, residual <= Self.maximumResidual else {
            throw LabError.invalid("두 점 사이 거리 또는 바닥 높이가 맞지 않아요. 1번부터 다시 측정해주세요.")
        }
    }
    public func apply(_ p: Point3) -> Point3 {
        let x=p.x-savedCenter.x, z=p.z-savedCenter.z, c=cos(yaw), s=sin(yaw)
        return Point3(observedCenter.x+c*x+s*z,p.y,observedCenter.z-s*x+c*z)
    }
    public func inverse(_ p: Point3) -> Point3 {
        let d=inverseDirection(Point3(p.x-observedCenter.x,p.y,p.z-observedCenter.z))
        return Point3(d.x+savedCenter.x,d.y,d.z+savedCenter.z)
    }
    public func inverseDirection(_ p: Point3) -> Point3 {
        let c=cos(yaw), s=sin(yaw)
        return Point3(c*p.x-s*p.z,p.y,s*p.x+c*p.z)
    }
}
