import Foundation

public struct StageRoute: Codable, Equatable, Sendable {
    public let version: Int
    public var area: StageArea
    /// p0 followed by p1...p5, all in stage floor metres.
    public var points: [FloorPoint]
    public var obstacles: [StageObstacle]
    public init(area: StageArea, points: [FloorPoint], obstacles: [StageObstacle], allowsOutsideEndpoints: Bool = false) throws {
        version=allowsOutsideEndpoints ? 2 : 1; self.area=area; self.points=points; self.obstacles=obstacles
        try validate()
    }
    public func validate() throws {
        try area.validate()
        guard [1,2].contains(version), ((version == 2 ? 3 : 2)...6).contains(points.count), points.allSatisfy(\.valid),
              Set(obstacles.map(\.id)).count == obstacles.count else { throw LabError.invalid("경로 버전, 순서 또는 점 개수가 유효하지 않습니다.") }
        for o in obstacles { try o.validate(); guard o.vertices.allSatisfy({area.contains($0)}) else { throw LabError.invalid("장애물이 무대 밖에 있습니다.") } }
    }
    public func conflicts(boundaryMargin: Double, obstacleClearance: Double) -> [String] {
        guard boundaryMargin >= 0, obstacleClearance >= 0 else { return ["여유 거리 설정 오류"] }
        var result=[String]()
        for i in points.indices where !(version == 2 && (i == 0 || i == points.count-1)) && !area.contains(points[i],margin:boundaryMargin) {
            result.append("p\(i)가 무대 경계 여유 밖입니다")
        }
        if points.count > 1 {
            for i in 0..<(points.count-1) {
                let a=points[i], b=points[i+1]
                if a.distance(to:b) < 0.05 { result.append("p\(i)→p\(i+1) 선분이 너무 짧습니다") }
                for o in obstacles where o.blocksPath && o.overlaps(a,b,clearance:obstacleClearance) {
                    result.append("p\(i)→p\(i+1)이 \(o.name) 여유 영역과 겹칩니다")
                }
            }
        }
        return result
    }
}
