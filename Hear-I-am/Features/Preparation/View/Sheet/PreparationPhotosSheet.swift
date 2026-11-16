import SwiftUI
import HearIAmCore

struct PreparationPhotosSheet: View {
    @ObservedObject var model: PreparationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    private var selected: ScanPhotoSource? {
        model.session.photoSources.first {$0.photo.id==selectedID} ?? model.session.photoSources.first
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:14) {
                    if let selected {
                        if let image=UIImage(contentsOfFile:selected.imageURL.path) {
                            Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:260)
                        }
                        Text(L("스캔 당시 사진")).font(.headline)
                        Text(selected.photo.capturedAt,format:.dateTime.hour().minute().second()).font(.caption)
                        Menu {
                            Button(L("연결 없음")) {link(selected,nil,nil)}
                            ForEach(model.draft.objects) {o in Button(o.name) {link(selected,o.id,nil)}}
                            let labels=model.draft.routePointLabels
                            ForEach(model.draft.route.indices,id:\.self) {i in Button(labels.indices.contains(i) ? labels[i] : L("%@번 지점", i+1)) {link(selected,nil,i)}}
                        } label:{Label(linkTitle(selected.photo),systemImage:"link")}
                        Button(L("이 사진 삭제"),role:.destructive) {model.session.deletePhoto(selected.photo.id);selectedID=nil}
                        ScrollView(.horizontal) {
                            LazyHStack {
                                ForEach(model.session.photoSources,id:\.photo.id) {source in
                                    Button {selectedID=source.photo.id} label:{
                                        if let image=UIImage(contentsOfFile:source.thumbnailURL.path) {
                                            Image(uiImage:image).resizable().scaledToFit().frame(width:110,height:80)
                                                .overlay(RoundedRectangle(cornerRadius:8).stroke(selected.photo.id==source.photo.id ? Color.hearGreen : .clear,lineWidth:3))
                                        }
                                    }.accessibilityLabel(L("촬영 사진 선택"))
                                }
                            }.padding(4)
                        }
                        Text(L("사진은 공간을 최종 저장할 때 함께 보관돼요. 연결할 기물이나 지점은 등록 후 선택할 수 있어요."))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {ContentUnavailableView(L("촬영한 사진이 없어요"),systemImage:"photo")}
                }.padding()
            }.navigationTitle(L("현장 사진")).navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.confirmationAction) {Button(L("닫기")) {dismiss()}}}
        }
    }
    func link(_ source: ScanPhotoSource,_ object: UUID?,_ point: Int?) {model.session.linkPhoto(source.photo.id,objectID:object,routeIndex:point)}
    func linkTitle(_ photo: ScanPhoto) -> String {
        if let id=photo.objectID,let o=model.draft.objects.first(where:{$0.id==id}) {return L("연결: ")+o.name}
        let labels=model.draft.routePointLabels
        if let index=photo.routePointIndex,model.draft.route.indices.contains(index) {return L("연결: ")+(labels.indices.contains(index) ? labels[index] : L("%@번 지점", index+1))}
        return L("기물·지점 연결")
    }
}
