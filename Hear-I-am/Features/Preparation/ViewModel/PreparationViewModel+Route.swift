import HearIAmCore

/// Step 4 · 경로. Start, 1–4 interior points, then a destination: 3–6 points in total.
extension PreparationViewModel {
    func addRoutePoint(destination: Bool = false) {
        place { draft,point in
            if let hit=draft.clearanceHit(adding:point) {
                session.event("route_point_blocked",detail:"\(hit.name) overlap=\(String(format:"%.2f",hit.overlap)) inside=\(hit.pointInside)")
            }
            if let issue=draft.edgeIssue(adding:point,asDestination:destination) { session.event("route_point_blocked",detail:issue) }
            try draft.addRoutePoint(point,asDestination:destination)
        }
    }
    func undoRoutePoint() {
        guard !busy else {return}
        draft.removeLastRoutePoint(); synchronize()
    }
}
