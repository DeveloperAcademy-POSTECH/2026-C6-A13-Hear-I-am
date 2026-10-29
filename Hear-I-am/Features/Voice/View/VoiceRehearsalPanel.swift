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
                Button {model.selectVoiceMode(mode,advanceAutomatically:false)} label: {
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
            Text("말하면 바로 진행해요. 카드를 누르면 다음 버튼이 나타나요.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// One question per screen: choose the stage first, then choose how to use it.
struct VoiceStagePicker: View {
    @ObservedObject var library: StageLibrary
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text(model.voiceChoosingMode ? "2 / 2 · 사용 방식" : "1 / 2 · 무대 선택")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                if model.voiceChoosingMode {
                    VoiceModePicker(model:model)
                } else {
                    Text("어느 무대를 사용할까요?").font(.title.bold()).fixedSize(horizontal:false,vertical:true)
                    Text("이름이나 번호를 말하거나 목록에서 골라주세요.")
                        .font(.subheadline).foregroundStyle(.secondary)
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
                            Text(model.voiceSearchQuery == nil ? "‘새 스캔’이라고 말하거나 장소 탭에서 새 스캔을 눌러 공간과 동선을 저장해주세요." : "다른 이름을 말씀하거나 취소해서 전체 목록으로 돌아가세요.").foregroundStyle(.secondary)
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
        let usable=item.supportsAlignment && (item.route.map {$0.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty} ?? false)
        let selected=model.selected?.id == item.id
        return Button {model.select(item,advanceAutomatically:false)} label: {
            HStack(alignment:.top,spacing:14) {
                Text("\(number)").font(.headline).frame(width:32,height:32)
                    .background(Color.primary,in:Circle()).foregroundStyle(Color(.systemBackground))
                VStack(alignment:.leading,spacing:7) {
                    Text(item.name).font(.headline).fixedSize(horizontal:false,vertical:true)
                    Text((model.voiceStagePaths[item.id] ?? ["장소 미지정"]).joined(separator:" · "))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text(usable ? "내부 지점 \(max(0,(item.route?.points.count ?? 2)-2))개" : "동선 준비가 필요해요")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(item.date.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute()))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Image(systemName:selected ? "checkmark.circle.fill" : "circle").font(.title3).accessibilityHidden(true)
            }.multilineTextAlignment(.leading).padding(18).frame(maxWidth:.infinity,alignment:.leading)
                .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
                .overlay(RoundedRectangle(cornerRadius:18).stroke(selected ? Color.primary : .clear,lineWidth:2))
        }.buttonStyle(.plain).disabled(!usable).opacity(usable ? 1 : 0.5)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityLabel("\(number)번, \(item.name)")
            .accessibilityHint(usable ? "선택한 후 다음 버튼을 누르면 사용 방식을 선택합니다" : "사용 가능한 동선을 먼저 준비해야 합니다")
    }
}
