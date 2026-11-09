import SwiftUI
import HearIAmCore

/// The step's how-to card over the camera (Figma 971:15416 · 971:15507 · 452:11233 ·
/// 452:12291 · 452:11746). Boundary takes two pages, the others one. The Camera Control card that
/// followed boundary and objects is gone with the button itself (#152).
struct PreparationIntro: View {
    let step: Int
    let page: Int
    /// Shows another page, or nil to close the card.
    let show: (Int?) -> Void
    /// The design's example stage: a route from the left wing over two objects to the right wing.
    fileprivate static let route=[FloorPoint(-1.5,2),FloorPoint(1.8,2),FloorPoint(5,6),FloorPoint(8,6),FloorPoint(11,2),FloorPoint(13.5,2)]
    fileprivate static let objects: [StageObstacle] = [
        try? StageObstacle(name:"기물 1",kind:.box,vertices:[FloorPoint(1.2,4.8),FloorPoint(2.8,4.8),FloorPoint(2.8,6.4),FloorPoint(1.2,6.4)]),
        try? StageObstacle(name:"기물 2",kind:.platform,vertices:[FloorPoint(3.4,1),FloorPoint(5,1),FloorPoint(5,2.6),FloorPoint(3.4,2.6)],facingEdge:0),
        try? StageObstacle(name:"기물 3",kind:.box,vertices:[FloorPoint(9.2,1.2),FloorPoint(10.8,1.2),FloorPoint(10.8,2.8),FloorPoint(9.2,2.8)]),
    ].compactMap {$0}
    static func pageCount(step: Int) -> Int {step == 1 ? 2 : 1}
    var body: some View {
        // Every page of the step is laid out underneath and only the current one shown, so the card keeps the
        // tallest page's size and does not jump between pages (11/07). The page dots hang 14pt under the card
        // without moving it off centre (971:15416 · 971:15507).
        ZStack {
            ForEach(0..<Self.pageCount(step:step),id:\.self) {index in
                PreparationIntroPage(step:step,page:index,show:show,animates:false).hidden()
            }
        }.fixedSize()
            .overlay {PreparationIntroPage(step:step,page:page,show:show)}
            .padding(28)
            .scanCard()
            // A page change is shown at once, without the press animation carrying the new page in (11/02).
            .transaction {$0.animation=nil;$0.disablesAnimations=true}
            .overlay(alignment:.topTrailing) {
                Button {show(nil)} label: {
                    Image(systemName:"xmark").font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
                        .frame(width:40,height:40).background(ScanChrome.close,in:Circle())
                }.buttonStyle(.plain).padding(16).accessibilityLabel("안내 닫기")
            }
            .overlay(alignment:.bottom) {
                if Self.pageCount(step:step) > 1 {
                    ScanPageDots(count:Self.pageCount(step:step),current:page).offset(y:ScanPageDots.height+14)
                }
            }
    }
}

