import SwiftUI
import HearIAmCore

struct VoiceModePicker: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if let selected=model.selected {
                VStack(alignment:.leading,spacing:8) {
                    Label("선택한 무대",systemImage:"checkmark.circle.fill").font(.subheadline)
                    Text(selected.name).font(.title2.bold()).fixedSize(horizontal:false,vertical:true)
                }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                    .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:20))
            }
            Text("어떻게 사용할까요?").font(.largeTitle.bold())
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
                        .background(model.voiceMode == mode ? Color.primary.opacity(0.09) : Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
                        .overlay(RoundedRectangle(cornerRadius:18).stroke(model.voiceMode == mode ? Color.primary : .clear,lineWidth:2))
                }.buttonStyle(.plain).foregroundStyle(Color.primary)
                    .accessibilityAddTraits(model.voiceMode == mode ? [.isSelected] : [])
            }
            Text("말하거나 누르면 바로 다음 단계로 넘어가요. 취소하면 무대를 다시 선택해요.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct VoiceRehearsalPanel: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:10) {
                Image(systemName:model.voiceTurnActive ? "waveform" : model.voiceShouldListen ? "mic.fill" : "mic.slash.fill")
                    .font(.title3).foregroundStyle(Color.primary).accessibilityHidden(true)
                Text(model.voiceStatusTitle).font(.headline)
                Spacer(minLength:0)
                if let mode=model.voiceMode {Text(mode.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)}
            }
            if !model.voiceTranscript.isEmpty {
                Text("“\(model.voiceTranscript)”").font(.subheadline).lineLimit(3)
            }
            if let error=model.voiceInputError {
                Text(error).font(.footnote).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
            } else {
                Text(model.voiceStatusDetail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if model.canCancelVoiceSelection {
                Button {model.cancelVoiceSelection()} label: {
                    Label("취소 · 이전 선택",systemImage:"arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                }.buttonStyle(.plain)
            }
            if model.voiceCanOfferInput {
                HStack(spacing:12) {
                    Button {model.retryVoiceListening()} label: {
                        Label(model.voiceInputError == nil ? "다시 말하기" : "다시 듣기",systemImage:"mic")
                            .frame(minHeight:44)
                    }.buttonStyle(.plain).foregroundStyle(Color.primary)
                    Spacer()
                    if model.voiceListeningEnabled {
                        Button("음성 끄기") {model.disableVoiceListening()}.frame(minHeight:44).foregroundStyle(.secondary)
                    }
                }.font(.subheadline.weight(.semibold))
            }
        }.padding(14).background(Color.primary.opacity(0.07),in:RoundedRectangle(cornerRadius:18))
            .padding(.horizontal,24).padding(.top,8)
            .accessibilityElement(children:.contain)
    }
}

struct VoiceListeningOverlay: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack(spacing:20) {
            Image(systemName:model.voiceProcessingCommand ? "ellipsis.bubble" : model.voiceTurnActive ? "mic.fill" : "checkmark.circle.fill")
                .font(.system(size:58)).foregroundStyle(Color.primary).accessibilityHidden(true)
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

/// One question per screen: choose the stage first, then choose how to use it.
struct VoiceStagePicker: View {
    @ObservedObject var library: StageLibrary
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text(model.voiceChoosingMode ? "2 / 2 · 사용 방식" : "1 / 2 · 무대 선택")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                if model.voiceChoosingMode {
                    VoiceModePicker(model:model)
                } else {
                    Text("어느 무대를\n사용할까요?").font(.largeTitle.bold())
                    Label("장소나 공연 이름으로 찾아보세요",systemImage:"magnifyingglass")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("예: “효자아트홀과 관련된 무대 열어줘”").font(.footnote).foregroundStyle(.secondary)
                    if let query=model.voiceSearchQuery {
                        HStack {
                            Text("‘\(query)’ 검색 결과").font(.headline)
                            Spacer()
                            Text("\(model.visibleVoiceStages.count)개").foregroundStyle(.secondary)
                        }
                    } else {Text("저장한 무대").font(.headline)}
                    if library.loading {ProgressView("무대를 불러오고 있어요")}
                    if model.visibleVoiceStages.isEmpty && !library.loading {
                        VStack(alignment:.leading,spacing:10) {
                            Image(systemName:"rectangle.stack").font(.largeTitle)
                            Text(model.voiceSearchQuery == nil ? "저장된 무대가 없어요" : "일치하는 무대가 없어요").font(.title2.bold())
                            Text(model.voiceSearchQuery == nil ? "홈에서 공간과 동선을 먼저 저장해주세요." : "다른 이름을 말씀하거나 취소해서 전체 목록으로 돌아가세요.").foregroundStyle(.secondary)
                        }.padding(.vertical,20)
                    }
                    ForEach(Array(model.visibleVoiceStages.enumerated()),id:\.element.id) { index,item in
                        stage(item,number:index+1)
                    }
                    if let error=library.error {
                        Text(error).font(.footnote)
                        Button("목록 다시 불러오기") {
                            Task {
                                await library.refresh()
                                model.voiceStages=library.groups.pinned+library.groups.recent
                            }
                        }
                    }
                }
            }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func stage(_ item:ScanManifest,number:Int) -> some View {
        let usable=item.route.map {$0.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty} ?? false
        return Button {model.select(item)} label: {
            HStack(alignment:.top,spacing:14) {
                Text("\(number)").font(.headline).frame(width:32,height:32)
                    .background(Color.primary,in:Circle()).foregroundStyle(Color(.systemBackground))
                VStack(alignment:.leading,spacing:7) {
                    Text(item.name).font(.headline).fixedSize(horizontal:false,vertical:true)
                    Text(usable ? "내부 지점 \(max(0,(item.route?.points.count ?? 2)-2))개" : "동선 준비가 필요해요")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(item.date.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute()))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Image(systemName:"chevron.right").font(.subheadline)
            }.multilineTextAlignment(.leading).padding(18).frame(maxWidth:.infinity,alignment:.leading)
                .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
        }.buttonStyle(.plain).disabled(!usable).opacity(usable ? 1 : 0.5)
            .accessibilityLabel("\(number)번, \(item.name)")
            .accessibilityHint(usable ? "선택하면 연습용 또는 실전용 선택으로 넘어갑니다" : "사용 가능한 동선을 먼저 준비해야 합니다")
    }
}
