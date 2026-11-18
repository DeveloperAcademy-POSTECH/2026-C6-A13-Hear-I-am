import Foundation
import HearIAmCore

/// What the send sheet lists before a file is made: the spaces in order, each with its scenes and their size.
struct StageShareSummary {
    struct Scene: Identifiable {
        let id: UUID
        let name: String
        let bytes: Int64
        /// A scene with one checkpoint is listed but not sent.
        let shareable: Bool
    }
    struct Space: Identifiable {
        let id: UUID?
        let name: String
        let scenes: [Scene]
    }
    let kind: StageShareIndex.Kind
    let title: String
    let performanceName: String
    let spaces: [Space]
    let planCount: Int
    var scenes: [Scene] { spaces.flatMap(\.scenes) }
    var sendable: [Scene] { scenes.filter(\.shareable) }
    var bytes: Int64 { sendable.reduce(0) { $0+$1.bytes } }
    var fileName: String { StageShare.fileName(for:title) }
}

/// A file made for the share sheet. Its folder goes when the share sheet closes.
struct StageShareOutgoing: Identifiable {
    let id=UUID()
    let url: URL
}

/// A received file copied out of the system's inbox, ready to read.
struct StageShareIncoming: Identifiable {
    let id=UUID()
    let url: URL
}

extension StageLibrary {
    nonisolated static let shareFolderPrefix="StageShare-"
    private static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown" }

    func shareSummary(performanceID: UUID) -> StageShareSummary? {
        guard let folder=catalog.performances.first(where:{$0.id==performanceID}) else { return nil }
        let all=scans(in:performanceID)
        var spaces=folder.venues.sorted {$0.updatedAt>$1.updatedAt}.map { venue in
            StageShareSummary.Space(id:venue.id,name:venue.name,scenes:all.filter {catalog.assignments[$0.id]?.venueID==venue.id}.map(shareScene))
        }.filter {!$0.scenes.isEmpty}
        let unfiled=all.filter {catalog.assignments[$0.id]?.venueID==nil}
        if !unfiled.isEmpty { spaces.append(.init(id:nil,name:L("공간 미지정"),scenes:unfiled.map(shareScene))) }
        return StageShareSummary(kind:.performance,title:folder.name,performanceName:folder.name,spaces:spaces,
                                 planCount:referencePlans(for:performanceID).count)
    }
    func shareSummary(sceneID: UUID) -> StageShareSummary? {
        guard let record=records.first(where:{$0.id==sceneID}) else { return nil }
        let venue=catalog.venue(for:sceneID)
        return StageShareSummary(kind:.scene,title:record.name,performanceName:catalog.folder(for:sceneID)?.name ?? record.name,
                                 spaces:[.init(id:venue?.id,name:venue?.name ?? L("공간 미지정"),scenes:[shareScene(record)])],planCount:0)
    }
    private func shareScene(_ record: ScanManifest) -> StageShareSummary.Scene {
        .init(id:record.id,name:record.name,bytes:StageShare.folderBytes(record.id,scansRoot:scans.root),shareable:StageShare.isShareable(record))
    }

