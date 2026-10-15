import Foundation
import CryptoKit

public struct MeshSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    /// Column-major local->saved AR-world transform. Mesh vertices remain local.
    public let transform: [Float]
    public let vertices: [Point3]
    public let indices: [UInt32]
    public init(id: UUID, transform: [Float], vertices: [Point3], indices: [UInt32]) {
        self.id=id; self.transform=transform; self.vertices=vertices; self.indices=indices
    }
    public func validate() throws {
        guard transform.count == 16, transform.allSatisfy(\.isFinite),
              abs(transform[3])<0.001, abs(transform[7])<0.001,
              abs(transform[11])<0.001, abs(transform[15]-1)<0.001,
              !vertices.isEmpty, vertices.allSatisfy(\.valid), !indices.isEmpty,
              indices.count % 3 == 0, indices.allSatisfy({Int($0)<vertices.count}) else {
            throw LabError.invalid("메시 좌표 또는 삼각형 인덱스가 유효하지 않습니다.")
        }
    }
}
public struct ScanManifest: Codable, Sendable {
    public var version=1
    public let id: UUID
    public let name: String
    public let date: Date
    public let frame: StageFrame
    public let checkpoint: Point3
    public let worldMapHash: String
    public let meshHash: String
    public let meshCount: Int
    public let vertexCount: Int
    public let device: String
    public let appVersion: String
    public init(id: UUID, name: String, frame: StageFrame, checkpoint: Point3,
                worldMapHash: String, meshHash: String, meshCount: Int, vertexCount: Int,
                device: String, appVersion: String) {
        self.id=id; self.name=name; date=Date(); self.frame=frame; self.checkpoint=checkpoint
        self.worldMapHash=worldMapHash; self.meshHash=meshHash; self.meshCount=meshCount
        self.vertexCount=vertexCount; self.device=device; self.appVersion=appVersion
    }
    public var anchorName: String { "PoC4.reference."+id.uuidString }
    public func validate() throws {
        try frame.validate()
        guard version==1, !name.isEmpty, checkpoint.valid, meshCount>0, vertexCount>0,
              checkpoint.distance(to: frame.origin)>=0.5,
              checkpoint.distance(to: frame.front)>=0.5,
              abs(checkpoint.y-frame.origin.y)<=0.15 else {
            throw LabError.invalid("스캔 버전 또는 기준점 정보가 올바르지 않습니다.")
        }
    }
}
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
                     worldMap: Data, meshes: [MeshSnapshot], device: String, appVersion: String) throws -> ScanManifest {
        guard !worldMap.isEmpty, !meshes.isEmpty, Set(meshes.map(\.id)).count == meshes.count else {
            throw LabError.invalid("공간 지도 또는 메시가 없습니다.")
        }
        for m in meshes { try m.validate() }
        let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
        let meshData=try encoder.encode(meshes)
        let manifest=ScanManifest(id:id, name:name, frame:frame, checkpoint:checkpoint,
            worldMapHash:Self.hash(worldMap), meshHash:Self.hash(meshData), meshCount:meshes.count,
            vertexCount:meshes.reduce(0){$0+$1.vertices.count}, device:device, appVersion:appVersion)
        try manifest.validate()
        let fm=FileManager.default
        try fm.createDirectory(at:root, withIntermediateDirectories:true)
        let dest=root.appendingPathComponent(id.uuidString, isDirectory:true)
        guard !fm.fileExists(atPath:dest.path) else { throw LabError.invalid("같은 스캔을 덮어쓸 수 없습니다. 새 스캔으로 저장하세요.") }
        let temp=root.appendingPathComponent(".saving-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:temp,withIntermediateDirectories:true)
        do {
            try worldMap.write(to:temp.appendingPathComponent("worldmap.bin"),options:.atomic)
            try meshData.write(to:temp.appendingPathComponent("mesh.json"),options:.atomic)
            try encoder.encode(manifest).write(to:temp.appendingPathComponent("manifest.json"),options:.atomic)
            try fm.moveItem(at:temp,to:dest)
            return manifest
        } catch { try? fm.removeItem(at:temp); throw error }
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
        return LoadedScan(manifest:m,worldMap:map,meshes:parts)
    }
}
