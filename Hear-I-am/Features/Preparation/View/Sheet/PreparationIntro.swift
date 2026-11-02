import SwiftUI
import HearIAmCore

/// The step's how-to card over the camera (Figma 452:12825 · 452:12401 · 452:12490 · 452:11233 ·
/// 452:11339 · 452:12291 · 452:11746). Boundary and objects take two pages; the others one.
struct PreparationIntro: View {
    let step: Int
    let page: Int
    /// Shows another page, or nil to close the card.
    let show: (Int?) -> Void
    /// The design's example stage: a route from the left wing over two objects to the right wing.
    private static let route=[FloorPoint(-1.5,2),FloorPoint(1.8,2),FloorPoint(5,6),FloorPoint(8,6),FloorPoint(11,2),FloorPoint(13.5,2)]
    private static let objects: [StageObstacle] = [
        try? StageObstacle(name:"기물 1",kind:.box,vertices:[FloorPoint(1.2,4.8),FloorPoint(2.8,4.8),FloorPoint(2.8,6.4),FloorPoint(1.2,6.4)]),
        try? StageObstacle(name:"기물 2",kind:.platform,vertices:[FloorPoint(3.4,1),FloorPoint(5,1),FloorPoint(5,2.6),FloorPoint(3.4,2.6)],facingEdge:0),
        try? StageObstacle(name:"기물 3",kind:.box,vertices:[FloorPoint(9.2,1.2),FloorPoint(10.8,1.2),FloorPoint(10.8,2.8),FloorPoint(9.2,2.8)]),
    ].compactMap {$0}
    static func pageCount(step: Int) -> Int {step == 1 || step == 2 ? 2 : 1}
    private var last: Bool {page+1 >= Self.pageCount(step:step)}

    var body: some View {
        // Figma: 28pt padding and gap, a 220pt #222327 illustration, 24pt title, 16pt copy, 44pt buttons.
        HStack(spacing:28) {
            illustration.frame(width:220).frame(maxHeight:.infinity)
                .background(ScanChrome.illustration,in:RoundedRectangle(cornerRadius:24,style:.continuous))
                .clipShape(RoundedRectangle(cornerRadius:24,style:.continuous))
            VStack(alignment:.leading,spacing:16) {
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.system(size:24,weight:.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                    Text(detail).font(.system(size:16,weight:.medium)).foregroundStyle(ScanChrome.secondary).lineSpacing(3)
                        .fixedSize(horizontal:false,vertical:true)
                }
                // The same two buttons only change their titles between pages, so 「시작하기」 does not pop in.
                HStack(spacing:6) {
                    ScanCardButton(title:page == 0 ? "다시보지 않기" : "이전으로",primary:false) {show(page == 0 ? nil : page-1)}
                    ScanCardButton(title:last ? "시작하기" : "다음으로") {show(last ? nil : page+1)}
                }
            }.frame(maxWidth:330,alignment:.leading)
        }.padding(28).frame(maxWidth:640).fixedSize(horizontal:false,vertical:true)
            .scanCard()
            // A page change is shown at once, without the press animation carrying the new page in (11/02).
            .transaction {$0.animation=nil;$0.disablesAnimations=true}
            .overlay(alignment:.topTrailing) {
                Button {show(nil)} label: {
                    Image(systemName:"xmark").font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
                        .frame(width:40,height:40).background(ScanChrome.close,in:Circle())
                }.buttonStyle(.plain).padding(16).accessibilityLabel("안내 닫기")
            }
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
            // White corner dots first; then every corner green with the last one ringed (452:12401 · 12490).
            ScanStageMap(width:12,depth:8,cornerStates:page == 0 ? [false,false,false,false] : [true,true,true,true],activeCorner:page == 0 ? nil : 1).padding(12)
        case 2:
            if page == 0 {
                ScanStageMap(width:12,depth:8,objects:[Self.objects[1]],cornerStates:[false,false,false,false],selectedObject:Self.objects[1].id).padding(12)
            } else {
                // The Camera Control button on the phone's edge (452:11339).
                Image("ScanCameraControl").resizable().scaledToFill().frame(width:220).clipped()
            }
        case 3:
            ScanStageMap(width:12,depth:8,points:Self.route,objects:[Self.objects[0],Self.objects[2]],cornerStates:[false,false,false,false],dimCorners:true).padding(12)
        default:
            ScanStageMap(style:.checkpoint,width:12,depth:8,points:Self.route,objects:Self.objects,checkpoint:FloorPoint(3.6,5.6),secondCheckpoint:FloorPoint(7.2,3.2),cornerStates:[false,false,false,false],dimCorners:true).padding(12)
        }
    }
    private var title: String {
        switch step {
        case 0: return "공연장 전체를 스캔해주세요"
        case 1: return page == 0 ? "공연할 영역을 정해주세요" : "물체의 포인트 추가"
        case 2: return page == 0 ? "기물을 미리 표시해주세요" : "물체의 포인트 추가"
        case 3: return "움직일 동선 찍기"
        default: return "확인(기준)점 찍기"
        }
    }
    private var detail: String {
        switch step {
        case 0: return "휴대폰을 양손으로 잡고 천천히 움직여주세요. 공연 확정 후에는 스캔 단계로 다시 되돌아 올 수 없어요."
        case 1: return page == 0 ? "실제로 공연할 영역을 직사각형 모양의 영역으로 지정해주세요 입장과 퇴장공간은 무대 밖에 있어도 괜찮아요" : "객석 기준 정면 오른쪽 → 정면 왼쪽 → 후면 왼쪽 → 후면 오른쪽 순서예요. 각 점들은 자동으로 연결돼요."
        case 2: return page == 0 ? "기물 추가를 통해 십자선을 기준으로 기물의 둘레를 따라 점을 추가한 후 바라볼 방향을 추가해주세요" : "기기의 상단 카메라 컨트롤 버튼 혹은 +버튼을 통해서 점을 추가해주세요 우측 상단 빛나는 부분을 확인해주세요"
        case 3: return "출발점과 도착점은 무대 밖에서도 지정이 가능해요. 중간 지점은 무대 영역안에 놓아주세요. 모든 점들을 포함하여 최대 \(StageRoute.maxPointCount)개의 점을 지정할 수 있어요"
        default: return "기기의 상단 카메라 컨트롤 버튼 혹은 +버튼을 통해서 점을 추가해주세요 우측 상단 빛나는 부분을 확인해주세요"
        }
    }
}
