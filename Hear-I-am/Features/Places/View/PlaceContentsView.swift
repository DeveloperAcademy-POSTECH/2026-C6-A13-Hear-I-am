import SwiftUI
import HearIAmCore

struct PlaceContentsView: View {
    let destination: PlaceDestination?
    @ObservedObject var model: PlaceLibrary
    @ObservedObject var library: StageLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete=false
    @State private var selecting=false
    @State private var selected: Set<UUID> = []
    @State private var nameOrder=false
    private var place: PlaceEntry? {model.index.places.first {$0.id==destination?.placeID}}
    private var folder: PlaceSubfolder? {place?.folders.first {$0.id==destination?.folderID}}
    private var title: String {folder?.name ?? place?.name ?? "장소 미지정"}
    private var available: Bool {destination.map(model.index.contains) ?? true}
    private var records: [ScanManifest] {
        let items=model.records(library.records,at:destination)
        return nameOrder ? items.sorted {if $0.name != $1.name {return $0.name.localizedStandardCompare($1.name) == .orderedAscending};return $0.date>$1.date} : items
    }
    var body: some View {
        ScrollView {
            if !available {
                ContentUnavailableView("폴더가 변경됐어요",systemImage:"folder",description:Text("장소 목록에서 다시 선택해주세요."))
            } else {
                VStack(alignment:.leading,spacing:22) {
                    if let place {
                        VStack(alignment:.leading,spacing:10) {
                            PlacePhoto(image:model.photos[place.photoID]).frame(height:170)
                            if folder != nil {Text(place.name).font(.subheadline).foregroundStyle(.secondary)}
                            Label(place.address,systemImage:"mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                            Text(place.kind.title).font(.caption).padding(.horizontal,10).padding(.vertical,5).background(Color(.systemGray6),in:Capsule())
                        }
                        if destination?.folderID == nil, !place.folders.isEmpty {
                            VStack(alignment:.leading,spacing:10) {
                                HStack {Text("하위 폴더 \(place.folders.count)").font(.headline);Spacer();Button {model.present(.edit(place))} label:{Image(systemName:"plus").frame(width:44,height:44)}.accessibilityLabel("하위 폴더 관리")}
                                ForEach(place.folders) {folder in
                                    let target=PlaceDestination(placeID:place.id,folderID:folder.id)
                                    NavigationLink {PlaceContentsView(destination:target,model:model,library:library)} label:{
                                        HStack(spacing:12) {
                                            Image(systemName:"folder").font(.title2)
                                            VStack(alignment:.leading,spacing:4) {Text(folder.name).font(.headline);Text("공연 \(model.records(library.records,at:target).count)개").font(.caption).foregroundStyle(.secondary)}
                                            Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                                        }.padding(16).placeCardStyle()
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    HStack {
                        Text("내 공연 \(records.count)").font(.headline)
                        Spacer()
                        Menu {
                            Button {nameOrder=false} label:{Label("최근 저장순",systemImage:nameOrder ? "" : "checkmark")}
                            Button {nameOrder=true} label:{Label("이름순",systemImage:nameOrder ? "checkmark" : "")}
                        } label:{Label(nameOrder ? "이름순" : "최근 저장순",systemImage:"chevron.down").font(.caption).frame(minHeight:44)}
                    }
                    if records.isEmpty {
                        ContentUnavailableView("아직 저장한 공연이 없어요",systemImage:"square.stack",description:Text(destination == nil ? "새 스캔을 저장하면 여기에서 볼 수 있어요." : "새 공연을 준비하거나 장소 미지정에서 공연을 옮겨보세요."))
                    } else {
                        LazyVStack(spacing:12) {
                            ForEach(records,id:\.id) {record in
                                if selecting {
                                    Button {if !selected.insert(record.id).inserted {selected.remove(record.id)}} label:{
                                        HStack {Image(systemName:selected.contains(record.id) ? "checkmark.circle.fill" : "circle").font(.title2);VStack(alignment:.leading,spacing:5) {Text(record.name).font(.headline);Text(record.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)};Spacer()}.padding(18).placeCardStyle()
                                    }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(record.id) ? [.isSelected] : [])
                                } else {
                                    PlacePerformanceCard(record:record,model:model,library:library,showsPath:false,onMove:{model.present(.move([record]))},onRename:{model.present(.rename(record))})
                                }
                            }
                        }
                    }
                }.padding(.horizontal,20).padding(.top,12).padding(.bottom,20)
            }
        }.background(Color(.systemBackground)).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    if selecting {Button("완료") {selecting=false;selected=[]}}
                    else {
                        Menu {
                            if !records.isEmpty {Button("공연 선택",systemImage:"checkmark.circle") {selecting=true}}
                            if let place {
                                Button("장소·폴더 수정",systemImage:"pencil") {model.present(.edit(place))}
                                if destination?.folderID == nil {Button("장소 삭제",systemImage:"trash",role:.destructive) {confirmDelete=true}}
                            }
                        } label:{Image(systemName:"ellipsis").frame(width:44,height:44)}.accessibilityLabel("장소 관리").disabled(model.busy)
                    }
                }
            }
            .safeAreaInset(edge:.bottom) {
                if available {
                    Button {
                        if selecting {
                            let moving=records.filter {selected.contains($0.id)}
                            model.present(.move(moving));selecting=false;selected=[]
                        } else {Task {await model.beginScan(at:destination,library:library)}}
                    } label:{Label(selecting ? "\(selected.count)개 공연 이동" : "새 공연 준비",systemImage:selecting ? "folder" : "plus").font(.headline).frame(maxWidth:.infinity,minHeight:52).foregroundStyle(.white).background(Color.hearInk,in:RoundedRectangle(cornerRadius:16))}
                        .disabled(model.busy || model.loading || (selecting && selected.isEmpty)).opacity(selecting && selected.isEmpty ? 0.4 : 1)
                        .padding(.horizontal,20).padding(.vertical,10).background(.regularMaterial)
                }
            }
            .alert("이 장소를 삭제할까요?",isPresented:$confirmDelete) {
                Button("취소",role:.cancel) {}
                Button("장소 삭제",role:.destructive) {
                    guard let place else {return}
                    Task {if await model.update({try await model.store.deletePlace(place.id)}) {dismiss()}}
                }
            } message:{Text("장소와 하위 폴더만 삭제합니다. 저장된 공연은 모두 장소 미지정으로 이동하며 스캔·동선·기록은 유지됩니다.")}
            .task {if let place {await model.visit(place.id)}}
    }
}
