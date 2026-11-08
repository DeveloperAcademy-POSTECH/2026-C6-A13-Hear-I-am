import SwiftUI
import MapKit
import HearIAmCore

struct PerformanceDetailView: View {
    @ObservedObject var library: StageLibrary
    let performanceID: UUID
    let onStartGuidance: (UUID) -> Void
    @State private var editing = false
    @State private var editingScenes = false
    @State private var selectedSceneID: UUID?
    @State private var linking = false
    @State private var deleting = false
    @State private var creatingSpace = false
    @State private var renamingSpace: PerformanceVenueTag?
    @State private var deletingSpace: PerformanceVenueTag?
    @State private var spaceName = ""
    @State private var query = ""
    @State private var error: String?
    @State private var busy = false
    @State private var focusedCard: UUID?
    @State private var openedScan: PerformanceOpenedScan?
    @State private var openedSpaceID: UUID?
    @Environment(\.dismiss) private var dismiss
    private var folder: PerformanceFolder? { library.performanceFolders.first { $0.id == performanceID } }
    private var plans: [PerformancePlan] { library.referencePlans(for: performanceID) }
    private var spaces: [PerformanceVenueTag] {
        (folder?.venues ?? []).filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    private var unfiled: [ScanManifest] { library.scans(in: performanceID, includeAllVenues: false) }

    var body: some View {
        ScrollView {
            if folder != nil {
                // Figma 971:32296 · 971:32413: 기본 동선 and 공연 및 연습 공간 under the title bar, no description line.
                VStack(alignment: .leading, spacing: 32) {
                    referenceSection
                    VStack(spacing: 16) {
                        HStack {
                            PerformanceSectionTitle(text: "공연 및 연습 공간")
                            Spacer()
                            Button { spaceName = ""; creatingSpace = true } label: { PerformanceOutlineButtonLabel(title: "추가하기", systemImage: "plus") }
                                .buttonStyle(.plain).accessibilityIdentifier("performance.space.create")
                        }.padding(.horizontal, 4)
                        PerformanceSearchField(text: $query, prompt: "공연 및 연습 공간 검색")
                        if spaces.isEmpty {
                            PerformanceEmptyCard(systemImage: "folder", text: query.isEmpty ? "공간을\n추가해주세요" : "검색한 공간이\n없습니다").padding(.top, 20)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(spaces) { space in
                                    HearSwipeDeleteRow(onOpen: { openedSpaceID = space.id }, onDelete: { deletingSpace = space }) {
                                        PerformanceFolderRow(name: space.name, date: space.updatedAt,
                                                             count: library.scans(in: performanceID, venueID: space.id, includeAllVenues: false).count)
                                    }.accessibilityIdentifier("performance.space.\(space.id.uuidString)")
                                        .contextMenu {
                                            Button("이름 변경", systemImage: "pencil") { spaceName = space.name; renamingSpace = space }
                                            Button("공간 폴더 삭제", systemImage: "trash", role: .destructive) { deletingSpace = space }
                                        }
                                }
                            }
                        }
                        if !unfiled.isEmpty && query.isEmpty {
                            NavigationLink {
                                PerformanceSpaceView(library: library, performanceID: performanceID, venueID: nil, onStartGuidance: onStartGuidance)
                            } label: {
                                HStack { Label("공간 미지정", systemImage: "tray"); Spacer(); Text("\(unfiled.count)"); Image(systemName: "chevron.right") }
                                    .font(.subheadline).padding(20).background(HearV3.surface, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16)
                }.padding(.top, 28).padding(.bottom, 24)
            } else { ContentUnavailableView("공연을 찾을 수 없어요", systemImage: "folder.badge.questionmark") }
        }
        #if DEBUG
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--scroll-bottom") ? .bottom : .top)
        #endif
        .v3Screen()
            .hearTopBar(folder?.name ?? "공연 관리") { HearBackButton() } trailing: {
                // 971:36544: edit and delete; linking saved scans stays between them.
                Menu {
                    Button("공연 정보 수정", systemImage: "pencil") { editing = true }
                    Button("저장된 스캔 연결", systemImage: "link") { linking = true }
                    Button("공연 폴더 삭제", systemImage: "trash", role: .destructive) { deleting = true }
                } label: { HearTopButtonLabel(systemImage: "ellipsis") }
                    .buttonStyle(.plain).accessibilityLabel("공연 관리 메뉴").disabled(busy)
            }
            .sheet(isPresented: $editing) { if let folder { PerformanceEditorSheet(library: library, folder: folder) { _ in }.suspendsVoiceWake() } }
            .sheet(isPresented: $linking) { PerformanceLinkStagesView(library: library, performanceID: performanceID).suspendsVoiceWake() }
            .fullScreenCover(isPresented: $editingScenes) {
                ReferenceSceneEditorView(library: library, performanceID: performanceID, initialSceneID: selectedSceneID).suspendsVoiceWake()
            }
            #if DEBUG
            .task {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--detail-delete") { try? await Task.sleep(for: .seconds(1)); deleting = true }
                guard args.contains("--detail-open-card") else { return }
                try? await Task.sleep(for: .seconds(1)); if let card = routeCards.first { open(card) }
            }
            #endif
            .navigationDestination(item: $openedSpaceID) { spaceID in
                PerformanceSpaceView(library: library, performanceID: performanceID, venueID: spaceID, onStartGuidance: onStartGuidance)
            }
            .navigationDestination(item: $openedScan) { opened in
                PerformanceSpaceView(library: library, performanceID: performanceID, venueID: opened.venueID,
                                     initialScanID: opened.scanID, onStartGuidance: onStartGuidance)
            }
            .sheet(isPresented: $creatingSpace) {
                PerformanceSpaceSearchSheet { name in spaceName = name; creatingSpace = false; saveSpace() }.suspendsVoiceWake()
            }
            .alert("공간 이름 변경", isPresented: Binding(get: { renamingSpace != nil }, set: { if !$0 { renamingSpace = nil } })) {
                TextField("공간 이름", text: $spaceName)
                Button("저장") { let id = renamingSpace?.id; saveSpace(id: id) }.disabled(spaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("취소", role: .cancel) { renamingSpace = nil }
            }
            // 971:36590: deleting a space asks the same way as deleting the performance folder.
            .hearConfirm("‘\(deletingSpace?.name ?? "")’ 공간 폴더를 삭제할까요?", isPresented: Binding(get: { deletingSpace != nil }, set: { if !$0 { deletingSpace = nil } }),
                         message: "이 공간 폴더가 삭제돼요.\n스캔한 무대와 사진은 ‘공간 미지정’에 남아요.") {
                if let space = deletingSpace { deleteSpace(space.id) }
            }
            // 971:36590: an alert over the page. The message says what really goes: the folder, its scenes and
            // spaces; the scans themselves stay, unfiled.
            .hearConfirm("‘\(folder?.name ?? "")’ 공연 폴더를 삭제할까요?", isPresented: $deleting,
                         message: "기본 동선과 공연 및 연습 공간이 함께 삭제돼요.\n스캔한 무대와 사진은 미분류로 남아요.") { deleteFolder() }
            .onChange(of: plans.map(\.id)) { _, ids in
                if let selectedSceneID, !ids.contains(selectedSceneID) { self.selectedSceneID = ids.first }
            }
            .alert("변경하지 못했어요", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
    /// Every route on this performance, in the order of the space list: each space's scanned scenes, the unfiled ones,
    /// then the reference routes drawn in the editor. Each says where it is from, 「공간(동선 이름)」.
    private var routeCards: [PerformanceRouteCard] {
        let venues = (folder?.venues ?? []).sorted { $0.updatedAt > $1.updatedAt }
        var cards = venues.flatMap { venue in
            library.scans(in: performanceID, venueID: venue.id, includeAllVenues: false)
                .compactMap { PerformanceRouteCard(scan: $0, venueName: venue.name, venueID: venue.id) }
        }
        cards += unfiled.compactMap { PerformanceRouteCard(scan: $0, venueName: "공간 미지정", venueID: nil) }
        cards += plans.map { PerformanceRouteCard(plan: $0) }
        return cards
    }
    private var referenceSection: some View {
        let cards = routeCards
        let focused = cards.first { $0.id == focusedCard } ?? cards.first
        return VStack(spacing: 16) {
            HStack {
                PerformanceSectionTitle(text: "기본 동선")
                Spacer()
                // 편집 opens the saved route the carousel is showing: a scanned scene in its space, a drawn route in the editor.
                Button {
                    if let focused, focused.isScan { open(focused) } else { selectedSceneID = focused?.id ?? plans.first?.id; editingScenes = true }
                } label: { PerformanceOutlineButtonLabel(title: "편집", systemImage: "pencil") }
                    .buttonStyle(.plain).accessibilityIdentifier("performance.scenes.edit")
            }.padding(.horizontal, 20)
            if cards.isEmpty {
                // Figma 971:32413: a 200pt card of white 5%, the route symbol and 「기본동선을 추가해주세요」 in grey.
                Button { editingScenes = true } label: {
                    PerformanceEmptyCard(systemImage: "point.topleft.down.to.point.bottomright.curvepath", text: "기본동선을\n추가해주세요")
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }.buttonStyle(.plain).padding(.horizontal, 18)
            } else {
                let rowHeight = cards.map { $0.height(width: UIScreen.main.bounds.width - 36) }.max() ?? 204
                GeometryReader { geometry in
                    let width = geometry.size.width - 36
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 10) {
                            ForEach(cards) { card in
                                // The whole column answers a tap, not just the drawn card: a shorter card's empty space
                                // under it too, so a press anywhere in the carousel opens that route.
                                Button { open(card) } label: {
                                    ReferenceSceneCard(plan: card.plan, height: card.height(width: width))
                                        .frame(width: width, height: rowHeight, alignment: .top)
                                        .contentShape(Rectangle())
                                }.buttonStyle(PerformanceCardPressStyle()).id(card.id).accessibilityLabel("\(card.label), 열기")
                            }
                        }.scrollTargetLayout()
                    }.contentMargins(.horizontal, 18, for: .scrollContent).scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $focusedCard)
                }.frame(height: rowHeight)
                if let focused {
                    // The caption under the card opens the same route.
                    Text(focused.label).font(HearFont.pretendard(.regular, size: 13)).foregroundStyle(HearV3.secondary)
                        .lineLimit(1).padding(.horizontal, 20).padding(.vertical, 8).contentShape(Rectangle())
                        .onTapGesture { open(focused) }.padding(.vertical, -8).contentTransition(.opacity)
                        .accessibilityHidden(true)
                }
                if cards.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(cards) { card in
                            Circle().fill(focused?.id == card.id ? HearV3.text : HearV3.secondary.opacity(0.4)).frame(width: 6, height: 6)
                        }
                    }.accessibilityElement(children: .ignore).accessibilityLabel("동선 \(cards.count)개 중 \((cards.firstIndex { $0.id == focused?.id } ?? 0) + 1)번째")
                }
            }
        }.animation(.easeInOut(duration: 0.2), value: focusedCard)
    }
    private func open(_ card: PerformanceRouteCard) {
        if card.isScan { openedScan = PerformanceOpenedScan(venueID: card.venueID, scanID: card.id) }
        else { selectedSceneID = card.id; editingScenes = true }
    }
    private func saveSpace(id: UUID? = nil) {
        guard !busy else { return }; busy = true
        let name = spaceName
        Task {
            do { if let id { try await library.renameVenue(id, in: performanceID, to: name) } else { _ = try await library.createVenue(name: name, in: performanceID) } }
            catch { self.error = error.localizedDescription }
            renamingSpace = nil; busy = false
        }
    }
    private func deleteSpace(_ id: UUID) {
        busy = true
        Task { do { try await library.deleteVenue(id, in: performanceID) } catch { self.error = error.localizedDescription }; deletingSpace = nil; busy = false }
    }
    private func deleteFolder() {
        busy = true
        Task { do { try await library.deletePerformance(performanceID); dismiss() } catch { self.error = error.localizedDescription }; busy = false }
    }
}

/// 「공간 추가」 (Figma 971:32566 · 971:36428): search places on the map and pick one, or keep the typed name.
/// Only the place's name is kept; the space has no address field.
struct PerformanceSpaceSearchSheet: View {
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @AppStorage("performance.space.recentSearches") private var recentStore = ""
    private struct Place: Codable, Hashable { var name: String; var address: String }
    private var recents: [Place] { (try? JSONDecoder().decode([Place].self, from: Data(recentStore.utf8))) ?? [] }
    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PerformanceSearchField(text: $query, prompt: "공연장 이름이나 주소 검색").padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if typed.isEmpty {
                        if !recents.isEmpty {
                            PerformanceSectionTitle(text: "최근 검색").font(HearFont.pretendard(.semibold, size: 17)).padding(.top, 24).padding(.bottom, 4)
                            ForEach(recents, id: \.self) { place in row(place) }
                        } else {
                            Text("공연장 이름이나 주소로 찾아보세요").font(HearFont.pretendard(.regular, size: 14)).foregroundStyle(HearV3.secondary)
                                .frame(maxWidth: .infinity, minHeight: 160)
                        }
                    } else {
                        if searching && results.isEmpty { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
                        ForEach(results.indices, id: \.self) { index in row(Self.place(results[index])) }
                        if !searching && results.isEmpty {
                            Text("검색 결과가 없어요. 체크를 누르면 「\(typed)」 이름으로 추가해요.").font(HearFont.pretendard(.regular, size: 14))
                                .foregroundStyle(HearV3.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 8)
            }.scrollDismissesKeyboard(.interactively)
        }
            .safeAreaInset(edge: .top, spacing: 0) {
                HearTopBar(title: "공간 추가", sheet: true, leading: ScanCircleButton(systemImage: "xmark", label: "닫기") { dismiss() },
                           trailing: Button { choose(Place(name: typed, address: "")) } label: { HearTopButtonLabel(systemImage: "checkmark", prominent: true) }
                    .buttonStyle(.plain).disabled(typed.isEmpty).opacity(typed.isEmpty ? 0.45 : 1).accessibilityLabel("입력한 이름으로 추가"))
            }
            .hearSheet()
            .task(id: typed) {
                guard !typed.isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                searching = true
                let request = MKLocalSearch.Request(); request.naturalLanguageQuery = typed
                request.resultTypes = [.pointOfInterest, .address]
                let found = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
                guard !Task.isCancelled else { return }
                results = Array(found.prefix(20)); searching = false
            }
    }
    private func row(_ place: Place) -> some View {
        Button { choose(place) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.circle").font(.system(size: 18)).foregroundStyle(.white).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name).font(HearFont.pretendard(.medium, size: 16)).foregroundStyle(.white).lineLimit(1)
                    if !place.address.isEmpty {
                        Text(place.address).font(HearFont.pretendard(.regular, size: 13)).foregroundStyle(HearV3.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(HearV3.secondary).padding(.top, 4)
            }.padding(.vertical, 14).overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5).padding(.leading, 30) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func choose(_ place: Place) {
        let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !place.address.isEmpty {
            let list = [place] + recents.filter { $0 != place }
            if let data = try? JSONEncoder().encode(Array(list.prefix(5))) { recentStore = String(decoding: data, as: UTF8.self) }
        }
        onDone(name)
    }
    private static func place(_ item: MKMapItem) -> Place {
        let mark = item.placemark
        let address = [mark.administrativeArea, mark.locality, mark.subLocality, mark.thoroughfare, mark.subThoroughfare]
            .compactMap { $0 }.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }.joined(separator: " ")
        return Place(name: item.name ?? address, address: address)
    }
}

/// A section heading on the performance pages (Figma 971:32296): Pretendard SemiBold 20.
struct PerformanceSectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(HearFont.pretendard(.semibold, size: 20)).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
    }
}

