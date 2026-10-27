import SwiftUI

/// Bottom bar: errors, the line being spoken, replay, and the primary action for the phase.
struct GuidanceControls: View {
    @ObservedObject var library: StageLibrary
    @ObservedObject var model: GuidanceViewModel
    let close: () -> Void
    let saveAndClose: () -> Void
    var body: some View {
        VStack(spacing:10) {
            if let saveError=model.saveError {Text(saveError).font(.footnote).foregroundStyle(model.voiceExperiment ? Color.primary : Color.red).fixedSize(horizontal:false,vertical:true)}
            if model.savingRecord {ProgressView("완료 기록을 저장하고 있어요")}
            if let error=model.audioIssue {Text(error).font(.footnote).foregroundStyle(model.voiceExperiment ? Color.primary : Color.red).fixedSize(horizontal:false,vertical:true)}
            if model.speaking && !(model.voiceExperiment && model.phase == .selection) {
                HStack(alignment:.top,spacing:8) {
                    Image(systemName:"speaker.wave.2.fill").foregroundStyle(model.voiceExperiment ? Color.primary : Color.hearGreen)
                    Text(model.spokenText).font(.caption).lineLimit(3)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if model.voiceExperiment && model.phase == .selection {
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:16) {selectionSecondaryActions}
                    VStack(spacing:0) {selectionSecondaryActions}
                }
            }
            if !(model.voiceExperiment && model.phase == .selection) && model.phase != .starting && !(model.phase == .finishing && model.speaking) {
                Button {model.replay()} label: {
                    Label(model.phase == .finishing ? "종료 안내 다시 듣기" : "설명 다시 듣기",systemImage:"speaker.wave.2")
                        .font(.subheadline.weight(.medium)).frame(minHeight:44).padding(.horizontal,12)
                }.buttonStyle(.plain).foregroundStyle(model.voiceExperiment ? Color.primary : Color.hearGreen)
                    .disabled(model.speaking || model.savingRecord)
                    .opacity(model.speaking || model.savingRecord ? 0.45 : 1)
            }
            if model.voiceExperiment && model.phase != .selection && model.canCancelVoiceSelection {
                Button("취소 · 이전 선택") {model.cancelVoiceSelection()}.font(.subheadline).frame(minHeight:44)
            }
            primary
        }.padding(.horizontal,24).padding(.top,12).padding(.bottom,12).background(.regularMaterial)
    }
    @ViewBuilder private var selectionSecondaryActions: some View {
        if model.canCancelVoiceSelection {
            Button {model.cancelVoiceSelection()} label: {
                Label("취소 · 이전 선택",systemImage:"arrow.uturn.backward")
                    .font(.subheadline.weight(.medium)).frame(minHeight:44)
            }.buttonStyle(.plain)
        }
        Button {model.replay()} label: {
            Label("설명 다시 듣기",systemImage:"speaker.wave.2")
                .font(.subheadline.weight(.medium)).frame(minHeight:44)
        }.buttonStyle(.plain)
    }
    private func touch(_ action: () -> Void) {
        model.prepareForVoiceTouch()
        action()
    }
    @ViewBuilder private var primary: some View {
        switch model.phase {
        case .selection:
            if library.records.isEmpty {GuidanceButton(title:"홈으로 돌아가기",action:close)}
            else if model.voiceExperiment {
                GuidanceButton(title:model.voiceChoosingMode ? "다음 · 공간 확인" : "다음 · 사용 방식",enabled:model.canContinueVoiceSelection) {model.continueVoiceSelection()}
            }
            else {GuidanceButton(title:"이 무대 사용하기",enabled:model.selected != nil && model.canAdvanceInstruction) {touch {model.restore()}}}
        case .restoring: GuidanceButton(title:"공간 확인 중…",enabled:false) {}
        case .checkpoint: GuidanceButton(title:"확인점 \(model.tracking.nextCheckpointNumber) 확인하기",enabled:model.canVerify) {touch {model.verifyCheckpoint()}}
        case .wear: GuidanceButton(title:"착용 완료",enabled:model.canAdvanceInstruction && model.tracking.ready) {touch {model.finishWear()}}
        case .departure: GuidanceButton(title:model.hasStarted ? "안내 다시 시작" : "안내 시작",enabled:model.departureReady && model.canAdvanceInstruction) {touch {model.startGuidance()}}
        case .starting,.guiding: GuidanceButton(title:"일시정지") {touch {model.pause()}}
        case .paused:
            GuidanceButton(title:"확인점 다시 확인",secondary:true) {touch {model.restore()}}
            GuidanceButton(title:"안내 다시 시작",enabled:model.canResume && model.canAdvanceInstruction) {touch {model.startGuidance()}}
        case .interrupted:
            GuidanceButton(title:"확인점 다시 확인") {touch {model.restore()}}
        case .failed:
            GuidanceButton(title:"무대 다시 선택",secondary:true) {touch {model.chooseAgain()}}
            GuidanceButton(title:"공간 다시 확인",enabled:!model.tracking.busy) {touch {model.restore()}}
        case .finishing: GuidanceButton(title:"안내 종료 중…",enabled:false) {}
        case .completed: GuidanceButton(title:model.saveError == nil ? "종료하고 기록 저장" : "기록 저장 다시 시도",enabled:!model.savingRecord,action:saveAndClose)
        }
    }
}
