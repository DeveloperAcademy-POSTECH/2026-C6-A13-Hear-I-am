import Foundation

public enum StartApproach {
    /// A straight approach within the saved LiDAR footprint, independently of the stage rectangle. Never invent an unscanned detour.
    public static func route(from position: FloorPoint, to saved: StageRoute, settings: GuideSettings, footprint: ScannedFootprint) throws -> StageRoute {
        try saved.validate();try settings.validate()
        guard let start=saved.points.first, position.valid else {
            throw LabError.invalid("현재 위치와 저장된 출발점을 확인할 수 없어요.")
        }
        guard footprint.contains(start) else {
            throw LabError.invalid("저장된 출발점이 LiDAR 스캔 범위에 포함되지 않아요. 출발점 주변까지 스캔했는지 확인해주세요.")
        }
        guard footprint.contains(position) else {
            throw LabError.invalid("현재 위치가 저장된 LiDAR 스캔 범위 밖이에요. 스캔했던 공간에서 다시 눌러주세요.")
        }
        guard footprint.covers(from:position,to:start) else {
            throw LabError.invalid("출발점까지 직선 경로에 스캔되지 않은 구간이 있어요. 조력자와 접근 위치를 확인해주세요.")
        }
        guard position.distance(to:start) > settings.startRadius else { throw LabError.invalid("이미 출발점에 도착했어요. 잠시 멈춰주세요.") }
        let route=try StageRoute(area:saved.area,points:[position,start],obstacles:saved.obstacles,dangerZones:saved.dangerZones)
        guard route.travelConflicts(obstacleClearance:settings.obstacleClearance).isEmpty else {
            throw LabError.invalid("출발점까지 직선 경로에 등록된 기물이 있어요. 조력자와 이동 경로를 확인해주세요.")
        }
        return route
    }
}
