import SwiftUI
import HearIAmCore

struct PlacePhoto: View {
    let image: UIImage?
    var body: some View {
        GeometryReader {proxy in
            if let image {Image(uiImage:image).resizable().scaledToFill().frame(width:proxy.size.width,height:proxy.size.height).clipped()}
            else {ZStack {Color(.systemGray6);Image(systemName:"photo").font(.title2).foregroundStyle(.secondary)}}
        }.clipShape(RoundedRectangle(cornerRadius:14)).accessibilityHidden(true)
    }
}
struct PlaceCard: View {
    let place: PlaceEntry
    @ObservedObject var model: PlaceLibrary
    @ObservedObject var library: StageLibrary
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(alignment:.top,spacing:10) {
            NavigationLink {
                PlaceContentsView(destination:.init(placeID:place.id),model:model,library:library)
            } label: {
                HStack(spacing:12) {
                    if !typeSize.isAccessibilitySize {PlacePhoto(image:model.photos[place.photoID]).frame(width:82,height:86)}
                    VStack(alignment:.leading,spacing:6) {
                        Text(place.name).font(.headline).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
                        Text(place.kind.title+" · "+place.address).font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        HStack(spacing:4) {
                            Text("공연 \(model.count(in:place,scans:library.records))개").fontWeight(.semibold)
                            if !place.folders.isEmpty {Text("· 폴더 \(place.folders.count)개").foregroundStyle(.secondary)}
                        }.font(.caption).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            VStack(spacing:2) {
                Button {Task {await model.update {try await model.store.togglePlaceFavorite(place.id)}}} label: {
                    Image(systemName:place.favorite ? "star.fill" : "star").font(.title3).frame(width:44,height:44)
                }.buttonStyle(.plain).disabled(model.busy)
                    .accessibilityLabel("\(place.name) 즐겨찾기 \(place.favorite ? "해제" : "추가")")
                Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary).padding(.top,6).accessibilityHidden(true)
            }
        }.padding(14).placeCardStyle()
    }
}
struct PlacePerformanceCard: View {
    let record: ScanManifest
    @ObservedObject var model: PlaceLibrary
    @ObservedObject var library: StageLibrary
    var showsPath=true
    var onMove: () -> Void
    var onRename: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(alignment:.top,spacing:8) {
                NavigationLink {
                    SavedStagePreview(record:record,store:library.scans)
                } label: {
                    HStack(alignment:.top,spacing:12) {
                        if !typeSize.isAccessibilitySize {
                            StageMap(showsLabels:false,width:record.route?.area.width ?? 12,depth:record.route?.area.depth ?? 8,points:record.route?.points ?? [],objects:record.route?.obstacles ?? [],dangerZones:record.route?.dangerZones ?? [])
                                .frame(width:80,height:88).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
                        }
                        VStack(alignment:.leading,spacing:7) {
                            HStack {Text(record.name).font(.headline);if model.index.favoriteScans.contains(record.id) {Image(systemName:"star.fill").font(.caption)}}
                            if showsPath {
                                VStack(alignment:.leading,spacing:4) {
                                    let path=model.index.path(for:record.id)
                                    Label(path[0],systemImage:model.index.destination(for:record.id) == nil ? "tray" : "mappin.and.ellipse")
                                    if path.count>1 {Label(path[1],systemImage:"folder")}
                                }.font(.caption).foregroundStyle(.secondary).padding(7).frame(maxWidth:.infinity,alignment:.leading)
                                    .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:9))
                            }
                            Text("\(record.date.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).month().day())) 저장 · 경로점 \(record.route?.points.count ?? 0)개")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("저장한 스캔을 3D로 봅니다")
                Menu {
                    Button("이름 변경",systemImage:"pencil",action:onRename)
                    Button("장소·폴더 이동",systemImage:"folder",action:onMove)
                    Button(model.index.favoriteScans.contains(record.id) ? "즐겨찾기 해제" : "즐겨찾기",systemImage:"star") {
                        Task {await model.update {try await model.store.togglePerformanceFavorite(record.id)}}
                    }
                } label:{Image(systemName:"ellipsis").frame(width:44,height:44)}
                    .accessibilityLabel("\(record.name), \(model.index.path(for:record.id).joined(separator:", ")), 관리")
                    .disabled(model.busy)
            }
        }.padding(14).placeCardStyle()
    }
}
extension View {
    func placeCardStyle() -> some View {
        background(Color(.systemBackground),in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).stroke(Color(.systemGray5)))
    }
}
