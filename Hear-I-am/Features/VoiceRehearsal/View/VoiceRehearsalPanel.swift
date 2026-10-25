import SwiftUI

struct VoiceModePicker: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("어떻게 사용할까요?").font(.title2.bold())
            ForEach(VoiceUsageMode.allCases) { mode in
                Button {model.selectVoiceMode(mode)} label: {
                    HStack(spacing:14) {
                        Image(systemName:mode.symbol).font(.title2).frame(width:32)
                        VStack(alignment:.leading,spacing:4) {
                            Text(mode.title).font(.headline)
                            Text(mode.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName:model.voiceMode == mode ? "checkmark.circle.fill" : "circle")
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(model.voiceMode == mode ? Color.hearGreen.opacity(0.09) : Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
                        .overlay(RoundedRectangle(cornerRadius:18).stroke(model.voiceMode == mode ? Color.hearGreen : .clear,lineWidth:2))
                }.buttonStyle(.plain).foregroundStyle(Color.hearGreen)
                    .accessibilityAddTraits(model.voiceMode == mode ? [.isSelected] : [])
            }
            Text("‘연습용’ 또는 ‘실전용’이라고 말해도 돼요.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct VoiceRehearsalPanel: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:10) {
                Image(systemName:model.voiceTurnActive ? "waveform" : model.voiceShouldListen ? "mic.fill" : "mic.slash.fill")
                    .font(.title3).foregroundStyle(Color.hearGreen).accessibilityHidden(true)
                Text(model.voiceStatusTitle).font(.headline)
                Spacer(minLength:0)
                if let mode=model.voiceMode {Text(mode.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)}
            }
            if !model.voiceTranscript.isEmpty {
                Text("“\(model.voiceTranscript)”").font(.subheadline).lineLimit(3)
            }
            if let error=model.voiceInputError {
                Text(error).font(.footnote).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)
            } else {
                Text(model.voiceStatusDetail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if model.voiceCanOfferInput {
                HStack(spacing:12) {
                    Button {model.retryVoiceListening()} label: {
                        Label(model.voiceInputError == nil ? "다시 말하기" : "다시 듣기",systemImage:"mic")
                            .frame(minHeight:44)
                    }.buttonStyle(.plain).foregroundStyle(Color.hearGreen)
                    Spacer()
                    if model.voiceListeningEnabled {
                        Button("음성 끄기") {model.disableVoiceListening()}.frame(minHeight:44).foregroundStyle(.secondary)
                    }
                }.font(.subheadline.weight(.semibold))
            }
        }.padding(14).background(Color.hearGreen.opacity(0.07),in:RoundedRectangle(cornerRadius:18))
            .padding(.horizontal,24).padding(.top,8)
            .accessibilityElement(children:.contain)
    }
}

struct VoiceListeningOverlay: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack(spacing:20) {
            Image(systemName:model.voiceProcessingCommand ? "ellipsis.bubble" : model.voiceTurnActive ? "mic.fill" : "checkmark.circle.fill")
                .font(.system(size:58)).foregroundStyle(Color.hearGreen).accessibilityHidden(true)
            Text(model.voiceProcessingCommand ? "요청을 확인하고 있어요" : model.voiceTurnActive ? "듣고 있어요" : "P\(model.guide?.rehearsalReturnArrivalIndex ?? 0)에 도착했어요")
                .font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(model.voiceTurnActive ? "잠시 멈춰주세요. 말씀을 마치면 요청을 확인해요." : "‘계속’이라고 말하면 다음 지점으로 안내해요.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !model.voiceTranscript.isEmpty, model.voiceTurnActive {
                Text("“\(model.voiceTranscript)”").font(.title3.weight(.medium)).multilineTextAlignment(.center)
                    .padding(16).frame(maxWidth:.infinity).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
            }
            Spacer(minLength:0)
        }.padding(24).padding(.top,24).frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(Color(.systemBackground))
    }
}
