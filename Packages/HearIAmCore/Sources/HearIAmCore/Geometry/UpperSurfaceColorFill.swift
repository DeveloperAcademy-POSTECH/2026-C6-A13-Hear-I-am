import Foundation
import simd

/// Short upward extrapolation on one connected AR mesh. All donors are ORIGINAL direct observations.
/// No welding across anchors, disconnected surfaces, corners, or missing geometry.
public enum UpperSurfaceColorFill {
    public static let maximumRise=0.30
    public static let maximumSideDistance=0.18
    private static let minimumRise=0.03
    private static let planeTolerance=0.02
    private static let normalAgreement=cos(10.0 * .pi/180)
    private static let maximumColorDifference=0.10
    private static let maximumEdgeLength=0.25
    private static let maximumVisitedVertices=256

    public struct Diagnostics: Codable, Equatable, Sendable {
        public var candidateVertices=0, inferredVertices=0
        public var rejected: [String:Int]=[:]
        public var inferredTriangles=0, inferredAreaSquareMeters=0.0
        public init() {}
        mutating func reject(_ reason: String) {rejected[reason,default:0]+=1}
        mutating func merge(_ other: Self) {
            candidateVertices+=other.candidateVertices;inferredVertices+=other.inferredVertices
            for (key,value) in other.rejected {rejected[key,default:0]+=value}
        }
        public var summary: String {
            "inferredVertices=\(inferredVertices)/\(candidateVertices) inferredTriangles=\(inferredTriangles) " +
            "inferredAreaM2=\(inferredAreaSquareMeters) rejected={" +
            rejected.keys.sorted().map {"\($0)=\(rejected[$0]!)"}.joined(separator:",")+"}"
        }
    }
    public struct FillResult: Sendable {
        public let mesh: MeshSnapshot
        public let diagnostics: Diagnostics
    }

