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

/// The 222×48 dark button at the bottom right that finishes the step.
struct ScanPrimaryButton: View {
    let title: String
    var enabled=true
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            Text(title).font(.system(size:18,weight:.bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width:222,height:48)
                .background(ScanChrome.primary,in:Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
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
            Text(title).font(.system(size:compact ? 16 : 17,weight:compact ? .medium : .semibold))
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

    /// 48pt glass capsule of 18pt chips; only the current step stands out. Tapping it opens every step (452:11199).
    private var stepCapsule: some View {
        HStack(spacing:0) {
            ForEach(visibleSteps,id:\.self) {s in
                let current=s == model.step
                Button {
                    if current {withAnimation(.snappy) {expanded.toggle()}}
                    else {model.changeStep(s);withAnimation(.snappy) {expanded=false}}
                } label: {
                    Text(s.title).font(.system(size:18,weight:.medium)).lineLimit(1)
                        .foregroundStyle(.white.opacity(current ? 1 : (model.canSelect(s) ? 0.85 : 0.45)))
                        .padding(.horizontal,14).frame(height:30)
                        .background(current ? ScanChrome.selected : .clear,in:Capsule())
                }.buttonStyle(.plain).disabled(!current && !model.canSelect(s))
                    .accessibilityLabel("\(s.rawValue+1)단계 \(s.title)\(model.isComplete(s) ? ", 완료" : "")\(current ? ", 현재 단계" : "")")
            }
        }.padding(.horizontal,9).frame(height:48)
            .liquidGlass(Capsule(),tint:ScanChrome.capsuleTint)
            .mask {
                if expanded {Capsule()}
                else {LinearGradient(stops:[.init(color:.black.opacity(0.35),location:0),.init(color:.black,location:0.25),.init(color:.black,location:0.75),.init(color:.black.opacity(0.35),location:1)],startPoint:.leading,endPoint:.trailing)}
            }
    }
    private var visibleSteps: [PreparationStep] {
        guard !expanded else {return PreparationStep.allCases}
        let i=model.step.rawValue
        return PreparationStep.allCases.filter {abs($0.rawValue-i) <= 1}
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

    /// 452:12878. Display switches only; the step's work stays on the bottom bar.
    private var moreMenu: some View {
        Menu {
            if model.step <= .objects && model.supportsMesh {
                Toggle(isOn:Binding(get:{model.showMesh},set:{model.showMesh=$0})) {Label("스캔 범위(메쉬) 표시",systemImage:"eye")}
            }
            if model.canShowPlanReference {
                Toggle(isOn:$model.showPlanReference) {Label("참고 잔상 표시",systemImage:"square.on.square.dashed")}
            }
            Text(model.supportsMesh ? "\(model.meshCount)개 표면 · \(model.mapping)" : "LiDAR 센서가 있어야 정확하게 측정돼요 · \(model.mapping)")
        } label: {
            ScanCircleLabel(systemImage:"ellipsis")
        }.accessibilityLabel("더보기")
    }
}