/// One page of the card: the 220pt illustration, then the title, copy and the two buttons in a 306pt column
/// (Figma 971:15416: 28pt between them, Pretendard 24 semibold over 16 medium, 1.4 line height).
private struct PreparationIntroPage: View {
    let step: Int
    let page: Int
    let show: (Int?) -> Void
    /// The measuring copies under the card stay still; only the page on show moves.
    var animates=true
    private var last: Bool {page+1 >= PreparationIntro.pageCount(step:step)}
    var body: some View {
        HStack(spacing:28) {
            illustration.frame(width:220).frame(maxHeight:.infinity)
                .background(illustrationFill,in:RoundedRectangle(cornerRadius:24,style:.continuous))
                .clipShape(RoundedRectangle(cornerRadius:24,style:.continuous))
            VStack(alignment:.leading,spacing:16) {
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(HearFont.pretendard(.semibold,size:24)).tracking(-0.72).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(detail).font(HearFont.pretendard(.medium,size:16)).tracking(-0.48).lineSpacing(3.3)
                        .foregroundStyle(ScanChrome.secondary).fixedSize(horizontal:false,vertical:true)
                }
                // The same two buttons only change their titles between pages, so 「시작하기」 does not pop in.
                HStack(spacing:6) {
                    ScanCardButton(title:page == 0 ? "다시보지 않기" : "이전으로",primary:false) {show(page == 0 ? nil : page-1)}
                    ScanCardButton(title:last ? "시작하기" : "다음으로") {show(last ? nil : page+1)}
                }
            }.frame(width:306,alignment:.leading).frame(maxHeight:.infinity)
        }
    }
    /// The two boundary pages use their own darker squares (#1E1E23 · #282828); the rest the shared #222327.
    private var illustrationFill: Color {
        guard step == 1 else {return ScanChrome.illustration}
        return page == 0 ? Color(red:30/255,green:30/255,blue:35/255) : Color(red:40/255,green:40/255,blue:40/255)
    }

    @ViewBuilder private var illustration: some View {
        switch step {
        case 0:
            ScanHandsIntroArt(animates:animates)
        case 1:
            // Grey corner dots first; then the four corners placed in order (971:15416 · 452:12490).
            if page == 0 {BoundaryIntroArt(placed:false)} else {BoundaryPlacingArt(animates:animates)}
        default:
            IntroLoop(period:IntroStageArt.period(step:step),animates:animates) {t in IntroStageArt(step:step,time:t)}
        }
    }
    private var title: String {
        switch step {
        case 0: return "공연장 전체를 스캔해주세요"
        case 1: return page == 0 ? "공연할 영역을 정해주세요" : "물체의 포인트 추가"
        case 2: return "기물을 미리 표시해주세요"
        case 3: return "움직일 동선 찍기"
        default: return "확인점 찍기"
        }
    }
    private var detail: String {
        switch step {
        case 0: return "휴대폰을 양손으로 잡고 천천히 움직여주세요. 공연 확정 후에는 스캔 단계로 다시 되돌아 올 수 없어요."
        case 1: return page == 0 ? "실제로 공연할 영역을\n직사각형 모양의 영역으로 지정해주세요\n입장과 퇴장공간은 무대 밖에 있어도 괜찮아요" : "객석 기준 정면 오른쪽 → 정면 왼쪽\n→ 후면 왼쪽 → 후면 오른쪽 순서예요.\n각 점들은 자동으로 연결돼요."
        case 2: return "기물 추가를 통해 십자선을 기준으로 기물의 둘레를 따라 점을 추가한 후 바라볼 방향을 추가해주세요"
        case 3: return "출발점과 도착점은 무대 밖에서도 지정이 가능해요. 중간 지점은 무대 영역안에 놓아주세요. 모든 점들을 포함하여 최대 \(StageRoute.maxPointCount)개의 점을 지정할 수 있어요"
        default: return "+버튼을 눌러 십자선 위치에 확인점을 추가해주세요."
        }
    }
}

/// The boundary pages' picture (971:15416 · 971:15507): the 146×80 stage in 20% white with a 1pt white edge,
/// a dot on each corner, and 「객석」 under it. First page grey dots; second page green dots with a ring on the
/// front right corner, the one placed first. The label sits 16pt under the stage so it clears the dots (11/07).
private struct BoundaryIntroArt: View {
    let placed: Bool
    private static let green=Color(red:0,green:1,blue:64/255)                 // #00FF40
    private static let grey=Color(red:126/255,green:126/255,blue:126/255)     // #7E7E7E
    var body: some View {
        VStack(spacing:16) {
            Rectangle().fill(.white.opacity(0.2)).overlay {Rectangle().strokeBorder(.white,lineWidth:1.08)}
                .frame(width:146,height:80)
                .overlay(alignment:.topLeading) {dot.offset(x:-dotSize/2-ring,y:-dotSize/2-ring)}
                .overlay(alignment:.topTrailing) {dot.offset(x:dotSize/2+ring,y:-dotSize/2-ring)}
                .overlay(alignment:.bottomLeading) {dot.offset(x:-dotSize/2-ring,y:dotSize/2+ring)}
                .overlay(alignment:.bottomTrailing) {
                    ZStack {
                        if placed {Circle().strokeBorder(Self.green,lineWidth:2.16).frame(width:22.3,height:22.3)}
                        dot
                    }.frame(width:dotSize+ring*2,height:dotSize+ring*2).offset(x:dotSize/2+ring,y:dotSize/2+ring)
                }
            Text("객석").font(HearFont.pretendard(.semibold,size:16)).foregroundStyle(.white)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true)
    }
    private var dotSize: CGFloat {placed ? 10 : 8.66}
    private let ring: CGFloat=2.16
    /// A filled dot inside a 2.16pt white ring, as the design's outside stroke.
    private var dot: some View {
        Circle().fill(.white).frame(width:dotSize+ring*2,height:dotSize+ring*2)
            .overlay {Circle().fill(placed ? Self.green : Self.grey).frame(width:dotSize,height:dotSize)}
    }
}

/// A looping clock for the intro drawings (#163): seconds into the current loop, or the finished picture when
/// motion is reduced or the page is only measured.
private struct IntroLoop<Content: View>: View {
    let period: Double
    let animates: Bool
    @ViewBuilder let content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Each card starts its drawing from the beginning when it opens.
    @State private var start=Date()
    var body: some View {
        if animates && !reduceMotion {
            TimelineView(.animation) {timeline in
                content(max(0,timeline.date.timeIntervalSince(start)).truncatingRemainder(dividingBy:period))
            }
        } else {content(period)}
    }
}

