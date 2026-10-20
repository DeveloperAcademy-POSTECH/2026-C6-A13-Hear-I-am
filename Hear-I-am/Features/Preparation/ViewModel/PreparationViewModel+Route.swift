import HearIAmCore

/// Step 4 · 경로. Start, 1–4 interior points, then a destination: 3–6 points in total.
extension PreparationViewModel {
    func addRoutePoint(destination: Bool = false) {
        place { draft,point in
            if let hit=draft.clearanceHit(adding:point) {
                session.event("route_point_blocked",detail:"\(hit.name) overlap=\(String(format:"%.2f",hit.overlap)) inside=\(hit.pointInside)")
            }
            try draft.addRoutePoint(point,asDestination:destination)
        }
    }
    func undoRoutePoint() {
        guard !busy else {return}
        let removed=draft.route.count-1
        for source in session.photoSources where source.photo.routePointIndex==removed {
            session.linkPhoto(source.photo.id,objectID:source.photo.objectID,routeIndex:nil)
        }
        draft.removeLastRoutePoint(); synchronize()
    }
}
