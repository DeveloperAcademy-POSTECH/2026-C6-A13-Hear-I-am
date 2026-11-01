import Foundation

/// One numbering shared by voice and touch: performance folders first, then their stored stages.
public struct PerformanceVoiceChoice: Equatable, Identifiable, Sendable {
    public let id:UUID
    public let name:String
    public let stageIDs:[UUID]
}
public enum PerformanceVoiceMenu {
    public static let unassignedID=UUID(uuidString:"00000000-0000-0000-0000-000000000100")!
    public static func choices(catalog:PerformanceCatalog,stageIDs:[UUID])->[PerformanceVoiceChoice] {
        let available=Set(stageIDs)
        var choices=catalog.performances.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}.compactMap {folder -> PerformanceVoiceChoice? in
            let ids=stageIDs.filter {catalog.assignments[$0]?.performanceID == folder.id}
            guard !ids.isEmpty else {return nil}
            return PerformanceVoiceChoice(id:folder.id,name:folder.name,stageIDs:ids)
        }
        let unassigned=stageIDs.filter {available.contains($0) && catalog.folder(for:$0) == nil}
        if !unassigned.isEmpty {choices.append(.init(id:unassignedID,name:"미분류 무대",stageIDs:unassigned))}
        return choices
    }
}
