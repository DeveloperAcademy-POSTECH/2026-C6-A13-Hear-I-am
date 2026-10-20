import Foundation

/// World coordinates are authoritative while the stage rectangle is being edited.
/// Re-project only for display/validation, never overwrite downstream world locations.
public struct PreparationDraft: Sendable {
    public static let captureOrder = [1, 0, 3, 2]
    public static let boundaryMargin = 0.01
    public static let checkpointEdgeTolerance = 0.05
    public static let obstacleClearance = GuideSettings.routeClearance
    public var corners: [Point3?] = Array(repeating: nil, count: 4)
    public var route: [Point3] = []
    private var confirmedHeightPoints: [Int: Point3] = [:]
    public var routeFinished = false
    public var objects: [WorldObstacle] = []
    public var checkpoint: Point3?
    public var planApplied = false
    public var dangerZones: [StageDangerZone] = []
    public init() {}
    public mutating func captureCorner(_ index: Int, at point: Point3) throws {
        guard corners.indices.contains(index), point.valid else { throw LabError.invalid("유효한 무대 모서리를 지정해주세요.") }
        var next=corners
        next[index]=point
        if let left=next[0], let right=next[1] {
            let front=try FrontEdgeGuide(frontLeft:left,frontRight:right)
            if let backLeft=next[3] { _ = try BackEdgeGuide(front:front,backLeft:backLeft) }
        }
        corners=next
    }
    public var area: StageArea? {
        guard corners.allSatisfy({ $0 != nil }) else { return nil }
        return try? StageArea(corners: corners.compactMap { $0 })
    }
    public var boundaryErrors: [String] {
        guard corners.allSatisfy({ $0 != nil }) else { return ["무대의 네 모서리를 지정해주세요."] }
        do { _ = try StageArea(corners: corners.compactMap { $0 }); return [] }
        catch { return [error.localizedDescription] }
    }
    public mutating func addRoutePoint(_ point: Point3, asDestination: Bool = false, confirmHeightMismatch: Bool = false) throws {
        guard let area else { throw LabError.invalid("무대 영역을 먼저 지정해주세요.") }
        if let error=routeSurfaceError(point,in:area,ignoreEstimatedHeight:confirmHeightMismatch) { throw LabError.invalid(error) }
        guard !routeFinished, route.count < 6 else { throw LabError.invalid("경로는 출발·도착을 포함해 최대 6개입니다.") }
        if asDestination {
            guard route.count >= 2 else { throw LabError.invalid("출발점과 내부 지점을 먼저 지정해주세요.") }
        } else if !route.isEmpty {
            guard route.count < 5, area.contains(area.floor(point), margin: Self.boundaryMargin) else {
                throw LabError.invalid("내부 지점은 무대 안에 최대 4개까지 지정할 수 있습니다.")
            }
        }
        if let last = route.last, last.distance(to: point) < 0.05 { throw LabError.invalid("이전 점에서 조금 더 떨어진 위치를 선택해주세요.") }
        if let hit = clearanceHit(adding: point) { throw LabError.invalid(hit.message+". 빨간 영역 밖을 찍어주세요.") }
        if let previous=route.last, let blocked=objects.compactMap({try? $0.projected(in:area)}).first(where: {
            $0.isStep && $0.blocksTravel(from:area.floor(previous),to:area.floor(point),clearance:effectiveObstacleClearance)
        }) { throw LabError.invalid("\(blocked.name)의 허용된 올라가는 변·내려오는 변으로 경로를 지정해주세요.") }
        if confirmHeightMismatch { confirmedHeightPoints[route.count]=point }
        route.append(point); routeFinished = asDestination; planApplied = false
    }
    /// Validate observed horizontal surfaces against the registered outline and measured height.
    public func routeSurfaceError(_ point: Point3, in area: StageArea, ignoreEstimatedHeight: Bool = false) -> String? {
        guard point.valid else { return "선택한 위치를 측정하지 못했어요. 다시 비춰주세요." }
        let h=point.y-area.floorHeight
        if abs(h) <= 0.10 { return nil }
        guard h > 0 else { return "선택한 면이 무대 바닥보다 낮아요. 무대 바닥과 네 모서리를 확인해주세요." }
        guard h <= ObjectHeight.ceiling else { return "선택한 면이 무대 바닥보다 2.5m 넘게 높아요. 무대 바닥과 선택 위치를 확인해주세요." }
        let covered=objects.filter { object in
            guard object.kind == .platform || object.kind == .stairs,
                  let shape=try? object.projected(in:area) else { return false }
            return shape.contains(area.floor(point))
        }
        guard !covered.isEmpty else {
            return "선택한 면은 바닥보다 약 \(Int((h*100).rounded()))cm 높지만 등록한 단상·계단 둘레 밖이에요. 기물 종류와 바닥 둘레를 확인해주세요."
        }
        if ignoreEstimatedHeight { return nil }
        guard covered.contains(where: { object in
            guard let top=object.height else { return true }
            guard top > 0 else { return false }
            return object.kind == .stairs ? h <= top+0.15+1e-9 : abs(h-top) <= 0.15+1e-9
        }) else {
            let estimates=covered.compactMap { object in
                object.height.map { "\(object.name): 약 \(Int(($0*100).rounded()))cm" }
            }.joined(separator:" · ")
            return "선택 높이: 약 \(Int((h*100).rounded()))cm\n자동 추정 높이: \(estimates)\n단상 ±15cm 또는 계단 최고 높이 +15cm 범위를 벗어났어요. 실제 윗면에 찍힌 위치가 맞는지 확인해주세요."
        }
        return nil
    }
    public func acceptsRouteSurface(_ point: Point3, in area: StageArea) -> Bool {
        routeSurfaceError(point,in:area) == nil
    }
    public mutating func removeLastRoutePoint() {
        guard !route.isEmpty else { return }
        confirmedHeightPoints[route.count-1]=nil
        route.removeLast(); routeFinished = false; planApplied = false
    }
    /// Projects a schematic 12×8 PerformancePlan proportionally onto the captured stage area.
    public mutating func applyPlan(_ plan: PerformancePlan) throws {
        guard let area else { throw LabError.invalid("무대의 네 모서리를 먼저 지정해주세요.") }
        try plan.validate()
        let sx = area.width / PerformancePlan.width
        let sy = area.depth / PerformancePlan.depth
        func mapped(_ p: FloorPoint) -> Point3 { area.world(FloorPoint(p.x * sx, p.y * sy)) }
        objects = plan.objects.map { WorldObstacle(id: $0.id, name: $0.name, kind: $0.kind, vertices: $0.vertices.map(mapped), height:$0.height, entryEdges:$0.entryEdges, exitEdges:$0.exitEdges) }
        confirmedHeightPoints=[:]
        route = plan.points.map(mapped)
        routeFinished = plan.finished
        planApplied = true
    }
    public var effectiveObstacleClearance: Double {
        guard planApplied, let area else { return Self.obstacleClearance }
        let scale = min(area.width / PerformancePlan.width, area.depth / PerformancePlan.depth)
        return min(Self.obstacleClearance, 0.15 * scale)
    }
    public func stageRoute() throws -> StageRoute {
        guard let area, routeFinished else { throw LabError.invalid("무대 범위와 도착점을 확정해주세요.") }
        guard route.enumerated().allSatisfy({ i, point in
            routeSurfaceError(point,in:area,ignoreEstimatedHeight:confirmedHeightPoints[i] == point) == nil
        }) else {
            throw LabError.invalid("경로가 새 무대 바닥과 높이가 다릅니다. 경로를 다시 지정해주세요.")
        }
        let obstacles = try objects.map { try $0.projected(in: area) }
        return try StageRoute(area: area, points: route.map(area.floor), obstacles: obstacles, allowsOutsideEndpoints: true, dangerZones: dangerZones, pointHeights:route.map {$0.y-area.floorHeight})
    }
    public var objectErrors: [String] {
        guard let area else { return boundaryErrors }
        return objects.compactMap { object in
            do {
                let o = try object.projected(in: area)
                guard o.vertices.allSatisfy({ area.contains($0) }) else { return "\(o.name)이 무대 밖입니다. 다시 지정해주세요." }
                return nil
            } catch { return "\(object.name): \(error.localizedDescription)" }
        }
    }
    /// Informational only: never included in validation errors or placement guards.
    public var dangerZoneRoutePointLabels: [String] {
        guard let area else { return [] }
        return route.enumerated().compactMap { index, point in
            guard dangerZones.contains(where: {
                $0.contains(area.floor(point),width:area.width,depth:area.depth)
            }) else { return nil }
            if index == 0 { return "시작점" }
            if routeFinished && index == route.count-1 { return "종료점" }
            return "P\(index)"
        }
    }
    public var routeErrors: [String] {
        do { return try stageRoute().conflicts(boundaryMargin: Self.boundaryMargin, obstacleClearance: effectiveObstacleClearance) }
        catch { return [error.localizedDescription] }
    }
    public var checkpointErrors: [String] {
        guard let area, let checkpoint else { return ["무대의 확인점 한 개를 지정해주세요."] }
        guard area.contains(area.floor(checkpoint)), abs(checkpoint.y-area.floorHeight) <= 0.10,
              area.corners.allSatisfy({ $0.distance(to: checkpoint) >= 0.5 }),
              checkpoint.distance(to: area.world(FloorPoint(0,-1))) >= 0.5 else {
            return ["확인점을 무대 안 같은 높이에서 모서리와 0.5m 이상 떨어진 곳에 다시 지정해주세요."]
        }
        let point=area.floor(checkpoint)
        for object in objects {
            guard let shape=try? object.projected(in:area) else {
                return ["기물 둘레를 확인한 후 확인점을 지정해주세요."]
            }
            if shape.contains(point), shape.boundaryDistance(to:point) > Self.checkpointEdgeTolerance+1e-9 {
                return ["확인점이 \(object.name) 내부에 있어요. 바닥과 만나는 경계 또는 기물 밖 바닥을 선택해주세요. 경계 안쪽 5cm까지 허용됩니다."]
            }
        }
        return []
    }
    public var errors: [String] { boundaryErrors + objectErrors + routeErrors + checkpointErrors }
}
