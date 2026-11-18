import SwiftUI
import UIKit
import HearIAmCore

/// 공연 공유 · 장면 공유: what goes into the file and how big it is, then the system share sheet.
struct StageShareSendSheet: View {
    enum Target: Hashable, Identifiable {
        case performance(UUID), scene(UUID)
        var id: Self { self }
    }
    @ObservedObject var library: StageLibrary
    let target: Target
    @State private var building=false
    @State private var outgoing: StageShareOutgoing?
    /// The file last made, removed however its share sheet closes (a swipe down reports nothing).
    @State private var made: StageShareOutgoing?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var summary: StageShareSummary? {
        switch target {
        case .performance(let id): library.shareSummary(performanceID:id)
        case .scene(let id): library.shareSummary(sceneID:id)
        }
    }
    private var performanceID: UUID? { if case let .performance(id)=target { id } else { nil } }

    var body: some View {
        ScrollView {
            if let summary {
                VStack(alignment:.leading,spacing:16) {
                    StageShareHeaderCard(title:summary.title,detail:detail(summary),systemImage:summary.kind == .performance ? "folder" : "cube")
                    if summary.kind == .performance {
                        Text(L("함께 보내는 것")).font(HearFont.pretendard(.semibold,size:14)).foregroundStyle(HearV3.secondary).padding(.horizontal,4)
                        contents(summary)
                    } else {
                        sceneFacts
                    }
                    StageShareNote(text:L("연습 · 공연 기록은 보내지 않아요. 확인점이 하나인 이전 장면은 안내가 안 돼서 빼고 보내요."))
                }.padding(.horizontal,16).padding(.top,12).padding(.bottom,24)
            } else {
                ContentUnavailableView(L("공유할 내용을 찾을 수 없어요"),systemImage:"square.and.arrow.up").padding(.top,80)
            }
        }
        .safeAreaInset(edge:.bottom,spacing:0) { if let summary { footer(summary) } }
        .hearTopBar(target.isPerformance ? L("공연 공유") : L("장면 공유"),sheet:true) {
            Button {dismiss()} label: {HearTopButtonLabel(systemImage:"xmark")}
                .buttonStyle(.plain).disabled(building).accessibilityLabel(L("닫기"))
        } trailing: {EmptyView()}
        .hearSheet()
        .interactiveDismissDisabled(building)
        .sheet(item:$outgoing,onDismiss:{ if let made {StageLibrary.removeShareFile(made);self.made=nil} }) { file in
            StageShareActivityView(url:file.url) {completed in
                outgoing=nil
                if completed {dismiss()}
            }.presentationDetents([.medium,.large]).ignoresSafeArea()
        }
        .alert(L("공유 파일을 만들지 못했어요"),isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) {
            Button(L("확인"),role:.cancel) {error=nil}
        } message: {Text(error ?? "")}
    }

    private func detail(_ summary: StageShareSummary) -> String {
        if summary.kind == .scene {
            return [library.catalog.folder(for:summary.scenes[0].id)?.name,summary.spaces.first?.id == nil ? nil : summary.spaces.first?.name]
                .compactMap {$0}.joined(separator:" · ")
        }
        let spaces=summary.spaces.filter {$0.id != nil}.count
        return L("공간 %@ · 장면 %@ · 기본 동선 %@", spaces, summary.sendable.count, summary.planCount)
    }

