import SwiftUI
import HearIAmCore

/// V3 performer view. AR stays attached behind this surface; visual changes never drive the signals.
struct GuidanceLiveView: View {
    @ObservedObject var model: GuidanceViewModel
    private var ink: Color {model.isPractice ? Color(red:0.08,green:0.09,blue:0.09) : HearV3.text}
    private var paper: Color {model.isPractice ? .white : HearV3.canvas}
    private var panel: Color {model.isPractice ? Color(.systemGray6) : HearV3.surface}
    private var accent: Color {model.isPractice ? Color.hearGreen : HearV3.accent}
    private var progress: Double {
        guard let guide=model.guide else {return 0}
        if model.phase == .finishing || model.phase == .completed {return 1}
        let first=guide.practiceFirstIndex ?? 1
        return min(1,max(0,Double(guide.targetIndex-first)/Double(max(1,guide.route.points.count-first))))
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing:0) {
                    VStack(alignment:.leading,spacing:20) {
                        Text("\(model.isPractice ? "연습용" : "실전용") · \(model.selected?.name ?? "선택한 무대")")
                            .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(accent)
                        ProgressView(value:progress).tint(accent)
                            .accessibilityLabel("동선 진행률")
                    }.padding(.bottom,42)
                    Image(systemName:model.headline.symbol)
                        .font(.system(size:76,weight:.medium)).foregroundStyle(accent)
                        .frame(minHeight:98).accessibilityHidden(true)
                    Text(directionTitle)
                        .font(.system(.title,design:.default,weight:.bold))
                        .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).padding(.top,22)
                    if let cue=model.cue, [.guiding,.approaching,.paused].contains(model.phase), model.guide?.facingPointIndex == nil, model.performanceHoldRemaining == 0 {
                        HStack(alignment:.firstTextBaseline,spacing:4) {
                            Text(cue.distance,format:.number.precision(.fractionLength(1)))
                                .font(.system(size:68,weight:.bold)).monospacedDigit().minimumScaleFactor(0.6)
                            Text("m").font(.title2).foregroundStyle(.secondary)
                        }.padding(.top,16)
                        Text("다음 지점 \(model.targetName)까지").font(.subheadline).foregroundStyle(.secondary).padding(.top,10)
                    } else {
                        Text(model.headline.detail).font(.title3).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).padding(.top,24)
                    }
                    VStack(spacing:10) {
                        Label(statusTitle,systemImage:statusSymbol).font(.subheadline.bold())
                        Text(statusDetail).font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity).padding(20).background(panel,in:RoundedRectangle(cornerRadius:24)).padding(.top,40)
                    Spacer(minLength:24)
                }.foregroundStyle(ink).padding(.horizontal,24).padding(.top,20)
                    .frame(minHeight:geometry.size.height,alignment:.top)
            }.background(paper)
        }
    }
    private var directionTitle: String {
        if model.phase == .guiding, model.arrivedName == nil, model.guide?.facingPointIndex == nil,
           model.performanceHoldRemaining == 0, let cue=model.cue {return "\(cue.direction)으로 이동"}
        return model.headline.title.replacingOccurrences(of:"\n",with:" ")
    }
    private var statusTitle: String {
        if model.phase == .finishing || model.phase == .completed {return "안내를 마쳤어요"}
        if !model.isPractice {return "마이크가 꺼져 있어요"}
        if model.voiceInputError != nil {return "음성 입력을 확인해주세요"}
        if model.phase == .paused {return "안내를 일시정지했어요"}
        if model.voiceShowsListening {return "듣고 있어요"}
        return "안내가 진행 중이에요"
    }
    private var statusSymbol: String {
        model.phase == .completed ? "checkmark.circle" : model.isPractice ? "waveform" : "mic.slash"
    }
    private var statusDetail: String {
        if model.phase == .finishing || model.phase == .completed {return "종료 안내가 끝나면 기록을 저장해요."}
        if !model.isPractice {return "실전 중에는 호출어를 듣지 않고\n이동 안내만 전달해요."}
        if let error=model.voiceInputError {return error}
        if model.phase == .paused {return "‘계속’이라고 말하거나 아래 버튼을 눌러주세요."}
        return "다른 요청이 필요하면\n“Hear I am”을 불러주세요."
    }
}

