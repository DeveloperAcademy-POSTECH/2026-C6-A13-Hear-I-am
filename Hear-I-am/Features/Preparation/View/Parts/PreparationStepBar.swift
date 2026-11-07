import SwiftUI

/// Shared look of the scan screen (Figma 「쿄조_설정,스캔, 보이스」 452:10996): Liquid Glass over the camera,
/// tinted as the design's fills are. Sizes are the design's: 44pt round buttons, 48pt step capsule, 42pt cards.
enum ScanChrome {
    static let buttonTint=Color.black.opacity(0.1)                                  // round buttons, tool group
    static let capsuleTint=Color(red:206/255,green:206/255,blue:206/255).opacity(0.1) // step capsule
    static let panelTint=Color.black.opacity(0.2)                                   // right panel, chips
    static let cardTint=Color.black.opacity(0.5)                                    // intro and review cards
    static let selected=Color.black.opacity(0.3)                                    // selected step chip
    static let primary=Color.black.opacity(0.77)                                    // 「스캔 완료」
    static let illustration=Color(red:34/255,green:35/255,blue:39/255)              // #222327
    static let close=Color(red:29/255,green:29/255,blue:29/255)                     // #1D1D1D
    static let danger=Color(red:159/255,green:50/255,blue:50/255)                   // #9F3232
    static let secondary=Color(red:235/255,green:235/255,blue:245/255).opacity(0.7)
    static let darkText=Color(red:38/255,green:38/255,blue:38/255)                  // #262626
    static let alert=Color(red:44/255,green:44/255,blue:46/255)                     // dark alert card
    static let accent=Color(red:10/255,green:132/255,blue:1)                        // #0A84FF
    /// The design's add-object symbol (452:13124); older symbol sets fall back to the box.
    static var addObjectSymbol: String {
        UIImage(systemName:"homepod.and.homepod.mini.badge.plus.fill") != nil ? "homepod.and.homepod.mini.badge.plus.fill" : "shippingbox.fill"
    }
}

/// A round glass button's face: back, help, more, camera and undo.
struct ScanCircleLabel: View {
    let systemImage: String
    var size: CGFloat=44
    var body: some View {
        Image(systemName:systemImage).font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
            .frame(width:size,height:size)
            .liquidGlass(Circle(),tint:ScanChrome.buttonTint,interactive:true)
            .contentShape(Circle())
    }
}

struct ScanCircleButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat=44
    var enabled=true
    let action: () -> Void
    var body: some View {
        Button(action:action) {ScanCircleLabel(systemImage:systemImage,size:size)}
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.45)
            .accessibilityLabel(label)
    }
}

/// The 140×48 dark button at the bottom right that finishes the step (971:30334); 30% while it cannot.
struct ScanPrimaryButton: View {
    let title: String
    var enabled=true
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            Text(title).font(HearFont.pretendard(.bold,size:18)).tracking(-0.54).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width:140,height:48)
                .background(enabled ? ScanChrome.primary : Color.black.opacity(0.8),in:Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3)
    }
}

/// Pill buttons inside dark cards: white for the main choice, dim for the other, dark red text to delete.
/// Cards use the 44pt size; the side panel's footer the 30pt one.
struct ScanCardButton: View {
    let title: String
    var primary=true
    var destructive=false
    var enabled=true
    var compact=false
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            Text(title).font(HearFont.pretendard(compact ? .medium : .semibold,size:compact ? 16 : 17))
                .foregroundStyle(destructive ? ScanChrome.danger : (primary ? ScanChrome.darkText : .white))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth:.infinity).frame(height:compact ? 30 : 44)
                .background(primary ? Color.white : Color.white.opacity(destructive ? 0 : 0.1),in:Capsule())
                .background(destructive ? Color.black.opacity(0.1) : .clear,in:Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }
}

extension View {
    /// Dark glass card behind the intro, review and plan cards (Figma: radius 42, black 50%).
    func scanCard(cornerRadius: CGFloat=42) -> some View {
        liquidGlass(RoundedRectangle(cornerRadius:cornerRadius,style:.continuous),tint:ScanChrome.cardTint)
            .environment(\.colorScheme,.dark)
    }
}

/// Top row: back, the step capsule, help and more.
struct PreparationStepBar: View {
    @ObservedObject var model: PreparationViewModel
    let exit: () -> Void
    @State private var expanded=false
    var body: some View {
        HStack(alignment:.top) {
            ScanCircleButton(systemImage:"chevron.backward",label:"나가기",enabled:!model.busy,action:exit)
            Spacer(minLength:12)
            VStack(spacing:8) {
                stepCapsule
                if model.step == .checkpoint {checkpointDots}
                if let hint=model.showsCrosshairHint {
                    Text(hint).font(.system(size:14)).foregroundStyle(!model.aimBlocked ? Color.white : Color(red:1,green:0.45,blue:0.45))
                        .multilineTextAlignment(.center).lineLimit(2)
                        .padding(.horizontal,14).padding(.vertical,7).liquidGlass(Capsule(),tint:ScanChrome.panelTint)
                        .frame(maxWidth:364)
                }
            }
            Spacer(minLength:12)
            HStack(spacing:10) {
                ScanCircleButton(systemImage:"questionmark",label:"단계 안내 다시 보기") {model.intro=0}
                moreMenu
            }
        }
    }

