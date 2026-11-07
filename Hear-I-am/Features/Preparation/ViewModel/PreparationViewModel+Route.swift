import HearIAmCore

extension PreparationViewModel {
    func addRoutePoint(destination: Bool = false) {
        guard canPlacePoint, !confirmingRouteHeight, let area=draft.area else {return}
        do {
            let point=try session.centerFloorPoint()
            if let hit=draft.clearanceHit(adding:point) {
                session.event("route_point_blocked",detail:"\(hit.name) overlap=\(String(format:"%.2f",hit.overlap)) inside=\(hit.pointInside)")
            }
            if let issue=draft.edgeIssue(adding:point,asDestination:destination) {
                session.event("route_point_blocked",detail:issue)
            }
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
    /// 「지정 완료」 on the route step: the last point placed becomes the destination when none was marked,
    /// then the step ends (971:29061 has no separate destination button).
    func finishRoute() {
        guard !busy, !confirmingRouteHeight else {return}
        if !draft.routeFinished {
            guard draft.route.count >= 2, let last=draft.route.last else {return}
            var candidate=draft
            candidate.removeLastRoutePoint()
            do {
                try candidate.addRoutePoint(last,asDestination:true,confirmHeightMismatch:true)
                draft=candidate; synchronize()
            } catch {session.errorMessage=error.localizedDescription; return}
        }
        guard draft.routeErrors.isEmpty else {session.errorMessage=draft.routeErrors.first; return}
        advance()
    }
    func cancelRouteHeight() { pendingRouteHeight=nil; confirmingRouteHeight=false }
    func undoRoutePoint() {
        guard !busy else {return}
        cancelRouteHeight()
        let removed=draft.route.count-1
        for source in session.photoSources where source.photo.routePointIndex==removed {
            session.linkPhoto(source.photo.id,objectID:source.photo.objectID,routeIndex:nil)
        }
        draft.removeLastRoutePoint(); synchronize()
    }
}
