import Foundation

/// E4 → E3 for the preparation order E2 → E1 → E4 → E3.
/// A direction hint only: the fourth corner must still be measured independently.
public struct BackEdgeGuide: Equatable, Sendable {
    public let start: Point3
    public let end: Point3

    public init(front: FrontEdgeGuide, backLeft: Point3) throws {
        let dx=front.rightStart.x-front.leftStart.x
        let dz=front.rightStart.z-front.leftStart.z
        let inwardX=(front.leftEnd.x-front.leftStart.x)/front.length
        let inwardZ=(front.leftEnd.z-front.leftStart.z)/front.length
        let depth=(backLeft.x-front.leftStart.x)*inwardX+(backLeft.z-front.leftStart.z)*inwardZ
        guard backLeft.valid, abs(backLeft.y-front.leftStart.y) <= 0.20, depth >= 0.5 else {
            throw LabError.invalid("뒤 왼쪽 모서리는 같은 바닥의 앞 변 뒤쪽에 지정해주세요.")
        }
        start=Point3(backLeft.x,front.leftStart.y,backLeft.z)
        end=Point3(backLeft.x+dx,front.leftStart.y,backLeft.z+dz)
    }
}
