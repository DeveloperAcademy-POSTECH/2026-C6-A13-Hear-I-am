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
/// 153-unit box. `time` is seconds into the design's draw-in; each segment grows outward during its own slice.
struct StrokeLogoShape: Shape {
    var time: Double
    var animatableData: Double {get {time} set {time=newValue}}

    /// The draw-in takes 1.78 s in the design (the 4 s loop's first half); the loop and the draw-out are not used.
    static let duration: Double = 1.8
    static let unit: CGFloat = 153.054
    static let lineWidth: CGFloat = 7.358/unit

    struct Segment {let ray:Int;let inner:CGFloat;let outer:CGFloat;let start:Double;let end:Double}
    /// Ray 0 points up and the index turns clockwise by 45°. Radii and timings come from the Figma keyframes.
    static let segments: [Segment] = [
        .init(ray:0,inner:24.2,outer:74.1,start:0.16,end:0.593),
        .init(ray:4,inner:24.2,outer:74.1,start:0.16,end:0.593),
        .init(ray:2,inner:24.2,outer:74.1,start:0.72,end:1.153),
        .init(ray:6,inner:24.2,outer:74.1,start:0.72,end:1.153),
        .init(ray:1,inner:24.2,outer:48.2,start:0.44,end:0.815),
        .init(ray:5,inner:24.2,outer:48.2,start:0.44,end:0.815),
        .init(ray:1,inner:53.2,outer:61.5,start:0.815,end:1.165),
        .init(ray:5,inner:53.2,outer:61.5,start:0.815,end:1.165),
        .init(ray:1,inner:66.5,outer:89.5,start:1.165,end:1.538),
        .init(ray:5,inner:66.5,outer:89.5,start:1.165,end:1.538),
        .init(ray:7,inner:24.2,outer:36.5,start:1.0,end:1.359),
        .init(ray:3,inner:24.2,outer:36.5,start:1.0,end:1.359),
        .init(ray:7,inner:43.6,outer:90.0,start:1.359,end:1.784),
        .init(ray:3,inner:43.6,outer:90.0,start:1.359,end:1.784),
    ]

    func path(in rect: CGRect) -> Path {
        var path=Path()
        let scale=min(rect.width,rect.height)/Self.unit
        let center=CGPoint(x:rect.midX,y:rect.midY)
        for segment in Self.segments {
            let fraction=max(0,min(1,(time-segment.start)/(segment.end-segment.start)))
            guard fraction > 0 else {continue}
            let angle = -CGFloat.pi/2 + CGFloat(segment.ray) * .pi/4
            let direction=CGPoint(x:cos(angle),y:sin(angle))
            let from=segment.inner*scale
            let to=(segment.inner+(segment.outer-segment.inner)*CGFloat(fraction))*scale
            path.move(to:CGPoint(x:center.x+direction.x*from,y:center.y+direction.y*from))
            path.addLine(to:CGPoint(x:center.x+direction.x*to,y:center.y+direction.y*to))
        }
        return path
    }
}

struct HearStrokeLogo: View {
    var size: CGFloat
    var time: Double = StrokeLogoShape.duration
    var body: some View {
        StrokeLogoShape(time:time)
            .stroke(.white,style:StrokeStyle(lineWidth:size*StrokeLogoShape.lineWidth,lineCap:.butt))
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
}

/// Launch screen (Figma 457:16069): the logo draws itself in once, then 「Hear I am」 sits under it.
/// Shown only while the app starts, so the motion never repeats or loops.
struct HearLaunchView: View {
    /// Draw-in plus a short hold before the role page takes over.
    static let duration: Double = StrokeLogoShape.duration + 0.6
    @State private var time: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing:36) {
            HearStrokeLogo(size:153,time:time)
            Text("Hear I am").font(.system(size:40,weight:.ultraLight)).foregroundStyle(.white)
        }.offset(y:-43)
            .frame(maxWidth:.infinity,maxHeight:.infinity).background(LandingStyle.canvas).ignoresSafeArea()
            .preferredColorScheme(.dark)
            .accessibilityElement(children:.combine).accessibilityLabel("Hear I am").accessibilityIdentifier("launch.brand")
            .onAppear {
                if reduceMotion {time=StrokeLogoShape.duration}
                else {withAnimation(.linear(duration:StrokeLogoShape.duration)) {time=StrokeLogoShape.duration}}
            }
    }
}

/// The soft white glow above the role page (Figma Ellipse 31: 311×264 blurred ellipse, top at −171).
private struct LandingGlow: View {
    var body: some View {
        Ellipse().fill(Color.white.opacity(0.3)).frame(width:311,height:264).blur(radius:75)
            .offset(y:-171).accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// Role page (Figma 476:3167 · 3204 · 3583). The logo is already drawn here; only the launch screen animates it.
struct RoleSelectionView: View {
    let select:(HearRole)->Void
    @State private var selected:HearRole?
    @State private var showingSettings=false
    var body: some View {
        NavigationStack {
            ZStack(alignment:.top) {
                LandingStyle.canvas.ignoresSafeArea()
                LandingGlow().ignoresSafeArea()
                VStack(spacing:0) {
                    HearStrokeLogo(size:96.5).padding(.top,107)
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
                }
                Button {showingSettings=true} label: {ScanCircleLabel(systemImage:"gearshape")}
                    .buttonStyle(.plain).frame(maxWidth:.infinity,alignment:.trailing).padding(.trailing,18).padding(.top,14)
                    .accessibilityLabel("설정").accessibilityIdentifier("role.settings")
            }
            .safeAreaInset(edge:.bottom,spacing:0) {
                Button {if let selected {select(selected)}} label: {
                    Text("선택한 사용자로 시작하기").font(.system(size:20,weight:.semibold))
                        .foregroundStyle(selected == nil ? LandingStyle.dimButtonText : LandingStyle.canvas)
                        .frame(maxWidth:.infinity).frame(height:50)
                        .background(selected == nil ? LandingStyle.dimButton : Color.white,in:Capsule())
                }.buttonStyle(.plain).disabled(selected == nil)
                    .padding(.horizontal,20).padding(.bottom,6)
                    .accessibilityIdentifier("role.continue")
                    .accessibilityHint(selected == nil ? "먼저 사용자를 선택해주세요" : "")
            }
            .toolbar(.hidden,for:.navigationBar)
            .navigationDestination(isPresented:$showingSettings) {HomeSettingsView()}
            .animation(.easeOut(duration:0.2),value:selected)
        }.preferredColorScheme(.dark)
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
