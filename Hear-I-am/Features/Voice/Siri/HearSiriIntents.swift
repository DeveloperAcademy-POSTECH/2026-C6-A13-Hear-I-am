import AppIntents
import Combine
import Foundation
import HearIAmCore

/// Starts voice guidance from Siri (#91). Localized App Shortcuts open the app from outside it.
/// The wake word inside the app (#90) only works while the app is open.
@MainActor final class VoiceLaunch: ObservableObject {
    struct Request: Equatable {
        let id=UUID()
        var stageID: UUID?
        var mode: VoiceUsageMode?
    }
    static let shared=VoiceLaunch()
    @Published var pending: Request?
}

/// A saved stage Siri can find by name.
struct StageEntity: AppEntity {
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"무대")
    static let defaultQuery=StageEntityQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title:"\(name)") }
}

struct StageEntityQuery: EntityStringQuery {
    private func stages() async -> [StageEntity] {
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let records=(try? await ScanStore(root:docs.appendingPathComponent("Scans",isDirectory:true)).list()) ?? []
        let catalog=(try? await PerformanceCatalogStore(root:docs.appendingPathComponent("Performances",isDirectory:true)).load()) ?? PerformanceCatalog()
        return records.filter(\.supportsAlignment).map { record in
            let names=[catalog.folder(for:record.id)?.name,catalog.venue(for:record.id)?.name,record.name].compactMap {$0}
            var unique:[String]=[]
            for name in names where !unique.contains(name) {unique.append(name)}
            return StageEntity(id:record.id,name:unique.joined(separator:" · "))
        }
    }
    func entities(for identifiers: [UUID]) async throws -> [StageEntity] {
        await stages().filter {identifiers.contains($0.id)}
    }
    func entities(matching string: String) async throws -> [StageEntity] {
        let request=VoiceStageSearch.normalized(string)
        return await stages().filter {
            let name=VoiceStageSearch.normalized($0.name)
            return !request.isEmpty && (name.contains(request) || request.contains(name))
        }
    }
    func suggestedEntities() async throws -> [StageEntity] { await stages() }
}

enum GuidanceModeChoice: String, AppEnum {
    case practice, performance
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"사용 방식")
    static let caseDisplayRepresentations: [GuidanceModeChoice: DisplayRepresentation]=[
        .practice:DisplayRepresentation(title:"연습용"),
        .performance:DisplayRepresentation(title:"실전용")
    ]
    var mode: VoiceUsageMode { self == .practice ? .practice : .performance }
}

struct StartVoiceGuidanceIntent: AppIntent {
    static let title: LocalizedStringResource="Hear I am으로 안내 시작"
    static let description=IntentDescription("앱을 열고 말로 무대를 골라 안내를 시작해요. 무대와 사용 방식을 함께 말하면 그 단계로 바로 넘어가요.")
    static let openAppWhenRun=true

    @Parameter(title:"무대") var stage: StageEntity?
    @Parameter(title:"사용 방식") var mode: GuidanceModeChoice?

    @MainActor func perform() async throws -> some IntentResult {
        // The app decides what to ask next: a missing or unclear stage is asked again by voice.
        VoiceLaunch.shared.pending=VoiceLaunch.Request(stageID:stage?.id,mode:mode?.mode)
        return .result()
    }
}

struct HearShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent:StartVoiceGuidanceIntent(),phrases:[
            "Start guidance in \(.applicationName)",
            "Start \(.applicationName)",
            "Open \(.applicationName)"
        ],shortTitle:"Start Guidance",systemImageName:"waveform")
    }
}
