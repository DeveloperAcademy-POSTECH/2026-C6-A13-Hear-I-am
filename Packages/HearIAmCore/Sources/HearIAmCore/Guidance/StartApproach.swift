import Foundation

public enum StartApproach {
    /// A straight approach within the scanned stage. Never invent an unscanned detour.
    public static func route(from position: FloorPoint, to saved: StageRoute, settings: GuideSettings) throws -> StageRoute {
        try saved.validate();try settings.validate()
        guard let start=saved.points.first, position.valid else {
            throw LabError.invalid("현재 위치와 저장된 출발점을 확인할 수 없어요.")
        }
        let margin=Int((settings.boundaryMargin*100).rounded())
        guard saved.area.contains(start,margin:settings.boundaryMargin) else {
            throw LabError.invalid("저장된 출발점이 무대 밖이거나 경계에서 \(margin)센티미터 이내에 있어 접근 안내를 시작할 수 없어요. 조력자와 출발점 위치를 확인해주세요.")
        }
        guard saved.area.contains(position,margin:settings.boundaryMargin) else {
            throw LabError.invalid("현재 위치가 무대 밖이거나 경계에서 \(margin)센티미터 이내에 있어요. 조력자와 무대 안쪽으로 이동한 뒤 다시 눌러주세요.")
        }
        guard position.distance(to:start) > settings.startRadius else { throw LabError.invalid("이미 출발점에 도착했어요. 잠시 멈춰주세요.") }
        let route=try StageRoute(area:saved.area,points:[position,start],obstacles:saved.obstacles,dangerZones:saved.dangerZones)
        guard route.conflicts(boundaryMargin:settings.boundaryMargin,obstacleClearance:settings.obstacleClearance).isEmpty else {
            throw LabError.invalid("출발점까지 직선 경로에 등록된 기물이 있어요. 조력자와 이동 경로를 확인해주세요.")
        }
        return route
    }
}