#if DEBUG
/// Camera-free rendering of the production view for simulator visual checks; it never starts audio or AR.
struct GuidanceV3PreviewHarness: View {
    @StateObject private var model: GuidanceViewModel
    init(practice: Bool) {
        let model=GuidanceViewModel()
        model.active=false;model.voiceMode=practice ? .practice : .performance;model.started=true
        let area=PerformancePlan.area
        let route=try! StageRoute(area:area,points:[.init(2,2),.init(4,2),.init(6,2),.init(8,2)],obstacles:[])
        var guide=RouteGuide(route:route,settings:GuideSettings(),usesRouteCorridor:true)
        _=guide.start(position:route.points[0],headingDegrees:0,trackingValid:true)
        for i in 0...4 {_=guide.observe(time:Double(i)/4,position:route.points[1],headingDegrees:0,trackingValid:true)}
        model.guide=guide
        let frame=try! StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,-1)))
        model.selected=ScanManifest(id:UUID(),name:"Lion King",frame:frame,checkpoint:area.world(.init(1,1)),worldMapHash:"",meshHash:"",meshCount:1,vertexCount:3,device:"Preview",appVersion:"1",route:route)
        model.cue=GuidanceCue(position:.init(6,4.4),goal:.init(6,2),headingDegrees:0,sector:0)
        model.phase = .guiding
        _model=StateObject(wrappedValue:model)
    }
    var body: some View {
        NavigationStack {
            GuidanceLiveView(model:model)
                .navigationTitle("Hear I am").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.topBarTrailing) {Image(systemName:"gearshape")}}
                .safeAreaInset(edge:.bottom) {
                    Label("안내 일시정지",systemImage:"pause.fill").font(.headline)
                        .frame(maxWidth:.infinity,minHeight:52)
                        .background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:18)).padding(24)
                }
                .background(model.isPractice ? Color.white : HearV3.canvas)
        }.preferredColorScheme(model.isPractice ? .light : .dark)
    }
}

/// Camera-free rendering of the voice walking and checkpoint screens (#167) for simulator checks:
/// `--voice-walk-preview <wait|walk|grow|done|check0|check1|check2>`, with `practice` in the name for 연습 안내.
/// `grow` waits 1.5 s and then starts, to watch the circle open and the light tighten.
struct VoiceWalkPreviewHarness: View {
    @StateObject private var model: GuidanceViewModel
    private let screen: String
    init(screen: String) {
        self.screen=screen
        let model=GuidanceViewModel()
        model.active=false
        model.voiceMode=screen.contains("practice") ? .practice : .performance
        let area=PerformancePlan.area
        let route=try! StageRoute(area:area,points:[.init(2,2),.init(4,2),.init(6,2),.init(8,2)],obstacles:[])
        var guide=RouteGuide(route:route,settings:GuideSettings(),usesRouteCorridor:true)
        _=guide.start(position:route.points[0],headingDegrees:0,trackingValid:true)
        model.guide=guide
        let frame=try! StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,-1)))
        model.selected=ScanManifest(id:UUID(),name:"긴장감 고조 장면",frame:frame,checkpoint:area.world(.init(1,1)),worldMapHash:"",meshHash:"",meshCount:1,vertexCount:3,device:"Preview",appVersion:"1",route:route)
        model.cue=GuidanceCue(position:.init(2,1.5),goal:.init(2,2),headingDegrees:0,sector:0)
        if screen.contains("walk") {model.started=true;model.phase = .guiding}
        else if screen.contains("done") {model.started=true;model.phase = .completed}
        else if screen.contains("check") {
            model.phase = .checkpoint
            let count=Int(String(screen.last ?? "0")) ?? 0
            model.tracking.measuredCheckpoints=Array(repeating:Point3(0,0,0),count:min(count,1))
            model.performanceCheckpointsDone=count >= 2
            model.checkpointAimed=count == 1
        } else if screen.contains("approach") {model.phase = .approaching}
        else {model.phase = .starting}
        _model=StateObject(wrappedValue:model)
    }
    var body: some View {
        NavigationStack {
            Group {
                if model.phase == .checkpoint {
                    ZStack {
                        LinearGradient(colors:[Color(white:0.55),Color(white:0.2)],startPoint:.top,endPoint:.bottom).ignoresSafeArea()
                        PerformanceCheckpointView(model:model,tracking:model.tracking)
                    }.toolbar(.hidden,for:.navigationBar)
                } else {VoiceGuidanceWalkView(model:model,previewLit:true)}
            }
            .navigationTitle(model.phase == .checkpoint ? "" : model.isPractice ? "연습 안내" : "실전 안내").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {VoiceBackButton {}}
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard screen.contains("grow") else {return}
            try? await Task.sleep(nanoseconds:1_500_000_000)
            model.started=true;model.phase = .guiding
        }
    }
}
#endif

