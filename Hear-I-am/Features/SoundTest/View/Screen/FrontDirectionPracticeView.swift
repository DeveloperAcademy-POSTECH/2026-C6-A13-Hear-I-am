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
        .readsAloud {["정면 찾기",title,instruction]+[secondaryTitle,primaryTitle].compactMap {$0.map {"\($0) 버튼"}}}
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
        // Once the front has been found the buttons stay while the user keeps turning and finding it again.
        case .turnAway, .finding: return model.practice.completedOnce ? "같은 정면으로 다시 연습" : nil
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
        case .turnAway, .finding: if model.practice.completedOnce { model.repeatExercise() }
        case .completed: model.repeatExercise()
        }
    }
    private func secondaryAction() {
        model.resetReference()
    }
}

/// The light that stands for the chosen front, seen from the phone (Figma 457:13594 · 13609 · 13642 · 13626 · 13659).
/// One disc and one edge blade, blurred together: before a front is set the disc is the design's wide white haze;
/// it tightens into the green disc, then slides to the front's side, flattens sideways and melts into the blade
/// leaking in from that edge, which is all that is left at 90° (Vector 5).
struct FrontGlow: View {
    let phase: FrontDirectionPractice.Phase
    let hasReference: Bool
    let bearing: Double?
    let deadband: Double
    /// Where the disc sits below the screen's centre: 59.5pt in 정면 찾기, 182.5pt on the walking screen (495:5562).
    var discOffsetY: CGFloat = 59.5
    @State private var smoother=GlowSmoother()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let state=smoother.step(to:target,at:context.date,instant:reduceMotion)
            GeometryReader { geometry in
                let w=geometry.size.width, h=geometry.size.height
                let n=state.neutral
                let side=abs(state.x), sign: CGFloat = state.x >= 0 ? 1 : -1
                let leak=smoothstep(0.15,0.55,side), spread=smoothstep(0.3,1,side)
                // 253pt haze (blur 130) → 165pt disc (blur 10) → pressed flat sideways into the blade (blur 21, Figma).
                let discWidth=mix(165*(1+0.6*spread),253,n), discHeight=mix(165*(1-0.45*spread),253,n)
                // The flattened disc keeps sliding past the edge and dissolves, so at 90° only the blade is left (Figma).
                let discX=mix(w/2+sign*side*(1.1+0.6*spread)*(w/2),w/2,n), discY=mix(h/2+discOffsetY,h*0.6,n)
                let blur=mix(10+11*side,130,n)
                ZStack {
                    Ellipse().fill(state.color.opacity(max(0,1-spread/0.8)))
                        .frame(width:discWidth,height:discHeight).position(x:discX,y:discY)
                    EdgeBlade(reach:w*0.157*(0.3+0.7*spread),push:40*(1-leak),trailing:sign >= 0)
                        .fill(state.color.opacity(0.7*leak))
                }.compositingGroup().blur(radius:blur)
                    .frame(width:w,height:h)
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
private func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {a+(b-a)*CGFloat(t)}

/// The light leaking in from one edge (Figma Vector 5 in 457:13659): a blade pointed past the top and bottom of the
/// screen whose inner edge bulges `reach` points inward at 62% of the height. `push` moves the whole blade past the edge.
struct EdgeBlade: Shape {
    var reach: CGFloat
    var push: CGFloat
    var trailing: Bool
    func path(in rect: CGRect) -> Path {
        let w=rect.width, h=rect.height
        // (inset from the edge in units of `reach`, y as a fraction of the height), from the design's path.
        func point(_ inset: CGFloat, _ y: CGFloat) -> CGPoint {
            let x = trailing ? w-inset*reach+push : inset*reach-push
            return CGPoint(x:x,y:y*h)
        }
        var path=Path()
        path.move(to:point(-0.52,0.014))
        path.addCurve(to:point(1,0.616),control1:point(-1.13,0.153),control2:point(1,0.415))
        path.addCurve(to:point(-0.75,1.12),control1:point(1,0.759),control2:point(-0.62,0.99))
        path.addLine(to:point(-6,1.12))
        path.addLine(to:point(-6,0.014))
        path.closeSubpath()
        return path
    }
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
        neutral+=((target.neutral ? 1 : 0)-neutral)*(instant ? 1 : 1-exp(-dt*2.5))
        return State(x:x,color:color,opacity:0.95,neutral:neutral)
    }
    /// Green at the front, yellow halfway, red at 90° and beyond; grey before a front is set.
    private var color: Color {
        let s=max(0,min(1,severity))
        let hue=s < 0.5 ? 0.36+(0.14-0.36)*(s*2) : 0.14+(0.0-0.14)*((s-0.5)*2)
        let saturation=(0.62+0.12*s)*(1-neutral)
        let brightness=0.92+0.08*neutral
        return Color(hue:hue,saturation:saturation,brightness:brightness)
    }
}