    /// Writes the file off the main thread into its own temporary folder.
    func makeShareFile(_ summary: StageShareSummary, performanceID: UUID?) async throws -> StageShareOutgoing {
        let scenes=summary.spaces.flatMap { space in
            space.scenes.filter(\.shareable).map {StageShareIndex.Scene(id:$0.id,name:$0.name,venueID:space.id)}
        }
        guard !scenes.isEmpty else { throw LabError.invalid(L("공유할 수 있는 장면이 없어요. 확인점이 두 개인 장면만 보낼 수 있어요.")) }
        let venues=summary.spaces.compactMap { space in space.id.map {StageShareIndex.Venue(id:$0,name:space.name)} }
            .filter {venue in scenes.contains {$0.venueID==venue.id}}
        let plans=summary.kind == .performance ? performanceID.map {referencePlans(for:$0)} ?? [] : []
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(Self.shareFolderPrefix+UUID().uuidString,isDirectory:true)
        let url=folder.appendingPathComponent(summary.fileName)
        let root=scans.root, kind=summary.kind, name=summary.performanceName, version=Self.appVersion
        try await Task.detached(priority:.userInitiated) {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            do {
                try StageShare.write(kind:kind,performanceName:name,venues:venues,scenes:scenes,plans:plans,appVersion:version,scansRoot:root,to:url)
            } catch {
                try? FileManager.default.removeItem(at:folder); throw error
            }
        }.value
        return StageShareOutgoing(url:url)
    }
    static func removeShareFile(_ outgoing: StageShareOutgoing) {
        try? FileManager.default.removeItem(at:outgoing.url.deletingLastPathComponent())
    }

    /// The system hands an opened file over in Documents/Inbox, which the Files app shows. It is moved into a
    /// temporary folder at once, so only the copy being read exists, and that goes when the import ends.
    static func receive(_ url: URL) throws -> StageShareIncoming {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(shareFolderPrefix+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let copy=folder.appendingPathComponent("received."+StageShare.fileExtension)
        let scoped=url.startAccessingSecurityScopedResource()
        defer { if scoped {url.stopAccessingSecurityScopedResource()} }
        do { try FileManager.default.copyItem(at:url,to:copy) }
        catch { try? FileManager.default.removeItem(at:folder); throw error }
        if isInInbox(url) { try? FileManager.default.removeItem(at:url) }
        return StageShareIncoming(url:copy)
    }
    /// A file that came from a phone nearby: the system's copy goes when its callback returns, so it is moved now.
    nonisolated static func adoptReceived(_ url: URL) throws -> StageShareIncoming {
        let fm=FileManager.default
        let folder=fm.temporaryDirectory.appendingPathComponent(shareFolderPrefix+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        let copy=folder.appendingPathComponent("received."+StageShare.fileExtension)
        do { try fm.moveItem(at:url,to:copy) }
        catch {
            do { try fm.copyItem(at:url,to:copy) } catch { try? fm.removeItem(at:folder); throw error }
        }
        return StageShareIncoming(url:copy)
    }
    static func finishReceiving(_ incoming: StageShareIncoming) {
        try? FileManager.default.removeItem(at:incoming.url.deletingLastPathComponent())
    }
    private static var inbox: URL {
        FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Inbox",isDirectory:true)
    }
    private static func isInInbox(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path==inbox.standardizedFileURL.path
    }

    func importShare(_ file: StageShareFile, choices: StageShareChoices) async throws -> StageShareResult {
        let result=try await StageShareInstaller.install(file,choices:choices,scans:scans,plans:planStore,catalog:catalogStore)
        await refresh()
        return result
    }

    /// At launch: share files left by a closed app, received copies the inbox still holds, and a stage import or
    /// replacement that stopped part way.
    /// Only what is an hour old goes: a file that opened the app arrives at about the same time as this runs.
    func cleanUpSharing() async {
        let fm=FileManager.default, cutoff=Date().addingTimeInterval(-3600)
        func old(_ url: URL) -> Bool { ((try? url.resourceValues(forKeys:[.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) < cutoff }
        for url in (try? fm.contentsOfDirectory(at:fm.temporaryDirectory,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []
        where url.lastPathComponent.hasPrefix(Self.shareFolderPrefix) && old(url) {
            try? fm.removeItem(at:url)
        }
        for url in (try? fm.contentsOfDirectory(at:Self.inbox,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []
        where url.pathExtension.lowercased()==StageShare.fileExtension && old(url) {
            try? fm.removeItem(at:url)
        }
        do { try await scans.recoverInterruptedImports() }
        catch { self.error=L("받다가 멈춘 장면을 정리하지 못했어요: %@", error.localizedDescription) }
    }
}
