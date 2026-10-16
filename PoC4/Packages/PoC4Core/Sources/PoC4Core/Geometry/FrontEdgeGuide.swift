import Foundation

/// Temporary floor-plane guides from the first two observed front corners.
/// They indicate direction only; the back edge remains unmeasured until E3 and E4 are captured.
public struct FrontEdgeGuide: Equatable, Sendable {
    public let leftStart: Point3
    public let rightStart: Point3
    public let leftEnd: Point3
    public let rightEnd: Point3
    public let length: Double

    public init(frontLeft: Point3, frontRight: Point3) throws {
        let dx=frontRight.x-frontLeft.x, dz=frontRight.z-frontLeft.z
        let width=hypot(dx,dz)
        guard frontLeft.valid, frontRight.valid, width >= 0.5,
              abs(frontRight.y-frontLeft.y) <= 0.20 else {
            throw LabError.invalid("앞의 두 꼭짓점은 같은 바닥에서 0.5m 이상 떨어져야 합니다.")
        }
        // Front-left -> front-right as seen from the audience. Clockwise in AR X/Z points backstage.
        let inwardX=dz/width, inwardZ = -dx/width
        let floor=(frontLeft.y+frontRight.y)/2
        length=max(3,min(12,width*1.2))
        leftStart=Point3(frontLeft.x,floor,frontLeft.z)
        rightStart=Point3(frontRight.x,floor,frontRight.z)
        leftEnd=Point3(frontLeft.x+inwardX*length,floor,frontLeft.z+inwardZ*length)
        rightEnd=Point3(frontRight.x+inwardX*length,floor,frontRight.z+inwardZ*length)
    }
}
