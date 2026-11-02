import SwiftUI

enum HearRole: String, CaseIterable, Identifiable {
    case performer, helper
    var id:String {rawValue}
    var title:String {self == .performer ? "공연자" : "조력자"}
    var detail:String {self == .performer ? "음성 안내를 따라\n무대에서 이동해요." : "무대를 스캔하고\n공연 동선을 준비해요."}
    /// The landing page's wording and photo (Figma 476:3188 · 476:3193).
    var landingTitle:String {self == .performer ? "아티스트" : "조력자"}
    var landingDetail:String {self == .performer ? "시각 장애 예술가들을\n위한 음성 안내" : "아티스트의 무대와\n동선을 준비하고 관리"}
    var landingImage:String {self == .performer ? "LandingArtist" : "LandingHelper"}
}

/// Figma 「Stroke Logo · OPPOSITE PAIRS」 (457:16071): eight rays around an empty centre, in the design's
/// 153-unit box. `time` is seconds into the design's 4 s loop: each segment grows outward during its draw-in
/// slice, holds, then shrinks back during its draw-out slice. Past the first loop the segments draw in once
/// more and stay. The stroke is part of the path so its width animates with the logo's size.
struct StrokeLogoShape: Shape {
    var time: Double
    var lineWidth: CGFloat
    var animatableData: AnimatablePair<Double,CGFloat> {
        get {AnimatablePair(time,lineWidth)}
        set {time=newValue.first; lineWidth=newValue.second}
    }

    static let loop: Double = 4
    /// The draw-in ends at 1.784 s; the logo is whole from there until the draw-out begins at 2.125 s.
    static let drawIn: Double = 1.8
    /// The launch plays the draw-in once and stops there (the draw-out and the second draw-in were too long).
    static let settled: Double = drawIn
    static let unit: CGFloat = 153.054
    static let lineWidth: CGFloat = 7.358/unit

    struct Segment {let ray:Int;let inner:CGFloat;let outer:CGFloat;let inStart:Double;let inEnd:Double;let outStart:Double;let outEnd:Double}
    /// Ray 0 points up and the index turns clockwise by 45°. Radii and timings come from the Figma keyframes
    /// (percentages of the 4 s loop).
    static let segments: [Segment] = [
        .init(ray:0,inner:24.2,outer:74.1,inStart:0.160,inEnd:0.593,outStart:3.316,outEnd:3.749),
        .init(ray:4,inner:24.2,outer:74.1,inStart:0.160,inEnd:0.593,outStart:3.316,outEnd:3.749),
        .init(ray:2,inner:24.2,outer:74.1,inStart:0.720,inEnd:1.153,outStart:2.756,outEnd:3.189),
        .init(ray:6,inner:24.2,outer:74.1,inStart:0.720,inEnd:1.153,outStart:2.756,outEnd:3.189),
        .init(ray:1,inner:24.2,outer:48.2,inStart:0.440,inEnd:0.815,outStart:3.094,outEnd:3.469),
        .init(ray:5,inner:24.2,outer:48.2,inStart:0.440,inEnd:0.815,outStart:3.094,outEnd:3.469),
        .init(ray:1,inner:53.2,outer:61.5,inStart:0.815,inEnd:1.165,outStart:2.744,outEnd:3.094),
        .init(ray:5,inner:53.2,outer:61.5,inStart:0.815,inEnd:1.165,outStart:2.744,outEnd:3.094),
        .init(ray:1,inner:66.5,outer:89.5,inStart:1.165,inEnd:1.538,outStart:2.371,outEnd:2.744),
        .init(ray:5,inner:66.5,outer:89.5,inStart:1.165,inEnd:1.538,outStart:2.371,outEnd:2.744),
        .init(ray:7,inner:24.2,outer:36.5,inStart:1.000,inEnd:1.359,outStart:2.550,outEnd:2.909),
        .init(ray:3,inner:24.2,outer:36.5,inStart:1.000,inEnd:1.357,outStart:2.552,outEnd:2.909),
        .init(ray:7,inner:43.6,outer:90.0,inStart:1.359,inEnd:1.784,outStart:2.125,outEnd:2.550),
        .init(ray:3,inner:43.6,outer:90.0,inStart:1.359,inEnd:1.788,outStart:2.121,outEnd:2.550),
    ]

