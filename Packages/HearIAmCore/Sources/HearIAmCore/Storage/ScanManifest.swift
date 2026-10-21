import Foundation

public struct ScanManifest: Codable, Sendable {
    public var version: Int
    public let route: StageRoute?
    public let photos: [ScanPhoto]
    public let settings: GuideSettings
    public let id: UUID
    public internal(set) var name: String
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
                device: String, appVersion: String, route: StageRoute? = nil, settings: GuideSettings = GuideSettings(), photos: [ScanPhoto] = []) {
        version=route == nil ? 1 : 2; self.route=route; self.settings=settings; self.photos=photos
        self.id=id; self.name=name; date=Date(); self.frame=frame; self.checkpoint=checkpoint
        self.worldMapHash=worldMapHash; self.meshHash=meshHash; self.meshCount=meshCount
        self.vertexCount=vertexCount; self.device=device; self.appVersion=appVersion
    }
    enum CodingKeys: String, CodingKey { case version, route, photos, settings, id, name, date, frame, checkpoint, worldMapHash, meshHash, meshCount, vertexCount, device, appVersion }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        version=try c.decode(Int.self,forKey:.version)
        route=try c.decodeIfPresent(StageRoute.self,forKey:.route)
        photos=try c.decodeIfPresent([ScanPhoto].self,forKey:.photos) ?? []
        // Stages saved with the old 0.35 m clearance use the current one, so they need not be prepared again (#38).
        var saved=try c.decodeIfPresent(GuideSettings.self,forKey:.settings) ?? GuideSettings()
        saved.obstacleClearance=min(saved.obstacleClearance,GuideSettings.routeClearance)
        settings=saved
        id=try c.decode(UUID.self,forKey:.id); name=try c.decode(String.self,forKey:.name)
        date=try c.decode(Date.self,forKey:.date); frame=try c.decode(StageFrame.self,forKey:.frame)
        checkpoint=try c.decode(Point3.self,forKey:.checkpoint)
        worldMapHash=try c.decode(String.self,forKey:.worldMapHash); meshHash=try c.decode(String.self,forKey:.meshHash)
        meshCount=try c.decode(Int.self,forKey:.meshCount); vertexCount=try c.decode(Int.self,forKey:.vertexCount)
        device=try c.decode(String.self,forKey:.device); appVersion=try c.decode(String.self,forKey:.appVersion)
    }
    /// Saved world maps already carry this prefix; renaming it breaks restoring existing stages.
    public var anchorName: String { "PoC4.reference."+id.uuidString }
    public func validate() throws {
        try frame.validate(); try settings.validate()
        guard photos.count<=ScanPhoto.maximumCount, Set(photos.map(\.id)).count==photos.count else {
            throw LabError.invalid("사진 수 또는 식별자가 올바르지 않습니다.")
        }
        for photo in photos {
            try photo.validate()
            if let id=photo.objectID, route?.obstacles.contains(where:{$0.id==id}) != true {
                throw LabError.invalid("사진에 연결된 기물이 없습니다.")
            }
            if let index=photo.routePointIndex, route?.points.indices.contains(index) != true {
                throw LabError.invalid("사진에 연결된 동선 지점이 없습니다.")
            }
        }
        if version == 2 {
            guard let route else { throw LabError.invalid("저장된 경로가 없습니다.") }
            try route.validate()
            guard route.area.corners.allSatisfy({checkpoint.distance(to:$0) >= 0.5}) else {
                throw LabError.invalid("C는 E의 네 꼭짓점과 별개로 선택해야 합니다.")
            }
            guard frame.origin.distance(to:route.area.world(FloorPoint(0,0))) < 0.02,
                  frame.front.distance(to:route.area.world(FloorPoint(0,-1))) < 0.02 else {
                throw LabError.invalid("저장된 무대 정면이 E와 일치하지 않습니다.")
            }
        }
        guard [1,2].contains(version), !name.isEmpty, checkpoint.valid, meshCount>0, vertexCount>0,
              checkpoint.distance(to: frame.origin)>=0.5,
              checkpoint.distance(to: frame.front)>=0.5,
              abs(checkpoint.y-frame.origin.y)<=0.15 else {
            throw LabError.invalid("스캔 버전 또는 기준점 정보가 올바르지 않습니다.")
        }
    }
}
