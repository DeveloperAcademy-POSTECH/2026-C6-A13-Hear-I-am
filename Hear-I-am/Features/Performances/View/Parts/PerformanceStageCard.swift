import SwiftUI
import HearIAmCore

/// Body and start action are separate controls, so inspecting a stage never starts guidance.
struct PerformanceStageCard: View {
    let record: ScanManifest
    let venueName: String
    @ObservedObject var library: StageLibrary
    let onStartGuidance: (UUID) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:14)) : AnyLayout(HStackLayout(alignment:.center,spacing:12))) {
            NavigationLink {
                SavedStagePreview(record:record,store:library.scans)
                    .onDisappear {Task {await library.refresh()}}
            } label: {
                HStack(spacing:12) {
                    if !typeSize.isAccessibilitySize {
                        PerformanceStageThumbnail(record:record,library:library).frame(width:72,height:80).clipShape(RoundedRectangle(cornerRadius:16)).accessibilityHidden(true)
                    }
                    VStack(alignment:.leading,spacing:6) {
                        Text(venueName).font(.headline)
                        Text(record.name).font(.subheadline).foregroundStyle(HearV3.secondary)
                        Text("\(record.route?.points.count ?? 0)지점 · 확인점 \(record.secondCheckpoint == nil ? 1 : 2)개").font(.caption).foregroundStyle(HearV3.secondary)
                        Text(record.date,format:.dateTime.year().month().day()).font(.caption).foregroundStyle(HearV3.secondary)
                        if !record.supportsAlignment {Text("안내하려면 확인점 2개가 있는 새 스캔이 필요해요.").font(.caption).foregroundStyle(.orange)}
                        else if record.route == nil {Text("저장된 동선이 없어 안내할 수 없어요.").font(.caption).foregroundStyle(.orange)}
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(venueName), \(record.name), 정리해서 보기").accessibilityIdentifier("performance.stage.preview.\(record.id.uuidString)")
            Button {onStartGuidance(record.id)} label: {
                Label("안내 시작",systemImage:"arrow.up.right").font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal:false,vertical:true).padding(.horizontal,14).frame(minHeight:48)
                    .background(HearV3.text,in:RoundedRectangle(cornerRadius:18)).foregroundStyle(HearV3.canvas)
            }.buttonStyle(.plain).accessibilityLabel("\(venueName), \(record.name), 실전 안내 준비 시작").accessibilityIdentifier("performance.stage.start.\(record.id.uuidString)")
                .accessibilityHint("조력자가 공간과 확인점 두 개를 확인한 뒤 안내를 시작해요.")
                .disabled(!record.supportsAlignment || record.route == nil)
        }.v3Card(inset:16)
    }
}

struct PerformanceStageThumbnail: View {
    let record: ScanManifest
    @ObservedObject var library: StageLibrary
    var body: some View {
        Group {
            if let photo=record.photos.first {SavedPhotoImage(store:library.scans,scanID:record.id,photo:photo)}
            else {
                StageMap(showsLabels:false,width:record.route?.area.width ?? 12,depth:record.route?.area.depth ?? 8,points:record.route?.points ?? [],objects:record.route?.obstacles ?? [],dangerZones:record.route?.dangerZones ?? [],v3Style:true)
            }
        }.background(HearV3.raised)
    }
}