    /// How much of the segment shows at `time`, from its inner end.
    static func fraction(_ s: Segment, at time: Double) -> Double {
        let t = time < loop ? time : time-loop
        let grown=max(0,min(1,(t-s.inStart)/(s.inEnd-s.inStart)))
        guard time < loop else {return grown}
        let shrunk=max(0,min(1,(t-s.outStart)/(s.outEnd-s.outStart)))
        return grown*(1-shrunk)
    }

    func path(in rect: CGRect) -> Path {
        var path=Path()
        let scale=min(rect.width,rect.height)/Self.unit
        let center=CGPoint(x:rect.midX,y:rect.midY)
        for segment in Self.segments {
            let fraction=Self.fraction(segment,at:time)
            guard fraction > 0 else {continue}
            let angle = -CGFloat.pi/2 + CGFloat(segment.ray) * .pi/4
            let direction=CGPoint(x:cos(angle),y:sin(angle))
            let from=segment.inner*scale
            let to=(segment.inner+(segment.outer-segment.inner)*CGFloat(fraction))*scale
            path.move(to:CGPoint(x:center.x+direction.x*from,y:center.y+direction.y*from))
            path.addLine(to:CGPoint(x:center.x+direction.x*to,y:center.y+direction.y*to))
        }
        return path.strokedPath(StrokeStyle(lineWidth:lineWidth,lineCap:.butt))
    }
}

struct HearStrokeLogo: View {
    var size: CGFloat
    var time: Double = StrokeLogoShape.settled
    var body: some View {
        StrokeLogoShape(time:time,lineWidth:size*StrokeLogoShape.lineWidth).fill(.white)
            .frame(width:size,height:size).accessibilityHidden(true)
    }
}

enum LandingStyle {
    static let canvas=Color(red:17/255,green:17/255,blue:17/255)
    static let secondary=Color(red:235/255,green:235/255,blue:245/255).opacity(0.7)
    static let dimButton=Color.white.opacity(0.2)
    static let dimButtonText=Color(red:153/255,green:153/255,blue:153/255)
    static let cardRadius: CGFloat = 28
    static let cardHeight: CGFloat = 259
    /// The design renders the photos at 80%, but the exported JPEGs come out lighter than the Figma render; 65% matches it.
    static let photoOpacity: Double = 0.65
    /// The design draws the logo at 153pt on the launch and 96.5pt on the role page; the user asked for
    /// both a step smaller (2026-11-02).
    static let launchLogo: CGFloat = 124
    static let pageLogo: CGFloat = 82
}

