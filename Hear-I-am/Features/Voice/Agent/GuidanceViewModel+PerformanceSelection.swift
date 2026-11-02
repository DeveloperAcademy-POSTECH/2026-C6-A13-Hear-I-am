import Foundation
import HearIAmCore

extension GuidanceViewModel {
    var showsVoicePerformances:Bool {voicePerformanceID == nil && !voiceChoosingMode && !helperPreparation}
    var voicePerformanceChoices:[PerformanceVoiceChoice] {
        let ids=voiceSearchIDs ?? voiceStages.map(\.id)
        return PerformanceVoiceMenu.choices(catalog:voiceCatalog,stageIDs:ids)
    }
    var voiceSelectionNames:[String] {
        showsVoicePerformances ? voicePerformanceChoices.map(\.name) : visibleVoiceStages.map {voiceStageTitle($0)}
    }
    var voiceSelectedPerformanceName:String? {
        if voicePerformanceID == PerformanceVoiceMenu.unassignedID {return "미분류 무대"}
        return voiceCatalog.performances.first {$0.id == voicePerformanceID}?.name
    }
    func voiceStageTitle(_ item:ScanManifest)->String {
        [voiceCatalog.venue(for:item.id)?.name,item.name].compactMap {$0}.joined(separator:" · ")
    }
    func selectVoicePerformance(_ id:UUID) {
        guard phase == .selection,!voiceChoosingMode,voicePerformanceChoices.contains(where:{$0.id == id}) else {return}
        prepareForVoiceTouch()
        selected=nil;guide=nil;run=nil;pendingRecord=nil
        voicePerformanceID=id
        voiceSelectionControlsVisible=false
        // One saved stage needs no 「어느 무대?」 question (11/02 test): it is taken straight away.
        if visibleVoiceStages.count == 1, let only=visibleVoiceStages.first {select(only);return}
        announceVoiceStageResults()
    }
    func selectVisibleVoiceItem(_ number:Int) {
        if showsVoicePerformances {
            guard voicePerformanceChoices.indices.contains(number-1) else {read(["화면에 있는 공연 번호를 말씀해주세요."]);return}
            selectVoicePerformance(voicePerformanceChoices[number-1].id)
        } else {
            guard visibleVoiceStages.indices.contains(number-1) else {read(["화면에 있는 무대 번호를 말씀해주세요."]);return}
            select(visibleVoiceStages[number-1])
        }
    }
}
