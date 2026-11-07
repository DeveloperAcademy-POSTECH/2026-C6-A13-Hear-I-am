import SwiftUI
import HearIAmCore

/// Multiple independent reference routes (Figma 971:32668 · 971:32812 · 971:32946). Actual scans keep their own
/// calibrated route settings. One route is drawn at a time; the name above it switches between them.
struct ReferenceSceneEditorView: View {
    @ObservedObject var library: StageLibrary
    let performanceID: UUID
    @State private var scenes: [PerformancePlan]
    @State private var selectedID: UUID?
    @State private var tool: ReferenceSceneTool = .point
    @State private var selectedObject: UUID?
    @State private var selectedPoint: Int?
    @State private var dragBaseline: PerformancePlan?
    @State private var past: [[PerformancePlan]] = []
    @State private var future: [[PerformancePlan]] = []
    @State private var removedSceneIDs: Set<UUID> = []
    @State private var renameTarget: ReferenceRenameTarget?
    @State private var renameText = ""
    @State private var managing = false
    @State private var deletingRoute: PerformancePlan?
    @State private var confirmExit = false
    @State private var message: String?
    @State private var saving = false
    @State private var dirty = false
    @Environment(\.dismiss) private var dismiss
    init(library: StageLibrary, performanceID: UUID, initialSceneID: UUID? = nil) {
        self.library = library; self.performanceID = performanceID
        var loaded = library.referencePlans(for: performanceID)
        if loaded.isEmpty { loaded = [Self.newRoute(named: "1번 동선")] }
        for index in loaded.indices { loaded[index].isReferenceOnly = true }
        _scenes = State(initialValue: loaded)
        _selectedID = State(initialValue: loaded.contains(where: { $0.id == initialSceneID }) ? initialSceneID : loaded.first?.id)
    }
    /// A new route starts with its start and arrival waiting in the two backstage strips (971:32668).
    static func newRoute(named name: String) -> PerformancePlan {
        var plan = PerformancePlan(); plan.name = name; plan.isReferenceOnly = true
        try? plan.append(.init(-0.7, 4)); try? plan.append(.init(PerformancePlan.width + 0.7, 4)); plan.completeReference()
        return plan
    }
    private var selectedIndex: Int? { scenes.firstIndex { $0.id == selectedID } }
    private var current: PerformancePlan? { selectedIndex.map { scenes[$0] } }