/// The soft white glow above the role page (Figma Ellipse 31: 311×264 blurred ellipse, top at −171).
private struct LandingGlow: View {
    var body: some View {
        Ellipse().fill(Color.white.opacity(0.3)).frame(width:311,height:264).blur(radius:75)
            .offset(y:-171).accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// Launch and role page in one (Figma 457:16069 → 476:3167 · 3204 · 3583). At launch the logo sits in the
/// centre of the screen over 「Hear I am」 and draws itself in once, then rises into its place at the top of
/// the role page while the page fades in. Opening this page later (changing the role) skips all of that.
struct RoleSelectionView: View {
    let select:(HearRole)->Void
    var animatesLaunch=false
    @State private var selected:HearRole?
    @State private var showingSettings=false
    @State private var launching: Bool
    /// Once the rise is over the logo lives in the page's own column, so it is centred by layout, not by numbers.
    @State private var risen: Bool
    @State private var time: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Draw in, hold, then the rise. The root waits this long before voice features start.
    static let hold: Double = 0.4
    static let rise: Double = 0.8
    static let launchDuration: Double = StrokeLogoShape.settled+hold+rise

    init(animatesLaunch: Bool = false, select: @escaping (HearRole)->Void) {
        self.select=select
        self.animatesLaunch=animatesLaunch
        _launching=State(initialValue:animatesLaunch)
        _risen=State(initialValue:!animatesLaunch)
        _time=State(initialValue:animatesLaunch ? 0 : StrokeLogoShape.settled)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            let launchLogo=LandingStyle.launchLogo, pageLogo=LandingStyle.pageLogo
            // The physical screen's centre in this (safe-area) space, so the launch logo is centred on the screen.
            let insets=geometry.safeAreaInsets
            let screenCenter=CGPoint(x:geometry.size.width/2,y:(geometry.size.height+insets.bottom-insets.top)/2)
            // The role page's slot: first in the top-aligned column, 107pt down (476:3204).
            let pageCenter=CGPoint(x:geometry.size.width/2,y:107+pageLogo/2)
            let logoCenter=launching ? screenCenter : pageCenter
            ZStack(alignment:.top) {
                LandingStyle.canvas.ignoresSafeArea()
                LandingGlow().ignoresSafeArea().opacity(launching ? 0 : 1)
                VStack(spacing:0) {
                    ZStack {
                        Color.clear
                        if risen {HearStrokeLogo(size:pageLogo)}
                    }.frame(width:pageLogo,height:pageLogo).padding(.top,107)
                    VStack(spacing:4) {
                        Text("사용자를 선택해주세요").font(.system(size:28,weight:.bold)).tracking(-0.84).foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                        Text("사용자에 따라 앱 사용 환경이 달라져요").font(.system(size:20,weight:.medium)).tracking(-0.6)
                            .foregroundStyle(LandingStyle.secondary)
                    }.multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.8).padding(.top,32)
                    HStack(alignment:.top,spacing:16) {
                        ForEach(HearRole.allCases) {role in
                            VStack(spacing:19) {
                                RoleDot(state:dotState(role))
                                RoleCard(role:role,selected:selected == role) {selected=role}
                            }
                        }
                    }.padding(.horizontal,20).padding(.top,58)
                    Spacer(minLength:16)
                }.frame(maxWidth:.infinity).opacity(launching ? 0 : 1)
                Button {showingSettings=true} label: {ScanCircleLabel(systemImage:"gearshape")}
                    .buttonStyle(.plain).frame(maxWidth:.infinity,alignment:.trailing).padding(.trailing,18).padding(.top,14)
                    .accessibilityLabel("설정").accessibilityIdentifier("role.settings")
                    .opacity(launching ? 0 : 1)
                // Launch layout (457:16069): the wordmark 36pt under the centred logo.
                Text("Hear I am").font(.system(size:40,weight:.ultraLight)).foregroundStyle(.white).fixedSize()
                    .position(x:screenCenter.x,y:screenCenter.y+launchLogo/2+36+24)
                    .opacity(launching ? 1 : 0).allowsHitTesting(false)
                    .accessibilityElement(children:.combine).accessibilityLabel("Hear I am").accessibilityIdentifier("launch.brand")
                    .accessibilityHidden(!launching)
                // The one logo: screen centre at launch, then the role page's slot.
                StrokeLogoShape(time:time,lineWidth:(launching ? launchLogo : pageLogo)*StrokeLogoShape.lineWidth)
                    .fill(.white)
                    .frame(width:launching ? launchLogo : pageLogo,height:launching ? launchLogo : pageLogo)
                    .position(logoCenter)
                    .opacity(risen ? 0 : 1)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }.frame(width:geometry.size.width,height:geometry.size.height)
            }
            .safeAreaInset(edge:.bottom,spacing:0) {
                Button {if let selected {select(selected)}} label: {
                    Text("선택한 사용자로 시작하기").font(.system(size:20,weight:.semibold))
                        .foregroundStyle(selected == nil ? LandingStyle.dimButtonText : LandingStyle.canvas)
                        .frame(maxWidth:.infinity).frame(height:50)
                        .background(selected == nil ? LandingStyle.dimButton : Color.white,in:Capsule())
                }.buttonStyle(.plain).disabled(selected == nil || launching)
                    .padding(.horizontal,20).padding(.bottom,6)
                    .opacity(launching ? 0 : 1)
                    .accessibilityIdentifier("role.continue")
                    .accessibilityHint(selected == nil ? "먼저 사용자를 선택해주세요" : "")
            }
            .toolbar(.hidden,for:.navigationBar)
            .navigationDestination(isPresented:$showingSettings) {HomeSettingsView()}
            .animation(.easeOut(duration:0.2),value:selected)
            .onAppear(perform:runLaunch)
        }.preferredColorScheme(.dark)
    }
    private func runLaunch() {
        guard launching else {return}
        if reduceMotion {time=StrokeLogoShape.settled; launching=false; risen=true; return}
        withAnimation(.linear(duration:StrokeLogoShape.settled)) {time=StrokeLogoShape.settled}
        Task { @MainActor in
            try? await Task.sleep(for:.seconds(StrokeLogoShape.settled+Self.hold))
            withAnimation(.easeInOut(duration:Self.rise)) {launching=false}
            try? await Task.sleep(for:.seconds(Self.rise))
            risen=true
        }
    }
    private func dotState(_ role:HearRole) -> RoleDot.State {
        guard let selected else {return .idle}
        return selected == role ? .selected : .other
    }
}

