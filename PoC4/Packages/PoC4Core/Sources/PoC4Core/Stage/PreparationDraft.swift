import Foundation

/// World coordinates are authoritative while the stage rectangle is being edited.
/// Re-project only for display/validation, never overwrite downstream world locations.
public struct PreparationDraft: Sendable {
    public static let captureOrder = [1, 0, 3, 2]
    public static let boundaryMargin = 0.01
    public static let obstacleClearance = 0.35
    public var corners: [Point3?] = Array(repeating: nil, count: 4)
    public var route: [Point3] = []
    public var routeFinished = false
    public var objects: [WorldObstacle] = []
    public var checkpoint: Point3?
    public init() {}
    public var area: StageArea? {
        guard corners.allSatisfy({ $0 != nil }) else { return nil }
        return try? StageArea(corners: corners.compactMap { $0 })
    }
    public var boundaryErrors: [String] {
        guard corners.allSatisfy({ $0 != nil }) else { return ["무대의 네 모서리를 지정해주세요."] }
        do { _ = try StageArea(corners: corners.compactMap { $0 }); return [] }
        catch { return [error.localizedDescription] }
    }
    public mutating func addRoutePoint(_ point: Point3, asDestination: Bool = false) throws {
        guard let area, point.valid, abs(point.y-area.floorHeight) <= 0.10 else {
            throw LabError.invalid("무대와 같은 높이의 바닥을 선택해주세요.")
        }
        guard !routeFinished, route.count < 6 else { throw LabError.invalid("경로는 출발·도착을 포함해 최대 6개입니다.") }
        if asDestination {
            guard route.count >= 2 else { throw LabError.invalid("출발점과 내부 지점을 먼저 지정해주세요.") }
        } else if !route.isEmpty {
            guard route.count < 5, area.contains(area.floor(point), margin: Self.boundaryMargin) else {
                throw LabError.invalid("내부 지점은 무대 안에 최대 4개까지 지정할 수 있습니다.")
            }
        }
        if let last = route.last, last.distance(to: point) < 0.05 { throw LabError.invalid("이전 점에서 조금 더 떨어진 위치를 선택해주세요.") }
        route.append(point); routeFinished = asDestination
    }
    public mutating func removeLastRoutePoint() {
        guard !route.isEmpty else { return }
        route.removeLast(); routeFinished = false
    }
    public func stageRoute() throws -> StageRoute {
        guard let area, routeFinished else { throw LabError.invalid("무대 범위와 도착점을 확정해주세요.") }
        guard route.allSatisfy({ abs($0.y-area.floorHeight) <= 0.10 }) else {
            throw LabError.invalid("경로가 새 무대 바닥과 높이가 다릅니다. 경로를 다시 지정해주세요.")
        }
        let obstacles = try objects.map { try $0.projected(in: area) }
        return try StageRoute(area: area, points: route.map(area.floor), obstacles: obstacles, allowsOutsideEndpoints: true)
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
    public var routeErrors: [String] {
        do { return try stageRoute().conflicts(boundaryMargin: Self.boundaryMargin, obstacleClearance: Self.obstacleClearance) }
        catch { return [error.localizedDescription] }
    }
    public var checkpointErrors: [String] {
        guard let area, let checkpoint else { return ["무대의 확인점 한 개를 지정해주세요."] }
        guard area.contains(area.floor(checkpoint)), abs(checkpoint.y-area.floorHeight) <= 0.10,
              area.corners.allSatisfy({ $0.distance(to: checkpoint) >= 0.5 }),
              checkpoint.distance(to: area.world(FloorPoint(0,-1))) >= 0.5 else {
            return ["확인점을 무대 안 같은 높이에서 모서리와 0.5m 이상 떨어진 곳에 다시 지정해주세요."]
        }
        guard !objects.contains(where: { (try? $0.projected(in: area).contains(area.floor(checkpoint))) == true }) else {
            return ["확인점이 통과 금지 기물과 겹칩니다."]
        }
        return []
    }
    public var errors: [String] { boundaryErrors + objectErrors + routeErrors + checkpointErrors }
}