    public static func fill(_ mesh: MeshSnapshot,blockedVertices: Set<Int> = []) -> FillResult {
        var diagnostics=Diagnostics()
        guard (try? mesh.validate()) != nil,let direct=mesh.surfaceColors else {
            return FillResult(mesh:mesh,diagnostics:diagnostics)
        }
        let t=mesh.transform
        let points=mesh.vertices.map {p in
            SIMD3(Double(t[0])*p.x+Double(t[4])*p.y+Double(t[8])*p.z+Double(t[12]),
                  Double(t[1])*p.x+Double(t[5])*p.y+Double(t[9])*p.z+Double(t[13]),
                  Double(t[2])*p.x+Double(t[6])*p.y+Double(t[10])*p.z+Double(t[14]))
        }
        var incident=Array(repeating:[Int](),count:points.count)
        var faceNormals=Array(repeating:SIMD3<Double>.zero,count:mesh.indices.count/3)
        for face in faceNormals.indices {
            let ids=(0..<3).map {Int(mesh.indices[face*3+$0])}
            let cross=simd_cross(points[ids[1]]-points[ids[0]],points[ids[2]]-points[ids[0]])
            let length=simd_length(cross)
            guard length>1e-8 else {continue}
            faceNormals[face]=cross/length
            for id in ids {incident[id].append(face)}
        }
        // A vertex shared by different planes is a barrier, even if their averaged normal looks vertical.
        let normals=incident.map {faces -> SIMD3<Double> in
            guard let first=faces.first else {return .zero}
            let reference=faceNormals[first]
            guard abs(reference.y)<=0.25,faces.allSatisfy({
                abs(faceNormals[$0].y)<=0.25 && abs(simd_dot(reference,faceNormals[$0]))>=normalAgreement
            }) else {return .zero}
            return reference
        }
        var inferred=mesh.inferredSurfaceColors ?? Data(repeating:0,count:direct.count)
        func observed(_ id: Int) -> Bool {direct[id*4+3]==255}
        func blocked(_ id: Int) -> Bool {blockedVertices.contains(id) && !observed(id)}
        func color(_ id: Int) -> SIMD3<Double> {
            SIMD3(Double(direct[id*4]),Double(direct[id*4+1]),Double(direct[id*4+2]))/255
        }
        // Avoid a graph search at every unobserved vertex in a large wall with no nearby measured support.
        let cellSize=0.35
        func cell(_ point: SIMD3<Double>) -> SIMD3<Int> {
            SIMD3(Int(floor(point.x/cellSize)),Int(floor(point.y/cellSize)),Int(floor(point.z/cellSize)))
        }
        var donorCells=[SIMD3<Int>:[Int]]()
        for id in points.indices where observed(id) && simd_length_squared(normals[id])>0.9 {
            donorCells[cell(points[id]),default:[]].append(id)
        }
        for target in points.indices where !observed(target) && inferred[target*4+3]==0 {
            if target%1024==0 && Task.isCancelled {return FillResult(mesh:mesh,diagnostics:Diagnostics())}
            // Floors and unused vertices are not inference candidates.
            guard incident[target].contains(where:{abs(faceNormals[$0].y)<=0.25}) else {continue}
            diagnostics.candidateVertices+=1
            guard !blocked(target) else {diagnostics.reject("observationConflict");continue}
            let normal=normals[target],origin=points[target]
            guard simd_length_squared(normal)>0.9 else {diagnostics.reject("cornerOrNonVertical");continue}
            let tangent=simd_normalize(simd_cross(SIMD3(0.0,1,0),normal))
            let low=cell(origin+SIMD3(-0.25,-maximumRise-1e-8,-0.25))
            let high=cell(origin+SIMD3(0.25,-minimumRise,0.25))
            var nearby=0
            search: for x in low.x...high.x {for y in low.y...high.y {for z in low.z...high.z {
                for donor in donorCells[SIMD3(x,y,z)] ?? [] {
                    let delta=points[donor]-origin
                    if delta.y >= -maximumRise-1e-8 && delta.y <= -minimumRise &&
                        abs(simd_dot(delta,normal))<=planeTolerance &&
                        abs(simd_dot(delta,tangent))<=maximumSideDistance &&
                        abs(simd_dot(normal,normals[donor]))>=normalAgreement {
                        nearby+=1
                        if nearby>=3 {break search}
                    }
                }
            }}}
            guard nearby>=3 else {diagnostics.reject("insufficientDirectSupport");continue}
            var visited: Set<Int>=[target],queue=[target],cursor=0
            var donors=[Int](),context=[Int](),overflow=false
            while cursor<queue.count && !overflow {
                let current=queue[cursor];cursor+=1
                if observed(current) {
                    context.append(current)
                    let rise=origin.y-points[current].y
                    if rise>=minimumRise && rise<=maximumRise+1e-8 {donors.append(current)}
                }
                for face in incident[current] {for corner in 0..<3 {
                    let neighbor=Int(mesh.indices[face*3+corner])
                    guard !visited.contains(neighbor),!blocked(neighbor),simd_length_squared(normals[neighbor])>0.9,
                          abs(simd_dot(normal,normals[neighbor]))>=normalAgreement,
                          simd_distance(points[current],points[neighbor])<=maximumEdgeLength else {continue}
                    let delta=points[neighbor]-origin
                    guard delta.y >= -maximumRise-1e-8,delta.y<=0.06,
                          abs(simd_dot(delta,normal))<=planeTolerance,
                          abs(simd_dot(delta,tangent))<=maximumSideDistance else {continue}
                    guard visited.count<maximumVisitedVertices else {overflow=true;break}
                    visited.insert(neighbor);queue.append(neighbor)
                }}
            }
            guard !overflow else {diagnostics.reject("neighborhoodLimit");continue}
            guard donors.count>=3 else {diagnostics.reject("insufficientDirectSupport");continue}
            let heights=donors.map {points[$0].y},sides=donors.map {simd_dot(points[$0]-origin,tangent)}
            // Two measured height levels, and support on BOTH sides of the column being extended.
            guard heights.max()!-heights.min()!>=0.04,
                  sides.min()! <= -0.025,sides.max()! >= 0.025 else {
                diagnostics.reject("insufficientSupportSpread");continue
            }
            // All directly measured colors in the reachable patch (including at/above target height) agree.
            // Never discard a minority color at a boundary as an "outlier" to fill over it.
            let colors=context.map(color)
            var consistent=true
            for i in colors.indices {
                if colors[(i+1)...].contains(where:{simd_distance(colors[i],$0)>maximumColorDifference}) {consistent=false;break}
            }
            guard consistent else {diagnostics.reject("colorBoundary");continue}
            let mean=donors.reduce(SIMD3<Double>.zero) {$0+color($1)}/Double(donors.count)
            for channel in 0..<3 {inferred[target*4+channel]=UInt8(clamping:Int((mean[channel]*255).rounded()))}
            inferred[target*4+3]=255;diagnostics.inferredVertices+=1
        }
        guard diagnostics.inferredVertices>0 else {return FillResult(mesh:mesh,diagnostics:diagnostics)}
        return FillResult(mesh:MeshSnapshot(id:mesh.id,transform:mesh.transform,vertices:mesh.vertices,indices:mesh.indices,
                                            surfaceColors:direct,inferredSurfaceColors:inferred),diagnostics:diagnostics)
    }
}
