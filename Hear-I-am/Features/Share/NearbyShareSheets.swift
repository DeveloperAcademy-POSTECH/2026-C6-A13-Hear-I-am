import SwiftUI
import MultipeerConnectivity
import HearIAmCore

/// What the app does once a received file is saved: open its performance and say what was saved. Set by the root.
private struct HearShareSavedKey: EnvironmentKey { static let defaultValue: ((StageShareResult) -> Void)? = nil }
extension EnvironmentValues {
    var hearShareSaved: ((StageShareResult) -> Void)? {
        get {self[HearShareSavedKey.self]}
        set {self[HearShareSavedKey.self]=newValue}
    }
}

/// 근처 폰으로 보내기: the phones showing 「근처에서 받기」, then the file goes to the one picked.
struct NearbySendSheet: View {
    let file: StageShareOutgoing
    let offer: NearbyStageShare.Offer
    let onSent: () -> Void
    @StateObject private var nearby=NearbyStageShare()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                StageShareHeaderCard(title:offer.title,detail:StageShareSendSheet.size(offer.bytes),systemImage:"dot.radiowaves.left.and.right")
                switch nearby.phase {
                case .asking(let name,_):
                    NearbyStatusCard(systemImage:"hourglass",title:L("‘%@’에서 받기를 기다리는 중이에요", name),detail:L("받는 폰 화면에서 「받기」를 눌러 주세요."))
                case .transferring(let value):
                    NearbyProgressCard(title:L("보내는 중이에요"),value:value)
                case .done:
                    NearbyStatusCard(systemImage:"checkmark.circle.fill",title:L("보냈어요"),detail:L("받는 폰에서 저장할 곳을 고르면 끝나요."),tint:HearV3.accent)
                case .failed(let message):
                    NearbyStatusCard(systemImage:"exclamationmark.triangle",title:L("보내지 못했어요"),detail:message,tint:.orange)
                    Button(L("다시 고르기")) {nearby.reset()}.buttonStyle(V3PrimaryButtonStyle())
                default:
                    peerList
                }
            }.padding(.horizontal,16).padding(.top,12).padding(.bottom,24)
        }
        .safeAreaInset(edge:.bottom,spacing:0) {
            if nearby.phase == .done {
                Button(L("완료")) {onSent()}.buttonStyle(V3PrimaryButtonStyle()).padding(16)
            }
        }
        .hearTopBar(L("근처 폰으로 보내기"),sheet:true) {
            Button {dismiss()} label: {HearTopButtonLabel(systemImage:"xmark")}.buttonStyle(.plain).accessibilityLabel(L("닫기"))
        } trailing: {EmptyView()}
        .hearSheet()
        .interactiveDismissDisabled(isSending)
        .onAppear {nearby.startBrowsing()}
        .onDisappear {nearby.stop()}
    }

    private var isSending: Bool { if case .transferring=nearby.phase { true } else { false } }

    private var peerList: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(L("받을 폰")).font(HearFont.pretendard(.semibold,size:14)).foregroundStyle(HearV3.secondary).padding(.horizontal,4)
            if nearby.peers.isEmpty {
                HStack(spacing:12) {
                    ProgressView()
                    Text(L("근처 폰을 찾는 중이에요")).font(HearFont.pretendard(.regular,size:15)).foregroundStyle(HearV3.secondary)
                }.frame(maxWidth:.infinity,minHeight:72).background(HearV3.surface,in:RoundedRectangle(cornerRadius:16,style:.continuous))
            } else {
                ForEach(nearby.peers,id:\.self) { peer in
                    Button {nearby.send(file.url,offer:offer,to:peer)} label: {
                        HStack(spacing:12) {
                            Image(systemName:"iphone").font(.system(size:20)).frame(width:40,height:40)
                                .background(HearV3.raised,in:Circle())
                            Text(peer.displayName).font(HearFont.pretendard(.medium,size:16))
                            Spacer()
                            Image(systemName:"arrow.up.circle.fill").font(.system(size:24)).foregroundStyle(HearV3.accent)
                        }.padding(.horizontal,16).padding(.vertical,12)
                            .background(HearV3.surface,in:RoundedRectangle(cornerRadius:16,style:.continuous)).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(L("%@에 보내기", peer.displayName))
                }
            }
            StageShareNote(text:L("받을 폰에서 Hear I am을 열고 공연 관리 위의 받기 버튼을 누르면 여기에 나타나요. 두 폰 모두 Wi-Fi와 블루투스가 켜져 있어야 해요."))
                .padding(.top,4)
        }
    }
}