/// 연습 안내 · 실전 안내 by voice (Figma 1028:18921 · 18910 · 18900). While the performer is led to the start the
/// small circle waits over the wide grey light with 「잠시 후 안내가 시작됩니다」. When guidance starts the circle
/// opens to 130pt with the direction arrow while the light tightens into the 정면 찾기 disc, and the next point and
/// the distance come in. At the end it all goes back to the waiting look under 「안내를 종료합니다 · 도착」.
/// The light moves as in 정면 찾기 (`WalkGlowDirection`): centred once the body faces the point, to the side only
/// after a clear turn away. The camera keeps tracking behind the canvas; nothing of it is shown.
struct VoiceGuidanceWalkView: View {
    @ObservedObject var model: GuidanceViewModel
    /// The simulator preview keeps the model inactive, so nothing is read aloud, but still shows the lit disc.
    var previewLit=false
    /// The arrow's angle as drawn; it turns the short way to `walkGlow.arrowDegrees`, so going from just left of
    /// ahead to just right no longer spins it all the way round (the 0…315° sector did, 11/10).
    @State private var arrowAngle: Double=0
    private var walking: Bool {
        model.phase == .approaching ||
            model.phase == .guiding && model.arrivedName == nil && model.guide?.facingPointIndex == nil && model.performanceHoldRemaining == 0
    }
    private var cue: GuidanceCue? {walking ? model.cue : nil}
    private var finished: Bool {[.finishing,.completed].contains(model.phase)}
    /// The circle is open, with the arrow and the labels, while led to the start (실전용) and from the first start
    /// until the end; at the start it closes to the waiting look until guidance begins.
    private var open: Bool {(model.started || model.phase == .approaching) && !finished}
    private static let grey=Color(red:118/255,green:118/255,blue:118/255)

