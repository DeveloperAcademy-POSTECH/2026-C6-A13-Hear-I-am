import SwiftUI
import HearIAmCore

struct FrontDirectionPracticeView: View {
    @StateObject private var model = FrontDirectionPracticeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @AccessibilityFocusState private var issueFocused: Bool

    private var title: String {
        if !model.isRunning { return "연습을 잠시 멈췄어요" }
        switch model.practice.phase {
        case .needsReference: return "앞을 향해 서주세요"
        case .turnAway: return "몸을 조금 돌려보세요"
        case .finding: return "소리를 따라 정면을 찾아보세요"
        case .completed: return "방향이 맞았어요"
        }
    }
    private var instruction: String {
        switch model.practice.phase {
        case .needsReference: return "휴대폰을 실제 안내 때처럼 몸에 고정하고, 조력자와 함께 기준이 될 정면을 정해주세요."
        case .turnAway: return "발은 제자리에 두고 몸을 왼쪽이나 오른쪽으로 돌려보세요. 정면에서 충분히 벗어나면 방향 안내가 시작돼요."
        case .finding: return "낮은 톡은 왼쪽, 높은 톡은 오른쪽이에요. 정면에 가까워질수록 빨라지고, 방향이 맞으면 확인 소리가 들려요."
        case .completed: return "지정한 정면으로 돌아왔어요. 같은 방향으로 다시 연습하거나 새로운 정면을 지정할 수 있어요."
        }
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            FrontGlow(phase:model.isRunning ? model.practice.phase : .needsReference,
                      hasReference:model.isRunning && model.practice.referenceHeading != nil,
                      bearing:model.practice.bearing,
                      deadband:SignalPlayer.directionDeadbandDegrees)
                .ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing:16) {
                Text(title).font(.system(size:26,weight:.bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .frame(maxWidth:260).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
                Text(instruction).font(.system(size:20,weight:.medium)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                    .lineSpacing(4).frame(maxWidth:300).fixedSize(horizontal:false,vertical:true)
                if let issue = model.issue { TutorialPlaybackError(message: issue).accessibilityFocused($issueFocused).padding(.top,8) }
                else if model.isRunning, !model.canSetReference {
                    Label("몸 방향을 확인하고 있어요", systemImage: "iphone").font(.system(size:15)).foregroundStyle(SettingsStyle.secondary).padding(.top,8)
                }
                Spacer()
            }.padding(.horizontal,16).padding(.top,43)
        }
        .settingsBottomBar {
            VStack(spacing:8) {
                if let secondary=secondaryTitle {
                    SettingsCapsuleButton(title:secondary,primary:false) {secondaryAction()}
                        .accessibilityIdentifier("practice.reset")
                }
                if let primary=primaryTitle {
                    SettingsCapsuleButton(title:primary) {primaryAction()}
                        .disabled(model.isRunning && model.practice.phase == .needsReference && !model.canSetReference)
                        .opacity(model.isRunning && model.practice.phase == .needsReference && !model.canSetReference ? 0.4 : 1)
                        .accessibilityIdentifier("practice.primary")
                }
            }
        }
        .settingsScreen()
        .navigationTitle("정면 찾기").navigationBarTitleDisplayMode(.inline)
        .onAppear { visible = true; model.start() }
        .onDisappear { visible = false; model.close() }
        .onChange(of: scenePhase) { _, phase in
            guard visible else { return }
            if phase == .active { model.start() }
            else { model.suspend("연습을 잠시 멈췄어요. 다시 정면을 지정해주세요.") }
        }
        .onChange(of: model.issue) { _, issue in
            if issue != nil { issueFocused = true }
        }
    }
    /// Figma 457:13594 · 13609: white 「이 방향을 정면으로 지정」 first, then a dark button to set it again.
    private var primaryTitle: String? {
        if !model.isRunning { return "다시 시작" }
        switch model.practice.phase {
        case .needsReference: return "이 방향을 정면으로 지정"
        case .turnAway, .finding: return nil
        case .completed: return "같은 정면으로 다시 연습"
        }
    }
    private var secondaryTitle: String? {
        model.isRunning && model.practice.referenceHeading != nil ? "이 방향을 정면으로 다시 지정" : nil
    }
    private func primaryAction() {
        if !model.isRunning { model.start(); return }
        switch model.practice.phase {
        case .needsReference: model.setReference()
        case .turnAway, .finding: break
        case .completed: model.repeatExercise()
        }
    }
    private func secondaryAction() {
        model.resetReference()
    }
}

/// The light that stands for the chosen front, seen from the phone (Figma 457:13609 · 13642 · 13674 · 13626 · 13659).
/// It slides toward the side the front is on and shifts green → yellow → red as the body turns away,
/// easing every frame so position, shape and colour change together and never jump.
struct FrontGlow: View {
    let phase: FrontDirectionPractice.Phase
    let hasReference: Bool
    let bearing: Double?
    let deadband: Double
    @State private var smoother=GlowSmoother()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let state=smoother.step(to:target,at:context.date,instant:reduceMotion)
            GeometryReader { geometry in
                let w=geometry.size.width, h=geometry.size.height
                let side=abs(state.x)
                ZStack {
                    // Body of the light: wider and flatter the further it moves to the edge.
                    Ellipse().fill(state.color)
                        .frame(width:w*(0.55+0.35*side+0.4*state.neutral),height:h*(0.11-0.03*side+0.2*state.neutral))
                        .offset(x:state.x*w*0.42)
                        .blur(radius:28)
                    // Its spill on the screen edge, so a far turn reads as light leaking in from that side.
                    Ellipse().fill(state.color.opacity(0.85*smoothstep(0.35,1,side)))
                        .frame(width:w*0.5,height:h*(0.18+0.12*side))
                        .offset(x:(state.x >= 0 ? 1 : -1)*w*0.52)
                        .blur(radius:42)
                }.frame(width:w,height:h).offset(y:h*0.04)
                    .opacity(state.opacity)
            }
        }
    }

    private var target: GlowSmoother.Target {
        guard hasReference else {return .init(x:0,severity:0,neutral:true)}
        guard phase == .finding, let bearing else {return .init(x:0,severity:0,neutral:false)}
        // bearing > 0: the front is to the right of where the phone points.
        let clamped=max(-90,min(90,bearing))
        // Yellow by about 50°, red from 90°.
        let turn=abs(bearing)
        let severity=turn <= deadband ? 0 : turn <= 50 ? 0.5*(turn-deadband)/max(50-deadband,1) : 0.5+0.5*min(1,(turn-50)/40)
        return .init(x:clamped/90,severity:severity,neutral:false)
    }
}

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t=max(0,min(1,(x-a)/max(b-a,0.0001)))
    return t*t*(3-2*t)
}

