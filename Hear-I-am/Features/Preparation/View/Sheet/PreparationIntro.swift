import SwiftUI
import HearIAmCore

/// The step's how-to card over the camera (Figma 452:12825 · 452:12401 · 452:12490 · 452:11233 ·
/// 452:11339 · 452:12291). Boundary and objects take two pages; the others one.
struct PreparationIntro: View {
    let step: Int
    let page: Int
    /// Shows another page, or nil to close the card.
    let show: (Int?) -> Void
    private let example=[FloorPoint(-2,2),FloorPoint(2,2),FloorPoint(5,6),FloorPoint(8,6),FloorPoint(10,2),FloorPoint(14,2)]
    private let exampleObject=try? StageObstacle(name:"기물",kind:.box,vertices:[FloorPoint(2,1),FloorPoint(3.4,1),FloorPoint(3.4,2.4),FloorPoint(2,2.4)])
    static func pageCount(step: Int) -> Int {step == 1 || step == 2 ? 2 : 1}
    private var last: Bool {page+1 >= Self.pageCount(step:step)}

    var body: some View {
        // Figma: 28pt padding and gap, a 220pt #222327 illustration, 24pt title, 16pt copy, 44pt buttons.
        HStack(spacing:28) {
            illustration.frame(width:220).frame(maxHeight:.infinity)
                .background(ScanChrome.illustration,in:RoundedRectangle(cornerRadius:24,style:.continuous))
            VStack(alignment:.leading,spacing:16) {
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.system(size:24,weight:.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                    Text(detail).font(.system(size:16,weight:.medium)).foregroundStyle(ScanChrome.secondary).lineSpacing(3)
                        .fixedSize(horizontal:false,vertical:true)
                }
                HStack(spacing:6) {
                    if page == 0 {ScanCardButton(title:"다시보지 않기",primary:false) {show(nil)}}
                    else {ScanCardButton(title:"이전으로",primary:false) {show(page-1)}}
                    ScanCardButton(title:last ? "시작하기" : "다음으로") {show(last ? nil : page+1)}
                }
            }.frame(maxWidth:306,alignment:.leading)
        }.padding(28).frame(maxWidth:610).fixedSize(horizontal:false,vertical:true)
            .scanCard()
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
            StageMap(width:12,depth:8,cornerStates:page == 0 ? [false,false,false,false] : [true,true,true,false],activeCorner:page == 0 ? nil : 3,v3Style:true).padding(12)
        case 2:
            StageMap(width:12,depth:8,objects:exampleObject.map {[$0]} ?? [],v3Style:true).padding(12)
        case 3:
            StageMap(points:example,v3Style:true).padding(12)
        default:
            StageMap(width:12,depth:8,checkpoint:FloorPoint(4,4),secondCheckpoint:FloorPoint(8,4),v3Style:true).padding(12)
        }
    }
    private var title: String {
        switch step {
        case 0: return "공연장 전체를 스캔해주세요"
        case 1: return page == 0 ? "공연할 영역을 정해주세요" : "네 꼭짓점을 차례로 찍어요"
        case 2: return page == 0 ? "기물을 미리 표시해주세요" : "물체의 포인트 추가"
        case 3: return "움직일 동선 찍기"
        default: return "위치를 다시 확인할 기준점이에요"
        }
    }
    private var detail: String {
        switch step {
        case 0: return "휴대폰을 양손으로 잡고 천천히 움직여주세요. 공간 확정 후에는 스캔 단계로 다시 되돌아 올 수 없어요."
        case 1: return page == 0 ? "실제로 공연할 영역을 직사각형 모양의 영역으로 지정해주세요. 입장과 퇴장공간은 무대 밖에 있어도 괜찮아요." : "객석 기준 정면 오른쪽 → 정면 왼쪽 → 후면 왼쪽 → 후면 오른쪽 순서예요. 각 점들은 자동으로 연결돼요."
        case 2: return page == 0 ? "기물 추가를 누른 뒤 십자선을 기준으로 기물의 둘레를 따라 점을 추가하고, 의자·계단은 바라볼 방향을 골라주세요." : "+ 버튼으로 기물 바닥 둘레에 점을 3~8개 추가해주세요. 사각형은 네 점이에요. 기물 등록으로 완료해요."
        case 3: return "출발점과 도착점은 무대 밖에서도 지정이 가능해요. 중간 지점은 무대 영역 안에 놓아주세요. 모든 점들을 포함하여 최대 \(StageRoute.maxPointCount)개의 점을 지정할 수 있어요."
        default: return "다시 찾기 쉬운 바닥이나 고정된 기물의 바닥 접점에 확인점 1번과 2번을 찍어주세요. 두 점은 1m 이상 떨어뜨리고, 무대 모서리에서 0.5m 이상 떨어져야 해요."
        }
    }
}
