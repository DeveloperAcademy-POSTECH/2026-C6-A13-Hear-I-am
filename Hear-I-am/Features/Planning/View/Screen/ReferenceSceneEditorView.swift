import SwiftUI
import HearIAmCore

/// Multiple independent reference scenes. Actual scans keep their own calibrated route settings.
struct ReferenceSceneEditorView: View {
    @ObservedObject var library: StageLibrary
    let performanceID: UUID
    @State private var scenes: [PerformancePlan]
    @State private var selectedID: UUID?
    @State private var tool: ReferenceSceneTool = .set
    @State private var selectedObject: UUID?
    @State private var dragBaseline: PerformancePlan?
    @State private var removedSceneIDs: Set<UUID> = []
    @State private var renameTarget: ReferenceRenameTarget?
    @State private var renameText = ""
    @State private var deletingObject: UUID?
    @State private var deletingScene = false
    @State private var confirmExit = false
    @State private var message: String?
    @State private var saving = false
    @State private var dirty = false
    @State private var addPageID = UUID()
    @Environment(\.dismiss) private var dismiss
    init(library: StageLibrary, performanceID: UUID, initialSceneID: UUID? = nil) {
        self.library = library; self.performanceID = performanceID
        var loaded = library.referencePlans(for: performanceID)
        if loaded.isEmpty { var plan = PerformancePlan(); plan.name = "1번 씬"; plan.isReferenceOnly = true; loaded = [plan] }
        for index in loaded.indices { loaded[index].isReferenceOnly = true }
        _scenes = State(initialValue: loaded)
        _selectedID = State(initialValue: loaded.contains(where: { $0.id == initialSceneID }) ? initialSceneID : loaded.first?.id)
    }
    private var selectedIndex: Int? { scenes.firstIndex { $0.id == selectedID } }
    private var current: PerformancePlan? { selectedIndex.map { scenes[$0] } }
    private var visibleObjects: [StageObstacle] { current?.objects.filter { tool == .prop ? $0.isStep : !$0.isStep } ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("편집 항목", selection: $tool) {
                        ForEach(ReferenceSceneTool.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tool.title).font(.title3.bold())
                        Text(tool.detail).font(.caption).foregroundStyle(HearV3.secondary)
                    }.padding(.horizontal, 16)
                    scenePages
                    if let plan = current {
                        HStack {
                            Text(tool == .route ? "이동 순서" : "세트 · 기물 목록").font(.headline)
                            Spacer()
                            if tool != .route {
                                Button { addObjectAtCenter() } label: { Label("추가", systemImage: "plus") }
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule).font(.caption)
                            }
                        }.padding(.horizontal, 16)
                        if tool == .route { routeRows(plan) }
                        else { objectRows }
                    }
                }.padding(.top, 16).padding(.bottom, 24)
            }.v3Screen().navigationTitle("기본 동선 설정").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { if dirty { confirmExit = true } else { dismiss() } } label: { Image(systemName: "chevron.backward") }.accessibilityLabel("나가기").disabled(saving)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("씬 이름 변경", systemImage: "pencil") { if let plan = current { renameText = plan.name; renameTarget = .scene(plan.id) } }
                            Button("새 씬 추가", systemImage: "plus") { addScene() }
                            if scenes.count > 1 { Button("현재 씬 삭제", systemImage: "trash", role: .destructive) { deletingScene = true } }
                        } label: { Image(systemName: "ellipsis") }.accessibilityLabel("씬 관리").disabled(saving || current == nil)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button(saving ? "저장 중…" : "저장하기", action: save)
                        .buttonStyle(V3PrimaryButtonStyle()).disabled(saving || scenes.isEmpty)
                        .padding(.horizontal, 16).padding(.vertical, 12).background(HearV3.canvas.opacity(0.95))
                        .accessibilityIdentifier("performance.scenes.save")
                }
                .disabled(saving).interactiveDismissDisabled(dirty || saving)
                .onChange(of: selectedID) { selectedObject = nil; dragBaseline = nil }
                .onChange(of: tool) { selectedObject = nil; dragBaseline = nil }
                .confirmationDialog("저장하지 않은 변경사항이 있어요", isPresented: $confirmExit, titleVisibility: .visible) {
                    Button("저장하지 않고 나가기", role: .destructive) { dismiss() }; Button("계속 편집", role: .cancel) { }
                }
                .alert("이름 변경", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                    TextField("이름", text: $renameText)
                    Button("저장") { rename() }.disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renameText.count > 80)
                    Button("취소", role: .cancel) { renameTarget = nil }
                }
                .confirmationDialog("기물을 삭제할까요?", isPresented: Binding(get: { deletingObject != nil }, set: { if !$0 { deletingObject = nil } }), titleVisibility: .visible) {
                    if let id = deletingObject { Button("삭제", role: .destructive) { edit { $0.removeObject(id) }; selectedObject = nil; deletingObject = nil } }
                    Button("취소", role: .cancel) { deletingObject = nil }
                } message: { Text("이 씬의 도면에서만 사라집니다.") }
                .confirmationDialog("현재 씬을 삭제할까요?", isPresented: $deletingScene, titleVisibility: .visible) {
                    Button("씬 삭제", role: .destructive) { removeScene() }; Button("취소", role: .cancel) { }
                } message: { Text("저장하기를 눌러야 반영됩니다. 스캔한 무대에는 영향을 주지 않아요.") }
                .alert("확인해주세요", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("확인", role: .cancel) { message = nil }
                } message: { Text(message ?? "") }
        }.v3Screen()
    }

    private var scenePages: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(scenes) { plan in
                            VStack(spacing: 10) {
                                ReferencePlanCanvas(plan: plan, editing: true, selectedObject: plan.id == selectedID ? selectedObject : nil,
                                                    onTap: { point in selectedID = plan.id; tap(point) },
                                                    onDragChanged: { start, end in if selectedID == plan.id { drag(from: start, to: end) } },
                                                    onDragEnded: { dragBaseline = nil })
                                    .frame(height: 250)
                                    .overlay(alignment: .topLeading) {
                                        Button { selectedID = plan.id; renameText = plan.name; renameTarget = .scene(plan.id) } label: {
                                            Text(plan.name).font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 6)
                                                .background(.thinMaterial, in: Capsule())
                                        }.buttonStyle(.plain).padding(12).accessibilityLabel("\(plan.name), 이름 변경")
                                    }
                                Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
                                Text("관객석").font(.caption2).foregroundStyle(.secondary)
                            }.frame(width: geometry.size.width - 36).id(plan.id)
                        }
                        Button(action: addScene) {
                            VStack(spacing: 16) { Image(systemName: "plus").font(.largeTitle); Text("새 씬 추가").font(.headline); Text("장면마다 다른 배치와 동선을 그려요").font(.caption).foregroundStyle(.secondary) }
                                .frame(width: geometry.size.width - 36, height: 250).background(HearV3.surface, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).id(addPageID).accessibilityIdentifier("performance.scenes.add")
                    }.scrollTargetLayout()
                }.contentMargins(.horizontal, 16, for: .scrollContent).scrollTargetBehavior(.viewAligned).scrollPosition(id: $selectedID)
            }.frame(height: 286)
            HStack(spacing: 7) {
                ForEach(scenes) { plan in
                    Button { withAnimation { selectedID = plan.id } } label: {
                        Circle().fill(selectedID == plan.id ? HearV3.text : HearV3.secondary.opacity(0.35)).frame(width: 6, height: 6).padding(6)
                    }.buttonStyle(.plain).accessibilityLabel("\(plan.name) 선택")
                }
                Image(systemName: "plus").font(.system(size: 8, weight: .bold)).foregroundStyle(selectedID == addPageID ? HearV3.text : HearV3.secondary.opacity(0.35))
            }.frame(maxWidth: .infinity).accessibilityLabel("\(scenes.count)개의 씬. 옆으로 넘겨 새 씬을 추가할 수 있어요.")
        }
    }
    private var objectRows: some View {
        VStack(spacing: 8) {
            if visibleObjects.isEmpty {
                Text("무대를 누르거나 추가 버튼으로\n\(tool.rawValue)을 배치해주세요.").font(.subheadline).multilineTextAlignment(.center)
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ForEach(visibleObjects) { object in
                    HStack {
                        Button { selectedObject = selectedObject == object.id ? nil : object.id } label: { Text(object.name).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44) }.buttonStyle(.plain)
                        Button { renameText = object.name; renameTarget = .object(object.id) } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("\(object.name) 이름 변경")
                        Button { deletingObject = object.id } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("\(object.name) 삭제")
                    }.font(.body).buttonStyle(.borderless).padding(.horizontal, 17).padding(.vertical, 16)
                        .background(selectedObject == object.id ? HearV3.selected : HearV3.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }.padding(.horizontal, 16)
    }
    private func routeRows(_ plan: PerformancePlan) -> some View {
        VStack(spacing: 8) {
            if plan.points.isEmpty {
                Text("지점을 추가하면 이동 순서가 여기에 표시돼요.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 110)
            }
            ForEach(plan.points.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text(plan.pointLabel(at: index)).font(.caption).frame(width: 40, height: 40).background(HearV3.selected, in: Circle())
                    Text(plan.settings(at: index).name.isEmpty ? plan.pointLabel(at: index) : plan.settings(at: index).name).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                    Button { renameText = plan.settings(at: index).name; renameTarget = .point(index) } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("\(plan.pointLabel(at: index)) 이름 변경")
                    Button { edit { $0.removePoint(at: index) } } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("\(plan.pointLabel(at: index)) 삭제")
                }.buttonStyle(.borderless).padding(.horizontal, 17).padding(.vertical, 16).background(HearV3.surface, in: RoundedRectangle(cornerRadius: 18))
            }
        }.padding(.horizontal, 16)
    }
    private func addScene() {
        var plan = PerformancePlan(); plan.isReferenceOnly = true
        var number = scenes.count + 1
        while scenes.contains(where: { $0.name == "\(number)번 씬" }) { number += 1 }
        plan.name = "\(number)번 씬"; scenes.append(plan); dirty = true; selectedObject = nil
        withAnimation { selectedID = plan.id }
    }
    private func removeScene() {
        guard let index = selectedIndex, scenes.count > 1 else { return }
        removedSceneIDs.insert(scenes[index].id); scenes.remove(at: index); selectedID = scenes[min(index, scenes.count - 1)].id; dirty = true
    }
    private func tap(_ point: FloorPoint) {
        guard let plan = current else { return }
        if tool == .route {
            if let index = plan.points.indices.min(by: { plan.points[$0].distance(to: point) < plan.points[$1].distance(to: point) }), plan.points[index].distance(to: point) < 0.4 {
                renameText = plan.settings(at: index).name; renameTarget = .point(index)
            } else { edit { plan in plan.resumeEditing(); try plan.append(point) } }
            return
        }
        if let hit = plan.objects.last(where: { $0.contains(point) }) { selectedObject = selectedObject == hit.id ? nil : hit.id; return }
        if selectedObject != nil { selectedObject = nil }
        else { addObject(at: point) }
    }
    private func addObjectAtCenter() { selectedObject = nil; addObject(at: .init(6, 4)) }
    private func addObject(at point: FloorPoint) {
        let p = FloorPoint(min(11.3, max(0.7, point.x)), min(7.3, max(0.7, point.y)))
        let prop = tool == .prop
        edit { plan in
            var number = plan.objects.filter { $0.isStep == prop }.count + 1
            let prefix = prop ? "기물" : "세트"
            while plan.objects.contains(where: { $0.name == "\(prefix) \(number)" }) { number += 1 }
            let name = "\(prefix) \(number)"
            let vertices = [FloorPoint(p.x - 0.6, p.y - 0.5), FloorPoint(p.x + 0.6, p.y - 0.5), FloorPoint(p.x + 0.6, p.y + 0.5), FloorPoint(p.x - 0.6, p.y + 0.5)]
            let object = try StageObstacle(name: name, kind: prop ? .platform : .other, passage: prop ? .passable : .prohibited, vertices: vertices)
            plan.objects.append(object); selectedObject = object.id
        }
    }
    private func drag(from start: FloorPoint, to end: FloorPoint) {
        guard let index = selectedIndex else { return }
        if dragBaseline == nil { dragBaseline = scenes[index] }
        guard var plan = dragBaseline else { return }
        do {
            if tool == .route {
                guard let pointIndex = plan.points.indices.min(by: { plan.points[$0].distance(to: start) < plan.points[$1].distance(to: start) }), plan.points[pointIndex].distance(to: start) < 0.6 else { return }
                try plan.movePoint(at: pointIndex, to: end)
            } else {
                guard let object = plan.objects.last(where: { $0.contains(start) || ($0.id == selectedObject && $0.vertices.contains(where: { $0.distance(to: start) < 0.7 })) }) else { return }
                selectedObject = object.id
                let xs = object.vertices.map(\.x), ys = object.vertices.map(\.y)
                let center = FloorPoint((xs.min()! + xs.max()!) / 2, (ys.min()! + ys.max()!) / 2)
                if object.vertices.contains(where: { $0.distance(to: start) < 0.5 }) {
                    try plan.resizeObject(object.id, width: max(0.3, abs(end.x - center.x) * 2), depth: max(0.3, abs(end.y - center.y) * 2))
                } else { try plan.moveObject(object.id, to: .init(center.x + end.x - start.x, center.y + end.y - start.y)) }
            }
            scenes[index] = plan; dirty = true
        } catch { /* Keep the last valid geometry while dragging beyond the canvas. */ }
    }
    private func rename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let target = renameTarget else { return }
        switch target {
        case .scene(let id): if let index = scenes.firstIndex(where: { $0.id == id }) { scenes[index].name = name; dirty = true }
        case .object(let id): edit { plan in if let index = plan.objects.firstIndex(where: { $0.id == id }) { plan.objects[index].name = name } }
        case .point(let index): edit { plan in var settings = plan.settings(at: index); settings.name = name; try plan.setPointSettings(settings, at: index) }
        }
        renameTarget = nil
    }
    private func edit(_ action: (inout PerformancePlan) throws -> Void) {
        guard let index = selectedIndex else { return }
        do { var plan = scenes[index]; try action(&plan); scenes[index] = plan; dirty = true }
        catch { message = error.localizedDescription }
    }
    private func save() {
        guard !saving else { return }; saving = true
        Task {
            do {
                for var plan in scenes { plan.completeReference(); try await library.savePerformancePlan(plan, for: performanceID) }
                for id in removedSceneIDs {
                    // An unsaved scene can be added and removed in the same editing session.
                    // Also allow retry after an earlier deletion in this batch already succeeded.
                    if library.catalog.performances.first(where: { $0.id == performanceID })?.referencePlanIDs.contains(id) == true {
                        try await library.removePerformancePlan(id: id, from: performanceID)
                    }
                }
                dirty = false; dismiss()
            } catch { message = "저장하지 못한 씬이 있어요. 편집 내용은 유지됩니다. \(error.localizedDescription)" }
            saving = false
        }
    }
}

private enum ReferenceSceneTool: String, CaseIterable, Identifiable {
    case set = "세트", prop = "기물", route = "동선"
    var id: Self { self }
    var title: String {
        switch self { case .set: return "이동 방해 위치를 표시해요"; case .prop: return "이용하는 기물을 배치해요"; case .route: return "이동 경로를 정해요" }
    }
    var detail: String {
        switch self {
        case .set: return "세트를 추가하고, 모서리 점을 끌어 크기를 조절해요"
        case .prop: return "의자 · 단상 등 장면에 필요한 기물을 배치해요"
        case .route: return "무대 위를 누르는 순서대로 이동 지점을 추가해요"
        }
    }
}
private enum ReferenceRenameTarget { case scene(UUID), object(UUID), point(Int) }
