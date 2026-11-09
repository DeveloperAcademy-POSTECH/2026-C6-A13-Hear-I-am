import Foundation
import simd

/// Aggregate counts only: no images, poses, vertex locations or identifying camera content.
/// Observation counts describe vertex × keyframe attempts, not unique pixels or physical objects.
public struct SurfaceColorDiagnostics: Codable, Equatable, Sendable {
    public enum Rejection: String, Sendable {
        case outOfRange, grazingAngle, outsideImage, personMask
        case centerDepthUnavailable, foregroundOcclusion, depthMismatch
        case neighborhoodDepthUnavailable, insufficientNeighbors, clippedColor
    }
    public enum MissingVertex: String, Sendable {
        case insufficientObservations, inconsistentColor, insufficientTimeSeparation
    }
    public let version: Int
    public let policy: String
    public var validFrames=0, invalidFrames=0, skippedMeshes=0
    public var eligibleVertices=0, coloredVertices=0
    public var attemptedObservations=0, acceptedObservations=0, partialNeighborhoodObservations=0
    public var rejectedObservations: [String:Int]=[:]
    public var missingVertices: [String:Int]=[:]
    public var coverageScope="mesh"
    public var eligibleTriangles=0, coloredTriangles=0
    public var grayTrianglesByMissingVertices: [String:Int]=[:]
    public var eligibleAreaSquareMeters=0.0, coloredAreaSquareMeters=0.0
    /// Optional for reports written before upper-surface inference existed. coloredVertices stays DIRECT only.
    public var upperFill: UpperSurfaceColorFill.Diagnostics?

    public init(policy: String) {version=2;self.policy=policy}
    public var coloredAreaFraction: Double {
        eligibleAreaSquareMeters>0 ? coloredAreaSquareMeters/eligibleAreaSquareMeters : 0
    }
    mutating func reject(_ reason: Rejection) {rejectedObservations[reason.rawValue,default:0]+=1}
    mutating func miss(_ reason: MissingVertex) {missingVertices[reason.rawValue,default:0]+=1}

    /// With a route, measure only surfaces that the folder actually renders (floor/replaced objects excluded).
    mutating func measureCoverage(_ meshes: [MeshSnapshot],route: StageRoute?) {
        coverageScope=route == nil ? "mesh" : "folder"
        for mesh in meshes where (try? mesh.validate()) != nil {
            if let route {
                let surface=ReplaySurfaceMesh(mesh:mesh,route:route)
                measure(vertices:surface.vertices,indices:surface.surfaceIndices,colors:surface.displaySurfaceColors,
                        inferred:surface.inferredSurfaceColors)
            } else {
                let t=mesh.transform
                let vertices=mesh.vertices.map {p in
                    Point3(Double(t[0])*p.x+Double(t[4])*p.y+Double(t[8])*p.z+Double(t[12]),
                           Double(t[1])*p.x+Double(t[5])*p.y+Double(t[9])*p.z+Double(t[13]),
                           Double(t[2])*p.x+Double(t[6])*p.y+Double(t[10])*p.z+Double(t[14]))
                }
                measure(vertices:vertices,indices:mesh.indices,colors:mesh.displaySurfaceColors,inferred:mesh.inferredSurfaceColors)
            }
        }
    }
    private mutating func measure(vertices: [Point3],indices: [UInt32],colors: Data?,inferred: Data?) {
        for i in stride(from:0,to:indices.count,by:3) {
            let ids=(0..<3).map {Int(indices[i+$0])}
            let a=vertices[ids[0]].vector,b=vertices[ids[1]].vector,c=vertices[ids[2]].vector
            let normal=simd_cross(b-a,c-a),length=simd_length(normal)
            guard length>1e-8,abs(normal.y)/length<0.65 else {continue}
            eligibleTriangles+=1;eligibleAreaSquareMeters+=length/2
            let missing=ids.filter {colors?[$0*4+3] != 255}.count
            if missing==0 {
                coloredTriangles+=1;coloredAreaSquareMeters+=length/2
                if ids.contains(where:{inferred?[$0*4+3]==255}) {
                    upperFill?.inferredTriangles+=1;upperFill?.inferredAreaSquareMeters+=length/2
                }
            }
            else {grayTrianglesByMissingVertices[String(missing),default:0]+=1}
        }
    }
    public var summary: String {
        func counts(_ values: [String:Int]) -> String {values.keys.sorted().map {"\($0)=\(values[$0]!)"}.joined(separator:",")}
        return "policy=\(policy) frames=\(validFrames) invalidFrames=\(invalidFrames) skippedMeshes=\(skippedMeshes) " +
            "directVertices=\(coloredVertices)/\(eligibleVertices) observations=\(acceptedObservations)/\(attemptedObservations) " +
            "partialNeighborhoods=\(partialNeighborhoodObservations) scope=\(coverageScope) " +
            "triangles=\(coloredTriangles)/\(eligibleTriangles) area=\(Int((coloredAreaFraction*100).rounded()))% " +
            "rejected={\(counts(rejectedObservations))} missingVertices={\(counts(missingVertices))} " +
            "grayTrianglesByMissingVertices={\(counts(grayTrianglesByMissingVertices))} upperFill={\(upperFill?.summary ?? "disabled")}"
    }
}
