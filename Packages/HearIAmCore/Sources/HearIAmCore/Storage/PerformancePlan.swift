import Foundation

/// A separate, schematic 3:2 canvas. Units are layout units, not a surveyed stage.
public struct PerformancePlan: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name = "새 공연 동선"
    public var updatedAt = Date()
    public private(set) var points: [FloorPoint] = []
    public private(set) var finished = false
    public var objects: [StageObstacle] = []
    public private(set) var pointSettings: [PerformancePlanPointSettings] = []
    public var objectFacings: [UUID: StageFacing] = [:]
    enum CodingKeys: String, CodingKey {case id,name,updatedAt,points,finished,objects,pointSettings,objectFacings}
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(UUID.self,forKey:.id);name=try c.decode(String.self,forKey:.name)
        updatedAt=try c.decode(Date.self,forKey:.updatedAt);points=try c.decode([FloorPoint].self,forKey:.points)
        finished=try c.decode(Bool.self,forKey:.finished);objects=try c.decode([StageObstacle].self,forKey:.objects)
        pointSettings=try c.decodeIfPresent([PerformancePlanPointSettings].self,forKey:.pointSettings) ?? Array(repeating:.init(),count:points.count)
        objectFacings=try c.decodeIfPresent([UUID: StageFacing].self,forKey:.objectFacings) ?? [:]
    }
    public static let width = 12.0
    public static let depth = 8.0
    public init() {}
    public static var area: StageArea {
        // Fixed, known-valid schematic geometry.
        try! StageArea(corners: [Point3(0,0,0), Point3(12,0,0), Point3(12,0,-8), Point3(0,0,-8)])
    }
    public mutating func append(_ point: FloorPoint) throws {
        guard !finished, points.count < StageRoute.maxPointCount, point.valid, (-3...15).contains(point.x), (-1...9).contains(point.y) else {
            throw LabError.invalid("경로를 편집하려면 최신 점을 삭제해주세요. 시작점 제외 최대 20점(도착점 포함)까지 가능합니다.")
        }
        if points.count == 1, !Self.area.contains(point, margin: 0.01) {
            throw LabError.invalid("첫 내부 지점 P1은 무대 안에 지정해주세요.")
        }
        // The current last point can be outside as a prospective destination;
        // adding another point would turn it into an interior waypoint.
        if points.count >= 2, let last = points.last, !Self.area.contains(last, margin: 0.01) {
            throw LabError.invalid("무대 밖의 마지막 점은 도착점으로 완료하거나 삭제해주세요.")
        }
        if let last = points.last, last.distance(to: point) < 0.05 { throw LabError.invalid("서로 다른 위치를 선택해주세요.") }
        points.append(point);pointSettings.append(.init())
    }
    public mutating func resumeEditing() {finished=false}
    public mutating func undoPoint() {
        guard !points.isEmpty else { return }
        points.removeLast();pointSettings.removeLast();finished = false
        if !pointSettings.isEmpty {pointSettings[pointSettings.count-1].holdSeconds=0}
    }
    public mutating func finishRoute() throws {
        guard points.count >= 3 else { throw LabError.invalid("출발점·내부 지점·도착점, 최소 3점이 필요합니다.") }
        let candidate = try StageRoute(area: Self.area, points: points, obstacles: objects, allowsOutsideEndpoints: true)
        let errors = candidate.conflicts(boundaryMargin: 0.01, obstacleClearance: 0.15)
        guard errors.isEmpty else { throw LabError.invalid(errors.joined(separator: "\n")) }
        finished = true
    }
    public mutating func addObject(at p: FloorPoint, platform: Bool) throws {
        let vertices = platform
            ? [FloorPoint(p.x-0.6,p.y-0.5),FloorPoint(p.x+0.6,p.y-0.5),FloorPoint(p.x+0.6,p.y+0.5),FloorPoint(p.x-0.6,p.y+0.5)]
            : [FloorPoint(p.x,p.y+0.6),FloorPoint(p.x-0.6,p.y-0.5),FloorPoint(p.x+0.6,p.y-0.5)]
        guard vertices.allSatisfy({Self.area.contains($0)}) else { throw LabError.invalid("기물이 무대 안에 들어오도록 배치해주세요.") }
        let count=objects.filter {$0.isStep==platform}.count+1
        let object=try StageObstacle(name: "\(platform ? "의자" : "장애물") \(count)", kind: platform ? .platform : .other,
                                     passage: platform ? .passable : .prohibited, vertices: vertices)
        objects.append(object)
        if platform {objectFacings[object.id] = .north}
    }
    public mutating func moveObject(_ id: UUID, to p: FloorPoint) throws {
        guard let i = objects.firstIndex(where: {$0.id == id}) else { return }
        let vertices = objects[i].vertices
        let center = FloorPoint(vertices.map(\.x).reduce(0,+)/Double(vertices.count), vertices.map(\.y).reduce(0,+)/Double(vertices.count))
        let moved = vertices.map { FloorPoint($0.x+p.x-center.x, $0.y+p.y-center.y) }
        guard moved.allSatisfy({Self.area.contains($0)}) else { throw LabError.invalid("기물을 무대 안에 배치해주세요.") }
        objects[i].vertices = moved
    }
    public func pointLabel(at index: Int) -> String {
        guard points.indices.contains(index) else {return ""}
        if index==0 {return "출발"}
        if finished && index==points.count-1 {return "도착"}
        return "P\(index)"
    }
    public func settings(at index: Int) -> PerformancePlanPointSettings {
        pointSettings.indices.contains(index) ? pointSettings[index] : .init()
    }
    public mutating func setPointSettings(_ settings: PerformancePlanPointSettings, at index: Int) throws {
        guard pointSettings.indices.contains(index) else {throw LabError.invalid("지점을 다시 선택해주세요.")}
        try settings.validate()
        guard settings.holdSeconds==0 || (index>0 && index<points.count-1) else {throw LabError.invalid("대기 시간은 중간 지점에만 설정할 수 있어요.")}
        var copy=settings;copy.name=copy.name.trimmingCharacters(in:.whitespacesAndNewlines)
        pointSettings[index]=copy
    }
    public mutating func resizeObject(_ id: UUID, width: Double, depth: Double) throws {
        guard let i=objects.firstIndex(where:{$0.id==id}),width.isFinite,depth.isFinite,
              width>=0.3,depth>=0.3,width<=Self.width,depth<=Self.depth else {throw LabError.invalid("기물 크기를 확인해주세요.")}
        let vertices=objects[i].vertices
        let minX=vertices.map(\.x).min()!, maxX=vertices.map(\.x).max()!
        let minY=vertices.map(\.y).min()!, maxY=vertices.map(\.y).max()!
        let center=FloorPoint((minX+maxX)/2,(minY+maxY)/2)
        let resized=vertices.map {FloorPoint(center.x+($0.x-center.x)*width/(maxX-minX),center.y+($0.y-center.y)*depth/(maxY-minY))}
        guard resized.allSatisfy({Self.area.contains($0)}) else {throw LabError.invalid("기물이 무대 안에 들어오도록 크기를 조절해주세요.")}
        var object=objects[i];object.vertices=resized;try object.validate();objects[i]=object
    }
    public mutating func removeObject(_ id: UUID) {objects.removeAll {$0.id==id};objectFacings.removeValue(forKey:id)}
    public func validate() throws {
        guard pointSettings.count==points.count else {throw LabError.invalid("지점 설정 개수가 맞지 않습니다.")}
        for (index,setting) in pointSettings.enumerated() {
            try setting.validate()
            guard setting.holdSeconds==0 || (index>0 && index<points.count-1) else {throw LabError.invalid("대기 시간은 중간 지점에만 설정할 수 있어요.")}
        }
        guard objectFacings.keys.allSatisfy({id in objects.contains {$0.id==id && $0.isStep}}) else {throw LabError.invalid("의자 방향 설정을 확인해주세요.")}
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80, finished else { throw LabError.invalid("이름을 입력하고 경로를 완료해주세요.") }
        let route = try StageRoute(area: Self.area, points: points, obstacles: objects, allowsOutsideEndpoints: true)
        let errors = route.conflicts(boundaryMargin: 0.01, obstacleClearance: 0.15)
        guard errors.isEmpty else { throw LabError.invalid(errors.joined(separator: "\n")) }
    }
}

/// Performance-level rehearsal instructions. They never modify a saved venue route automatically.
public struct PerformancePlanPointSettings: Codable, Equatable, Sendable {
    public var name: String
    public var holdSeconds: Int
    public var facing: StageFacing?
    public init(name: String = "", holdSeconds: Int = 0, facing: StageFacing? = nil) {
        self.name=name;self.holdSeconds=holdSeconds;self.facing=facing
    }
    public func validate() throws {
        guard name.count<=80,(0...3600).contains(holdSeconds) else {throw LabError.invalid("지점 이름은 80자, 대기 시간은 0~3600초까지 설정할 수 있어요.")}
    }
}
