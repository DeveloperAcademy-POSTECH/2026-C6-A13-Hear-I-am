import SwiftUI
import HearIAmCore

struct PreparationIntro: View {
    let step: Int
    let page: Int
    let next: () -> Void
    private let example=[FloorPoint(-2,2),FloorPoint(2,2),FloorPoint(5,6),FloorPoint(8,2),FloorPoint(10,6),FloorPoint(14,2)]
    var body: some View {
        HStack(spacing:28) {
            Group {
                if step == 0 {
                    VStack(spacing:12) {
                        HStack(spacing:8) {Image(systemName:"hand.raised"); Image(systemName:"iphone.gen3.landscape"); Image(systemName:"hand.raised").scaleEffect(x:-1,y:1)}.font(.system(size:50,weight:.light))
                        Text("천천히, 양손으로").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    StageMap(points:step == 3 ? example : [],checkpoint:step == 4 ? FloorPoint(6,4) : nil,
                             cornerStates:step == 1 && page == 1 ? [false,false,false,false] : nil,
                             activeCorner:step == 1 && page == 1 ? 1 : nil)
                }
            }.frame(width:260,height:175)
            VStack(alignment:.leading,spacing:12) {
                Text(title).font(.title3.bold())
                Text(detail).font(.system(size:14)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                ActionButton(title:step == 1 && page == 0 ? "다음" : "시작하기",action:next)
            }.frame(maxWidth:330,alignment:.leading)
        }.padding(26).background(.white,in:RoundedRectangle(cornerRadius:24)).frame(maxWidth:720)
    }
    private var title:String {
        switch step {
        case 0:return "공연장 전체를 스캔해주세요"
        case 1:return page == 0 ? "공연할 영역을 정해주세요" : "네 모서리를 차례로 찍어요"
        case 2:return "기물을 미리 표시해주세요"
        case 3:return "출발부터 도착까지 연결해요"
        default:return "위치를 다시 확인할 기준점이에요"
        }
    }
    private var detail:String {
        switch step {
        case 0:return "휴대폰을 양손으로 잡고 공연장과 백스테이지까지 충분히 담아주세요. 공간 확정 후에는 이 단계로 돌아올 수 없어요."
        case 1:return page == 0 ? "실제로 공연할 부분을 직사각형으로 지정해주세요. 입장·퇴장 공간은 무대 밖에 있어도 괜찮아요." : "객석 기준 앞 오른쪽 → 앞 왼쪽 → 뒤 왼쪽 → 뒤 오른쪽 순서입니다. 네 점은 자동으로 연결돼요."
        case 2:return "① 기물 추가를 누르세요.\n② 십자선을 물체 주변 바닥 모서리에 맞춰 둘레 점을 3~8개 추가하세요. 사각형은 네 점이에요.\n③ 단상·계단은 올라가는 변과 내려오는 변을 각각 여러 개 선택하세요. 미선택 측면은 통과 금지입니다. 기물 등록으로 완료해요."
        case 3:return "출발점과 도착점은 같은 높이의 무대 밖에도 지정할 수 있어요. 중간 지점은 무대 안 바닥 또는 등록한 단상·계단 윗면에 놓아주세요. 출발·도착 포함 최대 6점이에요."
        default:return "다시 찾기 쉬운 바닥이나 고정된 기물의 바닥 접점에 확인점을 찍어주세요. 기물 경계 안쪽 5cm까지 허용하며, 기물 윗면·깊은 내부는 피해주세요. 무대 모서리에서 0.5m 이상 떨어져야 해요."
        }
    }
}
