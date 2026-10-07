import SwiftUI
import WayDetectCore

struct RoutesView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: SessionController
    let select: (Route) -> Void
    @State private var editing: Route?
    var body: some View {
        List {
            Section {
                ForEach(store.routes) { route in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.name).font(.headline)
                                Text("\(route.spots.count)개 스팟 · \(route.totalSteps)걸음").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { editing = route } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                                .buttonStyle(.borderless).accessibilityLabel("\(route.name) 편집")
                                .disabled(session.isActive)
                        }
                        ForEach(Array(route.spots.enumerated()), id: \.element.id) { index, spot in
                            Label("\(index + 1). \(spot.name) · \(spot.instruction)", systemImage: "mappin.circle")
                                .font(.subheadline)
                        }
                        Button("이 경로 사용") { select(route) }.buttonStyle(.borderedProminent).disabled(session.isActive)
                    }.padding(.vertical, 8)
                }.onDelete { if !session.isActive { store.deleteRoutes(at: $0) } }
            }
            Section {
                InfoNote(text: "목표 걸음 후 1.5초 멈추면 도착으로 처리하고, 현재 정면을 새 12시로 설정합니다. 실제 위치를 확인하는 기능은 아닙니다.")
            }
        }.navigationTitle("경로")
            .toolbar { Button { editing = Route() } label: { Image(systemName: "plus") }.accessibilityLabel("경로 추가").disabled(session.isActive) }
            .sheet(item: $editing) { route in RouteEditor(route: route) }
    }
}
private struct RouteEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var route: Route
    var body: some View {
        NavigationStack {
            Form {
                Section("경로") { TextField("경로 이름", text: $route.name) }
                Section {
                    ForEach($route.spots) { $spot in
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("스팟 이름", text: $spot.name)
                            Picker("방향", selection: $spot.clock) {
                                ForEach([12] + Array(1...11), id: \.self) { clock in Text("\(clock)시 방향").tag(clock) }
                            }
                            HStack {
                                Text("걸음 수")
                                TextField("걸음", value: $spot.steps, format: .number)
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                    .accessibilityLabel("\(spot.name) 걸음 수")
                            }
                        }.padding(.vertical, 4)
                    }.onDelete { route.spots.remove(atOffsets: $0) }.onMove { route.spots.move(fromOffsets: $0, toOffset: $1) }
                    Button("스팟 추가", systemImage: "plus.circle") {
                        route.spots.append(RouteSpot(name: "스팟 \(route.spots.count + 1)"))
                    }.disabled(route.spots.count >= 20)
                } header: { Text("방문할 스팟 순서") } footer: {
                    Text("이전 스팟의 정면이 12시입니다. 예: 3시로 10걸음 → 1.5초 정지 → 현재 정면을 새 12시로 자동 설정.")
                }
                if let message = route.validationMessage { Text(message).foregroundStyle(.orange) }
            }.navigationTitle("경로 편집").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") { store.saveRoute(route); dismiss() }.disabled(route.validationMessage != nil)
                    }
                    ToolbarItem(placement: .bottomBar) { EditButton() }
                }
        }
    }
}
