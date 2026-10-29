import Foundation

public enum StartApproach {
    /// A straight approach within the scanned stage. Never invent an unscanned detour.
    public static func route(from position: FloorPoint, to saved: StageRoute, settings: GuideSettings) throws -> StageRoute {
        try saved.validate();try settings.validate()
        guard let start=saved.points.first, position.valid,
              saved.area.contains(position,margin:settings.boundaryMargin),
              saved.area.contains(start,margin:settings.boundaryMargin) else {
            throw LabError.invalid("출발점 접근 안내는 현재 위치와 출발점이 스캔한 무대 범위 안에 있을 때 사용할 수 있어요.")
        }
        guard position.distance(to:start) > settings.startRadius else { throw LabError.invalid("이미 출발점에 도착했어요. 잠시 멈춰주세요.") }
        let route=try StageRoute(area:saved.area,points:[position,start],obstacles:saved.obstacles,dangerZones:saved.dangerZones)
        guard route.conflicts(boundaryMargin:settings.boundaryMargin,obstacleClearance:settings.obstacleClearance).isEmpty else {
            throw LabError.invalid("출발점까지 직선 경로에 등록된 기물이 있어요. 조력자와 이동 경로를 확인해주세요.")
        }
        return route
    }
}
