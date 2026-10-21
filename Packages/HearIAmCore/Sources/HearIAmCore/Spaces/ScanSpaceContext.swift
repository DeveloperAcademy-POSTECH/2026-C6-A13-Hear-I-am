import Foundation

/// Saved with the scan bundle, so a failed save cannot orphan a separate room association.
public struct ScanSpaceContext: Codable, Equatable, Sendable {
    public enum Purpose: String, Codable, Sendable { case performance, base }
    public let venueID: String
    public let roomID: String
    public let purpose: Purpose
    /// Each base scan UUID is an immutable revision. New registrations get a new ID.
    public let baseScanID: UUID?
    public let baseMeshHash: String?
    public let roomArea: StageArea?
    public let checkpointNote: String?
    public let additions: [ObjectMeshLayer]
    public init(venueID: String, roomID: String, purpose: Purpose = .performance,
                baseScanID: UUID? = nil, baseMeshHash: String? = nil, roomArea: StageArea? = nil,
                checkpointNote: String? = nil, additions: [ObjectMeshLayer] = []) {
        self.venueID=venueID;self.roomID=roomID;self.purpose=purpose
        self.baseScanID=baseScanID;self.baseMeshHash=baseMeshHash;self.roomArea=roomArea
        self.checkpointNote=checkpointNote;self.additions=additions
    }
    public func validate(scanID: UUID, route: StageRoute?) throws {
        guard !venueID.isEmpty, !roomID.isEmpty, baseScanID != scanID,
              (baseScanID == nil) == (baseMeshHash == nil),
              baseMeshHash.map({$0.count == 64 && $0.allSatisfy(\.isHexDigit)}) ?? true else {
            throw LabError.invalid("공간 연결 또는 기본 스캔 버전이 올바르지 않습니다.")
        }
        try roomArea?.validate()
        if purpose == .base {
            guard route == nil, roomArea != nil, baseScanID == nil, additions.isEmpty,
                  let note=checkpointNote, note.count<=160, !note.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
                throw LabError.invalid("기본 공간의 범위와 확인점 설명을 확인해주세요.")
            }
        } else {
            guard route != nil else { throw LabError.invalid("공연 동선이 없습니다.") }
        }
        if baseScanID != nil {
            guard let roomArea, let area=route?.area,
                  area.corners.allSatisfy({ point in
                      let p=roomArea.floor(point)
                      return p.x>=(-0.02) && p.y>=(-0.02) && p.x<=roomArea.width+0.02 && p.y<=roomArea.depth+0.02 && abs(point.y-roomArea.floorHeight)<=0.10
                  }) else {throw LabError.invalid("공연 범위가 기본 공간 안 같은 바닥에 있어야 합니다.")}
        }
        guard Set(additions.map(\.objectID)).count == additions.count,
              Set(additions.flatMap(\.meshIDs)).count == additions.flatMap(\.meshIDs).count else {
            throw LabError.invalid("추가 기물 메시가 중복됩니다.")
        }
        for layer in additions {
            guard baseScanID != nil, route?.obstacles.contains(where:{$0.id == layer.objectID}) == true,
                  !layer.meshIDs.isEmpty else { throw LabError.invalid("추가 스캔의 기물 연결이 올바르지 않습니다.") }
        }
    }
}
public struct ObjectMeshLayer: Codable, Equatable, Sendable {
    public let objectID: UUID
    public let meshIDs: [UUID]
    public init(objectID: UUID, meshIDs: [UUID]) {self.objectID=objectID;self.meshIDs=meshIDs}
}

public struct SpaceLibraryPreferences: Codable, Equatable, Sendable {
    public var favorites: Set<String> = []
    public var recentRooms: [String: Date] = [:]
    public init() {}
    public mutating func visit(_ room: String, at date: Date = Date()) {recentRooms[room]=date}
}
