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
#endif

/// 연습 안내 by voice (Figma 495:5555 · 5569): the next point's direction as the arrow in the raised circle and
/// as the 정면 찾기 light, which sits straight ahead in green and slides to the side the point is on. The
/// camera keeps tracking behind the canvas; nothing of it is shown.
struct VoicePracticeGuidanceView: View {
    @ObservedObject var model: GuidanceViewModel
    private let deadband=DirectionTickGate.defaultDeadbandDegrees
    private var walking: Bool {model.phase == .guiding && model.arrivedName == nil && model.guide?.facingPointIndex == nil && model.performanceHoldRemaining == 0}
    private var cue: GuidanceCue? {walking ? model.cue : nil}

    var body: some View {
        GeometryReader {geometry in
            let w=geometry.size.width
            ZStack(alignment:.top) {
                VoiceStyle.canvas.ignoresSafeArea()
                FrontGlow(phase:.finding,hasReference:model.phase == .guiding && model.active,bearing:model.voiceGlowBearing,
                          deadband:deadband,discOffsetY:182.5)
                    .ignoresSafeArea().accessibilityHidden(true)
                VStack(spacing:0) {
                    ZStack {
                        Circle().fill(.white.opacity(0.05))
                        Circle().strokeBorder(LinearGradient(colors:[.white.opacity(0.35),.white.opacity(0.04)],startPoint:.top,endPoint:.bottom),lineWidth:1)
                        VoiceGuidanceArrow().stroke(VoiceStyle.arrow,style:StrokeStyle(lineWidth:6,lineCap:.round,lineJoin:.round))
                            .frame(width:130,height:130)
                            .rotationEffect(.degrees(Double(cue?.sector ?? 0)*45))
                            .opacity(cue == nil ? 0.35 : 1)
                    }
                    .frame(width:130,height:130)
                    .shadow(color:.black.opacity(0.35),radius:16,y:10)
                    .animation(.easeInOut(duration:0.35),value:cue?.sector)
                    .padding(.top,max(0,185-geometry.safeAreaInsets.top-44))
                    Text(subtitle).font(.system(size:20,weight:.semibold)).foregroundStyle(.white).padding(.top,62)
                    Text(title).font(.system(size:32,weight:.semibold)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).padding(.top,6).padding(.horizontal,24)
                    if let issue=model.voiceInputError {
                        Text(issue).font(.system(size:15)).foregroundStyle(VoiceStyle.status).multilineTextAlignment(.center)
                            .padding(.top,16).padding(.horizontal,32)
                    }
                    Spacer(minLength:0)
                }
                .frame(width:w)
                .accessibilityElement(children:.combine)
                .accessibilityLabel("\(subtitle). \(title)")
                LinearGradient(stops:[.init(color:VoiceStyle.canvas,location:0.036),.init(color:VoiceStyle.canvas.opacity(0),location:0.596)],
                               startPoint:.top,endPoint:.bottom)
                    .frame(height:156).ignoresSafeArea(edges:.top).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
    private var subtitle: String {
        switch model.phase {
        case .finishing,.completed: return "연습 안내"
        default: return "다음 포인트 · \(model.targetName)"
        }
    }
    private var title: String {
        switch model.phase {
        case .starting: return "안내를 시작하고 있어요"
        case .paused: return "일시정지 중"
        case .finishing,.completed: return "안내를 마쳤어요"
        default:
            if let cue {return "\(cue.direction) \(cue.distance.formatted(.number.precision(.fractionLength(1))))m"}
            return model.arrivedName == nil && model.guide?.facingPointIndex == nil && model.performanceHoldRemaining == 0 ? "안내하는 중" : model.headline.title.replacingOccurrences(of:"\n",with:" ")
        }
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