    /// The step capsule (971:28584 · 971:28313): every step in a row that scrolls sideways, 153pt wide folded and
    /// 316pt open, the current step centred and the row fading toward both ends (memo 971:30301). Tapping the
    /// current step opens or folds it; another step, when reachable, goes there.
    private var stepCapsule: some View {
        ScrollViewReader {proxy in
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:0) {
                    ForEach(PreparationStep.allCases,id:\.self) {s in
                        let current=s == model.step
                        Button {
                            if current {withAnimation(.snappy) {expanded.toggle()}}
                            else {model.changeStep(s);withAnimation(.snappy) {expanded=false}}
                        } label: {
                            Text(s.title).font(HearFont.pretendard(.medium,size:18)).tracking(-0.54).lineLimit(1)
                                .foregroundStyle(.white.opacity(current || model.canSelect(s) ? 1 : 0.45))
                                .padding(.horizontal,14).frame(height:30)
                                .background(current ? ScanChrome.selected : .clear,in:Capsule())
                                .contentShape(Capsule())
                        }.buttonStyle(.plain).disabled(!current && !model.canSelect(s)).id(s)
                            .accessibilityLabel("\(s.rawValue+1)단계 \(s.title)\(model.isComplete(s) ? ", 완료" : "")\(current ? ", 현재 단계" : "")")
                    }
                }.padding(.horizontal,8).frame(maxHeight:.infinity)
            }
            .mask {
                LinearGradient(stops:[.init(color:.black.opacity(0.3),location:0),.init(color:.black,location:0.2),
                                      .init(color:.black,location:0.8),.init(color:.black.opacity(0.3),location:1)],
                               startPoint:.leading,endPoint:.trailing)
            }
            .frame(width:expanded ? 316 : 153,height:expanded ? 46 : 48)
            .liquidGlass(Capsule(),tint:ScanChrome.capsuleTint)
            .clipShape(Capsule())
            .onAppear {proxy.scrollTo(model.step,anchor:.center)}
            .onChange(of:model.step) {_,step in withAnimation(.snappy(duration:0.35)) {proxy.scrollTo(step,anchor:.center)}}
            .onChange(of:expanded) {_,_ in
                Task { @MainActor in
                    try? await Task.sleep(for:.seconds(0.05))
                    withAnimation(.snappy(duration:0.35)) {proxy.scrollTo(model.step,anchor:.center)}
                }
            }
        }
        .animation(.snappy(duration:0.35),value:expanded)
        .accessibilityHint(expanded ? "단계를 눌러 이동" : "현재 단계를 누르면 모든 단계가 펼쳐져요")
    }

    /// Filled as each checkpoint is set (452:13197).
    private var checkpointDots: some View {
        HStack(spacing:6) {
            ForEach(0..<2,id:\.self) {i in
                let set=i == 0 ? model.draft.checkpoint != nil : model.draft.secondCheckpoint != nil
                Text("\(i+1)").font(.system(size:13,weight:.bold)).foregroundStyle(set ? .black : .white)
                    .frame(width:24,height:24).background(set ? Color.white : Color.black.opacity(0.55),in:Circle())
            }
        }.padding(5).liquidGlass(Capsule(),tint:ScanChrome.panelTint)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("확인점 1번 \(model.draft.checkpoint == nil ? "미지정" : "지정"), 2번 \(model.draft.secondCheckpoint == nil ? "미지정" : "지정")")
    }

    /// 452:12878. Opens the dark glass panel drawn by PreparationView under this button.
    private var moreMenu: some View {
        ScanCircleButton(systemImage:"ellipsis",label:"더보기") {
            withAnimation(.snappy(duration:0.3)) {model.showingMore.toggle()}
        }
    }
}

/// The more panel (Figma 452:12878): a dark glass card of 44pt rows, each an icon, a title and, for the
/// display switches, a green toggle. The last row opens the app settings for testing.
struct PreparationMorePanel: View {
    @ObservedObject var model: PreparationViewModel
    let openSettings: () -> Void
    private static let label=Color(red:245/255,green:245/255,blue:245/255)
    private static let green=Color(red:48/255,green:209/255,blue:88/255)

    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            if model.step <= .objects && model.supportsMesh {
                toggleRow("eye","스캔 범위(매쉬) 표시",isOn:Binding(get:{model.showMesh},set:{model.showMesh=$0}))
            }
            if model.canShowPlanReference {
                toggleRow("square.on.square.dashed","참고 잔상 표시",isOn:$model.showPlanReference)
            }
            Button {
                withAnimation(.snappy(duration:0.3)) {model.showingMore=false}
                openSettings()
            } label: {
                row("gearshape","설정 바로가기(개발자 용)") {EmptyView()}
            }.buttonStyle(.plain)
        }
        .padding(.horizontal,16).padding(.vertical,8)
        .frame(width:330)
        .background {
            RoundedRectangle(cornerRadius:34,style:.continuous).fill(Color(white:26/255).opacity(0.34))
                .liquidGlass(RoundedRectangle(cornerRadius:34,style:.continuous),tint:Color(white:26/255).opacity(0.34))
                .shadow(color:.black.opacity(0.45),radius:24,y:8)
        }
        .overlay(RoundedRectangle(cornerRadius:34,style:.continuous).strokeBorder(Color(white:166/255).opacity(0.6),lineWidth:0.5))
        .environment(\.colorScheme,.dark)
    }

    private func toggleRow(_ symbol: String, _ title: String, isOn: Binding<Bool>) -> some View {
        row(symbol,title) {
            Toggle(title,isOn:isOn).labelsHidden().tint(Self.green)
        }
    }
    private func row<Trailing: View>(_ symbol: String, _ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing:8) {
            Image(systemName:symbol).font(.system(size:17)).foregroundStyle(Self.label).frame(width:28)
            Text(title).font(.system(size:17)).tracking(-0.43).foregroundStyle(Self.label).lineLimit(1)
            Spacer(minLength:6)
            trailing()
        }
        .padding(.leading,6).padding(.trailing,8).frame(height:44)
        .contentShape(Rectangle())
    }
}