private func clamp01(_ value: Double) -> Double {min(1,max(0,value))}
/// Ease in and out over [start, start+length].
private func ease(_ t: Double, _ start: Double, _ length: Double) -> Double {
    let x=clamp01((t-start)/length); return x*x*(3-2*x)
}
/// The last part of every loop fades what was drawn before it starts over.
private func fadeOut(_ t: Double, period: Double) -> Double {1-ease(t,period-0.35,0.3)}

/// The objects, route and checkpoint cards' maps, drawn over time (#163). Objects: the square's four sides one
/// after another, then its facing side in red. Route: from the start, one point at a time. Checkpoints: the
/// route as it is, then the two checkpoints one by one. Each holds the full picture before fading to start over.
private struct IntroStageArt: View {
    let step: Int
    let time: Double
    static func period(step: Int) -> Double {
        switch step {
        case 2: return 4.2
        case 3: return 5.6
        default: return 3.6
        }
    }
    var body: some View {
        let period=Self.period(step:step)
        let fade=time >= period ? 1 : fadeOut(time,period:period)
        switch step {
        case 2:
            ScanStageMap(width:12,depth:8,objects:[PreparationIntro.objects[1]],cornerStates:[false,false,false,false],
                         selectedObject:PreparationIntro.objects[1].id,
                         objectReveal:ease(time,0.3,1.8),facingReveal:ease(time,2.25,0.5),revealOpacity:fade).padding(12)
        case 3:
            // Six points 0.55 s apart, after a short pause on the empty stage.
            ScanStageMap(width:12,depth:8,points:PreparationIntro.route,objects:[PreparationIntro.objects[0],PreparationIntro.objects[2]],
                         cornerStates:[false,false,false,false],dimCorners:true,
                         routeReveal:max(0,(time-0.3)/0.55),revealOpacity:fade).padding(12)
        default:
            ScanStageMap(style:.checkpoint,width:12,depth:8,points:PreparationIntro.route,objects:PreparationIntro.objects,
                         checkpoint:time >= 0.6 ? FloorPoint(3.6,5.6) : nil,secondCheckpoint:time >= 1.3 ? FloorPoint(7.2,3.2) : nil,
                         cornerStates:[false,false,false,false],dimCorners:true,revealOpacity:fade).padding(12)
        }
    }
}

/// The scan card's picture (Figma 452:12825): two open hands either side of a phone held sideways, and
/// 「천천히, 양손으로」 under them. The design's picture is one image, so the hands and phone are drawn here to
/// move on their own (#163): the hands come in and take the phone, move it left and right, then up and down,
/// let go and go back, over and over.
private struct ScanHandsIntroArt: View {
    let animates: Bool
    static let period=6.4
    var body: some View {
        IntroLoop(period:Self.period,animates:animates) {t in
            let rest=t >= Self.period
            // In 0.0–0.8 s the hands come to the phone; they let go at 5.2–5.9 s.
            let grip=rest ? 0 : ease(t,0.2,0.7)*(1-ease(t,5.2,0.7))
            let sway=rest ? 0 : sin(clamp01((t-1.1)/1.8)*2*Double.pi*2)*14
            let lift=rest ? 0 : sin(clamp01((t-3.1)/1.8)*2*Double.pi*2)*8
            VStack(spacing:22) {
                ZStack {
                    ScanIntroPhone()
                    // Holding, the fingertips just cover the phone's ends.
                    hand(mirrored:false).offset(x:-72+grip*30)
                    hand(mirrored:true).offset(x:72-grip*30)
                }
                .offset(x:sway,y:lift)
                .frame(width:220,height:56)
                Text("천천히, 양손으로").font(HearFont.pretendard(.medium,size:11)).foregroundStyle(.white.opacity(0.6))
            }.frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true)
        }
    }
    /// An outlined hand over a fill in the card's colour, so the phone does not show through the palm.
    private func hand(mirrored: Bool) -> some View {
        ZStack {
            Image(systemName:"hand.raised.fill").foregroundStyle(ScanChrome.illustration)
            Image(systemName:"hand.raised").foregroundStyle(.white)
        }
        .font(.system(size:46,weight:.medium))
        .scaleEffect(x:mirrored ? -1 : 1,y:1)
    }
}

/// The phone held sideways in the scan card: white edge, grey screen, the camera island on the left and the
/// home bar along the bottom (452:12825).
private struct ScanIntroPhone: View {
    var body: some View {
        RoundedRectangle(cornerRadius:8,style:.continuous)
            .fill(LinearGradient(colors:[Color(white:0.36),Color(white:0.26)],startPoint:.top,endPoint:.bottom))
            .overlay {RoundedRectangle(cornerRadius:8,style:.continuous).strokeBorder(.white,lineWidth:2.6)}
            .overlay(alignment:.leading) {Capsule().fill(.black).frame(width:3,height:8).padding(.leading,6)}
            .overlay(alignment:.bottom) {Capsule().fill(.white).frame(width:15,height:2).padding(.bottom,5)}
            .frame(width:52,height:31)
    }
}