    var body: some View {
        NavigationStack {
            ScrollView { editorContent }.scrollDisabled(dragBaseline != nil).v3Screen()
                .hearTopBar("기본 동선") {
                    ScanCircleButton(systemImage: "chevron.left", label: "나가기", enabled: !saving) { if dirty { confirmExit = true } else { dismiss() } }
                } trailing: {
                    Button(action: save) { HearTopButtonLabel(systemImage: "checkmark", prominent: true) }
                        .buttonStyle(.plain).disabled(saving).accessibilityLabel(saving ? "저장 중" : "저장하기")
                        .accessibilityIdentifier("performance.scenes.save")
                }
                .navigationDestination(isPresented: $managing) { manageList }
                .disabled(saving).interactiveDismissDisabled(dirty || saving)
                .onChange(of: selectedID) { selectedObject = nil; selectedPoint = nil; dragBaseline = nil }
                .onChange(of: tool) { selectedObject = nil; selectedPoint = nil; dragBaseline = nil }
                .confirmationDialog("저장하지 않은 변경사항이 있어요", isPresented: $confirmExit, titleVisibility: .visible) {
                    Button("저장하지 않고 나가기", role: .destructive) { dismiss() }; Button("계속 편집", role: .cancel) { }
                }
                .alert(renameTarget?.title ?? "이름 변경", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                    TextField("이름", text: $renameText)
                    Button("취소", role: .cancel) { renameTarget = nil }
                    Button("저장") { rename() }.disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renameText.count > 80)
                }
                .alert("확인해주세요", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("확인", role: .cancel) { message = nil }
                } message: { Text(message ?? "") }
        }.v3Screen()
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            routeHeader.padding(.top, 8)
            if let plan = current {
                canvas(plan).padding(.top, 16)
                Text("객석").font(HearFont.pretendard(.regular, size: 12)).foregroundStyle(HearV3.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 12)
                toolPicker.padding(.top, 24)
                Group { if tool == .point { pointRows(plan) } else { objectRows(plan) } }.padding(.top, 16)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath").font(.system(size: 40, weight: .light))
                    Text("동선이 없어요").font(HearFont.pretendard(.semibold, size: 20))
                    Button("새 동선 추가") { addScene() }.buttonStyle(V3PrimaryButtonStyle()).frame(maxWidth: 220)
                }.foregroundStyle(HearV3.secondary).frame(maxWidth: .infinity, minHeight: 320)
            }
        }.padding(.horizontal, 16).padding(.bottom, 32)
    }
    @ViewBuilder private func canvas(_ plan: PerformancePlan) -> some View {
        ReferencePlanCanvas(plan: plan, editing: true, selectedObject: tool == .obstacle ? selectedObject : nil,
                            selectedPoint: tool == .point ? selectedPoint : nil,
                            onTap: { tap($0) }, onDragChanged: { drag(from: $0, to: $1) }, onDragEnded: { dragBaseline = nil })
            .frame(height: 219)
            .overlay {
                if plan.points.count <= 2 && plan.objects.isEmpty {
                    Text("무대에 점을 찍어 새로운 동선을 추가해보세요").font(HearFont.pretendard(.regular, size: 11))
                        .foregroundStyle(.white.opacity(0.35)).allowsHitTesting(false)
                }
            }
    }
    /// 「1번 동선 ⌃⌄」 opens the route menu (971:32728); undo and redo sit on the right.
    private var routeHeader: some View {
        HStack(spacing: 8) {
            Menu {
                Section("동선") {
                    ForEach(scenes) { plan in
                        Button { selectedID = plan.id } label: {
                            if plan.id == selectedID { Label(plan.name, systemImage: "checkmark") } else { Text(plan.name) }
                        }
                    }
                }
                Section { Button("새 동선 추가", systemImage: "plus") { addScene() }.accessibilityIdentifier("performance.scenes.add") }
                Section { Button("동선 관리", systemImage: "gearshape") { managing = true } }
            } label: {
                HStack(spacing: 4) {
                    Text(current?.name ?? "동선 없음").font(HearFont.pretendard(.semibold, size: 20)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold))
                }.foregroundStyle(.white).frame(minHeight: 44).contentShape(Rectangle())
            }.accessibilityLabel("\(current?.name ?? "동선 없음"), 동선 선택")
            Spacer()
            ScanCircleButton(systemImage: "arrow.uturn.backward", label: "실행 취소", size: 36, enabled: !past.isEmpty) { undo() }
            ScanCircleButton(systemImage: "arrow.uturn.forward", label: "다시 실행", size: 36, enabled: !future.isEmpty) { redo() }
        }
    }
    private var toolPicker: some View {
        HStack(spacing: 0) {
            ForEach(ReferenceSceneTool.allCases) { item in
                Text(item.rawValue).font(HearFont.pretendard(.semibold, size: 14)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background { if tool == item { Capsule().fill(Color.white.opacity(0.3)) } }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.snappy(duration: 0.2)) { tool = item } }
                    .accessibilityAddTraits(tool == item ? [.isButton, .isSelected] : .isButton)
            }
        }.padding(2).background(Color.white.opacity(0.1), in: Capsule())
    }
    private func pointRows(_ plan: PerformancePlan) -> some View {
        VStack(spacing: 8) {
            ForEach(plan.points.indices, id: \.self) { index in
                let label = plan.pointLabel(at: index), name = plan.settings(at: index).name
                ReferenceEditorRow(selected: selectedPoint == index, onSelect: { selectedPoint = selectedPoint == index ? nil : index }) {
                    Text(label.hasPrefix("P") ? label.map(String.init).joined(separator: " ") : label)
                        .font(HearFont.pretendard(.semibold, size: 11)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Color.white.opacity(0.3), in: Circle())
                    Text(name.isEmpty ? label : name).font(HearFont.pretendard(.medium, size: 16)).foregroundStyle(.white).lineLimit(1)
                } menu: {
                    Button("이름 변경", systemImage: "pencil") { renameText = name; renameTarget = .point(index) }
                    if index > 0 && index < plan.points.count - 1 || !plan.finished && index > 0 {
                        Button("복제", systemImage: "plus.square.on.square") { edit { try Self.insert(&$0, FloorPoint(plan.points[index].x + 0.4, plan.points[index].y + 0.4), at: index + 1) } }
                    }
                    Section { Button("삭제", systemImage: "trash", role: .destructive) { selectedPoint = nil; edit { $0.removePoint(at: index) } } }
                }
            }
            Text("양 옆 공간은 백스테이지로 출발, 도착 점을 드래그해 위치를 조정하세요").font(HearFont.pretendard(.regular, size: 11))
                .foregroundStyle(.white.opacity(0.35)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 16)
        }
    }
    private func objectRows(_ plan: PerformancePlan) -> some View {
        VStack(spacing: 8) {
            if plan.objects.isEmpty {
                Text("무대를 눌러 장애물을 추가해보세요").font(HearFont.pretendard(.regular, size: 13)).foregroundStyle(HearV3.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            }
            ForEach(plan.objects) { object in
                ReferenceEditorRow(selected: selectedObject == object.id, onSelect: { selectedObject = selectedObject == object.id ? nil : object.id }) {
                    Text(object.name).font(HearFont.pretendard(.medium, size: 16)).foregroundStyle(.white).lineLimit(1)
                } menu: {
                    Button("이름 변경", systemImage: "pencil") { renameText = object.name; renameTarget = .object(object.id) }
                    Button("복제", systemImage: "plus.square.on.square") { duplicate(object) }
                    Picker(selection: Binding(get: { ReferenceShape(object) }, set: { shape in edit { try Self.reshape(&$0, object.id, to: shape) } })) {
                        ForEach(ReferenceShape.allCases) { Text($0.rawValue).tag($0) }
                    } label: { Label("도형", systemImage: "square.on.circle") ; Text(ReferenceShape(object).rawValue) }
                        .pickerStyle(.menu)
                    Section { Button("삭제", systemImage: "trash", role: .destructive) { selectedObject = nil; edit { $0.removeObject(object.id) } } }
                }
            }
        }
    }
    /// 「동선 관리」 (971:32767): every route, the one being edited marked 「현재 사용 중」.
    private var manageList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(scenes) { plan in
                    ReferenceEditorRow(selected: false, onSelect: { selectedID = plan.id; managing = false }) {
                        Text(plan.name).font(HearFont.pretendard(.medium, size: 16)).foregroundStyle(.white).lineLimit(1)
                        if plan.id == selectedID {
                            Text("현재 사용 중").font(HearFont.pretendard(.medium, size: 13)).foregroundStyle(HearV3.accent)
                                .padding(.horizontal, 8).padding(.vertical, 3).background(HearV3.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                    } menu: {
                        Button("이름 변경", systemImage: "pencil") { renameText = plan.name; renameTarget = .scene(plan.id) }
                        Button("복제", systemImage: "plus.square.on.square") { duplicateScene(plan) }
                        Section { Button("동선 삭제", systemImage: "trash", role: .destructive) { deletingRoute = plan } }
                    }
                }
                if scenes.isEmpty {
                    Text("동선이 없어요").font(HearFont.pretendard(.regular, size: 14)).foregroundStyle(HearV3.secondary).frame(maxWidth: .infinity, minHeight: 120)
                }
            }.padding(.horizontal, 16).padding(.top, 8)
        }.v3Screen().hearTopBar("동선 관리") { HearBackButton() } trailing: { EmptyView() }
            // Figma 971:36590: deleting a route asks like deleting a folder.
            .hearConfirm("‘\(deletingRoute?.name ?? "")’ 동선을 삭제할까요?", isPresented: Binding(get: { deletingRoute != nil }, set: { if !$0 { deletingRoute = nil } }),
                         message: "체크를 눌러 저장하면 이 동선이 삭제돼요.\n스캔한 무대에는 영향을 주지 않아요.") {
                if let plan = deletingRoute { removeScene(plan.id) }
            }
    }

    // MARK: - Editing
    private func addScene() {
        var number = scenes.count + 1
        while scenes.contains(where: { $0.name == "\(number)번 동선" }) { number += 1 }
        snapshot()
        let plan = Self.newRoute(named: "\(number)번 동선"); scenes.append(plan); dirty = true
        selectedID = plan.id
    }
    private func duplicateScene(_ plan: PerformancePlan) {
        snapshot()
        var copy = plan; copy.id = UUID(); copy.name = "\(plan.name) 복사본"
        copy.objects = plan.objects.compactMap { try? StageObstacle(name: $0.name, kind: $0.kind, passage: $0.passage, vertices: $0.vertices) }
        if let index = scenes.firstIndex(where: { $0.id == plan.id }) { scenes.insert(copy, at: index + 1) } else { scenes.append(copy) }
        dirty = true
    }
    private func removeScene(_ id: UUID) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        removedSceneIDs.insert(id); scenes.remove(at: index); past.removeAll(); future.removeAll()
        if selectedID == id { selectedID = scenes.isEmpty ? nil : scenes[min(index, scenes.count - 1)].id }
        dirty = true
    }
    private func duplicate(_ object: StageObstacle) {
        edit { plan in
            let moved = object.vertices.map { FloorPoint($0.x + 0.5, $0.y - 0.5) }
            let copy = try StageObstacle(name: "\(object.name) 복사본", kind: object.kind, passage: object.passage,
                                         vertices: moved.allSatisfy({ PerformancePlan.area.contains($0) }) ? moved : object.vertices)
            plan.objects.append(copy); selectedObject = copy.id
        }
    }
    private func tap(_ point: FloorPoint) {
        guard let plan = current else { return }
        if tool == .point {
            if let index = plan.points.indices.min(by: { plan.points[$0].distance(to: point) < plan.points[$1].distance(to: point) }),
               plan.points[index].distance(to: point) < 0.5 {
                selectedPoint = selectedPoint == index ? nil : index; return
            }
            selectedPoint = nil
            let backstageLeft = point.x < 0, backstageRight = point.x > PerformancePlan.width
            if plan.points.isEmpty { edit { $0.resumeEditing(); try $0.append(point) }; return }
            if backstageLeft { edit { try $0.movePoint(at: 0, to: point) }; return }
            if backstageRight {
                // The last point joins the arrival in the backstage; an arrival already there just moves.
                if plan.finished { edit { try $0.movePoint(at: $0.points.count - 1, to: point) } }
                else { edit { $0.resumeEditing(); try $0.append(point); $0.completeReference() } }
                return
            }
            if plan.finished && plan.points.count >= 2 { edit { try Self.insert(&$0, point, at: $0.points.count - 1) } }
            else { edit { $0.resumeEditing(); try $0.append(point) } }
            return
        }
        if let hit = plan.objects.last(where: { $0.contains(point) }) { selectedObject = selectedObject == hit.id ? nil : hit.id; return }
        if selectedObject != nil { selectedObject = nil; return }
        let p = FloorPoint(min(11.3, max(0.7, point.x)), min(7.3, max(0.7, point.y)))
        guard (0...PerformancePlan.width).contains(point.x) else { return }
        edit { plan in
            var number = plan.objects.count + 1
            while plan.objects.contains(where: { $0.name == "기물 \(number)" }) { number += 1 }
            let object = try StageObstacle(name: "기물 \(number)", kind: .box, passage: .prohibited, vertices: ReferenceShape.square.vertices(center: p, width: 1.2, depth: 1))
            plan.objects.append(object); selectedObject = object.id
        }
    }
    private func drag(from start: FloorPoint, to end: FloorPoint) {
        guard let index = selectedIndex else { return }
        var plan = dragBaseline ?? scenes[index]
        do {
            if tool == .point {
                guard let pointIndex = plan.points.indices.min(by: { plan.points[$0].distance(to: start) < plan.points[$1].distance(to: start) }), plan.points[pointIndex].distance(to: start) < 0.6 else { return }
                if dragBaseline == nil { dragBaseline = plan; snapshot() }
                selectedPoint = pointIndex
                try plan.movePoint(at: pointIndex, to: end)
            } else {
                guard let object = plan.objects.last(where: { $0.contains(start) || ($0.id == selectedObject && $0.vertices.contains(where: { $0.distance(to: start) < 0.7 })) }) else { return }
                if dragBaseline == nil { dragBaseline = plan; snapshot() }
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
        case .scene(let id): if let index = scenes.firstIndex(where: { $0.id == id }) { snapshot(); scenes[index].name = name; dirty = true }
        case .object(let id): edit { plan in if let index = plan.objects.firstIndex(where: { $0.id == id }) { plan.objects[index].name = name } }
        case .point(let index): edit { plan in var settings = plan.settings(at: index); settings.name = name; try plan.setPointSettings(settings, at: index) }
        }
        renameTarget = nil
    }
    private func edit(_ action: (inout PerformancePlan) throws -> Void) {
        guard let index = selectedIndex else { return }
        do { var plan = scenes[index]; try action(&plan); snapshot(); scenes[index] = plan; dirty = true }
        catch { message = error.localizedDescription }
    }
    private func save() {
        guard !saving else { return }; saving = true
        Task {
            do {
                for var plan in scenes { plan.completeReference(); try await library.savePerformancePlan(plan, for: performanceID) }
                for id in removedSceneIDs {
                    // An unsaved route can be added and removed in the same editing session.
                    // Also allow retry after an earlier deletion in this batch already succeeded.
                    if library.catalog.performances.first(where: { $0.id == performanceID })?.referencePlanIDs.contains(id) == true {
                        try await library.removePerformancePlan(id: id, from: performanceID)
                    }
                }
                dirty = false; dismiss()
            } catch { message = "저장하지 못한 동선이 있어요. 편집 내용은 유지됩니다. \(error.localizedDescription)" }
            saving = false
        }
    }
    private func snapshot() { past.append(scenes); if past.count > 50 { past.removeFirst() }; future.removeAll() }
    private func undo() {
        guard let previous = past.popLast() else { return }
        future.append(scenes); restore(previous)
    }
    private func redo() {
        guard let next = future.popLast() else { return }
        past.append(scenes); restore(next)
    }
    private func restore(_ state: [PerformancePlan]) {
        scenes = state; removedSceneIDs.subtract(state.map(\.id)); selectedObject = nil; selectedPoint = nil; dirty = true
        if !scenes.contains(where: { $0.id == selectedID }) { selectedID = scenes.first?.id }
    }
    /// Puts a point at `index`, keeping every later point and its settings: the plan only appends at the end.
    static func insert(_ plan: inout PerformancePlan, _ point: FloorPoint, at index: Int) throws {
        let wasFinished = plan.finished
        let tail = (index..<plan.points.count).map { (plan.points[$0], plan.settings(at: $0)) }
        for _ in tail { plan.removePoint(at: plan.points.count - 1) }
        plan.resumeEditing()
        try plan.append(point)
        for (offset, item) in tail.enumerated() {
            try plan.append(item.0); try plan.setPointSettings(item.1, at: index + 1 + offset)
        }
        if wasFinished { plan.completeReference() }
    }
    static func reshape(_ plan: inout PerformancePlan, _ id: UUID, to shape: ReferenceShape) throws {
        guard let i = plan.objects.firstIndex(where: { $0.id == id }) else { return }
        let v = plan.objects[i].vertices
        let minX = v.map(\.x).min()!, maxX = v.map(\.x).max()!, minY = v.map(\.y).min()!, maxY = v.map(\.y).max()!
        var object = plan.objects[i]
        object.vertices = shape.vertices(center: .init((minX + maxX) / 2, (minY + maxY) / 2), width: maxX - minX, depth: maxY - minY)
        try object.validate(); plan.objects[i] = object
    }
}

