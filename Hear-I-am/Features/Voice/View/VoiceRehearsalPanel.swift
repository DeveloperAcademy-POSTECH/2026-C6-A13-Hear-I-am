import SwiftUI
import HearIAmCore

struct VoiceModePicker: View {
    @ObservedObject var model:GuidanceViewModel
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("어떻게 진행할까요?").font(.title.bold())
            if let selected=model.selected {
                Text(([model.voiceCatalog.folder(for:selected.id)?.name,model.voiceCatalog.venue(for:selected.id)?.name,selected.name].compactMap {$0}).joined(separator:" · "))
                    .font(.subheadline).foregroundStyle(HearV3.secondary)
            }
            ForEach(VoiceUsageMode.allCases) {mode in
                Button {model.selectVoiceMode(mode)} label: {
                    HStack(alignment:.top,spacing:16) {
                        Image(systemName:mode.symbol).font(.title2).frame(width:30).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:8) {
                            Text(mode.title).font(.headline)
                            Text(mode == .practice ? "혼자 공간을 찾고 현재 위치에서 P1으로 이동해요. 이동 중에는 다시 불러 요청할 수 있어요." : "조력자가 공간과 확인점 두 곳을 확인해요. 안내가 시작되면 마이크가 꺼져요.")
                                .font(.subheadline).foregroundStyle(HearV3.secondary)
                        }
                        Spacer(minLength:0)
                        Image(systemName:"chevron.right").accessibilityHidden(true)
                    }.v3Card(inset:20)
                }.buttonStyle(.plain).accessibilityIdentifier("voice.mode.\(mode.rawValue)")
            }
        }
    }
}

struct VoiceStagePicker: View {
    @ObservedObject var library:StageLibrary
    @ObservedObject var model:GuidanceViewModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                if model.voiceChoosingMode {
                    VoiceModePicker(model:model)
                    Button("무대 다시 선택") {model.cancelVoiceSelection()}
                        .frame(minHeight:48).accessibilityIdentifier("voice.selection.back")
                }
                else {
                    Text(model.showsVoicePerformances ? "어떤 공연을 준비할까요?" : "어느 무대에서 진행할까요?")
                        .font(.title.bold()).fixedSize(horizontal:false,vertical:true)
                    Text(model.voiceSelectedPerformanceName ?? "공연 이름이나 공연장 이름으로 찾아보세요.")
                        .foregroundStyle(HearV3.secondary)
                    if let query=model.voiceSearchQuery {Text("‘\(query)’ 검색 결과").font(.subheadline)}
                    if library.loading {ProgressView("무대를 불러오고 있어요")}
                    if model.showsVoicePerformances {
                        ForEach(Array(model.voicePerformanceChoices.enumerated()),id:\.element.id) {index,item in
                            Button {model.selectVoicePerformance(item.id)} label: {
                                HStack(spacing:16) {
                                    Text(String(format:"%02d",index+1)).font(.caption.monospacedDigit()).foregroundStyle(HearV3.secondary)
                                    VStack(alignment:.leading,spacing:6) {
                                        Text(item.name).font(.headline)
                                        Text("저장된 무대 \(item.stageIDs.count)개").font(.subheadline).foregroundStyle(HearV3.secondary)
                                    }
                                    Spacer(minLength:0)
                                    Image(systemName:"chevron.right").accessibilityHidden(true)
                                }.v3Card(inset:18)
                            }.buttonStyle(.plain).accessibilityLabel("\(index+1)번, \(item.name), 저장된 무대 \(item.stageIDs.count)개")
                                .accessibilityIdentifier("voice.performance.\(item.id)")
                        }
                    } else {
                        ForEach(Array(model.visibleVoiceStages.enumerated()),id:\.element.id) {index,item in stage(item,number:index+1)}
                    }
                    if model.visibleVoiceStages.isEmpty && !library.loading {
                        ContentUnavailableView("저장된 무대를 찾지 못했어요",systemImage:"folder",description:Text("다른 이름으로 요청하거나 조력자 화면에서 무대를 준비해주세요."))
                    }
                    if model.canCancelVoiceSelection {
                        Button("이전 선택으로") {model.cancelVoiceSelection()}.frame(minHeight:48).accessibilityIdentifier("voice.selection.back")
                    }
                    if let error=library.error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("목록 다시 불러오기") {
                            Task {
                                await library.refresh()
                                model.voiceStages=library.groups.pinned+library.groups.recent
                                model.voiceCatalog=library.catalog
                                model.voiceStagePaths=library.voiceStageContexts
                                model.announceVoiceStageResults()
                            }
                        }
                    }
                }
            }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
        }.background(HearV3.canvas).foregroundStyle(HearV3.text)
    }
    private func stage(_ item:ScanManifest,number:Int)->some View {
        let usable=item.supportsAlignment && (item.route.map {$0.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty} ?? false)
        return Button {model.select(item)} label: {
            HStack(alignment:.top,spacing:16) {
                Text(String(format:"%02d",number)).font(.caption.monospacedDigit()).foregroundStyle(HearV3.secondary)
                VStack(alignment:.leading,spacing:8) {
                    Text(model.voiceCatalog.venue(for:item.id)?.name ?? "공연장 미지정").font(.headline)
                    Text(item.name).font(.subheadline)
                    Text(usable ? "\(max(0,(item.route?.points.count ?? 2)-2))개 지점 · \(item.date.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).month().day())) 저장" : "동선 준비가 필요해요")
                        .font(.caption).foregroundStyle(HearV3.secondary)
                }.fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
                Image(systemName:"chevron.right").accessibilityHidden(true)
            }.v3Card(inset:18)
        }.buttonStyle(.plain).disabled(!usable).opacity(usable ? 1 : 0.5)
            .accessibilityLabel("\(number)번, \(model.voiceStageTitle(item))")
            .accessibilityHint(usable ? "사용 방식을 선택합니다" : "사용 가능한 동선을 먼저 준비해야 합니다")
            .accessibilityIdentifier("voice.stage.\(item.id)")
    }
}
