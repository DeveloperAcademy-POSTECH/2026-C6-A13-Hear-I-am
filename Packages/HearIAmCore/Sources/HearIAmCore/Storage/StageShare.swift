import Foundation

/// What a shared `.heariam` file holds: one performance's stages (or one stage) with the spaces they belong to,
/// and, for a whole performance, its reference routes. Records never travel.
public struct StageShareIndex: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case performance, scene }
    public struct Venue: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public init(id: UUID, name: String) { self.id=id; self.name=name }
    }
    public struct Scene: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let name: String
        /// nil: the sender kept this stage without a space.
        public let venueID: UUID?
        public init(id: UUID, name: String, venueID: UUID?) { self.id=id; self.name=name; self.venueID=venueID }
    }
    public static let currentVersion=1
    public static let maximumScenes=200
    public var version=StageShareIndex.currentVersion
    public let kind: Kind
    public let performanceName: String
    public let venues: [Venue]
    public let scenes: [Scene]
    public let planIDs: [UUID]
    public let appVersion: String
    public let createdAt: Date
    public init(kind: Kind, performanceName: String, venues: [Venue], scenes: [Scene], planIDs: [UUID], appVersion: String, createdAt: Date = Date()) {
        self.kind=kind; self.performanceName=performanceName; self.venues=venues; self.scenes=scenes
        self.planIDs=planIDs; self.appVersion=appVersion; self.createdAt=createdAt
    }
    public func validate() throws {
        guard version==Self.currentVersion else { throw LabError.invalid(L("이 앱보다 새 버전에서 만든 공유 파일이에요. 앱을 업데이트해주세요.")) }
        let names=[performanceName]+venues.map(\.name)+scenes.map(\.name)
        guard !scenes.isEmpty, scenes.count<=Self.maximumScenes, venues.count<=Self.maximumScenes, planIDs.count<=Self.maximumScenes,
              names.allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count<=80}),
              Set(scenes.map(\.id)).count==scenes.count, Set(venues.map(\.id)).count==venues.count,
              Set(planIDs).count==planIDs.count,
              scenes.allSatisfy({scene in scene.venueID.map {id in venues.contains {$0.id==id}} ?? true}),
              kind == .performance || (scenes.count==1 && planIDs.isEmpty) else { throw StageShareArchive.invalid() }
    }
}

public enum StageShare {
    public static let fileExtension="heariam"
    public static let typeIdentifier="com.jiwonkim.heariam.share"
    /// A stage with one checkpoint cannot be aligned again on another visit, so it is never sent.
    public static func isShareable(_ manifest: ScanManifest) -> Bool { manifest.supportsAlignment }

    /// Bytes a stage folder takes on disk, shown before sending. Missing files count as zero.
    public static func folderBytes(_ id: UUID, scansRoot: URL) -> Int64 {
        let dir=scansRoot.appendingPathComponent(id.uuidString,isDirectory:true)
        guard let files=FileManager.default.enumerator(at:dir,includingPropertiesForKeys:[.fileSizeKey]) else { return 0 }
        return files.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys:[.fileSizeKey]).fileSize } }.reduce(0) { $0+Int64($1) }
    }

    /// A file name for the share sheet: the visible name without characters a file system rejects.
    public static func fileName(for name: String) -> String {
        let cleaned=name.components(separatedBy:CharacterSet(charactersIn:"/\\:?%*|\"<>")).joined(separator:" ")
            .trimmingCharacters(in:.whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Hear I am" : String(cleaned.prefix(60)))+"."+fileExtension
    }

    /// Writes the stages exactly as they are stored. A stage whose files no longer match its manifest is refused
    /// rather than sent.
    @discardableResult
    public static func write(kind: StageShareIndex.Kind, performanceName: String, venues: [StageShareIndex.Venue],
                             scenes: [StageShareIndex.Scene], plans: [PerformancePlan], appVersion: String,
                             scansRoot: URL, to url: URL) throws -> StageShareIndex {
        let index=StageShareIndex(kind:kind,performanceName:performanceName,venues:venues,scenes:scenes,
                                  planIDs:plans.map(\.id),appVersion:appVersion)
        try index.validate()
        let writer=try StageShareArchive.Writer(url:url)
        do {
            let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
            try writer.add(encoder.encode(index),at:"share.json")
            for plan in plans {
                try plan.validate()
                try writer.add(encoder.encode(plan),at:"plans/\(plan.id.uuidString).json")
            }
            for scene in scenes {
                let dir=scansRoot.appendingPathComponent(scene.id.uuidString,isDirectory:true)
                let manifestData=try Data(contentsOf:dir.appendingPathComponent("manifest.json"))
                let manifest=try JSONDecoder().decode(ScanManifest.self,from:manifestData)
                try manifest.validate()
                guard manifest.id==scene.id, isShareable(manifest) else {
                    throw LabError.invalid(L("확인점이 하나인 이전 장면은 공유할 수 없어요."))
                }
                let map=try Data(contentsOf:dir.appendingPathComponent("worldmap.bin"))
                let mesh=try Data(contentsOf:dir.appendingPathComponent("mesh.json"))
                guard ScanStore.hash(map)==manifest.worldMapHash, ScanStore.hash(mesh)==manifest.meshHash else {
                    throw LabError.invalid(L("‘%@’ 장면 파일이 손상되어 공유할 수 없어요.", manifest.name))
                }
                let prefix="scenes/\(scene.id.uuidString)/"
                try writer.add(manifestData,at:prefix+"manifest.json")
                try writer.add(map,at:prefix+"worldmap.bin")
                try writer.add(mesh,at:prefix+"mesh.json")
                let colors=dir.appendingPathComponent("surface-colors.json")
                if FileManager.default.fileExists(atPath:colors.path) { try writer.add(Data(contentsOf:colors),at:prefix+"surface-colors.json") }
                // A photo that went missing is left out; the stage still opens without it, as it does here.
                for photo in manifest.photos {
                    for name in [photo.id.uuidString+".jpg",photo.id.uuidString+"-thumb.jpg"] {
                        let file=dir.appendingPathComponent("photos").appendingPathComponent(name)
                        if let data=try? Data(contentsOf:file) { try writer.add(data,at:prefix+"photos/"+name) }
                    }
                }
            }
            try writer.finish()
            return index
        } catch {
            try? FileManager.default.removeItem(at:url)
            throw error
        }
    }
}

