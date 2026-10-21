import SwiftUI
import HearIAmCore

struct SpacesView: View {
    @ObservedObject var library: StageLibrary
    @State private var filter=SpaceFilter()
    @State private var filtersPresented=false
    @AppStorage("spaces.operatorTools") private var operatorTools=false
    private var results: [SpaceVenue] {
        filter.apply(to:library.venues,favorites:library.spacePreferences.favorites,baseRooms:library.baseRoomIDs,performanceRooms:library.performanceRoomIDs)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    searchBar
                    Picker("공간 종류",selection:$filter.kind) {
                        Text("전체").tag(nil as SpaceKind?)
                        ForEach(SpaceKind.allCases,id:\.self) {Text($0.label).tag(Optional($0))}
                    }.pickerStyle(.segmented).onChange(of:filter.kind) {_,kind in if kind == .rehearsal {filter.scale=nil}}
                    activeFilters
                    if filter.query.isEmpty && filter.kind == nil && !hasFilters {recentRooms}
                    HStack {
                        Text(filter.query.isEmpty ? "등록된 공간 \(results.count)" : "검색 결과 \(results.count)").font(.title3.bold())
                        Spacer()
                        Menu {
                            Picker("정렬",selection:$filter.newestFirst) {Text("이름순").tag(false);Text("최근 등록순").tag(true)}
                        } label:{Label(filter.newestFirst ? "최근 등록순" : "이름순",systemImage:"chevron.down").font(.subheadline).frame(minHeight:44)}
                        Button {filtersPresented=true} label:{Image(systemName:"line.3.horizontal.decrease").frame(width:44,height:44)}.accessibilityLabel("공간 필터")
                    }
                    if results.isEmpty {
                        ContentUnavailableView {Label("조건에 맞는 공간이 없어요",systemImage:"magnifyingglass")} description:{Text("검색어나 필터를 바꿔보세요.")} actions:{Button("필터 초기화") {filter=SpaceFilter()}}
                    }
                    LazyVStack(spacing:18) {
                        ForEach(results) {venue in venueCard(venue)}
                    }
                    if !library.unassignedScans.isEmpty {
                        NavigationLink {UnassignedSpacesView(library:library)} label:{
                            HStack {Label("아직 장소를 연결하지 않은 무대",systemImage:"tray");Spacer();Text("\(library.unassignedScans.count)");Image(systemName:"chevron.right")}.font(.subheadline).padding(16).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:16))
                        }
                    }
                }.padding(20).padding(.bottom,12)
            }.navigationTitle("공간").background(Color(.systemBackground))
                .sheet(isPresented:$filtersPresented) {SpaceFilterSheet(filter:$filter,regions:Array(Set(library.venues.map(\.region))).sorted())}
                .refreshable {await library.refresh()}
                .task {await library.refresh()}
                #if DEBUG
                .toolbar {ToolbarItem(placement:.topBarTrailing) {
                    Menu {Toggle("운영용 기본 공간 등록",isOn:$operatorTools)} label:{Image(systemName:"ellipsis.circle")}.accessibilityLabel("개발용 공간 관리")
                }}
                #endif
        }
    }
    private var searchBar: some View {
        HStack {
            Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
            TextField("공연장·연습실·지역 검색",text:$filter.query).submitLabel(.search).autocorrectionDisabled()
            if !filter.query.isEmpty {Button {filter.query=""} label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary).frame(width:32,height:44)}.accessibilityLabel("검색어 지우기")}
        }.padding(.horizontal,12).frame(minHeight:48).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:13))
    }
    private var hasFilters: Bool {filter.region != nil || filter.scale != nil || filter.favoritesOnly || filter.baseOnly || filter.performancesOnly}
    @ViewBuilder private var activeFilters: some View {
        if hasFilters {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack {
                    if let region=filter.region {chip(region) {filter.region=nil}}
                    if let scale=filter.scale {chip(scale.label) {filter.scale=nil}}
                    if filter.favoritesOnly {chip("즐겨찾기") {filter.favoritesOnly=false}}
                    if filter.baseOnly {chip("기본 공간 있음") {filter.baseOnly=false}}
                    if filter.performancesOnly {chip("내 공연 있음") {filter.performancesOnly=false}}
                }
            }
        }
    }
    private func chip(_ text: String,clear: @escaping () -> Void) -> some View {
        Button(action:clear) {Label(text,systemImage:"xmark").font(.caption.weight(.medium)).padding(.horizontal,12).frame(minHeight:44).background(Color(.systemGray6),in:Capsule())}.accessibilityLabel("\(text) 필터 해제")
    }
    private func venueCard(_ venue: SpaceVenue) -> some View {
        VStack(alignment:.leading,spacing:0) {
            ZStack(alignment:.topTrailing) {
                NavigationLink {VenueDetailView(venue:venue,library:library)} label:{SpacePhotoView(photo:venue.photos.first)}.buttonStyle(.plain)
                favorite(venue).padding(10)
            }
            NavigationLink {VenueDetailView(venue:venue,library:library)} label:{
                VStack(alignment:.leading,spacing:10) {
                    Text(venue.name).font(.title3.bold()).foregroundStyle(.primary)
                    Label(venue.address,systemImage:"mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Text(venue.rooms.contains {library.baseRoomIDs.contains($0.id)} ? "기본 공간 있음 · 이 기기에 저장됨" : "공간 정보만 등록됨")
                        Spacer()
                        if venue.rooms.count==1, let scale=venue.rooms.first?.scale {Text(scale.label)}
                    }.font(.caption).foregroundStyle(venue.rooms.contains {library.baseRoomIDs.contains($0.id)} ? Color.hearGreen : .secondary)
                    Divider().padding(.vertical,3)
                    HStack {Text("내부 공간 보기");Spacer();Image(systemName:"chevron.right")}.font(.subheadline).frame(minHeight:30)
                }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            }.buttonStyle(.plain)
        }.background(.white).clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.gray.opacity(0.2)))
    }
    private func favorite(_ venue: SpaceVenue) -> some View {
        Button {library.favoriteVenue(venue.id)} label:{Image(systemName:library.spacePreferences.favorites.contains(venue.id) ? "star.fill" : "star").font(.title3).frame(width:44,height:44).background(.regularMaterial,in:Circle())}.buttonStyle(.plain).accessibilityLabel("\(venue.name) 즐겨찾기 \(library.spacePreferences.favorites.contains(venue.id) ? "해제" : "추가")")
    }
    @ViewBuilder private var recentRooms: some View {
        let rooms=library.venues.flatMap {venue in venue.rooms.map {(venue,$0)}}.filter {library.spacePreferences.recentRooms[$0.1.id] != nil}.sorted {library.spacePreferences.recentRooms[$0.1.id]! > library.spacePreferences.recentRooms[$1.1.id]!}
        if !rooms.isEmpty {
            VStack(alignment:.leading,spacing:12) {
                Text("최근 사용한 공간").font(.title3.bold())
                ForEach(Array(rooms.prefix(3)),id:\.1.id) {venue,room in
                    NavigationLink {RoomDetailView(venue:venue,room:room,library:library)} label:{RoomCard(room:room,detail:venue.name)}.buttonStyle(.plain)
                }
            }
        }
    }
}
