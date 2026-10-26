import SwiftUI

struct PreparationStepBar: View {
    @ObservedObject var model: PreparationViewModel
    let exit: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:12) {
                Text("무대 준비").font(.headline)
                ForEach(PreparationStep.allCases,id:\.self) { step in stepButton(step) }
                Spacer(minLength:0)
                exitButton
            }.fixedSize(horizontal:true,vertical:false)
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Text("무대 준비").font(.headline).fixedSize(horizontal:false,vertical:true)
                        Spacer(minLength:8)
                        exitButton.fixedSize(horizontal:true,vertical:false)
                    }
                    stepMenu
                }
            } else {
                HStack {
                    Text("무대 준비").font(.headline)
                    Spacer(minLength:8)
                    stepMenu
                    exitButton
                }
            }
        }.padding(.vertical,4)
    }
    private var stepMenu: some View {
        Menu {
            ForEach(PreparationStep.allCases,id:\.self) { step in stepButton(step) }
        } label: {
            Label("\(model.step.rawValue+1)/5 \(model.step.title)",systemImage:"chevron.down")
                .font(.subheadline.weight(.semibold)).frame(minHeight:44)
                .fixedSize(horizontal:false,vertical:true)
        }.tint(.hearInk).accessibilityLabel("준비 단계, \(model.step.rawValue+1)단계 \(model.step.title)")
    }
    private var exitButton: some View {
        Button("나가기",action:exit).font(.subheadline).frame(minWidth:44,minHeight:44).disabled(model.busy)
    }
    private func stepButton(_ step: PreparationStep) -> some View {
        Button {model.changeStep(step)} label: {
            Label(step.title,systemImage:model.isComplete(step) ? "checkmark.circle.fill" : (model.step == step ? "largecircle.fill.circle" : "circle"))
                .font(.caption.weight(model.step == step ? .bold : .regular)).frame(minHeight:44)
                .foregroundStyle(model.step == step ? Color.hearInk : .secondary)
        }.disabled(!model.canSelect(step))
            .accessibilityLabel("\(step.rawValue+1)단계 \(step.title)\(model.isComplete(step) ? ", 완료" : "")")
            .accessibilityAddTraits(model.step == step ? .isSelected : [])
    }
}