/// A received file, opened but not yet saved anywhere. Nothing is written until a stage is staged.
public struct StageShareFile: Sendable {
    public let index: StageShareIndex
    private let reader: StageShareArchive.Reader

    public init(url: URL) throws {
        reader=try StageShareArchive.Reader(url:url)
        let decoded: StageShareIndex
        do { decoded=try JSONDecoder().decode(StageShareIndex.self,from:reader.data("share.json")) }
        catch let error as LabError { throw error }
        catch { throw StageShareArchive.invalid() }
        try decoded.validate()
        let scenes=Set(decoded.scenes.map(\.id.uuidString)), plans=Set(decoded.planIDs.map(\.uuidString))
        for path in reader.entries.keys {
            let parts=path.split(separator:"/").map(String.init)
            if parts[0]=="scenes", !scenes.contains(parts[1]) { throw StageShareArchive.invalid() }
            if parts[0]=="plans", !plans.contains(String(parts[1].dropLast(5))) { throw StageShareArchive.invalid() }
        }
        for id in scenes {
            for name in ["manifest.json","worldmap.bin","mesh.json"] where reader.entries["scenes/\(id)/\(name)"]==nil {
                throw StageShareArchive.invalid()
            }
        }
        for id in plans where reader.entries["plans/\(id).json"]==nil { throw StageShareArchive.invalid() }
        index=decoded
    }

    /// Bytes this stage takes inside the file.
    public func bytes(of sceneID: UUID) -> Int64 {
        let prefix="scenes/\(sceneID.uuidString)/"
        return reader.entries.values.filter { $0.path.hasPrefix(prefix) }.reduce(0) { $0+Int64($1.rawSize) }
    }

    public func plans() throws -> [PerformancePlan] {
        try index.planIDs.map { id in
            let plan: PerformancePlan
            do { plan=try JSONDecoder().decode(PerformancePlan.self,from:reader.data("plans/\(id.uuidString).json")) }
            catch let error as LabError { throw error }
            catch { throw StageShareArchive.invalid() }
            try plan.validate()
            guard plan.id==id else { throw StageShareArchive.invalid() }
            return plan
        }
    }

    /// Writes one stage into `stagingRoot/<id>` and checks it the way a saved stage is checked when it is opened:
    /// manifest, map and mesh hashes, mesh counts, and every photo it names. Photos it does not name stay behind.
    public func stageScene(_ id: UUID, in stagingRoot: URL) async throws -> ScanManifest {
        guard index.scenes.contains(where:{$0.id==id}) else { throw StageShareArchive.invalid() }
        let prefix="scenes/\(id.uuidString)/"
        let dir=stagingRoot.appendingPathComponent(id.uuidString,isDirectory:true)
        let fm=FileManager.default
        if fm.fileExists(atPath:dir.path) { try fm.removeItem(at:dir) }
        try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        let manifestData=try reader.data(prefix+"manifest.json")
        let manifest: ScanManifest
        do { manifest=try JSONDecoder().decode(ScanManifest.self,from:manifestData) } catch { throw StageShareArchive.invalid() }
        guard manifest.id==id, StageShare.isShareable(manifest) else { throw StageShareArchive.invalid() }
        try manifestData.write(to:dir.appendingPathComponent("manifest.json"))
        for name in ["worldmap.bin","mesh.json","surface-colors.json"] where reader.entries[prefix+name] != nil {
            try reader.data(prefix+name).write(to:dir.appendingPathComponent(name))
        }
        if !manifest.photos.isEmpty {
            let photos=dir.appendingPathComponent("photos",isDirectory:true)
            try fm.createDirectory(at:photos,withIntermediateDirectories:true)
            for photo in manifest.photos {
                for name in [photo.id.uuidString+".jpg",photo.id.uuidString+"-thumb.jpg"] where reader.entries[prefix+"photos/"+name] != nil {
                    try reader.data(prefix+"photos/"+name).write(to:photos.appendingPathComponent(name))
                }
            }
        }
        let store=ScanStore(root:stagingRoot)
        let loaded=try await store.load(id)
        // The app already shows a stage whose photo is missing; a photo that fails its hash is dropped the same way.
        for photo in loaded.manifest.photos {
            for thumbnail in [false,true] {
                let file=dir.appendingPathComponent("photos").appendingPathComponent(photo.id.uuidString+(thumbnail ? "-thumb.jpg" : ".jpg"))
                guard fm.fileExists(atPath:file.path) else { continue }
                do { _ = try await store.photoData(scanID:id,photoID:photo.id,thumbnail:thumbnail) }
                catch { try fm.removeItem(at:file) }
            }
        }
        return loaded.manifest
    }
}
