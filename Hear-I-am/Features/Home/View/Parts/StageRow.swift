import SwiftUI
import HearIAmCore

struct StageRow: View {
    let record: ScanManifest
    @ObservedObject var library: StageLibrary
    let onRename: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:12) {
                StageMap(showsLabels:false,width:record.route?.area.width ?? 12,depth:record.route?.area.depth ?? 8,points:record.route?.points ?? [],objects:record.route?.obstacles ?? [])
                    .frame(width:92,height:92).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:6) {
                    Button(action:onRename) {
                        HStack(alignment:.firstTextBaseline,spacing:5) {
                            Text(record.name).font(.headline).lineLimit(2)
                            Image(systemName:"pencil").font(.caption).foregroundStyle(.secondary)
                        }.frame(minHeight:44,alignment:.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(record.name) 이름 변경")
                    Text("내부 지점 \(max(0,(record.route?.points.count ?? 2)-2))개 · 기물 \(record.route?.obstacles.count ?? 0)개").font(.caption).foregroundStyle(.secondary)
                    Text(record.date,format:.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
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
