import Foundation

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
