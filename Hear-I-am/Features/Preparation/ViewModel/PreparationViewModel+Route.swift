import HearIAmCore

/// Step 4 · 경로. Start, 1–4 interior points, then a destination: 3–6 points in total.
extension PreparationViewModel {
    func addRoutePoint(destination: Bool = false) {
        place { draft,point in try draft.addRoutePoint(point,asDestination:destination) }
    }
    func undoRoutePoint() {
        guard !busy else {return}
        draft.removeLastRoutePoint(); synchronize()
    }
}
