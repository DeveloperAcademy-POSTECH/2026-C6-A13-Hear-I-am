import SwiftUI
import HearIAmCore

/// One completed run. A run with a saved replay fills the page with it (Figma 971:31085); an older run without one
/// keeps its plan and numbers. The scene chip switches between runs on the same stage; ⋯ can delete this one.
struct GuidanceRecordDetail: View {
    var library: StageLibrary?
    @State private var current: GuidanceRecord
    @State private var deleting=false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(record: GuidanceRecord,library: StageLibrary? = nil) {
        self.library=library;_current=State(initialValue:record)
    }
    var body: some View {
        Group {
            if let replay=current.replay {
                GuidanceReplayView(record:current,replay:replay,sceneChip:AnyView(sceneChip),
                                   onDelete:library == nil ? nil : {deleting=true}).id(current.id)
            } else {
                ScrollView {legacySummary.padding(20)}.v3Screen()
                    .hearTopBar(center:{sceneChip}) {HearBackButton()} trailing: {
                        if library != nil {
                            Menu {
                                Button(role:.destructive) {deleting=true} label: {Label(L("현재 기록 삭제"),systemImage:"trash")}
                            } label: {HearTopButtonLabel(systemImage:"ellipsis")}.buttonStyle(.plain).accessibilityLabel(L("기록 메뉴"))
                        }
                    }
            }
        }
        .toolbar(.hidden,for:.tabBar)
        .hearConfirm(L("이 기록을 삭제할까요?"),isPresented:$deleting,
                     message:L("%@ 기록이 삭제돼요.\n삭제한 기록은 복구할 수 없어요.", Self.dateLabel(current))) {delete()}
        .alert(L("삭제하지 못했어요"),isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) {
            Button(L("확인"),role:.cancel) {error=nil}
        } message: {Text(error ?? "")}
    }
    /// Runs on the same stage, newest first; this one alone when the page has no library.
    private var siblings: [GuidanceRecord] {
        let all=library?.guidanceRecords.filter {$0.stageID == current.stageID} ?? []
        return all.contains {$0.id == current.id} ? all.sorted {$0.completedAt > $1.completedAt} : [current]
    }
    /// 971:31106: the clapper, the scene's name and a small round chevron on 5% glass.
    private var sceneChip: some View {
        Menu {
            Section(current.stageName) {
                ForEach(siblings) {record in
                    Button {current=record} label: {
                        if record.id == current.id {Label(Self.dateLabel(record),systemImage:"checkmark")}
                        else {Text(Self.dateLabel(record))}
                    }
                }
            }
        } label: {
            HStack(spacing:12) {
                Image(systemName:"movieclapper").font(.system(size:15,weight:.medium))
                Text(current.stageName).font(.system(size:12,weight:.semibold)).lineLimit(1)
                Image(systemName:"chevron.down").font(.system(size:9,weight:.bold))
                    .frame(width:18,height:18).background(.white.opacity(0.2),in:Circle())
            }.foregroundStyle(.white).padding(.horizontal,14).frame(height:44)
                .liquidGlass(Capsule(),tint:.white.opacity(0.05),interactive:true)
        }.buttonStyle(.plain)
            .accessibilityLabel(L("%@, %@ 기록, 같은 장면의 다른 기록 고르기", current.stageName, Self.dateLabel(current)))
    }
    static func dateLabel(_ record: GuidanceRecord) -> String {
        record.completedAt.formatted(.dateTime.locale(HearLanguage.current.locale).month().day().hour().minute())
    }
    private func delete() {
        guard let library else {return}
        let id=current.id
        Task {
            do {try await library.deleteGuidanceRecord(id);dismiss()}
            catch {self.error=error.localizedDescription}
        }
    }
    private var legacySummary: some View {
        VStack(alignment:.leading,spacing:20) {
            StageMap(width:current.route.area.width,depth:current.route.area.depth,points:current.guidancePath,objects:current.route.obstacles,dangerZones:current.route.dangerZones)
                .frame(height:220).accessibilityLabel(L("완료한 안내의 저장 동선"))
            Label(L("이 기록에는 실제 이동 위치가 저장되어 있지 않아요."),systemImage:"clock.badge.questionmark")
                .font(.subheadline).foregroundStyle(HearV3.secondary)
            VStack(spacing:18) {
                metric(L("안내 시간"),GuidanceRecordRow.durationLabel(current.activeSeconds))
                Divider()
                metric(L("도착한 지점"),L("%@곳", current.reachedPointCount))
                Divider()
                metric(L("안내 경로 길이"),String(format:"%.1f m",current.guidanceRouteLength))
            }.padding(20).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:20,style:.continuous))
        }
    }
    private func metric(_ title: String,_ value: String) -> some View {
        HStack {Text(title).foregroundStyle(HearV3.secondary);Spacer();Text(value).font(.title3.bold()).monospacedDigit()}
    }
}
