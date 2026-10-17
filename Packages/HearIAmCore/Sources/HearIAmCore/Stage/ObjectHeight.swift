import Foundation

/// Height of a drafted object, read from the scan mesh inside its floor outline. The app only
/// suggests a kind from it; the operator still confirms the object (asked 10/17: telling a platform
/// from an obstacle by itself could send the performer onto a box).
public struct ObjectHeight: Equatable, Sendable {
    /// Tops at or below this are suggested as a platform, above it as an obstacle. Placeholder until
    /// the real platform and obstacle heights are known.
    public static let platformMax=0.30
    /// Below this the mesh shows nothing standing on the floor, so no kind is suggested.
    public static let flatMax=0.03
    /// Mesh above this belongs to walls or the ceiling, not the object.
    public static let ceiling=2.5
    public static let minimumSamples=20
    /// The top is read as the 90th percentile, so a few stray vertices above it do not count.
    static let percentile=0.9

    public let height: Double
    /// Mesh vertices that fell inside the outline.
    public let samples: Int
    public init(height: Double, samples: Int) { self.height=height; self.samples=samples }

    public var suggestedKind: ObstacleKind? {
        height < Self.flatMax ? nil : (height <= Self.platformMax ? .platform : .other)
    }
    public var detail: String {
        String(format:"height=%.2fm samples=%d suggested=%@",height,samples,suggestedKind?.rawValue ?? "none")
    }

    /// nil when the outline is not a valid floor polygon or fewer than `minimumSamples` vertices fall inside it.
    public static func measure(meshes: [MeshSnapshot], outline: [Point3], area: StageArea) -> ObjectHeight? {
        guard let shape=try? StageObstacle(name:"measure",kind:.other,vertices:outline.map(area.floor)) else { return nil }
        let xs=shape.vertices.map(\.x), ys=shape.vertices.map(\.y)
        guard let minX=xs.min(), let maxX=xs.max(), let minY=ys.min(), let maxY=ys.max() else { return nil }
        var heights: [Double]=[]
        for mesh in meshes {
            for p in mesh.worldVertices {
                let h=p.y-area.floorHeight
                guard h <= ceiling else { continue }
                let f=area.floor(p)
                guard f.x >= minX, f.x <= maxX, f.y >= minY, f.y <= maxY, shape.contains(f) else { continue }
                heights.append(h)
            }
        }
        guard heights.count >= minimumSamples else { return nil }
        heights.sort()
        let index=min(heights.count-1,Int((Double(heights.count-1)*percentile).rounded()))
        return ObjectHeight(height:max(0,heights[index]),samples:heights.count)
    }
}

extension MeshSnapshot {
    /// Vertices in the saved AR world, applying the column-major local-to-world transform.
    public var worldVertices: [Point3] {
        let m=transform.map(Double.init)
        return vertices.map { v in
            Point3(m[0]*v.x+m[4]*v.y+m[8]*v.z+m[12],
                   m[1]*v.x+m[5]*v.y+m[9]*v.z+m[13],
                   m[2]*v.x+m[6]*v.y+m[10]*v.z+m[14])
        }
    }
}