/// The small glass capsule beside a heading, 「✎ 편집」 and 「+ 추가하기」 (971:32423): 30pt high, tinted white 5%.
struct PerformanceOutlineButtonLabel: View {
    let title: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .medium))
            Text(title).font(HearFont.pretendard(.medium, size: 14)).tracking(-0.42)
        }.foregroundStyle(.white).padding(.horizontal, 12).frame(height: 30)
            .liquidGlass(Capsule(), tint: .white.opacity(0.05), interactive: true)
            .contentShape(Capsule())
    }
}

/// The empty state inside a 200pt card (971:32426 · 971:32441): a 48pt symbol over two grey lines.
struct PerformanceEmptyCard: View {
    let systemImage: String
    let text: String
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage).font(.system(size: 44, weight: .regular)).frame(width: 60, height: 60)
            Text(text).font(HearFont.pretendard(.medium, size: 20)).tracking(-0.6).lineSpacing(4).multilineTextAlignment(.center)
        }.foregroundStyle(PerformanceSearchField.grey).frame(maxWidth: .infinity).frame(height: 200)
    }
}

struct PerformanceOpenedScan: Hashable, Identifiable {
    let venueID: UUID?
    let scanID: UUID
    var id: UUID { scanID }
}

/// One card of the 기본 동선 carousel: a scanned scene drawn on the schematic stage, or a reference route.
/// A card that dips slightly under the finger, so a press reads as opening it.
struct PerformanceCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.2), value: configuration.isPressed)
    }
}