    var body: some View {
        GeometryReader {geometry in
            let w=geometry.size.width
            ZStack(alignment:.top) {
                VoiceStyle.canvas
                FrontGlow(phase:model.walkGlow.phase == .aligned ? .completed : .finding,
                          hasReference:[.guiding,.approaching].contains(model.phase) && (model.active || previewLit),bearing:model.walkGlow.bearing,
                          deadband:SignalPlayer.directionDeadbandDegrees,discOffsetY:182.5)
                    .accessibilityHidden(true)
                // Positions are the design's, measured from the top of the 874pt frame.
                if finished {
                    Text("안내를 종료합니다").font(HearFont.pretendard(.semibold,size:32)).tracking(-0.96).foregroundStyle(.white)
                        .frame(width:w).padding(.top,156).transition(.opacity)
                } else if !open {
                    Text("잠시 후\n안내가 시작됩니다").font(HearFont.pretendard(.semibold,size:32)).tracking(-0.96).lineSpacing(9.6)
                        .multilineTextAlignment(.center).foregroundStyle(.white)
                        .frame(width:w).padding(.top,148).transition(.opacity)
                } else {
                    VStack(spacing:0) {
                        Text(model.targetName).font(HearFont.pretendard(.semibold,size:32)).tracking(-0.96).foregroundStyle(.white)
                            .frame(height:42)
                        Text("다음 포인트").font(HearFont.pretendard(.regular,size:20)).tracking(-0.6).foregroundStyle(Self.grey)
                            .frame(height:26)
                    }.frame(width:w).padding(.top,148).transition(.opacity.combined(with:.offset(y:-8)))
                }
                circle.position(x:w/2,y:open ? 304 : 299)
                if open || finished {
                    Text(value).font(HearFont.pretendard(.bold,size:valueIsShort ? 46 : 30)).tracking(valueIsShort ? -1.38 : -0.9)
                        .monospacedDigit().foregroundStyle(.white).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.6).padding(.horizontal,24)
                        .frame(width:w).padding(.top,408).transition(.opacity.combined(with:.offset(y:8)))
                    if let issue=model.voiceInputError {
                        Text(issue).font(.system(size:15)).foregroundStyle(VoiceStyle.status).multilineTextAlignment(.center)
                            .frame(width:w-64).padding(.top,480)
                    }
                }
                LinearGradient(stops:[.init(color:VoiceStyle.canvas,location:0.036),.init(color:VoiceStyle.canvas.opacity(0),location:0.596)],
                               startPoint:.top,endPoint:.bottom)
                    .frame(height:156).allowsHitTesting(false).accessibilityHidden(true)
            }
            .onChange(of:model.walkGlow.arrowDegrees) {_,target in
                // While the circle is still opening the arrow takes its direction without turning.
                let turn=WalkGlowDirection.wrap(target-arrowAngle)
                if open {withAnimation(.smooth(duration:0.45)) {arrowAngle+=turn}} else {arrowAngle+=turn}
            }
            .onChange(of:open) {_,_ in arrowAngle=model.walkGlow.arrowDegrees}
            .animation(.smooth(duration:0.9),value:open)
            .animation(.smooth(duration:0.9),value:finished)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(accessibilityText)
        }.ignoresSafeArea()
    }
    /// 52pt while waiting and after the end (1028:18926), 130pt with the arrow while guidance runs (1028:18914).
    private var circle: some View {
        let size: CGFloat = open ? 130 : 52
        return ZStack {
            Circle().fill(.white.opacity(0.05))
            Circle().strokeBorder(LinearGradient(colors:[.white.opacity(0.35),.white.opacity(0.04)],startPoint:.top,endPoint:.bottom),lineWidth:1)
        }
        .frame(width:size,height:size)
        // The arrow is drawn at full size and scaled with the circle, so it never sets the circle's size.
        .overlay {
            VoiceGuidanceArrow().stroke(VoiceStyle.arrow,style:StrokeStyle(lineWidth:6,lineCap:.round,lineJoin:.round))
                .frame(width:130,height:130)
                .rotationEffect(.degrees(arrowAngle))
                .opacity(!open ? 0 : cue == nil ? 0.35 : 1)
                .scaleEffect(size/130)
        }
        .shadow(color:.black.opacity(open ? 0.35 : 0.2),radius:open ? 16 : 8,y:open ? 10 : 4)
    }
    private var value: String {
        if finished {return "도착"}
        if let cue {return "\(cue.distance.formatted(.number.precision(.fractionLength(1))))m"}
        switch model.phase {
        case .paused: return "일시정지"
        case .starting: return "안내를 다시 시작해요"
        default:
            return model.arrivedName == nil && model.guide?.facingPointIndex == nil && model.performanceHoldRemaining == 0 ? "안내하는 중" : model.headline.title.replacingOccurrences(of:"\n",with:" ")
        }
    }
    private var valueIsShort: Bool {finished || cue != nil}
    private var accessibilityText: String {
        if finished {return "안내를 종료합니다. 도착"}
        if !open {return "잠시 후 안내가 시작됩니다"}
        if let cue {return "다음 포인트 \(model.targetName). \(cue.direction) \(value)"}
        return "다음 포인트 \(model.targetName). \(value)"
    }
}

/// 실전용 확인점 찾기 (Figma 1028:18949 · 18930 · 18968) over the whole camera, as the scan screen is, with the scan
/// screen's glass. 「확인점 1 확인」 lights up once the crosshair is on the saved checkpoint 1 and measures it; the
/// same for 2; then 「완료」 confirms both, as the button flow's 「확인점 n 확인하기」 did.
struct PerformanceCheckpointView: View {
    @ObservedObject var model: GuidanceViewModel
    @ObservedObject var tracking: ARSessionController
    var onBack: () -> Void = {}
    var onSettings: () -> Void = {}
    private var measured: Int {model.performanceCheckpointsDone ? 2 : min(2,tracking.measuredCheckpoints.count)}
    private var done: Bool {model.performanceCheckpointsDone}
    private var enabled: Bool {done || model.checkpointAimed}