/// 근처에서 받기: this phone is visible until a file arrives, then the usual 받은 공연 steps follow in the same sheet.
struct NearbyReceiveSheet: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var nearby=NearbyStageShare()
    @State private var incoming: StageShareIncoming?
    @Environment(\.hearShareSaved) private var shareSaved
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let incoming {
            StageShareReceiveSheet(library:library,incoming:incoming) {result,_ in shareSaved?(result)}
        } else {
            waiting
                .onAppear {
                    nearby.onReceived={incoming=$0}
                    nearby.startReceiving()
                }
                .onDisappear {nearby.stop()}
        }
    }

    private var waiting: some View {
        ScrollView {
            VStack(spacing:20) {
                switch nearby.phase {
                case .transferring(let value):
                    NearbyProgressCard(title:L("받는 중이에요"),value:value).padding(.top,40)
                case .failed(let message):
                    NearbyStatusCard(systemImage:"exclamationmark.triangle",title:L("받지 못했어요"),detail:message,tint:.orange).padding(.top,40)
                    Button(L("다시 기다리기")) {nearby.stop(); nearby.startReceiving()}.buttonStyle(V3PrimaryButtonStyle())
                default:
                    NearbyRadar().frame(width:180,height:180).padding(.top,36)
                    VStack(spacing:8) {
                        Text(L("받을 준비가 됐어요")).font(HearFont.pretendard(.semibold,size:22))
                        Text(L("보내는 폰에서 ‘%@’을 골라 주세요.", nearby.name)).font(HearFont.pretendard(.regular,size:15))
                            .foregroundStyle(HearV3.secondary).multilineTextAlignment(.center)
                    }
                    StageShareNote(text:L("이 화면을 열어 둔 동안에만 근처 폰에 보여요. 보내 온 파일은 「받기」를 눌러야 받아요."))
                }
            }.padding(.horizontal,16).padding(.bottom,24).frame(maxWidth:.infinity)
        }
        .hearTopBar(L("근처에서 받기"),sheet:true) {
            Button {dismiss()} label: {HearTopButtonLabel(systemImage:"xmark")}.buttonStyle(.plain).accessibilityLabel(L("닫기"))
        } trailing: {EmptyView()}
        .hearSheet()
        .overlay {
            if case let .asking(name,offer)=nearby.phase {
                HearConfirmAlert(title:L("‘%@’이 보낸 파일", name),
                                 message:L("‘%@’ · %@\n받은 뒤에 저장할 것을 고를 수 있어요.", offer.title, StageShareSendSheet.size(offer.bytes)),
                                 confirm:L("받기"),onCancel:{nearby.answer(false)},onConfirm:{nearby.answer(true)})
            }
        }
    }
}

struct NearbyStatusCard: View {
    let systemImage: String
    let title: String
    let detail: String
    var tint: Color=HearV3.text
    var body: some View {
        HStack(alignment:.top,spacing:14) {
            Image(systemName:systemImage).font(.system(size:22)).foregroundStyle(tint).frame(width:28)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(HearFont.pretendard(.semibold,size:17)).fixedSize(horizontal:false,vertical:true)
                Text(detail).font(HearFont.pretendard(.regular,size:14)).foregroundStyle(HearV3.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:0)
        }.padding(18).background(HearV3.surface,in:RoundedRectangle(cornerRadius:18,style:.continuous))
            .accessibilityElement(children:.combine)
    }
}

struct NearbyProgressCard: View {
    let title: String
    let value: Double
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(title).font(HearFont.pretendard(.semibold,size:17))
                Spacer()
                Text("\(Int((value*100).rounded()))%").font(HearFont.pretendard(.medium,size:15)).monospacedDigit().foregroundStyle(HearV3.secondary)
            }
            ProgressView(value:value).tint(HearV3.accent)
        }.padding(18).background(HearV3.surface,in:RoundedRectangle(cornerRadius:18,style:.continuous))
            .accessibilityElement(children:.combine)
    }
}

/// Rings spreading from the phone while it waits to be found.
struct NearbyRadar: View {
    @State private var spreading=false
    var body: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle().stroke(HearV3.accent.opacity(0.5),lineWidth:1.5)
                    .scaleEffect(spreading ? 1 : 0.3).opacity(spreading ? 0 : 0.9)
                    .animation(.easeOut(duration:2.4).repeatForever(autoreverses:false).delay(Double(ring)*0.8),value:spreading)
            }
            Image(systemName:"iphone.radiowaves.left.and.right").font(.system(size:40,weight:.regular)).foregroundStyle(.white)
        }.onAppear {spreading=true}.accessibilityHidden(true)
    }
}