/// The second boundary page (Figma 452:12490), placed corner by corner (#163): front right, front left, back
/// left, back right, as the copy says. Each corner turns green with the ring on it, the side from the corner
/// before draws in, and the last one closes the rectangle and fills it. It holds, fades and starts over.
private struct BoundaryPlacingArt: View {
    let animates: Bool
    static let period=4.6
    private static let green=Color(red:0,green:1,blue:64/255)                 // #00FF40
    private static let grey=Color(red:126/255,green:126/255,blue:126/255)     // #7E7E7E
    /// Corners in placing order, in the 146×80 stage: front right, front left, back left, back right.
    private static let order=[CGPoint(x:146,y:80),CGPoint(x:0,y:80),CGPoint(x:0,y:0),CGPoint(x:146,y:0)]
    /// When each corner is placed, in seconds into the loop.
    private static let times=[0.4,1.0,1.6,2.2]
    var body: some View {
        IntroLoop(period:Self.period,animates:animates) {t in
            let fade=t >= Self.period ? 1 : fadeOut(t,period:Self.period)
            // The same place as the first page's stage and label, so the picture does not shift between pages.
            VStack(spacing:4) {
                Canvas {context,size in
                    let origin=CGPoint(x:(size.width-146)/2,y:(size.height-80)/2)
                    let at={(p: CGPoint) in CGPoint(x:origin.x+p.x,y:origin.y+p.y)}
                    let placed=Self.times.map {t >= $0}
                    let count=placed.filter {$0}.count
                    var layer=context; layer.opacity=fade
                    // The fill comes in once the last side closes the shape.
                    let closing=ease(t,Self.times[3]+0.05,0.35)
                    var rect=Path(); rect.addLines(Self.order.map(at)); rect.closeSubpath()
                    layer.fill(rect,with:.color(.white.opacity(0.2*closing)))
                    // Each side runs from the corner before and reaches the next one as it is placed; the last
                    // side closes the shape right after.
                    for i in 1..<Self.order.count+1 {
                        let from=Self.order[i-1], to=Self.order[i % Self.order.count]
                        let start=i < Self.order.count ? Self.times[i]-0.3 : Self.times[3]+0.05
                        let drawn=ease(t,start,0.3)
                        guard drawn > 0 else {continue}
                        var side=Path(); side.move(to:at(from)); side.addLine(to:at(to))
                        layer.stroke(side.trimmedPath(from:0,to:drawn),with:.color(.white),lineWidth:1.08)
                    }
                    for i in Self.order.indices {
                        let p=at(Self.order[i]), done=placed[i]
                        let size: CGFloat=done ? 10 : 8.66, ring: CGFloat=2.16
                        var dot=context; if done {dot.opacity=fade}
                        dot.fill(Path(ellipseIn:CGRect(x:p.x-size/2-ring,y:p.y-size/2-ring,width:size+ring*2,height:size+ring*2)),with:.color(.white))
                        dot.fill(Path(ellipseIn:CGRect(x:p.x-size/2,y:p.y-size/2,width:size,height:size)),with:.color(done ? Self.green : Self.grey))
                    }
                    // The ring marks the corner just placed; it pops in a little larger and settles.
                    if count > 0 {
                        let p=at(Self.order[count-1])
                        let pop=1+0.35*(1-ease(t,Self.times[count-1],0.25))
                        let r=22.3/2*pop
                        layer.stroke(Path(ellipseIn:CGRect(x:p.x-r+1.08,y:p.y-r+1.08,width:r*2-2.16,height:r*2-2.16)),with:.color(Self.green),lineWidth:2.16)
                    }
                }.frame(width:180,height:104).padding(.top,-12)
                Text("객석").font(HearFont.pretendard(.semibold,size:16)).foregroundStyle(.white)
            }.frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true)
        }
    }
}

/// The page dots under a multi-page card (971:15416): 6pt dots 6pt apart in a 22pt capsule of 30% black,
/// the current one white and the others 40% white.
struct ScanPageDots: View {
    static let height: CGFloat=22
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing:6) {
            ForEach(0..<count,id:\.self) {i in
                Circle().fill(.white.opacity(i == current ? 1 : 0.4)).frame(width:6,height:6)
            }
        }.padding(.horizontal,12).frame(height:Self.height).background(.black.opacity(0.3),in:Capsule())
            .accessibilityElement().accessibilityLabel("\(count)장 중 \(current+1)장")
    }
}
