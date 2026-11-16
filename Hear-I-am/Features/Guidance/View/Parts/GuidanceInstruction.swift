import SwiftUI

/// Full-screen instruction for phases without a camera: wear, departure, interrupted, failed.
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
                    Label(model.tracking.ready ? (model.isPractice ? "저장 공간 재인식 완료" : "확인점 검증 완료") : "위치 확인 중",systemImage:model.tracking.ready ? "checkmark.circle.fill" : "circle")
                    Label(model.tracking.heading != nil ? "몸의 방향 확인 완료" : "카메라를 몸 바깥쪽으로 향해주세요",systemImage:"location.north")
                    if let distance=model.startDistance, !model.hasStarted, !model.isPractice { Text("출발점까지 \(distance,format:.number.precision(.fractionLength(1))) m").font(.headline.monospacedDigit()) }
                    Text(model.hasStarted ? "안내를 중단했던 목표부터 이어서 안내해요." : model.isPractice ? "출발점을 거치지 않고 현재 위치에서 P1으로 안내해요. ‘출발’이라고 말해주세요." : "무대 안팎의 스캔한 공간에서 ‘출발점까지 안내’를 누르면 현재 위치에서 출발점까지 안내해요. 출발점에 도착한 뒤 ‘안내 시작’을 눌러 공연 동선을 시작하세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if model.phase == .failed {
                    Text("저장한 공연장인지 확인해주세요. 카메라 권한은 설정 앱에서 변경할 수 있어요.").font(.footnote).foregroundStyle(.secondary)
                    Button("앱 설정 열기") {if let url=URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)}}
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(24).foregroundStyle(HearV3.text)
        }
    }
    @ViewBuilder private func illustration(symbol: String) -> some View {
        if model.phase == .wear { Image("HearV3Waist").resizable().scaledToFit().frame(height:170).frame(maxWidth:.infinity).accessibilityHidden(true) }
        else {
            Image(systemName:symbol).font(.system(size:72,weight:.medium)).foregroundStyle(model.voiceExperiment ? Color.primary : (model.phase == .failed || model.phase == .interrupted ? .red : Color.hearGreen))
                .frame(maxWidth:.infinity).padding(.vertical,24).accessibilityHidden(true)
        }
    }
}