    private func contents(_ summary: StageShareSummary) -> some View {
        VStack(alignment:.leading,spacing:0) {
            if summary.planCount>0 {
                HStack(spacing:12) {
                    Image(systemName:"point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(HearV3.accent).accessibilityHidden(true)
                    Text(L("기본 동선")).font(HearFont.pretendard(.regular,size:16))
                    Spacer()
                    Text(L("%@개", summary.planCount)).font(HearFont.pretendard(.regular,size:14)).foregroundStyle(HearV3.secondary)
                }.padding(.horizontal,18).padding(.vertical,14)
                Divider().overlay(.white.opacity(0.08))
            }
            ForEach(Array(summary.spaces.enumerated()),id:\.offset) { index,space in
                Text(space.name).font(HearFont.pretendard(.semibold,size:16)).padding(.horizontal,18).padding(.top,14).padding(.bottom,4)
                ForEach(space.scenes) { scene in
                    HStack {
                        Text(scene.name).strikethrough(!scene.shareable)
                        Spacer()
                        Text(scene.shareable ? Self.size(scene.bytes) : L("확인점 1개 · 안 보냄")).font(.caption).foregroundStyle(HearV3.secondary)
                    }.font(HearFont.pretendard(.regular,size:15)).foregroundStyle(scene.shareable ? .white.opacity(0.85) : HearV3.secondary)
                        .padding(.leading,30).padding(.trailing,18).padding(.vertical,6)
                        .accessibilityElement(children:.combine)
                }
                if index<summary.spaces.count-1 { Divider().overlay(.white.opacity(0.08)).padding(.top,8) }
            }
            Spacer().frame(height:10)
        }.background(HearV3.surface,in:RoundedRectangle(cornerRadius:18,style:.continuous))
    }

    /// One scene: what its file carries.
    private var sceneFacts: some View {
        let record=summary?.scenes.first.flatMap {scene in library.records.first {$0.id==scene.id}}
        let facts=[L("공간 지도 · 메시"),L("동선 · 지점 %@개", record?.route?.points.count ?? 0),
                   L("기물 %@개 · 확인점 2개", record?.route?.obstacles.count ?? 0),L("현장 사진 %@장", record?.photos.count ?? 0)]
        return LazyVGrid(columns:[GridItem(.flexible(),spacing:8),GridItem(.flexible(),spacing:8)],spacing:8) {
            ForEach(facts,id:\.self) { fact in
                Text(fact).font(HearFont.pretendard(.regular,size:14)).foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,14).padding(.vertical,12)
                    .background(HearV3.surface,in:RoundedRectangle(cornerRadius:14,style:.continuous))
            }
        }
    }

    private func footer(_ summary: StageShareSummary) -> some View {
        VStack(spacing:12) {
            HStack {
                Text(L("보낼 파일")).foregroundStyle(HearV3.secondary)
                Spacer()
                Text("\(summary.fileName) · \(Self.size(summary.bytes))").fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            }.font(HearFont.pretendard(.regular,size:14)).padding(.horizontal,4)
            Button(action:{share(summary)}) {
                if building { ProgressView().tint(HearV3.canvas) }
                else { Label(L("공유하기"),systemImage:"square.and.arrow.up") }
            }.buttonStyle(V3PrimaryButtonStyle()).disabled(building || summary.sendable.isEmpty)
                .accessibilityIdentifier("share.send")
        }.padding(.horizontal,16).padding(.top,12).padding(.bottom,12)
    }

    private func share(_ summary: StageShareSummary) {
        building=true
        Task {
            defer {building=false}
            do {
                let file=try await library.makeShareFile(summary,performanceID:performanceID)
                made=file; outgoing=file
            }
            catch { self.error=error.localizedDescription }
        }
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)
    }
}

private extension StageShareSendSheet.Target {
    var isPerformance: Bool { if case .performance=self { true } else { false } }
}

/// The card at the top of both share flows: an icon, the name and one line of what it holds.
struct StageShareHeaderCard: View {
    let title: String
    let detail: String
    let systemImage: String
    var body: some View {
        HStack(spacing:14) {
            Image(systemName:systemImage).font(.system(size:22,weight:.regular)).frame(width:48,height:48)
                .background(HearV3.raised,in:RoundedRectangle(cornerRadius:14,style:.continuous)).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:2) {
                Text(title).font(HearFont.pretendard(.semibold,size:20)).lineLimit(2)
                if !detail.isEmpty { Text(detail).font(HearFont.pretendard(.regular,size:14)).foregroundStyle(HearV3.secondary) }
            }
            Spacer(minLength:0)
        }.padding(16).background(HearV3.surface,in:RoundedRectangle(cornerRadius:18,style:.continuous))
            .accessibilityElement(children:.combine)
    }
}

/// A grey line with an info mark, under the lists of both share flows.
struct StageShareNote: View {
    let text: String
    var systemImage="info.circle"
    var tint: Color=HearV3.secondary
    var body: some View {
        HStack(alignment:.top,spacing:8) {
            Image(systemName:systemImage).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).fixedSize(horizontal:false,vertical:true)
        }.font(HearFont.pretendard(.regular,size:13)).foregroundStyle(HearV3.secondary).lineSpacing(2).padding(.horizontal,4)
    }
}

/// The system share sheet (AirDrop, Messages, Files). `onFinish` gets whether something was sent.
struct StageShareActivityView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller=UIActivityViewController(activityItems:[url],applicationActivities:nil)
        controller.completionWithItemsHandler={_,completed,_,_ in onFinish(completed)}
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