    var body: some View {
        GeometryReader {geometry in
            let insets=geometry.safeAreaInsets
            ZStack(alignment:.top) {
                Image(systemName:"plus").font(.system(size:34,weight:.light))
                    .foregroundStyle(model.checkpointAimed || done ? Color.white : Color.white.opacity(0.75))
                    .shadow(color:.black.opacity(0.5),radius:1.5)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                    .allowsHitTesting(false).accessibilityHidden(true)
                VStack(spacing:0) {
                    HStack(alignment:.top) {
                        ScanCircleButton(systemImage:"chevron.backward",label:"뒤로",action:onBack)
                        Spacer(minLength:12)
                        VStack(spacing:8) {
                            if let name=model.selected?.name, model.helperStart {
                                // Chosen in the performance already; another scene is chosen there.
                                PerformanceScenePill(name:name,choosable:false).liquidGlass(Capsule(),tint:ScanChrome.capsuleTint)
                            } else if let name=model.selected?.name {
                                Menu {
                                    Button("무대 다시 선택",systemImage:"arrow.uturn.backward") {model.prepareForVoiceTouch();model.chooseAgain()}
                                } label: {PerformanceScenePill(name:name).liquidGlass(Capsule(),tint:ScanChrome.capsuleTint).contentShape(Capsule())}
                                .accessibilityLabel("\(name), 무대 바꾸기")
                            }
                            dots
                        }
                        Spacer(minLength:12)
                        Menu {
                            Button("설정",systemImage:"gearshape",action:onSettings)
                            Button("안내 끝내기",systemImage:"xmark",action:onBack)
                        } label: {ScanCircleLabel(systemImage:"ellipsis")}
                        .accessibilityLabel("안내 설정 및 종료")
                    }
                    Spacer()
                    Button {
                        if done {model.confirmPerformanceCheckpoints()} else {model.capturePerformanceCheckpoint()}
                    } label: {
                        Text(model.selected == nil ? "무대를 찾을 수 없어요" : model.phase != .checkpoint ? "공연장을 찾는 중…" : done ? "완료" : "확인점 \(min(measured+1,2)) 확인")
                            .font(HearFont.pretendard(.semibold,size:18)).foregroundStyle(enabled ? ScanChrome.darkText : .white)
                            .frame(maxWidth:.infinity,minHeight:50)
                            .background(enabled ? Color.white : Color.clear,in:Capsule())
                            .liquidGlass(Capsule(),tint:enabled ? nil : ScanChrome.panelTint)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                    .animation(.smooth(duration:0.25),value:enabled)
                    .accessibilityHint(enabled ? "" : "가운데 조준점을 저장한 확인점에 맞추면 켜져요.")
                    .accessibilityIdentifier("performance.checkpoints.done")
                }
                .padding(.horizontal,16).padding(.top,insets.top+6).padding(.bottom,max(insets.bottom,16)+12)
            }
            .frame(width:geometry.size.width+insets.leading+insets.trailing,height:geometry.size.height+insets.top+insets.bottom)
            .ignoresSafeArea()
        }
    }
    /// The two checkpoints, white once measured (1028:18930).
    private var dots: some View {
        HStack(spacing:8) {
            ForEach(1...2,id:\.self) {number in
                let done=number <= measured
                Text("\(number)").font(HearFont.pretendard(.semibold,size:14))
                    .foregroundStyle(done ? Color(white:17/255) : .white)
                    .frame(width:23,height:23)
                    .background(done ? Color.white : Color.black.opacity(0.4),in:Circle())
            }
        }
        .padding(.horizontal,10).padding(.vertical,6)
        .liquidGlass(Capsule(),tint:ScanChrome.panelTint)
        .animation(.smooth(duration:0.3),value:measured)
        .accessibilityElement(children:.ignore).accessibilityLabel("확인점 2개 중 \(measured)개 확인")
    }
}

/// The scene being prepared, as the pill in the middle of the top bar (1028:18941).
struct PerformanceScenePill: View {
    let name: String
    var choosable=true
    var body: some View {
        HStack(spacing:12) {
            Image(systemName:"movieclapper").font(.system(size:15,weight:.medium))
            Text(name).font(.system(size:12,weight:.semibold)).lineLimit(1)
            if choosable {
                Image(systemName:"chevron.down").font(.system(size:9,weight:.bold))
                    .frame(width:18,height:18).background(.white.opacity(0.2),in:Circle())
            }
        }
        .foregroundStyle(.white).padding(.horizontal,14).frame(height:44)
        .accessibilityElement(children:.combine)
    }
}

/// The arrow of the design's circle (495:5560): a 54pt shaft with a 38pt head, drawn pointing up in a 130pt box.
struct VoiceGuidanceArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let s=rect.width/130
        var path=Path()
        path.move(to:CGPoint(x:rect.minX+65*s,y:rect.minY+92*s));path.addLine(to:CGPoint(x:rect.minX+65*s,y:rect.minY+38*s))
        path.move(to:CGPoint(x:rect.minX+84*s,y:rect.minY+56.73*s));path.addLine(to:CGPoint(x:rect.minX+65*s,y:rect.minY+38*s))
        path.addLine(to:CGPoint(x:rect.minX+46*s,y:rect.minY+56.73*s))
        return path
    }
}
