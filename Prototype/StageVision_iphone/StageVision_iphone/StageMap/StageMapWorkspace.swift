import SwiftUI
import ARKit

struct StageMapWorkspace: View {
    @StateObject private var store = StageMapStore()
    @State private var scanning = false
    @State private var name = "새 무대"
    @State private var venue = ""
    @State private var selectedPoint: Int?
    @State private var selectedEdge = 0
    @State private var positionMode = false
    @State private var exporting = false
    @State private var document = StageMapDocument(data: Data())
    @State private var confirmNew = false
    @State private var confirmOriginal = false
    @State private var confirmFront = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let map = store.map {
                            if geometry.size.width >= 760 {
                                HStack(alignment: .top, spacing: 22) {
                                    plan(map).frame(maxWidth: .infinity)
                                    settings(map).frame(width: 320)
                                }
                            } else {
                                plan(map)
                                settings(map)
                            }
                        } else {
                            setup
                        }
                    }
                    .padding(20).frame(maxWidth: 1300).frame(maxWidth: .infinity)
                }
            }
            .background(Color(red: 0.055, green: 0.075, blue: 0.105))
            .navigationTitle("무대 지도")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("실행 취소", systemImage: "arrow.uturn.backward") { store.undo(); resetSelection() }
                        .disabled(!store.canUndo)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("새 스캔", systemImage: "viewfinder") {
                        if store.map != nil { confirmNew = true } else { scanning = true }
                    }.disabled(!ARWorldTrackingConfiguration.isSupported)
                }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            StageScannerView(name: name, venue: venue) { map in
                store.replace(map); resetSelection()
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "StageMap") { result in
            if case .failure(let error) = result { store.message = "내보내기 실패: \(error.localizedDescription)" }
        }
        .alert("StageMap", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("확인") { store.message = nil }
        } message: { Text(store.message ?? "") }
        .confirmationDialog("새 스캔이 완료되면 현재 지도가 교체됩니다. 저장하지 않은 변경은 실행 취소로 복원할 수 있습니다.", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("새 무대 스캔") { scanning = true }
        }
        .confirmationDialog("편집을 초기화하고 원본 경계로 돌아갈까요? 위험구역 설정도 초기화됩니다.", isPresented: $confirmOriginal, titleVisibility: .visible) {
            Button("원본 경계로 초기화", role: .destructive) {
                store.edit { map in
                    map.floorPolygon = map.originalFloorPolygon
                    map.boundarySegments = map.floorPolygon.indices.map { BoundarySegment(startIndex: $0, endIndex: ($0 + 1) % map.floorPolygon.count) }
                    map.reindex()
                }
                resetSelection()
            }
        }
        .confirmationDialog("선택한 구간의 바깥쪽을 객석 방향으로, 중점을 새 원점으로 설정합니다. 구간 방향 분류는 다시 지정하세요.", isPresented: $confirmFront, titleVisibility: .visible) {
            Button("선택 구간을 무대 앞쪽으로") { store.edit { $0.setFront(edge: selectedEdge) } }
        }
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("수동 경계 기반 무대 스캔", systemImage: "viewfinder").font(.title2.bold())
            Text("바닥과 기준 방향을 정한 뒤, 실제 무대 경계를 조준해 기록하세요. 비정형 무대도 2D에서 편집하고 JSON으로 저장할 수 있습니다.")
            TextField("무대 이름", text: $name).textFieldStyle(.roundedBorder)
            TextField("장소", text: $venue).textFieldStyle(.roundedBorder)
            Button("무대 스캔 시작") { scanning = true }
                .buttonStyle(.borderedProminent).disabled(!ARWorldTrackingConfiguration.isSupported)
            if !ARWorldTrackingConfiguration.isSupported {
                Text("이 기기에서는 AR 스캔을 지원하지 않습니다. 기존 직사각형 탭 또는 아래 편집 예제를 사용하세요.").foregroundStyle(.orange)
            }
            Button("2D 편집 예제 열기") {
                var map = StageMap(points: [MapPoint(-4, 0), MapPoint(4, 0), MapPoint(4, 4), MapPoint(1, 4), MapPoint(1, 6), MapPoint(-4, 6)])
                map.name = "편집 예제 · 측정 데이터 아님"
                map.quality.source = "demo-not-measured"; map.quality.tracking = "not-captured"
                map.quality.unverifiedSegmentIndexes = Array(map.floorPolygon.indices)
                map.rebuildRiskZones(); store.replace(map)
            }.buttonStyle(.bordered)
            Text("스캔은 시야가 확보된 스태프가 무대 안쪽에서 진행하세요. LiDAR가 없는 ARKit 지원 기기도 사용할 수 있습니다.")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding(18).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
    private func plan(_ map: StageMap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(map.name).font(.title2.bold())
            Text("무대 뒤쪽 +Y ↑ · 오른쪽 +X →").font(.caption).frame(maxWidth: .infinity)
            StagePlanView(map: map, selectedPoint: $selectedPoint, selectedEdge: $selectedEdge, positionMode: positionMode,
                          move: { store.movePoint($0, to: $1) }, setPosition: { p in
                guard map.issue == nil, StageGeometry.contains(p, polygon: map.floorPolygon) else {
                    store.message = "시작 위치는 유효한 무대 다각형 내부를 선택하세요."; return
                }
                store.edit { $0.startPosition = p }
            })
            .frame(height: 400)
            Text("↓ 관객석 · 무대 앞쪽 −Y").font(.caption).frame(maxWidth: .infinity)
            if let issue = map.issue {
                Label(issue.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text("유효한 경계가 될 때까지 저장과 위험구역 표시를 중지합니다.").font(.caption)
            }
            let width = (map.floorPolygon.map(\.x).max() ?? 0) - (map.floorPolygon.map(\.x).min() ?? 0)
            let depth = (map.floorPolygon.map(\.y).max() ?? 0) - (map.floorPolygon.map(\.y).min() ?? 0)
            Text(String(format: "면적 %.2fm² · 최대 폭 %.2fm · 깊이 %.2fm", abs(StageGeometry.signedArea(map.floorPolygon)), width, depth))
                .font(.subheadline.monospacedDigit())
            Text("점: 드래그로 이동 · 선분: 터치로 선택 · 노랑: 선택 · 주황: 위험구역\n좌표와 위험 폭의 단위는 m입니다. 격자는 기본 1m이며 넓은 범위에서는 간격이 늘어납니다.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("평면도 터치로 무용수 시작 위치 지정", isOn: $positionMode)
            if let p = map.startPosition {
                Text(String(format: "시작 위치 X %.2f · Y %.2f", p.x, p.y))
                if map.isRisk(p) { Label("시작 위치가 위험구역에 있습니다.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                Button("시작 위치 지우기") { store.edit { $0.startPosition = nil } }
            }
            Text("수동 시작 위치이며 자동 추적하지 않습니다.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func settings(_ map: StageMap) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("무대 정보") {
                VStack {
                    TextField("무대 이름", text: Binding(get: { store.map?.name ?? "" }, set: { value in store.edit { $0.name = value }; name = value }))
                    TextField("장소", text: Binding(get: { store.map?.venue ?? "" }, set: { value in store.edit { $0.venue = value }; venue = value }))
                }.textFieldStyle(.roundedBorder)
            }
            GroupBox("경계 편집") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("선택 점", selection: $selectedPoint) {
                        Text("점 선택").tag(Optional<Int>.none)
                        ForEach(map.floorPolygon.indices, id: \.self) { Text("점 \($0 + 1)").tag(Optional($0)) }
                    }
                    if let i = selectedPoint, map.floorPolygon.indices.contains(i) {
                        Text(String(format: "X %.2f · Y %.2f", map.floorPolygon[i].x, map.floorPolygon[i].y)).monospacedDigit()
                        HStack {
                            nudge("←", i, MapPoint(-0.05, 0)); nudge("→", i, MapPoint(0.05, 0))
                            nudge("↓", i, MapPoint(0, -0.05)); nudge("↑", i, MapPoint(0, 0.05))
                        }
                        Text("화살표 한 번 = 5cm 이동").font(.caption)
                        Button("선택 점 삭제", role: .destructive) { store.deletePoint(i); resetSelection() }.disabled(map.floorPolygon.count <= 3)
                    }
                    Button("선택 구간 중간에 점 추가") { store.insertPoint(after: selectedEdge); selectedPoint = selectedEdge + 1 }
                        .disabled(map.floorPolygon.count >= StageGeometry.maximumPoints)
                    Button("원본 경계로 초기화", role: .destructive) { confirmOriginal = true }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if map.boundarySegments.indices.contains(selectedEdge) {
                segmentSettings(map)
            }
            GroupBox("품질과 저장") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("경계 오차: 미측정 · 입력 \(map.floorPolygon.count)점").font(.subheadline)
                    Text("가상 평면 입력 \(map.quality.virtualPlanePointIndexes.count)점 · 추적 저하 \(map.quality.trackingInterruptionCount)회").font(.caption)
                    if !map.quality.unverifiedSegmentIndexes.isEmpty {
                        Text("확인 필요: \(map.quality.unverifiedSegmentIndexes.map { "S\($0 + 1)" }.joined(separator: ", "))").font(.caption).foregroundStyle(.orange)
                    }
                    Text("가상 평면 입력·긴 구간·편집한 경계는 현장 확인이 필요합니다. 측정 결과는 안전을 보장하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    if map.quality.source == "demo-not-measured" { Text("예제 데이터입니다. 실제 측정값이 아닙니다.").foregroundStyle(.orange) }
                    Button(store.isDirty ? "JSON 저장 · 변경 있음" : "JSON 저장") { store.save() }
                        .buttonStyle(.borderedProminent).disabled(map.issue != nil)
                    Button("JSON 내보내기 / 파일에 저장") {
                        do { document = try store.document(); exporting = true }
                        catch { store.message = error.localizedDescription }
                    }.buttonStyle(.bordered).disabled(map.issue != nil)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func segmentSettings(_ map: StageMap) -> some View {
        GroupBox("구간별 위험구역") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("경계 구간", selection: $selectedEdge) {
                    ForEach(map.boundarySegments.indices, id: \.self) { i in
                        Text("S\(i + 1) · 점 \(i + 1) → \((i + 1) % map.floorPolygon.count + 1)").tag(i)
                    }
                }
                Picker("구간 방향", selection: Binding(get: { store.map?.boundarySegments[selectedEdge].side ?? .other }, set: { side in store.edit { $0.boundarySegments[selectedEdge].side = side } })) {
                    ForEach(BoundarySide.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("이 구간 위험구역 사용", isOn: Binding(get: { store.map?.boundarySegments[selectedEdge].riskEnabled ?? false }, set: { value in store.edit { $0.boundarySegments[selectedEdge].riskEnabled = value } }))
                Picker("위험 폭", selection: Binding(get: { store.map?.boundarySegments[selectedEdge].riskDistance ?? 1 }, set: { value in store.edit { $0.boundarySegments[selectedEdge].riskDistance = value } })) {
                    Text("1.0m").tag(1.0); Text("1.5m").tag(1.5)
                }.pickerStyle(.segmented)
                Button("이 구간을 무대 앞쪽·원점으로") { confirmFront = true }.disabled(map.issue != nil)
                Text("방향 분류는 구간의 이름입니다. 위 버튼은 좌표계 자체를 회전하고 원점을 바꿉니다.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func nudge(_ label: String, _ i: Int, _ delta: MapPoint) -> some View {
        Button(label) {
            if let map = store.map { store.movePoint(i, to: map.floorPolygon[i] + delta) }
        }.buttonStyle(.bordered).accessibilityLabel("점 \(i + 1) \(label) 방향 5cm 이동")
    }
    private func resetSelection() { selectedPoint = nil; selectedEdge = 0 }
}
