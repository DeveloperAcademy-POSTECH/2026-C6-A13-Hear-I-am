import Foundation

public struct StageRoute: Codable, Equatable, Sendable {
    /// Start plus up to 20 subsequent points, including the destination.
    public static let maxPointCount = 21
    public let version: Int
    public var area: StageArea
    /// p0 followed by up to p20, all in stage floor metres.
    public var points: [FloorPoint]
    public var obstacles: [StageObstacle]
    public var pointHeights: [Double]?
    /// Seconds of silence before the next leg, indexed like points. Missing in legacy saves.
    public var pointHoldSeconds: [Int]?
    public static let maximumHoldSeconds = 3600
    public func holdSeconds(at index: Int) -> Int {
        guard index > 0, index < points.count-1, let values=pointHoldSeconds, values.indices.contains(index) else { return 0 }
        return values[index]
    }
    public mutating func setHoldSeconds(_ seconds: Int, at index: Int) throws {
        guard index > 0, index < points.count-1, (0...Self.maximumHoldSeconds).contains(seconds) else {
            throw LabError.invalid("중간 경로점의 안내 대기 시간을 0~3600초로 입력해주세요.")
        }
        var values=pointHoldSeconds ?? Array(repeating:0,count:points.count)
        guard values.count == points.count else { throw LabError.invalid("경로점 대기 시간 개수가 맞지 않습니다.") }
        values[index]=seconds; pointHoldSeconds=values
    }
    public var dangerZones: [StageDangerZone]
    public init(area: StageArea, points: [FloorPoint], obstacles: [StageObstacle], allowsOutsideEndpoints: Bool = false, dangerZones: [StageDangerZone] = [], pointHeights: [Double]? = nil, pointHoldSeconds: [Int]? = nil) throws {
        version=allowsOutsideEndpoints ? 2 : 1; self.area=area; self.points=points; self.obstacles=obstacles
        self.dangerZones=dangerZones; self.pointHeights=pointHeights; self.pointHoldSeconds=pointHoldSeconds
        try validate()
    }
    enum CodingKeys: String, CodingKey { case version, area, points, obstacles, dangerZones, pointHeights, pointHoldSeconds }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        version=try c.decode(Int.self,forKey:.version)
        area=try c.decode(StageArea.self,forKey:.area)
        points=try c.decode([FloorPoint].self,forKey:.points)
        obstacles=try c.decode([StageObstacle].self,forKey:.obstacles)
        dangerZones=try c.decodeIfPresent([StageDangerZone].self,forKey:.dangerZones) ?? []
        pointHeights=try c.decodeIfPresent([Double].self,forKey:.pointHeights)
        pointHoldSeconds=try c.decodeIfPresent([Int].self,forKey:.pointHoldSeconds)
        try validate()
    }
    public func validate() throws {
        try area.validate()
        if let values=pointHoldSeconds {
            guard values.count == points.count, values.allSatisfy({(0...Self.maximumHoldSeconds).contains($0)}),
                  values.first == 0, values.last == 0 else {
                throw LabError.invalid("경로점 대기 시간은 중간 지점만 0~3600초로 설정할 수 있습니다.")
            }
        }
        if let pointHeights {
            guard pointHeights.count == points.count, pointHeights.allSatisfy({$0.isFinite}) else {
                throw LabError.invalid("경로 지점의 높이 정보가 올바르지 않습니다.")
            }
        }
        guard Set(dangerZones.map(\.edge)).count == dangerZones.count else {
            throw LabError.invalid("같은 무대 변에 위험 구역을 중복 설정할 수 없습니다.")
        }
        guard [1,2].contains(version), ((version == 2 ? 3 : 2)...Self.maxPointCount).contains(points.count), points.allSatisfy(\.valid),
              Set(obstacles.map(\.id)).count == obstacles.count else { throw LabError.invalid("경로 버전, 순서 또는 점 개수가 유효하지 않습니다.") }
        for o in obstacles { try o.validate(); guard o.vertices.allSatisfy({area.contains($0)}) else { throw LabError.invalid("장애물이 무대 밖에 있습니다.") } }
    }
    /// The chair or stairs point `index` stands on, if any.
    public func step(at index: Int) -> StageObstacle? {
        guard points.indices.contains(index) else { return nil }
        return obstacles.first { $0.isStep && $0.contains(points[index]) }
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
                for o in obstacles where o.blocksTravel(from:a,to:b,clearance:obstacleClearance) {
                    result.append("p\(i)→p\(i+1)이 \(o.name) 통과 금지 측면 또는 여유 영역과 겹칩니다")
                }
            }
        }
        return result
    }
}