struct PerformanceRouteCard: Identifiable {
    let id: UUID
    let plan: PerformancePlan
    let label: String
    let venueID: UUID?
    let isScan: Bool
    /// Stage depth over width; a scanned stage keeps its own proportions, so its card is taller or shorter.
    let aspect: Double
    init(plan: PerformancePlan) {
        id = plan.id; self.plan = plan; label = "기본 동선(\(plan.name))"; venueID = nil; isScan = false
        aspect = PerformancePlan.depth / PerformancePlan.width
    }
    /// The scan's route, scaled from its measured stage onto the 12 × 8 schematic. Nil when it has no route yet.
    init?(scan: ScanManifest, venueName: String, venueID: UUID?) {
        guard let route = scan.route, route.points.count >= 2, route.area.width > 0.1, route.area.depth > 0.1 else { return nil }
        let sx = PerformancePlan.width / route.area.width, sy = PerformancePlan.depth / route.area.depth
        var plan = PerformancePlan(); plan.id = scan.id; plan.name = scan.name; plan.isReferenceOnly = true
        for point in route.points { try? plan.append(FloorPoint(min(15, max(-3, point.x * sx)), min(9, max(-1, point.y * sy)))) }
        plan.completeReference()
        plan.objects = route.obstacles.compactMap {
            try? StageObstacle(name: $0.name, kind: $0.kind, passage: $0.passage, vertices: $0.vertices.map { FloorPoint($0.x * sx, $0.y * sy) })
        }
        id = scan.id; self.plan = plan; label = "\(venueName)(\(scan.name))"; self.venueID = venueID; isScan = true
        aspect = route.area.depth / route.area.width
    }
    /// The schematic spans the stage plus both 1.4 m backstage strips; its height follows the stage's proportions.
    func height(width: CGFloat) -> CGFloat {
        let stageWidth = (width - 32) * PerformancePlan.width / (PerformancePlan.width + 2.8)
        return min(280, max(150, stageWidth * aspect + 32))
    }
}