/// The 20pt dot above each card: 30% white when nothing is chosen, 50% for the other card, white with a ring when chosen.
private struct RoleDot: View {
    enum State {case idle,other,selected}
    let state: State
    var body: some View {
        ZStack {
            Circle().stroke(.white,lineWidth:2).frame(width:30,height:30).opacity(state == .selected ? 1 : 0)
            Circle().fill(Color.white.opacity(state == .selected ? 1 : state == .other ? 0.5 : 0.3)).frame(width:20,height:20)
        }.frame(width:32,height:32).accessibilityHidden(true)
    }
}

/// 173×259 photo card with the blurred dark fade and the role's name (Figma 476:3188).
private struct RoleCard: View {
    let role: HearRole
    let selected: Bool
    let action: () -> Void
    private var shape: RoundedRectangle {RoundedRectangle(cornerRadius:LandingStyle.cardRadius,style:.continuous)}
    /// Clear from 52% of the card down to 80% black at 88%, as the design's 234pt gradient placed at 129pt.
    private var fade: LinearGradient {
        LinearGradient(stops:[.init(color:.clear,location:0.52),.init(color:.black.opacity(0.8),location:0.876),.init(color:.black.opacity(0.8),location:1)],
                       startPoint:.top,endPoint:.bottom)
    }
    var body: some View {
        Button(action:action) {
            Color.clear.frame(height:LandingStyle.cardHeight)
                .overlay {
                    ZStack {
                        Image(role.landingImage).resizable().scaledToFill().opacity(LandingStyle.photoOpacity)
                        Image(role.landingImage).resizable().scaledToFill().opacity(LandingStyle.photoOpacity).blur(radius:20)
                            .mask(LinearGradient(stops:[.init(color:.clear,location:0.5),.init(color:.black,location:0.876)],startPoint:.top,endPoint:.bottom))
                        fade
                    }
                }
                .overlay(alignment:.bottomLeading) {
                    VStack(alignment:.leading,spacing:0) {
                        Text(role.landingTitle).font(.system(size:18,weight:.semibold)).tracking(-0.54).foregroundStyle(.white)
                        Text(role.landingDetail).font(.system(size:14,weight:.medium)).tracking(-0.42).foregroundStyle(.white.opacity(0.8))
                            .lineSpacing(2).fixedSize(horizontal:false,vertical:true)
                    }.padding(.leading,19).padding(.trailing,12).padding(.bottom,19)
                }
                .clipShape(shape).contentShape(shape)
        }.buttonStyle(.plain)
            .accessibilityLabel("\(role.landingTitle), \(role.landingDetail.replacingOccurrences(of:"\n",with:" "))")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("role.\(role.rawValue)")
    }
}