/// Exponential easing of the light's position, colour stage and grey→colour change.
final class GlowSmoother {
    struct Target {let x: Double; let severity: Double; let neutral: Bool}
    struct State {let x: Double; let color: Color; let opacity: Double; let neutral: Double}
    private var x=0.0, severity=0.0, neutral=1.0
    private var last: Date?

    func step(to target: Target, at date: Date, instant: Bool) -> State {
        let dt=min(0.1,max(0,last.map {date.timeIntervalSince($0)} ?? 0))
        last=date
        // Turned fully around, the sign of the bearing flips; stay on the side already shown.
        var tx=target.x
        if abs(tx) >= 0.99, abs(x) > 0.5, (tx > 0) != (x > 0) {tx = x > 0 ? 1 : -1}
        let k=instant ? 1 : 1-exp(-dt*7)
        x+=(tx-x)*k
        severity+=(target.severity-severity)*k
        neutral+=((target.neutral ? 1 : 0)-neutral)*(instant ? 1 : 1-exp(-dt*4))
        return State(x:x,color:color,opacity:0.95,neutral:neutral)
    }
    /// Green at the front, yellow halfway, red at 90° and beyond; grey before a front is set.
    private var color: Color {
        let s=max(0,min(1,severity))
        let hue=s < 0.5 ? 0.36+(0.14-0.36)*(s*2) : 0.14+(0.0-0.14)*((s-0.5)*2)
        let saturation=(0.62+0.12*s)*(1-neutral)
        let brightness=0.92-0.4*neutral
        return Color(hue:hue,saturation:saturation,brightness:brightness)
    }
}
