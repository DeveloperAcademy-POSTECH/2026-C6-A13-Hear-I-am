import Foundation

/// A one-run entry from a relocalized position to the first named P1. The saved route is never rewritten.
/// This validates a straight segment; it does not calculate a detour or claim that a scan is walkable.
public struct PracticeEntry: Sendable {
    public let origin: FloorPoint
    public let targetIndex: Int
    public let footprint: ScannedFootprint

    public init(position: FloorPoint, route: StageRoute, settings: GuideSettings, footprint: ScannedFootprint) throws {
        try route.validate(); try settings.validate()
        guard let index=route.points.indices.first(where:{route.pointLabel(at:$0).caseInsensitiveCompare("P1") == .orderedSame}),
              index > 0 else { throw LabError.invalid("이 동선에는 P1 지점이 없어요. 조력자에게 동선을 확인해주세요.") }
        origin=position;targetIndex=index;self.footprint=footprint
        try validateRemaining(from:position,route:route,settings:settings)
    }

    /// Used both before departure and after relocalizing an interrupted first leg.
    public func validateRemaining(from position: FloorPoint, route: StageRoute, settings: GuideSettings) throws {
        guard position.valid, route.points.indices.contains(targetIndex), footprint.contains(position),
              footprint.contains(route.points[targetIndex]) else {
            throw LabError.invalid("현재 위치 또는 P1이 저장된 스캔 범위 밖이에요. 스캔한 공간 안에서 다시 확인해주세요.")
        }
        let target=route.points[targetIndex]
        guard footprint.covers(from:position,to:target) else {
            throw LabError.invalid("P1까지 직선 경로에 스캔되지 않은 구간이 있어요. 위치를 바꾸거나 조력자에게 도움을 요청해주세요.")
        }
        guard !route.obstacles.contains(where:{$0.blocksTravel(from:position,to:target,clearance:settings.obstacleClearance)}) else {
            throw LabError.invalid("P1까지 직선 경로에 등록된 기물이 있어요. 위치를 바꾸거나 조력자에게 도움을 요청해주세요.")
        }
    }
}
