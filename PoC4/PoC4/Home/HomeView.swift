import SwiftUI
import PoC4Core

struct HearRootView: View {
    @StateObject private var library=StageLibrary()
    var body: some View {
        TabView {
            HomeView(library:library).tabItem {Label("홈",systemImage:"house.fill")}
            PlanLibraryView(library:library).tabItem {Label("공연 사전 저장",systemImage:"map")}
            NavigationStack {UnavailableFeature(title:"기록",symbol:"clock").navigationTitle("기록")}
                .tabItem {Label("기록",systemImage:"clock")}
        }.tint(.hearInk).preferredColorScheme(.light)
            .task {await library.refresh()}
            .alert("확인이 필요해요",isPresented:Binding(get:{library.error != nil},set:{if !$0 {library.error=nil}})) {
                Button("확인",role:.cancel) {library.error=nil}
            } message: {Text(library.error ?? "")}
    }
}

struct HomeView: View {
    @ObservedObject var library: StageLibrary
    @State private var preparing=false
    @State private var notice: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:26) {
                    VStack(alignment:.leading,spacing:8) {
                        HStack {
                            Image(systemName:"sparkle").font(.title2).foregroundStyle(.white).frame(width:44,height:44).background(.black,in:RoundedRectangle(cornerRadius:12))
                            Text("Hear I am").font(.largeTitle.bold())
                            Spacer()
                            Button {notice="설정은 준비 중입니다."} label: {Image(systemName:"gearshape").font(.title3).frame(width:44,height:44)}.accessibilityLabel("설정")
                        }
                        Text("무엇을 시작할까요?").font(.title3).foregroundStyle(.secondary)
                    }
                    HStack(spacing:12) {
                        homeAction("무대 준비하기",subtitle:"공간과 경로 저장",image:"ScanAction",dark:true) {preparing=true}
                        homeAction("안내 사용하기",subtitle:"저장한 무대 선택",image:"BeltAction",dark:false) {notice="안내 사용하기는 기획 중입니다. 무대 준비와 저장 기능을 먼저 이용해주세요."}
                    }
                    if !library.groups.pinned.isEmpty {
                        stageSection("고정한 무대",records:library.groups.pinned)
                    }
                    VStack(alignment:.leading,spacing:14) {
                        HStack {Text("최근 저장한 무대").font(.title2.bold()); Spacer(); Text("최근 저장순").font(.caption).foregroundStyle(.secondary)}
                        if library.loading && library.records.isEmpty {ProgressView().frame(maxWidth:.infinity)}
                        else if library.records.isEmpty {
                            VStack(spacing:12) {
                                Image("StageEmpty").resizable().scaledToFit().frame(height:155).accessibilityHidden(true)
                                Text("첫 무대를 준비해보세요").font(.headline)
                                Text("공간과 동선을 저장하면 여기에서 볼 수 있어요.").font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity).padding(20).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:22))
                        } else if library.groups.recent.isEmpty {
                            Text("저장한 무대가 모두 위에 고정되어 있어요.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical)
                        } else {ForEach(library.groups.recent,id:\.id) {StageRow(record:$0,library:library)}}
                    }
                }.padding(20).padding(.bottom,16)
            }.background(Color(.systemBackground)).toolbar(.hidden,for:.navigationBar)
                .refreshable {await library.refresh()}
                .fullScreenCover(isPresented:$preparing,onDismiss:{Task {await library.refresh()}}) {PreparationView()}
                .alert("Hear I am",isPresented:Binding(get:{notice != nil},set:{if !$0 {notice=nil}})) {Button("확인",role:.cancel) {notice=nil}} message: {Text(notice ?? "")}
        }
    }
    private func stageSection(_ title: String, records: [ScanManifest]) -> some View {
        VStack(alignment:.leading,spacing:14) {Text(title).font(.title2.bold()); ForEach(records,id:\.id) {StageRow(record:$0,library:library)}}
    }
    private func homeAction(_ title: String,subtitle: String,image: String,dark: Bool,action: @escaping ()->Void) -> some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:14) {
                Image(image).resizable().scaledToFit().frame(height:86).frame(maxWidth:.infinity).accessibilityHidden(true)
                Spacer(minLength:0)
                HStack(spacing:3) {Text(title).font(.system(size:19,weight:.bold)).minimumScaleFactor(0.8).lineLimit(1); Spacer(minLength:0); Image(systemName:"chevron.right").font(.caption.bold())}
                Text(subtitle).font(.system(size:13)).foregroundStyle(dark ? Color.white.opacity(0.75) : .secondary)
            }.padding(16).frame(maxWidth:.infinity).frame(height:207)
                .foregroundStyle(dark ? .white : .hearInk)
                .background(dark ? Color.hearInk : Color(.systemBackground),in:RoundedRectangle(cornerRadius:22))
                .overlay(RoundedRectangle(cornerRadius:22).stroke(.gray.opacity(dark ? 0 : 0.25)))
        }.buttonStyle(.plain)
    }
}

private struct StageRow: View {
    let record: ScanManifest
    @ObservedObject var library: StageLibrary
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:12) {
                StageMap(width:record.route?.area.width ?? 12,depth:record.route?.area.depth ?? 8,points:record.route?.points ?? [],objects:record.route?.obstacles ?? [])
                    .frame(width:92,height:92).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:6) {
                    Text(record.name).font(.headline).lineLimit(2)
                    Text("내부 지점 \(max(0,(record.route?.points.count ?? 2)-2))개 · 기물 \(record.route?.obstacles.count ?? 0)개").font(.caption).foregroundStyle(.secondary)
                    Text(record.date,format:.dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Button {library.togglePin(record.id)} label: {Image(systemName:library.pins.ids.contains(record.id) ? "star.fill" : "star").font(.title3).frame(width:32,height:44)}
                    .accessibilityLabel(library.pins.ids.contains(record.id) ? "\(record.name) 고정 해제" : "\(record.name) 고정")
            }
            Text("저장 완료 · 사용 전 현장 확인 필요").font(.caption).foregroundStyle(Color.hearGreen)
            Divider()
            NavigationLink {SavedStagePreview(record:record,store:library.scans)} label: {
                Label("스캔 공간 3D로 보기",systemImage:"cube").font(.subheadline)
                Spacer(); Image(systemName:"chevron.right").font(.caption)
            }.padding(.vertical,3)
        }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.gray.opacity(0.24)))
    }
}