/// Pick existing durable scans before assigning them to this performance.
struct PerformanceLinkStagesView: View {
    @ObservedObject var library:StageLibrary
    let performanceID:UUID
    @State private var selected:Set<UUID>=[]
    @State private var query=""
    @State private var classifying=false
    @State private var classificationIDs:[UUID]=[]
    @Environment(\.dismiss) private var dismiss
    private var scans:[ScanManifest] {library.records.filter {query.isEmpty || $0.name.localizedStandardContains(query) || (library.catalog.folder(for:$0.id)?.name.localizedStandardContains(query) ?? false)}}
    var body:some View {
        NavigationStack {
            List {
                Section {Text("스캔한 무대를 선택해주세요. 다른 공연에 연결된 무대는 이 공연으로 옮겨집니다.").font(.subheadline).foregroundStyle(.secondary)}
                if scans.isEmpty {ContentUnavailableView("연결할 무대가 없어요",systemImage:"building.2",description:Text(query.isEmpty ? "스캔 탭에서 무대를 먼저 저장해주세요." : "다른 이름으로 검색해주세요."))}
                ForEach(scans,id:\.id) {scan in
                    Button {if selected.contains(scan.id) {selected.remove(scan.id)} else {selected.insert(scan.id)}} label:{
                        HStack {
                            VStack(alignment:.leading,spacing:5) {Text(scan.name);Text(library.catalog.folder(for:scan.id)?.name ?? "미분류 무대").font(.caption).foregroundStyle(.secondary)}
                            Spacer();Image(systemName:selected.contains(scan.id) ? "checkmark.circle.fill" : "circle")
                        }.frame(minHeight:48)
                    }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(scan.id) ? .isSelected : [])
                }
            }.scrollContentBackground(.hidden).clearNavigationBackground().navigationTitle("무대 연결").navigationBarTitleDisplayMode(.inline)
                .searchable(text:$query,prompt:"무대 또는 공연 이름 검색")
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("닫기",systemImage:"xmark") {dismiss()}.labelStyle(.iconOnly)}}
                .safeAreaInset(edge:.bottom) {Button("선택한 \(selected.count)개 연결") {classificationIDs=Array(selected);classifying=true}.buttonStyle(V3PrimaryButtonStyle()).disabled(selected.isEmpty).padding(20)}
                .sheet(isPresented:$classifying) {StageClassificationView(library:library,scanIDs:classificationIDs,initialPerformanceID:performanceID) {_ in dismiss()}.suspendsVoiceWake()}
        }.hearSheet()
    }
}
