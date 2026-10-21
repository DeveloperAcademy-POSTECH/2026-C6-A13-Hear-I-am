import Foundation
import CryptoKit

public struct LoadedScan: Sendable {
    public let manifest: ScanManifest
    public let worldMap: Data
    public let meshes: [MeshSnapshot]
}
/// Actor keeps serialization/disk access off UI; directories are published only after all files exist.
public actor ScanStore {
    public let root: URL
    public init(root: URL) { self.root=root }
    public static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format:"%02x",$0) }.joined() }
    public func save(id: UUID, name: String, frame: StageFrame, checkpoint: Point3,
                     worldMap: Data, meshes: [MeshSnapshot], device: String, appVersion: String, route: StageRoute? = nil, settings: GuideSettings = GuideSettings(), photos: [ScanPhotoSource] = [], space: ScanSpaceContext? = nil) throws -> ScanManifest {
        guard !worldMap.isEmpty, !meshes.isEmpty, Set(meshes.map(\.id)).count == meshes.count else {
            throw LabError.invalid("공간 지도 또는 메시가 없습니다.")
        }
        for m in meshes { try m.validate() }
        let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
        let meshData=try encoder.encode(meshes)
        let manifest=ScanManifest(id:id, name:name, frame:frame, checkpoint:checkpoint,
            worldMapHash:Self.hash(worldMap), meshHash:Self.hash(meshData), meshCount:meshes.count,
            vertexCount:meshes.reduce(0){$0+$1.vertices.count}, device:device, appVersion:appVersion, route:route, settings:settings, photos:photos.map(\.photo),space:space)
        try manifest.validate()
        try Self.validateLayers(manifest, meshes:meshes)
        let fm=FileManager.default
        try fm.createDirectory(at:root, withIntermediateDirectories:true)
        let dest=root.appendingPathComponent(id.uuidString, isDirectory:true)
        guard !fm.fileExists(atPath:dest.path) else { throw LabError.invalid("같은 스캔을 덮어쓸 수 없습니다. 새 스캔으로 저장하세요.") }
        let temp=root.appendingPathComponent(".saving-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:temp,withIntermediateDirectories:true)
        do {
            try worldMap.write(to:temp.appendingPathComponent("worldmap.bin"),options:.atomic)
            try meshData.write(to:temp.appendingPathComponent("mesh.json"),options:.atomic)
            if !photos.isEmpty {
                let photoDir=temp.appendingPathComponent("photos",isDirectory:true)
                try fm.createDirectory(at:photoDir,withIntermediateDirectories:true)
                for source in photos {
                    let image=try Self.checkedPhotoData(source.imageURL,hash:source.photo.imageHash,limit:ScanPhoto.maximumImageBytes)
                    let thumb=try Self.checkedPhotoData(source.thumbnailURL,hash:source.photo.thumbnailHash,limit:ScanPhoto.maximumThumbnailBytes)
                    try image.write(to:photoDir.appendingPathComponent(source.photo.id.uuidString+".jpg"),options:.atomic)
                    try thumb.write(to:photoDir.appendingPathComponent(source.photo.id.uuidString+"-thumb.jpg"),options:.atomic)
                }
            }
            try encoder.encode(manifest).write(to:temp.appendingPathComponent("manifest.json"),options:.atomic)
            try fm.moveItem(at:temp,to:dest)
            return manifest
        } catch { try? fm.removeItem(at:temp); throw error }
    }
    /// Photos load independently: a missing/corrupt image must not hide the saved 3D scan.
    public func photoData(scanID: UUID, photoID: UUID, thumbnail: Bool) throws -> Data {
        let dir=root.appendingPathComponent(scanID.uuidString,isDirectory:true)
        let manifest=try JSONDecoder().decode(ScanManifest.self,from:Data(contentsOf:dir.appendingPathComponent("manifest.json")))
        guard manifest.id==scanID, let photo=manifest.photos.first(where:{$0.id==photoID}) else {
            throw LabError.invalid("사진을 찾을 수 없습니다.")
        }
        try photo.validate()
        let url=dir.appendingPathComponent("photos").appendingPathComponent(photoID.uuidString+(thumbnail ? "-thumb.jpg" : ".jpg"))
        return try Self.checkedPhotoData(url,hash:thumbnail ? photo.thumbnailHash : photo.imageHash,
                                        limit:thumbnail ? ScanPhoto.maximumThumbnailBytes : ScanPhoto.maximumImageBytes)
    }
    private static func checkedPhotoData(_ url: URL, hash: String, limit: Int) throws -> Data {
        let values=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
        guard values.isRegularFile==true, values.isSymbolicLink != true,
              let size=values.fileSize, size>0, size<=limit else { throw LabError.invalid("사진 파일 크기가 올바르지 않습니다.") }
        let data=try Data(contentsOf:url)
        guard data.count<=limit, Self.hash(data)==hash else { throw LabError.invalid("사진 파일이 변경되었거나 손상되었습니다.") }
        return data
    }
    public func list() throws -> [ScanManifest] {
        let fm=FileManager.default
        guard fm.fileExists(atPath:root.path) else { return [] }
        let urls=try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)
        // Do not silently hide a corrupted record.
        return try urls.filter { UUID(uuidString:$0.lastPathComponent) != nil }.map {
            let m=try JSONDecoder().decode(ScanManifest.self,from:Data(contentsOf:$0.appendingPathComponent("manifest.json")))
            try m.validate()
            guard m.id.uuidString==$0.lastPathComponent else { throw LabError.invalid("스캔 ID 불일치") }
            return m
        }.sorted {$0.date>$1.date}
    }
    /// Update only the display name, preserving the original date, identity and scan assets.
    public func rename(_ id: UUID, to name: String) throws -> ScanManifest {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count<=80 else {
            throw LabError.invalid("무대 이름은 1~80자로 입력해주세요.")
        }
        let url=root.appendingPathComponent(id.uuidString,isDirectory:true).appendingPathComponent("manifest.json")
        var manifest=try JSONDecoder().decode(ScanManifest.self,from:Data(contentsOf:url))
        guard manifest.id==id else {throw LabError.invalid("스캔 ID 불일치")}
        try manifest.validate()
        manifest.name=trimmed
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        try encoder.encode(manifest).write(to:url,options:.atomic)
        return manifest
    }
    /// Associate an existing full scan without touching its map, geometry, photos or timestamps.
    /// A base-derived performance cannot move to another physical room.
    public func assign(_ id: UUID, venueID: String, roomID: String) throws -> ScanManifest {
        let url=root.appendingPathComponent(id.uuidString).appendingPathComponent("manifest.json")
        var manifest=try JSONDecoder().decode(ScanManifest.self,from:Data(contentsOf:url))
        guard manifest.id==id, manifest.route != nil, manifest.space?.purpose != .base else {
            throw LabError.invalid("공연 동선이 있는 저장 공간만 연결할 수 있습니다.")
        }
        if let context=manifest.space, context.baseScanID != nil {
            guard context.venueID==venueID, context.roomID==roomID else {
                throw LabError.invalid("기본 공간을 사용한 공연은 다른 장소로 옮길 수 없습니다.")
            }
            return manifest
        }
        manifest.space=ScanSpaceContext(venueID:venueID,roomID:roomID)
        try manifest.validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        try encoder.encode(manifest).write(to:url,options:.atomic)
        return manifest
    }
    private static func validateLayers(_ manifest: ScanManifest, meshes: [MeshSnapshot]) throws {
        let ids=Set(meshes.map(\.id))
        guard manifest.space?.additions.flatMap(\.meshIDs).allSatisfy({ids.contains($0)}) ?? true else {
            throw LabError.invalid("추가 기물의 메시가 없습니다.")
        }
    }
    /// Remove only the selected scan bundle; completed guidance records live in a separate store.
    public func delete(_ id: UUID) throws {
        let directory=root.appendingPathComponent(id.uuidString,isDirectory:true)
        if FileManager.default.fileExists(atPath:directory.path) {try FileManager.default.removeItem(at:directory)}
    }
    public func load(_ id: UUID) throws -> LoadedScan {
        let dir=root.appendingPathComponent(id.uuidString,isDirectory:true)
        let m=try JSONDecoder().decode(ScanManifest.self,from:Data(contentsOf:dir.appendingPathComponent("manifest.json")))
        try m.validate()
        let map=try Data(contentsOf:dir.appendingPathComponent("worldmap.bin"))
        let mesh=try Data(contentsOf:dir.appendingPathComponent("mesh.json"))
        guard m.id==id, Self.hash(map)==m.worldMapHash, Self.hash(mesh)==m.meshHash else {
            throw LabError.invalid("저장 파일이 변경되었거나 손상되었습니다.")
        }
        let parts=try JSONDecoder().decode([MeshSnapshot].self,from:mesh)
        guard parts.count==m.meshCount, Set(parts.map(\.id)).count==parts.count,
              parts.reduce(0,{$0+$1.vertices.count})==m.vertexCount else { throw LabError.invalid("메시 개수 불일치") }
        for part in parts { try part.validate() }
        try Self.validateLayers(m,meshes:parts)
        return LoadedScan(manifest:m,worldMap:map,meshes:parts)
    }
}