/// One rounded row of the editor's lists: tap to pick it, ⋯ for its actions.
private struct ReferenceEditorRow<Content: View, MenuContent: View>: View {
    let selected: Bool
    let onSelect: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let menu: MenuContent
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) { content }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .onTapGesture(perform: onSelect).accessibilityAddTraits(.isButton)
            Menu { menu } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("더보기")
        }.padding(.leading, 16).padding(.trailing, 6).frame(minHeight: 76)
            .background(selected ? Color.white.opacity(0.14) : HearV3.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

enum ReferenceShape: String, CaseIterable, Identifiable {
    case square = "네모", circle = "동그라미", triangle = "세모"
    var id: Self { self }
    init(_ object: StageObstacle) {
        switch object.vertices.count { case 3: self = .triangle; case 4: self = .square; default: self = .circle }
    }
    func vertices(center c: FloorPoint, width w: Double, depth d: Double) -> [FloorPoint] {
        switch self {
        case .square: return [.init(c.x - w / 2, c.y - d / 2), .init(c.x + w / 2, c.y - d / 2), .init(c.x + w / 2, c.y + d / 2), .init(c.x - w / 2, c.y + d / 2)]
        case .triangle: return [.init(c.x, c.y + d / 2), .init(c.x - w / 2, c.y - d / 2), .init(c.x + w / 2, c.y - d / 2)]
        case .circle: return (0..<16).map { k in let a = Double(k) / 16 * 2 * .pi; return .init(c.x + cos(a) * w / 2, c.y + sin(a) * d / 2) }
        }
    }
}

private enum ReferenceSceneTool: String, CaseIterable, Identifiable {
    case point = "포인트", obstacle = "장애물"
    var id: Self { self }
}
private enum ReferenceRenameTarget {
    case scene(UUID), object(UUID), point(Int)
    var title: String {
        switch self { case .scene: return "동선 이름 변경"; case .object: return "장애물 이름 변경"; case .point: return "지점 이름 변경" }
    }
}
