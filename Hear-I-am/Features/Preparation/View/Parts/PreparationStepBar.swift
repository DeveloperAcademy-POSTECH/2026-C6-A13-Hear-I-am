import SwiftUI

struct PreparationStepBar: View {
    @ObservedObject var model: PreparationViewModel
    let exit: () -> Void
    var body: some View {
        HStack(spacing:12) {
            Text(model.isBaseRegistration ? "기본 공간 등록" : "무대 준비").font(.headline)
            ForEach(model.steps,id:\.self) {s in
                if s != .scan {Rectangle().fill(.gray.opacity(0.25)).frame(maxWidth:20).frame(height:1)}
                Button {model.changeStep(s)} label:{
                    HStack(spacing:5) {
                        Image(systemName:model.isComplete(s) ? "checkmark.circle.fill" : (model.step == s ? "largecircle.fill.circle" : "circle"))
                        Text(s.title)
                    }.font(.system(size:12,weight:model.step == s ? .bold : .regular))
                        .foregroundStyle(model.step == s ? Color.hearInk : .secondary)
                }.disabled(!model.canSelect(s)).accessibilityLabel("\(s.rawValue+1)단계 \(s.title)\(model.isComplete(s) ? ", 완료" : "")")
            }
            Spacer(minLength:0)
            Button("나가기",action:exit).font(.subheadline).disabled(model.busy)
        }.padding(.horizontal,20).frame(height:52)
    }
}
