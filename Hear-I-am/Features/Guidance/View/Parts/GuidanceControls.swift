import SwiftUI

/// Bottom bar: errors, the line being spoken, replay, and the primary action for the phase.
struct GuidanceControls: View {
    @ObservedObject var library: StageLibrary
    @ObservedObject var model: GuidanceViewModel
    let close: () -> Void
    let saveAndClose: () -> Void
    var body: some View {
        VStack(spacing:10) {
            if let saveError=model.saveError {Text(saveError).font(.footnote).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
            if model.savingRecord {ProgressView("완료 기록을 저장하고 있어요")}
            if let error=model.audioIssue {Text(error).font(.footnote).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
            if model.speaking {
                HStack(alignment:.top,spacing:8) {
                    Image(systemName:"speaker.wave.2.fill").foregroundStyle(Color.hearGreen)
                    Text(model.spokenText).font(.caption).lineLimit(3)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if model.phase != .starting && model.phase != .countdown && !(model.phase == .finishing && model.speaking) {
                Button {model.replay()} label: {
                    Label(model.phase == .finishing ? "종료 안내 다시 듣기" : "설명 다시 듣기",systemImage:"speaker.wave.2")
                        .font(.subheadline.weight(.medium)).frame(minHeight:44).padding(.horizontal,12)
                }.buttonStyle(.plain).foregroundStyle(Color.hearGreen)
                    .disabled(model.speaking || model.savingRecord)
                    .opacity(model.speaking || model.savingRecord ? 0.45 : 1)
            }
            primary
        }.padding(.horizontal,24).padding(.top,12).padding(.bottom,12).background(.regularMaterial)
    }
    @ViewBuilder private var primary: some View {
        switch model.phase {
        case .selection:
            if library.records.isEmpty {GuidanceButton(title:"홈으로 돌아가기",action:close)}
            else {GuidanceButton(title:"이 무대 사용하기",enabled:model.selected != nil && model.instructionDone && !model.speaking) {model.restore()}}
        case .restoring: GuidanceButton(title:"공간 확인 중…",enabled:false) {}
        case .checkpoint: GuidanceButton(title:"확인점 확인하기",enabled:model.canVerify) {model.verifyCheckpoint()}
        case .wear: GuidanceButton(title:"착용 준비 시작",enabled:model.instructionDone && !model.speaking) {model.beginWear()}
        case .countdown: GuidanceButton(title:"착용 시간 다시 시작",secondary:true) {model.beginWear()}
        case .departure: GuidanceButton(title:model.hasStarted ? "안내 다시 시작" : "안내 시작",enabled:model.departureReady && model.instructionDone && !model.speaking) {model.startGuidance()}
        case .starting,.guiding: GuidanceButton(title:"일시정지") {model.pause()}
        case .aligning: GuidanceButton(title:"자동 재개 취소 · 일시정지",secondary:true) {model.pause()}
        case .paused:
            GuidanceButton(title:"확인점 다시 확인",secondary:true) {model.restore()}
            GuidanceButton(title:"안내 다시 시작",enabled:model.canResume && model.instructionDone && !model.speaking) {model.startGuidance()}
        case .interrupted:
            GuidanceButton(title:"확인점 다시 확인") {model.restore()}
        case .failed:
            GuidanceButton(title:"무대 다시 선택",secondary:true) {model.chooseAgain()}
            GuidanceButton(title:"공간 다시 확인",enabled:!model.tracking.busy) {model.restore()}
        case .finishing: GuidanceButton(title:"안내 종료 중…",enabled:false) {}
        case .completed: GuidanceButton(title:model.saveError == nil ? "종료하고 기록 저장" : "기록 저장 다시 시도",enabled:!model.speaking && !model.savingRecord,action:saveAndClose)
        }
    }
}
