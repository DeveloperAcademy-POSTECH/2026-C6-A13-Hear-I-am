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
    /// Routes made in this session whose last point is not yet joined to the arrival (971:33297): tapping the
    /// backstage strip that holds the arrival joins them.
    @State private var unlinked: Set<UUID> = []
    /// Scanned scenes shown beside the drawn routes; saving writes an edited one back to its scan.
    private let scanned: [UUID: ScanRouteBridge]
    @Environment(\.dismiss) private var dismiss
    init(library: StageLibrary, performanceID: UUID, initialSceneID: UUID? = nil) {
        self.library = library; self.performanceID = performanceID
        // The same order as the 기본 동선 carousel: each space's scanned routes, the unfiled ones, then drawn routes.
        let bridges = ScanRouteBridge.all(in: library, performanceID: performanceID)
        scanned = Dictionary(bridges.map { ($0.scanID, $0) }, uniquingKeysWith: { a, _ in a })
        var loaded = bridges.map(\.plan) + library.referencePlans(for: performanceID)
        if loaded.isEmpty { loaded = [Self.newRoute(named: L("새 동선"))] }
        for index in loaded.indices { loaded[index].isReferenceOnly = true }
        _scenes = State(initialValue: loaded)
        _unlinked = State(initialValue: loaded.count == 1 && loaded[0].points.count <= 2 ? [loaded[0].id] : [])
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
                .hearTopBar(L("기본 동선")) {
                    ScanCircleButton(systemImage: "chevron.left", label: L("나가기"), enabled: !saving) { if dirty { confirmExit = true } else { dismiss() } }
                } trailing: {
                    Button(action: save) { HearTopButtonLabel(systemImage: "checkmark", prominent: true) }
                        .buttonStyle(.plain).disabled(saving).accessibilityLabel(saving ? L("저장 중") : L("저장하기"))
                        .accessibilityIdentifier("performance.scenes.save")
                }
                .navigationDestination(isPresented: $managing) { manageList }
                .disabled(saving).interactiveDismissDisabled(dirty || saving)
                .onChange(of: selectedID) { _, id in
                    selectedObject = nil; selectedPoint = nil; dragBaseline = nil
                    if let id, scanned[id] != nil { tool = .point }
                }
                .onChange(of: tool) { selectedObject = nil; selectedPoint = nil; dragBaseline = nil }
                .confirmationDialog(L("저장하지 않은 변경사항이 있어요"), isPresented: $confirmExit, titleVisibility: .visible) {
                    Button(L("저장하지 않고 나가기"), role: .destructive) { dismiss() }; Button(L("계속 편집"), role: .cancel) { }
                }
                .modifier(renameAlert(shown: !managing))
                .alert(L("확인해주세요"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button(L("확인"), role: .cancel) { message = nil }
                } message: { Text(message ?? "") }
                #if DEBUG
                .onAppear {
                    // Preview states for the editor screens: a fresh route, a picked point, the obstacle tab, the list.
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("--editor-new") { addScene(); past.removeAll() }
                    if let i = args.firstIndex(of: "--editor-point"), args.count > i + 1, let n = Int(args[i + 1]) { selectedPoint = n }
                    if args.contains("--editor-obstacles") {
                        tool = .obstacle
                        DispatchQueue.main.async { selectedObject = current?.objects.first?.id }
                    }
                    if args.contains("--editor-manage") { managing = true }
                    if args.contains("--editor-rename"), let plan = scenes.first {
                        managing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { renameText = plan.name; renameTarget = .scene(plan.id) }
                    }
                }
                #endif
        }.v3Screen()
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            routeHeader.padding(.top, 8)
            if let plan = current {
                canvas(plan).padding(.top, 16)
                Text(L("객석")).font(.system(size: 12, weight: .semibold)).tracking(-0.08).foregroundStyle(Color(white: 0.62))
                    .frame(maxWidth: .infinity).padding(.top, 12)
                if scanned[plan.id] == nil { toolPicker.padding(.top, 24) }
                else {
                    // A scanned stage keeps its measured size and objects; only its route changes here.
                    Text(L("스캔한 무대예요. 무대 크기와 장애물은 그대로 두고 동선만 바꿀 수 있어요."))
                        .font(HearFont.pretendard(.regular, size: 13)).foregroundStyle(HearV3.secondary).padding(.top, 24)
                }
                Group { if tool == .point { pointRows(plan) } else { objectRows(plan) } }.padding(.top, 16)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath").font(.system(size: 40, weight: .light))
                    Text(L("동선이 없어요")).font(HearFont.pretendard(.semibold, size: 20))
                    Button(L("새 동선 추가")) { addScene() }.buttonStyle(V3PrimaryButtonStyle()).frame(maxWidth: 220)
                }.foregroundStyle(HearV3.secondary).frame(maxWidth: .infinity, minHeight: 320)
            }
        }.padding(.horizontal, 16).padding(.bottom, 32)
    }
    @ViewBuilder private func canvas(_ plan: PerformancePlan) -> some View {
        ReferencePlanCanvas(plan: plan, editing: true, selectedObject: tool == .obstacle ? selectedObject : nil,
                            selectedPoint: tool == .point ? selectedPoint : nil, arrivalLinked: !unlinked.contains(plan.id),
                            onTap: { tap($0) }, onDragChanged: { drag(from: $0, to: $1) }, onDragEnded: { dragBaseline = nil })
            .frame(height: 219)
            .overlay {
                if plan.points.count <= 2 && plan.objects.isEmpty {
                    Text(L("무대에 점을 찍어 새로운 동선을 추가해보세요")).font(HearFont.pretendard(.regular, size: 11))
                        .foregroundStyle(.white.opacity(0.35)).allowsHitTesting(false)
                }
            }
    }
    /// 「1번 동선 ⌃⌄」 opens the route menu (971:32728); undo and redo sit on the right.
    private var routeHeader: some View {
        HStack(spacing: 8) {
            Menu {
                Section(L("동선")) {
                    ForEach(scenes) { plan in
                        Button { selectedID = plan.id } label: {
                            if plan.id == selectedID { Label(menuName(plan), systemImage: "checkmark") } else { Text(menuName(plan)) }
                        }
                    }
                }
                Section { Button(L("새 동선 추가"), systemImage: "plus") { addScene() }.accessibilityIdentifier("performance.scenes.add") }
                Section { Button(L("동선 관리"), systemImage: "gearshape") { managing = true } }
            } label: {
                HStack(spacing: 4) {
                    Text(current.map(menuName) ?? L("동선 없음")).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                }.foregroundStyle(.white).frame(minHeight: 44).contentShape(Rectangle())
            }.accessibilityLabel(L("%@, 동선 선택", current?.name ?? L("동선 없음")))
            Spacer()
            HistoryButton(systemImage: "arrow.uturn.backward", label: L("실행 취소"), enabled: !past.isEmpty) { undo() }
            HistoryButton(systemImage: "arrow.uturn.forward", label: L("다시 실행"), enabled: !future.isEmpty) { redo() }
        }
    }
    /// Figma 971:32821: 포인트 · 장애물 on a glass track with a glass thumb, so it reads as Liquid Glass at rest too,
    /// not only while the system control is being dragged. Tap a side or slide the thumb across.
    private var toolPicker: some View {
        ReferenceToolPicker(selection: $tool)
    }
    private func pointRows(_ plan: PerformancePlan) -> some View {
        VStack(spacing: 8) {
            ForEach(plan.points.indices, id: \.self) { index in
                let label = plan.pointLabel(at: index), name = plan.settings(at: index).name
                ReferenceEditorRow(selected: selectedPoint == index, onSelect: { selectedPoint = selectedPoint == index ? nil : index }) {
                    Text(label.hasPrefix("P") ? label.map(String.init).joined(separator: " ") : label)
                        .font(HearFont.pretendard(.semibold, size: 12)).foregroundStyle(Color(red: 230 / 255, green: 231 / 255, blue: 238 / 255))
                        .frame(width: 40, height: 40).background(Color(red: 168 / 255, green: 168 / 255, blue: 174 / 255).opacity(0.5), in: Circle())
                    Text(name.isEmpty ? label : name).font(HearFont.pretendard(.regular, size: 16)).foregroundStyle(.white).lineLimit(1)
                } menu: {
                    Button(L("이름 변경"), systemImage: "pencil") { renameText = name; renameTarget = .point(index) }
                    if index > 0 && index < plan.points.count - 1 || !plan.finished && index > 0 {
                        Button(L("복제"), systemImage: "plus.square.on.square") { edit { try Self.insert(&$0, FloorPoint(plan.points[index].x + 0.4, plan.points[index].y + 0.4), at: index + 1) } }
                    }
                    Section { Button(L("삭제"), systemImage: "trash", role: .destructive) { selectedPoint = nil; edit { $0.removePoint(at: index) } } }
                }
            }
            Text(L("양 옆 공간은 백스테이지로 출발, 도착 점을 드래그해 위치를 조정하세요")).font(HearFont.pretendard(.regular, size: 11))
                .foregroundStyle(.white.opacity(0.35)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 16)
        }
    }
    private func objectRows(_ plan: PerformancePlan) -> some View {
        VStack(spacing: 8) {
            if plan.objects.isEmpty {
                Text(L("무대를 눌러 장애물을 추가해보세요")).font(HearFont.pretendard(.regular, size: 13)).foregroundStyle(HearV3.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            }
            ForEach(plan.objects) { object in
                ReferenceEditorRow(selected: selectedObject == object.id, onSelect: { selectedObject = selectedObject == object.id ? nil : object.id }) {
                    Text(object.name).font(HearFont.pretendard(.regular, size: 16)).foregroundStyle(.white).lineLimit(1)
                } menu: {
                    Button(L("이름 변경"), systemImage: "pencil") { renameText = object.name; renameTarget = .object(object.id) }
                    Button(L("복제"), systemImage: "plus.square.on.square") { duplicate(object) }
                    Picker(selection: Binding(get: { ReferenceShape(object) }, set: { shape in edit { try Self.reshape(&$0, object.id, to: shape) } })) {
                        ForEach(ReferenceShape.allCases) { Text(L($0.rawValue)).tag($0) }
                    } label: { Label(L("도형"), systemImage: "square.on.circle") ; Text(L(ReferenceShape(object).rawValue)) }
                        .pickerStyle(.menu)
                    Section { Button(L("삭제"), systemImage: "trash", role: .destructive) { selectedObject = nil; edit { $0.removeObject(object.id) } } }
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
                        Text(menuName(plan)).font(HearFont.pretendard(.regular, size: 16)).foregroundStyle(.white).lineLimit(1)
                        if plan.id == selectedID {
                            // 971:32767: plain green text beside the name, no badge.
                            Text(L("현재 사용 중")).font(HearFont.pretendard(.regular, size: 13)).foregroundStyle(HearV3.accent)
                        }
                    } menu: {
                        Button(L("이름 변경"), systemImage: "pencil") { renameText = plan.name; renameTarget = .scene(plan.id) }
                        Button(L("복제"), systemImage: "plus.square.on.square") { duplicateScene(plan) }
                        // A scanned route goes with its scan, deleted from its space; here it can only be edited.
                        if scanned[plan.id] == nil {
                            Section { Button(L("동선 삭제"), systemImage: "trash", role: .destructive) { deletingRoute = plan } }
                        }
                    }
                }
                if scenes.isEmpty {
                    Text(L("동선이 없어요")).font(HearFont.pretendard(.regular, size: 14)).foregroundStyle(HearV3.secondary).frame(maxWidth: .infinity, minHeight: 120)
                }
            }.padding(.horizontal, 16).padding(.top, 8)
        }.v3Screen().hearTopBar(L("동선 관리")) { HearBackButton() } trailing: { EmptyView() }
            // The rename box opens on this page; on the editor underneath it only appeared after going back.
            .modifier(renameAlert(shown: managing))
            // Figma 971:36590: deleting a route asks like deleting a folder.
            .hearConfirm(L("‘%@’ 동선을 삭제할까요?", deletingRoute?.name ?? ""), isPresented: Binding(get: { deletingRoute != nil }, set: { if !$0 { deletingRoute = nil } }),
                         message: L("체크를 눌러 저장하면 이 동선이 삭제돼요.\n스캔한 무대에는 영향을 주지 않아요.")) {
                if let plan = deletingRoute { removeScene(plan.id) }
            }
    }

    /// The rename box, attached to whichever page is on top: the editor or 「동선 관리」.
    private func renameAlert(shown: Bool) -> ReferenceRenameAlert {
        ReferenceRenameAlert(title: renameTarget?.title ?? L("이름 변경"),
                             isPresented: Binding(get: { shown && renameTarget != nil }, set: { if !$0 { renameTarget = nil } }),
                             text: $renameText, onCancel: { renameTarget = nil }, onSave: rename)
    }
    /// A scanned route says which space it is from, 「CGV(커튼콜)」, as on the performance page.
    private func menuName(_ plan: PerformancePlan) -> String {
        scanned[plan.id].map { "\($0.venueName)(\(plan.name))" } ?? plan.name
    }

    // MARK: - Editing
    private func addScene() {
        // 971:32668: a new route is 「새 동선」 until renamed; a second one is 「새 동선 2」.
        var name = L("새 동선"), number = 1
        while scenes.contains(where: { $0.name == name }) { number += 1; name = L("새 동선 %@", number) }
        snapshot()
        let plan = Self.newRoute(named: name); scenes.append(plan); dirty = true
        unlinked.insert(plan.id); selectedID = plan.id
    }
    private func duplicateScene(_ plan: PerformancePlan) {
        snapshot()
        var copy = plan; copy.id = UUID(); copy.name = L("%@ 복사본", plan.name)
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
            let copy = try StageObstacle(name: L("%@ 복사본", object.name), kind: object.kind, passage: object.passage,
                                         vertices: moved.allSatisfy({ PerformancePlan.area.contains($0) }) ? moved : object.vertices)
            plan.objects.append(copy); selectedObject = copy.id
        }
    }
    /// A scanned route's stage and obstacles stay as measured; only its points move.
    private var routeOnly: Bool { current.map { scanned[$0.id] != nil } ?? false }
    private func tap(_ point: FloorPoint) {
        guard let plan = current, tool == .point || !routeOnly else { return }
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
                // 971:33297: with the points placed, tapping the arrival's backstage joins the last point to it.
                if unlinked.contains(plan.id) && plan.points.count > 2 {
                    withAnimation(.snappy(duration: 0.25)) { _ = unlinked.remove(plan.id) }; return
                }
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
            while plan.objects.contains(where: { $0.name == L("기물 %@", number) }) { number += 1 }
            let object = try StageObstacle(name: L("기물 %@", number), kind: .box, passage: .prohibited, vertices: ReferenceShape.square.vertices(center: p, width: 1.2, depth: 1))
            plan.objects.append(object); selectedObject = object.id
        }
    }
    private func drag(from start: FloorPoint, to end: FloorPoint) {
        guard let index = selectedIndex, tool == .point || !routeOnly else { return }
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
        guard !saving else { return }
        // A scanned route guidance would refuse is named before anything is written, so nothing is half saved (#179).
        var routes: [UUID: StageRoute] = [:]
        do {
            for var plan in scenes {
                plan.completeReference()
                guard let bridge = scanned[plan.id] else { continue }
                var opened = bridge.plan; opened.completeReference()
                var geometry = plan; geometry.name = opened.name
                guard geometry != opened else { continue }
                let route = try bridge.route(from: plan)
                let conflicts = route.guidanceConflicts(library.records.first { $0.id == plan.id }?.settings ?? GuideSettings())
                guard conflicts.isEmpty else {
                    message = L("‘%@’ 동선은 안내에 쓸 수 없어요. %@", plan.name, conflicts.joined(separator: " ")); return
                }
                routes[plan.id] = route
            }
        } catch { message = L("저장하지 못한 동선이 있어요. 편집 내용은 유지됩니다. %@", error.localizedDescription); return }
        saving = true
        Task {
            do {
                for var plan in scenes {
                    plan.completeReference()
                    if let bridge = scanned[plan.id] {
                        // A scanned route is written back to its scan, and only when it changed. Its photos follow
                        // the points they were taken at.
                        if let route = routes[plan.id] {
                            try await library.updateScanRoute(plan.id, route: route, origins: plan.points.indices.map { plan.settings(at: $0).sourceIndex })
                        }
                        if plan.name != bridge.plan.name { try await library.renameStage(plan.id, to: plan.name) }
                    } else { try await library.savePerformancePlan(plan, for: performanceID) }
                }
                for id in removedSceneIDs {
                    // An unsaved route can be added and removed in the same editing session.
                    // Also allow retry after an earlier deletion in this batch already succeeded.
                    if library.catalog.performances.first(where: { $0.id == performanceID })?.referencePlanIDs.contains(id) == true {
                        try await library.removePerformancePlan(id: id, from: performanceID)
                    }
                }
                dirty = false; dismiss()
            } catch { message = L("저장하지 못한 동선이 있어요. 편집 내용은 유지됩니다. %@", error.localizedDescription) }
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
    /// Puts a point at `index`, keeping every later point and its settings (#179).
    static func insert(_ plan: inout PerformancePlan, _ point: FloorPoint, at index: Int) throws {
        try plan.insertPoint(point, at: index)
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

/// Undo and redo (971:32930): 36pt glass circles that stay visible when there is nothing to undo; only the
/// arrow dims, as in the design.
private struct HistoryButton: View {
    let systemImage: String
    let label: String
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
                .frame(width: 36, height: 36).liquidGlass(Circle(), tint: .white.opacity(0.05), interactive: enabled).contentShape(Circle())
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label)
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
            HStack(spacing: 18) { content }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .onTapGesture(perform: onSelect).accessibilityAddTraits(.isButton)
            Menu { menu } label: {
                Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel(L("더보기"))
        }.padding(.leading, 17).padding(.trailing, 6).frame(minHeight: 76)
            // 971:32824: 10% grey rows, 18pt corners; the picked one a little lighter.
            .background(selected ? Color.white.opacity(0.12) : Color(red: 85 / 255, green: 87 / 255, blue: 89 / 255).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        switch self { case .scene: return L("동선 이름 변경"); case .object: return L("장애물 이름 변경"); case .point: return L("지점 이름 변경") }
    }
}

/// A scanned scene's route laid onto the 12 × 8 schematic so the route editor can show and edit it, and back again
/// onto the measured stage on save. Each axis scales on its own; heights follow the nearest measured point.
struct ScanRouteBridge {
    let scanID: UUID
    let venueName: String
    let venueID: UUID?
    let route: StageRoute
    /// The schematic as it was opened; an untouched route is not written back.
    let plan: PerformancePlan
    private let sx: Double, sy: Double
    init?(scan: ScanManifest, venueName: String, venueID: UUID?) {
        guard let route = scan.route, route.points.count >= 2, route.area.width > 0.1, route.area.depth > 0.1 else { return nil }
        scanID = scan.id; self.venueName = venueName; self.venueID = venueID; self.route = route
        let sx = PerformancePlan.width / route.area.width, sy = PerformancePlan.depth / route.area.depth
        self.sx = sx; self.sy = sy
        var plan = PerformancePlan(); plan.id = scan.id; plan.name = scan.name; plan.isReferenceOnly = true
        for point in route.points { try? plan.append(FloorPoint(min(15, max(-3, point.x * sx)), min(9, max(-1, point.y * sy)))) }
        plan.completeReference()
        plan.objects = route.obstacles.map { var o = $0; o.vertices = o.vertices.map { FloorPoint($0.x * sx, $0.y * sy) }; return o }
        // Only names the user gave are carried; the automatic ones (P1, 의자1) follow the points as they change.
        let defaults = StageRoute.pointLabels(points: route.points, obstacles: route.obstacles)
        for index in plan.points.indices where route.points.indices.contains(index) {
            let name = route.pointNames.indices.contains(index) && route.pointNames[index] != defaults[index] ? route.pointNames[index] : ""
            var settings = PerformancePlanPointSettings(name: name, holdSeconds: route.holdSeconds(at: index), facing: route.facing(at: index))
            settings.sourceIndex = index
            try? plan.setPointSettings(settings, at: index)
        }
        self.plan = plan
    }
    /// The edited points back on the measured stage. The stage, its danger zones and the scanned obstacles are kept
    /// exactly as measured: only the route changes.
    func route(from edited: PerformancePlan) throws -> StageRoute {
        let points = edited.points.map { FloorPoint($0.x / sx, $0.y / sy) }
        let obstacles = route.obstacles
        let heights = route.pointHeights.map { measured in
            points.map { p in route.points.indices.min { route.points[$0].distance(to: p) < route.points[$1].distance(to: p) }.map { measured[$0] } ?? 0 }
        }
        let defaults = StageRoute.pointLabels(points: points, obstacles: obstacles)
        let settings = edited.points.indices.map { edited.settings(at: $0) }
        let holds = settings.indices.map { $0 == 0 || $0 == settings.count - 1 ? 0 : settings[$0].holdSeconds }
        let facings = settings.map(\.facing)
        // Settings the scan never had stay absent, so an untouched route saves exactly as it was.
        return try StageRoute(area: route.area, points: points, obstacles: obstacles, allowsOutsideEndpoints: route.version == 2,
                              dangerZones: route.dangerZones, pointHeights: heights,
                              pointHoldSeconds: route.pointHoldSeconds == nil && holds.allSatisfy { $0 == 0 } ? nil : holds,
                              pointNames: settings.indices.map { settings[$0].name.isEmpty ? defaults[$0] : settings[$0].name },
                              pointFacings: route.pointFacings == nil && facings.allSatisfy { $0 == nil } ? nil : facings)
    }
    /// Every scanned route on a performance, in the order of its space list, then the unfiled ones.
    @MainActor static func all(in library: StageLibrary, performanceID: UUID) -> [ScanRouteBridge] {
        let venues = (library.performanceFolders.first { $0.id == performanceID }?.venues ?? []).sorted { $0.updatedAt > $1.updatedAt }
        return venues.flatMap { venue in
            library.scans(in: performanceID, venueID: venue.id, includeAllVenues: false).compactMap { ScanRouteBridge(scan: $0, venueName: venue.name, venueID: venue.id) }
        } + library.scans(in: performanceID, includeAllVenues: false).compactMap { ScanRouteBridge(scan: $0, venueName: L("공간 미지정"), venueID: nil) }
    }
}

private struct ReferenceRenameAlert: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void
    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            TextField(L("이름"), text: $text)
            Button(L("취소"), role: .cancel, action: onCancel)
            Button(L("저장"), action: onSave).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 80)
        }
    }
}

