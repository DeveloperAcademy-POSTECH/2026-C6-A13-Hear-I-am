import SwiftUI
import HearIAmCore

struct PreparationDangerZoneSheet: View {
    @ObservedObject var model: PreparationViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            HStack(spacing:16) {
                VStack(spacing:8) {
                    PreparationMiniMap(model:model).frame(minWidth:180,minHeight:120)
                    Text(StageDangerZone.summary(model.draft.dangerZones))
                        .font(.caption).accessibilityLabel(StageDangerZone.summary(model.draft.dangerZones))
                }.frame(maxWidth:260).padding(.vertical)
                Form {
                    Section {
                        ForEach(StageDangerZone.Edge.allCases) { edge in
                            let selected=model.draft.dangerZones.first { $0.edge == edge }
                            VStack(alignment:.leading,spacing:8) {
                                Toggle(edge.label,isOn:Binding(
                                    get:{ model.draft.dangerZones.contains { $0.edge == edge } },
                                    set:{ model.setDangerZone(edge,distance:$0 ? .halfMetre : nil) }))
                                if selected != nil {
                                    Picker("\(edge.label) 거리",selection:Binding(
                                        get:{ model.draft.dangerZones.first { $0.edge == edge }?.distance ?? .halfMetre },
                                        set:{ model.setDangerZone(edge,distance:$0) })) {
                                        ForEach(StageDangerZone.Distance.allCases) { distance in
                                            Text(distance.label).tag(distance)
                                        }
                                    }.pickerStyle(.segmented)
                                }
                            }
                        }
                    } header: { Text("변 선택 · 거리") }
                    footer: { Text("객석에서 무대를 바라보는 기준입니다. 여러 변을 선택할 수 있으며, 선택한 변에서 무대 안쪽으로 표시됩니다. 작은 무대에서는 구역이 겹치거나 무대 전체를 덮을 수 있습니다.") }
                }.disabled(model.busy)
            }.padding(.horizontal)
                .navigationTitle("위험 구역 (Danger zone)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("완료") { dismiss() } } }
        }
    }
}
