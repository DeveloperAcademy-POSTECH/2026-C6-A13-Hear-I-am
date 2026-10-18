import SwiftUI
import HearIAmCore

/// Floor plan of the current draft, re-projected onto the latest stage rectangle.
struct PreparationMiniMap: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        let draft=model.draft, area=draft.area, boundary=model.step == .boundary
        StageMap(width:area?.width ?? 12,depth:area?.depth ?? 8,
                 points:area.map {a in draft.route.map(a.floor)} ?? [],finished:draft.routeFinished,
                 objects:area.map {a in draft.objects.compactMap {try? $0.projected(in:a)}} ?? [],
                 dangerZones:area == nil ? [] : draft.dangerZones,
                 checkpoint:area.flatMap {a in draft.checkpoint.map(a.floor)},
                 cornerStates:boundary ? draft.corners.map {$0 != nil} : nil,
                 activeCorner:boundary ? model.nextCorner : nil)
    }
}
