import SwiftUI
import HearIAmCore

struct SpaceFilterSheet: View {
    @Binding var filter: SpaceFilter
    let regions: [String]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("지역") {
                    Picker("지역 선택",selection:$filter.region) {
                        Text("전체 지역").tag(nil as String?)
                        ForEach(regions,id:\.self) {Text($0).tag(Optional($0))}
                    }
                }
                if filter.kind != .rehearsal {
                    Section {Picker("객석 규모",selection:$filter.scale) {
                        Text("전체 규모").tag(nil as SeatScale?)
                        ForEach(SeatScale.allCases,id:\.self) {Text("\($0.label) · \($0.detail)").tag(Optional($0))}
                    }} footer:{Text("내부 공연장의 객석 수 기준입니다. 공식 명칭인 ‘대극장·소극장’이나 무대 면적과는 다릅니다.")}
                }
                Section("내 공간") {
                    Toggle("즐겨찾기만",isOn:$filter.favoritesOnly)
                    Toggle("기본 공간이 저장된 곳만",isOn:$filter.baseOnly)
                    Toggle("내 공연이 있는 곳만",isOn:$filter.performancesOnly)
                }
                Section {Button("필터 초기화") {let query=filter.query;let kind=filter.kind;filter=SpaceFilter();filter.query=query;filter.kind=kind}}
            }.navigationTitle("공간 필터").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.confirmationAction) {Button("적용") {dismiss()}}}
        }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
}
