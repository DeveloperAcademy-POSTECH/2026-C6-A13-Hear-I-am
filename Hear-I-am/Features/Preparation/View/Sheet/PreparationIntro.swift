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
                PreparationIntroPage(step:step,page:index,show:show).hidden()
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
            VStack(spacing:14) {
                HStack(spacing:14) {Image(systemName:"hand.raised"); Image(systemName:"iphone.gen3.landscape"); Image(systemName:"hand.raised").scaleEffect(x:-1,y:1)}
                    .font(.system(size:44,weight:.light)).foregroundStyle(.white)
                Text("천천히, 양손으로").font(.caption).foregroundStyle(.white.opacity(0.7))
            }.padding(.vertical,24)
        case 1:
            // Grey corner dots first; then every corner green with the front right one ringed (971:15416 · 971:15507).
            BoundaryIntroArt(placed:page == 1)
        case 2:
            ScanStageMap(width:12,depth:8,objects:[PreparationIntro.objects[1]],cornerStates:[false,false,false,false],selectedObject:PreparationIntro.objects[1].id).padding(12)
        case 3:
            ScanStageMap(width:12,depth:8,points:PreparationIntro.route,objects:[PreparationIntro.objects[0],PreparationIntro.objects[2]],cornerStates:[false,false,false,false],dimCorners:true).padding(12)
        default:
            ScanStageMap(style:.checkpoint,width:12,depth:8,points:PreparationIntro.route,objects:PreparationIntro.objects,checkpoint:FloorPoint(3.6,5.6),secondCheckpoint:FloorPoint(7.2,3.2),cornerStates:[false,false,false,false],dimCorners:true).padding(12)
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
