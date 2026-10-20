import HearIAmCore

extension PreparationViewModel {
    func addRoutePoint(destination: Bool = false) {
        guard canPlacePoint, !confirmingRouteHeight, let area=draft.area else {return}
        do {
            let point=try session.centerFloorPoint()
            // Preflight every structural and path constraint before offering a height override.
            var candidate=draft
            try candidate.addRoutePoint(point,asDestination:destination,confirmHeightMismatch:true)
            if let warning=draft.routeSurfaceError(point,in:area) {
                pendingRouteHeight=(point,destination,draft,session.token)
                routeHeightMessage=warning
                confirmingRouteHeight=true
            } else {
                try draft.addRoutePoint(point,asDestination:destination)
                synchronize()
            }
        } catch {session.errorMessage=error.localizedDescription}
    }
    func confirmRouteHeight() {
        defer {pendingRouteHeight=nil; confirmingRouteHeight=false}
        guard let pending=pendingRouteHeight, step == .route, !busy, canPlacePoint,
              pending.token == session.token,
              pending.draft.corners == draft.corners, pending.draft.objects == draft.objects,
              pending.draft.route == draft.route, pending.draft.routeFinished == draft.routeFinished else {
            session.errorMessage="추적 상태 또는 입력이 바뀌었어요. 경로점을 다시 선택해주세요."
            return
        }
        do {
            // Use the captured point, not the crosshair's possibly changed position.
            try draft.addRoutePoint(pending.point,asDestination:pending.destination,confirmHeightMismatch:true)
            session.event("route_height_confirmed",detail:routeHeightMessage)
            synchronize()
        } catch {session.errorMessage=error.localizedDescription}
    }
    func cancelRouteHeight() { pendingRouteHeight=nil; confirmingRouteHeight=false }
    func undoRoutePoint() {
        guard !busy else {return}
        cancelRouteHeight()
        draft.removeLastRoutePoint(); synchronize()
    }
}
