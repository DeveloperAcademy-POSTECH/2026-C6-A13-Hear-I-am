import Foundation

public struct MeshSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    /// Column-major local->saved AR-world transform. Mesh vertices remain local.
    public let transform: [Float]
    public let vertices: [Point3]
    public let indices: [UInt32]
    /// Optional sRGB RGBA8 per vertex. Alpha is observation coverage (0 or 255), not transparency.
    /// Absent in older scans. Used only for display, never for geometry or guidance.
    public let surfaceColors: Data?
    /// Optional RGBA8 estimates, disjoint from directly observed surfaceColors. Never used as observations.
    public let inferredSurfaceColors: Data?
    public init(id: UUID, transform: [Float], vertices: [Point3], indices: [UInt32], surfaceColors: Data? = nil,
                inferredSurfaceColors: Data? = nil) {
        self.id=id; self.transform=transform; self.vertices=vertices; self.indices=indices
        self.surfaceColors=surfaceColors
        self.inferredSurfaceColors=inferredSurfaceColors
    }
    /// Display composition only; persistence and subsequent inference retain the two separate sources.
    public var displaySurfaceColors: Data? {
        guard let inferredSurfaceColors,let surfaceColors,
              surfaceColors.count==vertices.count*4,inferredSurfaceColors.count==surfaceColors.count else {return surfaceColors}
        var combined=surfaceColors
        for i in vertices.indices where surfaceColors[i*4+3]==0 && inferredSurfaceColors[i*4+3]==255 {
            combined.replaceSubrange(i*4..<i*4+4,with:inferredSurfaceColors[i*4..<i*4+4])
        }
        return combined
    }
    public func validate() throws {
        guard transform.count == 16, transform.allSatisfy(\.isFinite),
              abs(transform[3])<0.001, abs(transform[7])<0.001,
              abs(transform[11])<0.001, abs(transform[15]-1)<0.001,
              !vertices.isEmpty, vertices.allSatisfy(\.valid), !indices.isEmpty,
              indices.count % 3 == 0, indices.allSatisfy({Int($0)<vertices.count}) else {
            throw LabError.invalid(L("메시 좌표 또는 삼각형 인덱스가 유효하지 않습니다."))
        }
        if let surfaceColors {
            guard surfaceColors.count == vertices.count*4,
                  stride(from:3,to:surfaceColors.count,by:4).allSatisfy({surfaceColors[$0]==0 || surfaceColors[$0]==255}) else {
                throw LabError.invalid(L("메시 표면 색상 정보가 유효하지 않습니다."))
            }
        }
        if let inferredSurfaceColors {
            guard let surfaceColors,inferredSurfaceColors.count==vertices.count*4,
                  stride(from:3,to:inferredSurfaceColors.count,by:4).allSatisfy({
                      inferredSurfaceColors[$0]==0 || (inferredSurfaceColors[$0]==255 && surfaceColors[$0]==0)
                  }) else {throw LabError.invalid(L("메시 추정 색상 정보가 유효하지 않습니다."))}
        }
    }
}
