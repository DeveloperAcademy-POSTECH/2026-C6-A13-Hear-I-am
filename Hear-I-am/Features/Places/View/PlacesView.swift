import SwiftUI
import HearIAmCore

struct PlacesView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model=PlaceLibrary()
    @State private var query=""
    @State private var kind: PlaceKind?
    @State private var favoritesOnly=false
    @State private var sort=PlaceSort.recent
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    private var searching: Bool {!query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
    private var places: [PlaceEntry] {sort.sorted(model.index.places.filter {(kind == nil || $0.kind == kind) && (!favoritesOnly || $0.favorite)})}
    private var results: PlaceSearchResults {PlaceSearch.search(query,index:model.index,scans:library.records)}
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    searchField
                    if !model.ready {
                        if model.loading {ProgressView("장소 불러오는 중").frame(maxWidth:.infinity)}
                        else {ContentUnavailableView {Label("장소를 불러오지 못했어요",systemImage:"folder.badge.questionmark")} description:{Text("기존 스캔은 유지됩니다.")} actions:{Button("다시 불러오기") {Task {await model.refresh()}}}}
                    } else if searching {searchResults}
                    else {placeList}
                }.padding(.horizontal,20).padding(.top,8).padding(.bottom,12)
            }.background(Color(.systemBackground)).scrollDismissesKeyboard(.interactively)
                .navigationTitle("장소").navigationBarTitleDisplayMode(.large)
                .toolbar {ToolbarItem(placement:.topBarTrailing) {
                    Button {searchFocused=false;model.present(.edit(nil))} label:{Image(systemName:"plus").font(.title3).frame(width:40,height:40).background(Color(.systemGray6),in:Circle())}
                        .accessibilityLabel("장소 등록").disabled(!model.ready || model.busy || model.loading)
                }}
                .safeAreaInset(edge:.bottom,alignment:.trailing) {
                    if !searchFocused {
                        HStack {Spacer();Button {Task {await model.beginScan(at:nil,library:library)}} label:{Label("새 스캔",systemImage:"viewfinder").font(.subheadline.weight(.semibold)).padding(.horizontal,20).frame(minHeight:50).foregroundStyle(.white).background(Color.hearInk,in:Capsule()).shadow(color:.black.opacity(0.16),radius:8,y:3)}.accessibilityHint("장소를 지정하지 않고 새 스캔을 시작합니다").disabled(!model.ready || model.busy || model.loading)}
                            .padding(.horizontal,20).padding(.top,10).padding(.bottom,12)
                    }
                }
        }.tint(.hearInk)
            .task {await model.refresh()}
            .onChange(of:scenePhase) {_, phase in if phase == .active, !model.scanPresented,model.sheet == nil {Task {await model.refresh();await library.refresh()}}}
            .sheet(item:$model.sheet) {request in
                switch request.content {
                case .edit(let place):PlaceEditorView(model:model,library:library,place:place)
                case .move(let scans):PlaceMoveView(scans:scans,model:model,library:library)
                case .rename(let scan):PlaceRenameView(scan:scan,library:library)
                }
            }
            .fullScreenCover(isPresented:$model.scanPresented,onDismiss:{Task {await model.finishScan(library:library)}}) {
                PreparationView(library:library)
            }
            .alert("확인이 필요해요",isPresented:Binding(get:{model.error != nil && model.sheet == nil},set:{if !$0 {model.error=nil}})) {Button("확인",role:.cancel) {model.error=nil}} message:{Text(model.error ?? "")}
    }
    private var searchField: some View {
        HStack(spacing:10) {
            HStack(spacing:8) {
                Image(systemName:"magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("장소 · 공연 검색",text:$query).focused($searchFocused).submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityLabel("장소 또는 공연 검색")
                if !query.isEmpty {Button {query=""} label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary).frame(width:32,height:40)}.accessibilityLabel("검색어 지우기")}
            }.font(.subheadline).padding(.horizontal,12).frame(minHeight:44).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:13))
            if searchFocused || searching {Button("취소") {query="";searchFocused=false}.font(.subheadline).frame(minHeight:44)}
        }
    }
    private var placeList: some View {
        VStack(alignment:.leading,spacing:20) {
            NavigationLink {PlaceContentsView(destination:nil,model:model,library:library)} label:{
                HStack(spacing:10) {
                    Image(systemName:"tray").font(.title3);Text("장소 미지정").font(.subheadline.weight(.semibold));Spacer()
                    Text("공연 \(model.records(library.records,at:nil).count)개").font(.caption).foregroundStyle(.secondary)
                    Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                }.padding(16).placeCardStyle()
            }.buttonStyle(.plain)
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text("내 장소").font(.headline);Text("\(places.count)").font(.headline).foregroundStyle(.secondary);Spacer()
                    Menu {
                        ForEach(PlaceSort.allCases,id:\.self) {option in
                            Button {sort=option} label:{
                                HStack {Text(option.title);if sort==option {Image(systemName:"checkmark")}}
                            }
                        }
                    } label:{Label(sort.title,systemImage:"chevron.down").font(.caption).frame(minHeight:44)}
                }
                HStack(spacing:10) {
                    Picker("장소 유형",selection:$kind) {Text("전체").tag(nil as PlaceKind?);ForEach(PlaceKind.allCases,id:\.self) {Text($0.title).tag(Optional($0))}}.pickerStyle(.segmented)
                    Button {favoritesOnly.toggle()} label:{Image(systemName:favoritesOnly ? "star.fill" : "star").font(.title3).frame(width:44,height:44).background(Color(.systemGray6),in:Circle())}.accessibilityLabel("즐겨찾기만 보기").accessibilityValue(favoritesOnly ? "켬" : "끔")
                }
                if places.isEmpty {
                    if model.index.places.isEmpty {
                        ContentUnavailableView("장소별로 공연을 모아보세요",systemImage:"folder",description:Text("오른쪽 위 + 버튼으로 장소를 등록하세요. 장소 없이도 새 스캔을 시작할 수 있어요."))
                    } else {
                        ContentUnavailableView {Label("조건에 맞는 장소가 없어요",systemImage:"line.3.horizontal.decrease.circle")} description:{Text("장소 유형이나 즐겨찾기 조건을 바꿔보세요.")} actions:{Button("필터 초기화") {kind=nil;favoritesOnly=false}}
                    }
                } else {LazyVStack(spacing:10) {ForEach(places) {PlaceCard(place:$0,model:model,library:library)}}}
            }
        }
    }
    private var searchResults: some View {
        let results=self.results
        return VStack(alignment:.leading,spacing:22) {
            Text("검색 결과 \(results.places.count+results.performances.count)개").font(.caption).foregroundStyle(.secondary)
            if results.places.isEmpty && results.performances.isEmpty {
                ContentUnavailableView.search(text:query)
            }
            if !results.places.isEmpty {
                VStack(alignment:.leading,spacing:12) {
                    Text("장소 \(results.places.count)").font(.headline)
                    ForEach(results.places) {PlaceCard(place:$0,model:model,library:library)}
                }
            }
            if !results.performances.isEmpty {
                VStack(alignment:.leading,spacing:12) {
                    Text("\(!results.matchesPerformanceName && !results.places.isEmpty ? "이 장소의 공연" : "공연") \(results.performances.count)").font(.headline)
                    ForEach(results.performances,id:\.id) {record in
                        PlacePerformanceCard(record:record,model:model,library:library,onMove:{model.present(.move([record]))},onRename:{model.present(.rename(record))})
                    }
                }
            }
        }
    }
}
