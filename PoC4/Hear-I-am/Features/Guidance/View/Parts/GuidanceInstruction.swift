import SwiftUI

/// Full-screen instruction for phases without a camera: wear, countdown, departure, interrupted, failed.
struct GuidanceInstruction: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        let headline=model.headline
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                illustration(symbol:headline.symbol)
                Text(headline.title).font(.largeTitle.bold()).fixedSize(horizontal:false,vertical:true)
                Text(headline.detail).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if let selected=model.selected { Text(selected.name).font(.subheadline).foregroundStyle(.secondary) }
                if model.phase == .departure {
                    Label(model.tracking.ready ? "확인점 검증 완료" : "위치 확인 중",systemImage:model.tracking.ready ? "checkmark.circle.fill" : "circle")
                    Label(model.tracking.heading != nil ? "몸의 방향 확인 완료" : "카메라를 몸 바깥쪽으로 향해주세요",systemImage:"location.north")
                    if let distance=model.startDistance, !model.hasStarted { Text("출발점까지 \(distance,format:.number.precision(.fractionLength(1))) m").font(.headline.monospacedDigit()) }
                    Text(model.hasStarted ? "안내를 중단했던 동선 위에서 재개할 수 있어요." : "출발점까지의 별도 길 안내는 제공하지 않아요. 출발점에서 잠시 멈춰주세요. 어느 방향을 바라봐도 몸의 방향에 맞춰 안내해요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if model.phase == .failed {
                    Text("저장한 공연장인지 확인해주세요. 카메라 권한은 설정 앱에서 변경할 수 있어요.").font(.footnote).foregroundStyle(.secondary)
                    Button("앱 설정 열기") {if let url=URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)}}
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(24)
        }
    }
    @ViewBuilder private func illustration(symbol: String) -> some View {
        if model.phase == .wear { Image("BeltAction").resizable().scaledToFit().frame(height:170).frame(maxWidth:.infinity).accessibilityHidden(true) }
        else if model.phase == .countdown { Text("\(model.countdown)").font(.system(size:100,weight:.semibold,design:.rounded)).monospacedDigit().frame(maxWidth:.infinity).foregroundStyle(Color.hearGreen) }
        else {
            Image(systemName:symbol).font(.system(size:72,weight:.medium)).foregroundStyle(model.phase == .failed || model.phase == .interrupted ? .red : Color.hearGreen)
                .frame(maxWidth:.infinity).padding(.vertical,24).accessibilityHidden(true)
        }
    }
}