/// Two-way glass switch for the editor's 포인트 · 장애물 (971:32821). The thumb follows the finger and swells a little
/// while held, as the system control does, and lands on the side it is let go over.
private struct ReferenceToolPicker: View {
    @Binding var selection: ReferenceSceneTool
    @State private var dragX: CGFloat?
    @GestureState private var pressing = false
    var body: some View {
        GeometryReader { geometry in
            let cases = ReferenceSceneTool.allCases
            let inset: CGFloat = 4
            let segment = (geometry.size.width - inset * 2) / CGFloat(cases.count)
            let index = CGFloat(cases.firstIndex(of: selection) ?? 0)
            let thumbX = dragX.map { min(max($0 - segment / 2, inset), geometry.size.width - inset - segment) } ?? inset + segment * index
            ZStack(alignment: .leading) {
                Capsule().fill(.clear).frame(width: segment, height: geometry.size.height - inset * 2)
                    .liquidGlass(Capsule(), tint: .white.opacity(0.16), interactive: true)
                    .scaleEffect(pressing ? 1.06 : 1)
                    .offset(x: thumbX)
                HStack(spacing: 0) {
                    ForEach(cases) { item in
                        Text(L(item.rawValue)).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(item == selection ? 1 : 0.6)).frame(width: segment)
                    }
                }.padding(.horizontal, inset).allowsHitTesting(false)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { value in
                        // A tap jumps on release; a slide carries the thumb under the finger.
                        if abs(value.translation.width) > 4 || dragX != nil { dragX = value.location.x }
                    }
                    .onEnded { value in
                        let picked = cases[min(cases.count - 1, max(0, Int((value.location.x - inset) / segment)))]
                        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { selection = picked; dragX = nil }
                    })
                .animation(.spring(duration: 0.3, bounce: 0.15), value: pressing)
        }.frame(height: 48)
            .liquidGlass(Capsule(), tint: .white.opacity(0.05))
            .sensoryFeedback(.selection, trigger: selection)
            .accessibilityElement(children: .ignore).accessibilityLabel(L("편집 대상")).accessibilityValue(L(selection.rawValue))
            .accessibilityAdjustableAction { direction in
                let cases = ReferenceSceneTool.allCases, i = cases.firstIndex(of: selection) ?? 0
                switch direction {
                case .increment: selection = cases[min(cases.count - 1, i + 1)]
                case .decrement: selection = cases[max(0, i - 1)]
                @unknown default: break
                }
            }
    }
}
