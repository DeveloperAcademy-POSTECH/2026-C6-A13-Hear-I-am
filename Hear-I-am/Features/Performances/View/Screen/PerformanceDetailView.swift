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
                            PerformanceSectionTitle(text: L("공연 및 연습 공간"))
                            Spacer()
                            Button { spaceName = ""; creatingSpace = true } label: { PerformanceOutlineButtonLabel(title: L("추가하기"), systemImage: "plus") }
                                .buttonStyle(.plain).accessibilityIdentifier("performance.space.create")
                        }.padding(.horizontal, 4)
                        PerformanceSearchField(text: $query, prompt: L("공연 및 연습 공간 검색"))
                        if spaces.isEmpty {
                            PerformanceEmptyCard(systemImage: "folder", text: query.isEmpty ? L("공간을\n추가해주세요") : L("검색한 공간이\n없습니다")).padding(.top, 20)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(spaces) { space in
                                    HearSwipeDeleteRow(onOpen: { openedSpaceID = space.id }, onDelete: { deletingSpace = space }) {
                                        PerformanceFolderRow(name: space.name, date: space.updatedAt,
                                                             count: library.scans(in: performanceID, venueID: space.id, includeAllVenues: false).count)
                                    }.accessibilityIdentifier("performance.space.\(space.id.uuidString)")
                                        .contextMenu {
                                            Button(L("이름 변경"), systemImage: "pencil") { spaceName = space.name; renamingSpace = space }
                                            Button(L("공간 폴더 삭제"), systemImage: "trash", role: .destructive) { deletingSpace = space }
                                        }
                                }
                            }
                        }
                        if !unfiled.isEmpty && query.isEmpty {
                            NavigationLink {
                                PerformanceSpaceView(library: library, performanceID: performanceID, venueID: nil, onStartGuidance: onStartGuidance)
                            } label: {
                                HStack { Label(L("공간 미지정"), systemImage: "tray"); Spacer(); Text("\(unfiled.count)"); Image(systemName: "chevron.right") }
                                    .font(.subheadline).padding(20).background(HearV3.surface, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16)
                }.padding(.top, 28).padding(.bottom, 24)
            } else { ContentUnavailableView(L("공연을 찾을 수 없어요"), systemImage: "folder.badge.questionmark") }
        }
        #if DEBUG
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--scroll-bottom") ? .bottom : .top)
        #endif
        .v3Screen()
            .hearTopBar(folder?.name ?? L("공연 관리")) { HearBackButton() } trailing: {
                // 971:36544: edit and delete; linking saved scans stays between them.
                Menu {
                    Button(L("공연 정보 수정"), systemImage: "pencil") { editing = true }
                    Button(L("저장된 스캔 연결"), systemImage: "link") { linking = true }
                    Button(L("공연 폴더 삭제"), systemImage: "trash", role: .destructive) { deleting = true }
                } label: { HearTopButtonLabel(systemImage: "ellipsis") }
                    .buttonStyle(.plain).accessibilityLabel(L("공연 관리 메뉴")).disabled(busy)
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
            .alert(L("공간 이름 변경"), isPresented: Binding(get: { renamingSpace != nil }, set: { if !$0 { renamingSpace = nil } })) {
                TextField(L("공간 이름"), text: $spaceName)
                Button(L("저장")) { let id = renamingSpace?.id; saveSpace(id: id) }.disabled(spaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L("취소"), role: .cancel) { renamingSpace = nil }
            }
            // 971:36590: deleting a space asks the same way as deleting the performance folder.
            .hearConfirm(L("‘%@’ 공간 폴더를 삭제할까요?", deletingSpace?.name ?? ""), isPresented: Binding(get: { deletingSpace != nil }, set: { if !$0 { deletingSpace = nil } }),
                         message: L("이 공간 폴더가 삭제돼요.\n스캔한 무대와 사진은 ‘공간 미지정’에 남아요.")) {
                if let space = deletingSpace { deleteSpace(space.id) }
            }
            // 971:36590: an alert over the page. The message says what really goes: the folder, its scenes and
            // spaces; the scans themselves stay, unfiled.
            .hearConfirm(L("‘%@’ 공연 폴더를 삭제할까요?", folder?.name ?? ""), isPresented: $deleting,
                         message: L("스캔한 무대와 사진, 기본 동선, 공연 및 연습 공간이 함께 삭제돼요.\n안내 기록은 남아요.")) { deleteFolder() }
            .onChange(of: plans.map(\.id)) { _, ids in
                if let selectedSceneID, !ids.contains(selectedSceneID) { self.selectedSceneID = ids.first }
            }
            .alert(L("변경하지 못했어요"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L("확인"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
    /// Every route on this performance, in the order of the space list: each space's scanned scenes, the unfiled ones,
    /// then the reference routes drawn in the editor. Each says where it is from, 「공간(동선 이름)」.
    private var routeCards: [PerformanceRouteCard] {
        var cards = ScanRouteBridge.all(in: library, performanceID: performanceID).map(PerformanceRouteCard.init(scan:))
        cards += plans.map { PerformanceRouteCard(plan: $0) }
        return cards
    }
    private var referenceSection: some View {
        let cards = routeCards
        let focused = cards.first { $0.id == focusedCard } ?? cards.first
        return VStack(spacing: 16) {
            HStack {
                PerformanceSectionTitle(text: L("기본 동선"))
                Spacer()
                // 편집 opens the route editor on the route the carousel is showing, scanned or drawn.
                Button { selectedSceneID = focused?.id ?? cards.first?.id; editingScenes = true } label: { PerformanceOutlineButtonLabel(title: L("편집"), systemImage: "pencil") }
                    .buttonStyle(.plain).accessibilityIdentifier("performance.scenes.edit")
            }.padding(.horizontal, 20)
            if cards.isEmpty {
                // Figma 971:32413: a 200pt card of white 5%, the route symbol and 「기본동선을 추가해주세요」 in grey.
                Button { editingScenes = true } label: {
                    PerformanceEmptyCard(systemImage: "point.topleft.down.to.point.bottomright.curvepath", text: L("기본동선을\n추가해주세요"))
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
                                }.buttonStyle(PerformanceCardPressStyle()).id(card.id).accessibilityLabel(L("%@, 열기", card.label))
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
                    }.accessibilityElement(children: .ignore).accessibilityLabel(L("동선 %@개 중 %@번째", cards.count, (cards.firstIndex { $0.id == focused?.id } ?? 0) + 1))
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

/// 「공간 추가」 (Figma 872:3484 · 971:32566 · 971:36428): search places on the map and pick one, or keep the typed name. Before
/// anything is typed it shows the recent picks and the performance venues around the phone.
/// Only the place's name is kept; the space has no address field.
struct PerformanceSpaceSearchSheet: View {
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchResults: [Place] = []
    @State private var searching = false
    @StateObject private var nearby = NearbyVenueFinder()
    @AppStorage("performance.space.recentSearches") private var recentStore = ""
    struct Place: Codable, Hashable { var name: String; var address: String }
    private var recents: [Place] { (try? JSONDecoder().decode([Place].self, from: Data(recentStore.utf8))) ?? [] }
    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var combinedResults: [Place] {
        var seen = Set<String>()
        var merged: [Place] = []
        for item in nearby.completions + searchResults {
            let key = "\(item.name)|\(item.address)"
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }
        return Array(merged.prefix(20))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PerformanceSearchField(text: $query, prompt: L("공연장 이름이나 주소 검색"), clears: false)
                .padding(.horizontal, 14)
                .padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if typed.isEmpty {
                        // 872:3484 · 971:32566: 「최근 검색」 then 「주변 공연장」, each a 20pt heading over its rows.
                        if !recents.isEmpty { section(L("최근 검색"), recents.prefix(3).map { $0 }, hideLastDivider: false) }
                        if !nearby.places.isEmpty { section(L("주변 공연장"), nearby.places.map(Self.place), hideLastDivider: true) }
                        if recents.isEmpty && nearby.places.isEmpty {
                            Text(nearby.searching ? L("주변 공연장을 찾고 있어요") : L("공연장 이름이나 주소로 검색해보세요"))
                                .font(HearFont.pretendard(.regular, size: 14)).foregroundStyle(HearV3.secondary).frame(maxWidth: .infinity, minHeight: 160)
                        }
                    } else {
                        // 971:36428: the matches straight under the field, no heading.
                        let matches = combinedResults
                        VStack(spacing: 0) {
                            if (searching || nearby.completing) && matches.isEmpty {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                            }
                            ForEach(matches.indices, id: \.self) { index in
                                row(matches[index], last: index == matches.count - 1)
                            }
                            if !searching && !nearby.completing && matches.isEmpty {
                                Text(L("검색 결과가 없어요. 우측 상단 체크를 누르면 「%@」 이름으로 추가해요.", typed))
                                    .font(HearFont.pretendard(.regular, size: 14))
                                    .foregroundStyle(HearV3.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 120)
                            }
                        }
                    }
                }.padding(.horizontal, 14).padding(.top, 28).padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively)
        }
            .safeAreaInset(edge: .top, spacing: 0) {
                HearTopBar(title: L("공간 추가"), sheet: true, leading: ScanCircleButton(systemImage: "xmark", label: L("닫기")) { dismiss() },
                           trailing: Button { choose(Place(name: typed, address: "")) } label: { HearTopButtonLabel(systemImage: "checkmark", prominent: true) }
                    .buttonStyle(.plain).disabled(typed.isEmpty).opacity(typed.isEmpty ? 0.45 : 1).accessibilityLabel(L("입력한 이름으로 추가")))
            }
            .hearSheet()
            .task { nearby.start() }
            .onChange(of: typed) { _, newValue in
                nearby.updateQuery(newValue)
            }
            .task(id: typed) {
                nearby.updateQuery(typed)
                guard !typed.isEmpty else { searchResults = []; searching = false; return }
                searching = true
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = typed
                request.resultTypes = [.pointOfInterest, .address]
                request.region = nearby.region ?? NearbyVenueFinder.koreaRegion
                let found = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
                guard !Task.isCancelled else { return }
                let koreanItems = found.filter(NearbyVenueFinder.isKoreanItem)
                searchResults = Array(koreanItems.map(Self.place).prefix(20))
                searching = false
            }
            #if DEBUG
            .onAppear {
                // Fills the sheet like the design for screenshots: recents, nearby venues or a typed search.
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--space-search-sample") {
                    let sample = Place(name: "효자아트홀", address: "경북 포항시 남구 효자동")
                    if let data = try? JSONEncoder().encode([sample, Place(name: "포항문화예술회관", address: "경북 포항시 남구 대잠동"),
                                                             Place(name: "대구공연예술연습공간", address: "대구 중구 동인동")]) {
                        recentStore = String(decoding: data, as: UTF8.self)
                    }
                }
                if let i = args.firstIndex(of: "--space-query"), args.count > i + 1 { query = args[i + 1] }
            }
            #endif
    }
    private func section(_ title: String, _ places: [Place], hideLastDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(HearFont.pretendard(.semibold, size: 20)).tracking(-0.6).foregroundStyle(.white)
            VStack(spacing: 0) {
                ForEach(places.indices, id: \.self) { index in
                    row(places[index], last: hideLastDivider && index == places.count - 1)
                }
            }
        }
    }
    /// 872:3500 · 971:32582: the outlined pin in a 30pt column, the name in body text with the drill-in arrow, the address in grey,
    /// and a hairline under the text that the pin column stays clear of.
    private func row(_ place: Place, last: Bool) -> some View {
        Button { choose(place) } label: {
            HStack(alignment: .top, spacing: 8) {
                HearMapPin().stroke(.white, style: StrokeStyle(lineWidth: 1.67, lineCap: .round)).frame(width: 20, height: 20).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Text(place.name).font(.system(size: 17)).tracking(-0.43).foregroundStyle(.white).lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(PerformanceSearchField.grey)
                                .frame(width: 28, height: 28)
                        }.frame(height: 28)
                        if !place.address.isEmpty {
                            Text(place.address).font(.system(size: 15)).tracking(-0.23).foregroundStyle(PerformanceSearchField.grey).lineLimit(1)
                        }
                    }
                    Rectangle().fill(last ? .clear : .white.opacity(0.2)).frame(height: 1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(8).contentShape(Rectangle())
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
    static func place(_ item: MKMapItem) -> Place {
        let mark = item.placemark
        let address = [mark.administrativeArea, mark.locality, mark.subLocality, mark.thoroughfare, mark.subThoroughfare]
            .compactMap { $0 }.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }.joined(separator: " ")
        return Place(name: item.name ?? address, address: address)
    }
}

/// Performance venues around the phone for 「주변 공연장」 (872:3484 · 971:32566) and South Korea-only keyword autocomplete.
@MainActor final class NearbyVenueFinder: NSObject, ObservableObject, CLLocationManagerDelegate, MKLocalSearchCompleterDelegate {
    static let koreaRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.35, longitude: 127.85),
        span: MKCoordinateSpan(latitudeDelta: 5.5, longitudeDelta: 4.5)
    )
    private static let defaultKoreaLocation = CLLocation(latitude: 36.0190, longitude: 129.3435)
    private static let koreanRegions = [
        "대한민국", "서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종",
        "경기", "강원", "충북", L("충청"), "전북", L("전라"), "경북", L("경상"), "제주"
    ]

    @Published private(set) var places: [MKMapItem] = []
    @Published private(set) var completions: [PerformanceSpaceSearchSheet.Place] = []
    @Published private(set) var searching = false
    @Published private(set) var completing = false
    /// Where the phone is (within South Korea), so typed searches also favour nearby Korean places.
    private(set) var region: MKCoordinateRegion?
    private let manager = CLLocationManager()
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        completer.region = Self.koreaRegion
    }

    static func isInKorea(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (33.0...38.9).contains(coordinate.latitude) && (124.5...132.0).contains(coordinate.longitude)
    }

    static func isKoreanItem(_ item: MKMapItem) -> Bool {
        if let code = item.placemark.isoCountryCode, !code.isEmpty {
            return code.uppercased() == "KR"
        }
        return isInKorea(item.placemark.coordinate)
    }

    private static func koreanPlace(from completion: MKLocalSearchCompletion) -> PerformanceSpaceSearchSheet.Place? {
        let name = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawSub = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !rawSub.isEmpty, !rawSub.contains("근처 검색") else { return nil }
        let isKoreanAddress = koreanRegions.contains { rawSub.hasPrefix($0) }
            || rawSub.hasSuffix("South Korea")
            || rawSub.hasSuffix("Republic of Korea")
        guard isKoreanAddress else { return nil }
        var address = rawSub
        if address.hasPrefix("대한민국") {
            address = String(address.dropFirst("대한민국".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        }
        return PerformanceSpaceSearchSheet.Place(name: name, address: address)
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completer.cancel()
            completions = []
            completing = false
            return
        }
        completer.region = region ?? Self.koreaRegion
        if completer.queryFragment != trimmed {
            completing = true
            completer.queryFragment = trimmed
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let rawResults = completer.results
        Task { @MainActor in
            self.completions = rawResults.compactMap(Self.koreanPlace)
            self.completing = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.completing = false }
    }

    func start() {
        manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: searching = true; manager.requestLocation()
        default: break
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways, places.isEmpty, !searching { searching = true; self.manager.requestLocation() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await find(around: location) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in searching = false }
    }
    private func find(around location: CLLocation) async {
        let targetLocation = Self.isInKorea(location.coordinate) ? location : Self.defaultKoreaLocation
        let localRegion = MKCoordinateRegion(center: targetLocation.coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        if Self.isInKorea(location.coordinate) {
            region = localRegion
            completer.region = localRegion
        } else {
            region = Self.koreaRegion
            completer.region = Self.koreaRegion
        }
        // Apple's venue categories are sparse in Korea, so a plain 「공연장」 search around the phone fills in.
        let request = MKLocalPointsOfInterestRequest(center: targetLocation.coordinate, radius: 5_000)
        var categories: [MKPointOfInterestCategory] = [.theater]
        if #available(iOS 18.0, *) { categories += [.musicVenue] }
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        var found = ((try? await MKLocalSearch(request: request).start())?.mapItems ?? []).filter(Self.isKoreanItem)
        if found.isEmpty {
            let typed = MKLocalSearch.Request(); typed.naturalLanguageQuery = "공연장"; typed.resultTypes = .pointOfInterest
            typed.region = MKCoordinateRegion(center: targetLocation.coordinate, latitudinalMeters: 10_000, longitudinalMeters: 10_000)
            found = ((try? await MKLocalSearch(request: typed).start())?.mapItems ?? []).filter(Self.isKoreanItem)
        }
        places = Array(found.sorted { ($0.placemark.location?.distance(from: targetLocation) ?? 0) < ($1.placemark.location?.distance(from: targetLocation) ?? 0) }.prefix(3))
        searching = false
    }
}

/// The outlined map pin of the place rows (971:32584), drawn in a 20pt box.
struct HearMapPin: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 20
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(16.67, 8.33))
        path.addCurve(to: p(10.5, 18.17), control1: p(16.67, 12.49), control2: p(12.05, 16.83))
        path.addCurve(to: p(9.5, 18.17), control1: p(10.21, 18.39), control2: p(9.79, 18.39))
        path.addCurve(to: p(3.33, 8.33), control1: p(7.95, 16.83), control2: p(3.33, 12.49))
        path.addArc(center: p(10, 8.33), radius: 6.67 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.closeSubpath()
        path.addEllipse(in: CGRect(origin: p(7.5, 5.83), size: CGSize(width: 5 * s, height: 5 * s)))
        return path
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
        id = plan.id; self.plan = plan; label = L("기본 동선(%@)", plan.name); venueID = nil; isScan = false
        aspect = PerformancePlan.depth / PerformancePlan.width
    }
    /// The scan's route, scaled from its measured stage onto the 12 × 8 schematic, as the route editor opens it.
    init(scan bridge: ScanRouteBridge) {
        id = bridge.scanID; plan = bridge.plan; label = "\(bridge.venueName)(\(bridge.plan.name))"; venueID = bridge.venueID; isScan = true
        aspect = bridge.route.area.depth / bridge.route.area.width
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
                Section {Text(L("스캔한 무대를 선택해주세요. 다른 공연에 연결된 무대는 이 공연으로 옮겨집니다.")).font(.subheadline).foregroundStyle(.secondary)}
                if scans.isEmpty {ContentUnavailableView(L("연결할 무대가 없어요"),systemImage:"building.2",description:Text(query.isEmpty ? L("스캔 탭에서 무대를 먼저 저장해주세요.") : L("다른 이름으로 검색해주세요.")))}
                ForEach(scans,id:\.id) {scan in
                    Button {if selected.contains(scan.id) {selected.remove(scan.id)} else {selected.insert(scan.id)}} label:{
                        HStack {
                            VStack(alignment:.leading,spacing:5) {Text(scan.name);Text(library.catalog.folder(for:scan.id)?.name ?? L("분류 필요")).font(.caption).foregroundStyle(.secondary)}
                            Spacer();Image(systemName:selected.contains(scan.id) ? "checkmark.circle.fill" : "circle")
                        }.frame(minHeight:48)
                    }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(scan.id) ? .isSelected : [])
                }
            }.scrollContentBackground(.hidden).clearNavigationBackground().navigationTitle(L("무대 연결")).navigationBarTitleDisplayMode(.inline)
                .searchable(text:$query,prompt:L("무대 또는 공연 이름 검색"))
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button(L("닫기"),systemImage:"xmark") {dismiss()}.labelStyle(.iconOnly)}}
                .safeAreaInset(edge:.bottom) {Button(L("선택한 %@개 연결", selected.count)) {classificationIDs=Array(selected);classifying=true}.buttonStyle(V3PrimaryButtonStyle()).disabled(selected.isEmpty).padding(20)}
                .sheet(isPresented:$classifying) {StageClassificationView(library:library,scanIDs:classificationIDs,initialPerformanceID:performanceID) {_ in dismiss()}.suspendsVoiceWake()}
        }.hearSheet()
    }
}
