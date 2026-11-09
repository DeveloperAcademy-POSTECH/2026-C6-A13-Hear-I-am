import Foundation
import simd

public struct SurfaceColorAlignmentDiagnostics: Codable, Equatable, Sendable {
    public var rasterPolicy="nativeDepthIntegerStride"
    public var meshSource="unavailable"
    public var finalMeshCount=0, cachedMeshCount=0, geometryChangedMeshes=0, addedMeshes=0, removedMeshes=0
    public var maximumMeshTranslationMeters=0.0
    public var maximumCameraTranslationMeters=0.0, maximumCameraRotationDegrees=0.0
    public var cameraTranslationMeters: [String:Int]=[:]
    public init() {}
    public mutating func recordCameraPose(original: simd_float4x4,final: simd_float4x4) {
        let distance=Double(simd_distance(original.columns.3,final.columns.3))
        let trace=simd_dot(original.columns.0,final.columns.0)+simd_dot(original.columns.1,final.columns.1)+simd_dot(original.columns.2,final.columns.2)
        let angle=Double(acos(max(-1,min(1,(trace-1)/2))))*180 / .pi
        maximumCameraTranslationMeters=max(maximumCameraTranslationMeters,distance)
        maximumCameraRotationDegrees=max(maximumCameraRotationDegrees,angle)
        cameraTranslationMeters[distance<=0.02 ? "upTo0.02" : distance<=0.10 ? "0.02To0.10" : distance<=0.50 ? "0.10To0.50" : "over0.50",default:0]+=1
    }
    public mutating func recordMeshes(final: [MeshSnapshot],cached: [MeshSnapshot]) {
        finalMeshCount=final.count;cachedMeshCount=cached.count
        let before=Dictionary(cached.map {($0.id,$0)},uniquingKeysWith: {_,new in new})
        let finalIDs=Set(final.map(\.id))
        removedMeshes=cached.filter {!finalIDs.contains($0.id)}.count
        for mesh in final {
            guard let old=before[mesh.id] else {addedMeshes+=1;continue}
            if old.vertices != mesh.vertices || old.indices != mesh.indices {geometryChangedMeshes+=1}
            if old.transform.count==16,mesh.transform.count==16 {
                let a=SIMD3(old.transform[12],old.transform[13],old.transform[14])
                let b=SIMD3(mesh.transform[12],mesh.transform[13],mesh.transform[14])
                maximumMeshTranslationMeters=max(maximumMeshTranslationMeters,Double(simd_distance(a,b)))
            }
        }
    }
    public var summary: String {
        "raster=\(rasterPolicy) meshSource=\(meshSource) meshes=\(finalMeshCount) cached=\(cachedMeshCount) " +
        "geometryChanged=\(geometryChangedMeshes) added=\(addedMeshes) removed=\(removedMeshes) " +
        "maxMeshTranslationM=\(maximumMeshTranslationMeters) maxCameraTranslationM=\(maximumCameraTranslationMeters) maxCameraRotationDeg=\(maximumCameraRotationDegrees)"
    }
}

/// Numeric evidence, not an object/occlusion classifier. All counts are aggregates, with no poses or images.
public struct SurfaceDepthDiagnostics: Codable, Equatable, Sendable {
    public var rejectedObservations=0
    public var firstFailureLocation: [String:Int]=[:]
    public var firstFailureReason: [String:Int]=[:]
    public var firstResidualMagnitudeMeters: [String:Int]=[:]
    public var firstExcessOverToleranceMeters: [String:Int]=[:]
    public var firstFailureConfidence: [String:Int]=[:]
    public var cameraDepthMeters: [String:Int]=[:]
    public var viewingAngle: [String:Int]=[:]
    public var footprintPatterns: [String:Int]=[:]
    public var reliablePixelsPerFootprint: [String:Int]=[:]
    public var framesWithPersonMask=0, framesWithoutPersonMask=0
    public var verticesWithDepthConflict=0, uncoloredVerticesWithDepthConflict=0, directVerticesWithDepthConflict=0
    public var conflictViewsPerVertex: [String:Int]=[:]
    public var acceptedViewsAtConflictedVertices: [String:Int]=[:]
    public var uncoloredAcceptedViews: [String:Int]=[:]
    public var signPatternsAcrossViews: [String:Int]=[:]
    public var uncoloredSignPatterns: [String:Int]=[:]
    public init() {}

    mutating func record(_ evidence: SurfaceDepthEvidence,reason: SurfaceColorDiagnostics.Rejection) {
        rejectedObservations+=1
        firstFailureLocation[evidence.isCenter ? "center" : "neighbor",default:0]+=1
        firstFailureReason[reason.rawValue,default:0]+=1
        firstFailureConfidence[String(evidence.confidence),default:0]+=1
        cameraDepthMeters[evidence.cameraDepth<=1 ? "upTo1" : evidence.cameraDepth<=2 ? "1To2" : evidence.cameraDepth<=3 ? "2To3" : "3To5",default:0]+=1
        viewingAngle[evidence.facing>=0.85 ? "frontal" : evidence.facing>=0.6 ? "oblique" : "grazing",default:0]+=1
        if let residual=evidence.residual,let tolerance=evidence.tolerance {
            let magnitude=abs(residual),excess=max(0,magnitude-tolerance)
            firstResidualMagnitudeMeters[magnitude<=0.10 ? "upTo0.10" : magnitude<=0.20 ? "0.10To0.20" : magnitude<=0.50 ? "0.20To0.50" : "over0.50",default:0]+=1
            firstExcessOverToleranceMeters[excess<=0.02 ? "upTo0.02" : excess<=0.05 ? "0.02To0.05" : excess<=0.15 ? "0.05To0.15" : "over0.15",default:0]+=1
        } else {
            firstResidualMagnitudeMeters["invalidPrediction",default:0]+=1
            firstExcessOverToleranceMeters["invalidPrediction",default:0]+=1
        }
        footprintPatterns[evidence.pattern,default:0]+=1
        reliablePixelsPerFootprint[String(evidence.reliablePixels),default:0]+=1
    }
    mutating func record(_ vertex: SurfaceVertexDepthEvidence,accepted: Int,direct: Bool) {
        guard vertex.conflicts>0 else {return}
        verticesWithDepthConflict+=1
        let count=accepted==0 ? "zero" : accepted==1 ? "one" : "twoOrMore"
        let sign=vertex.mixedWithinView ? "mixedWithinView" : vertex.near && vertex.far ? "signChangesAcrossViews" : vertex.near ? "nearOnly" : vertex.far ? "farOnly" : "invalidPredictionOnly"
        conflictViewsPerVertex[vertex.conflicts==1 ? "one" : vertex.conflicts<=3 ? "twoOrThree" : "fourOrMore",default:0]+=1
        acceptedViewsAtConflictedVertices[count,default:0]+=1
        signPatternsAcrossViews[sign,default:0]+=1
        if direct {directVerticesWithDepthConflict+=1}
        else {
            uncoloredVerticesWithDepthConflict+=1
            uncoloredAcceptedViews[count,default:0]+=1
            uncoloredSignPatterns[sign,default:0]+=1
        }
    }
    public var summary: String {
        func counts(_ values: [String:Int]) -> String {values.sorted {$0.key<$1.key}.map {"\($0.key)=\($0.value)"}.joined(separator:",")}
        return "rejected=\(rejectedObservations) firstLocation={\(counts(firstFailureLocation))} " +
            "residualM={\(counts(firstResidualMagnitudeMeters))} excessM={\(counts(firstExcessOverToleranceMeters))} " +
            "patterns={\(counts(footprintPatterns))} conflictedVertices=\(verticesWithDepthConflict) " +
            "uncoloredConflictedVertices=\(uncoloredVerticesWithDepthConflict) " +
            "uncoloredAcceptedViews={\(counts(uncoloredAcceptedViews))} uncoloredSigns={\(counts(uncoloredSignPatterns))} " +
            "maskFrames=\(framesWithPersonMask)/\(framesWithPersonMask+framesWithoutPersonMask)"
    }
}

/// Transient per-attempt and per-vertex evidence; never serialized.
struct SurfaceDepthEvidence {
    var isCenter: Bool
    var confidence: UInt8
    var cameraDepth: Float
    var facing: Float
    var residual: Float?
    var tolerance: Float?
    var reliablePixels=0,nearPixels=0,farPixels=0,matchedPixels=0,invalidPredictions=0
    var centerMatches=false
    var residualMagnitudes=[Float]()
    var pattern: String {
        if invalidPredictions>0 {return "invalidPrediction"}
        if nearPixels>0 && farPixels>0 {return "mixedSigns"}
        if centerMatches {return "neighborOnlyConflict"}
        let sorted=residualMagnitudes.sorted()
        let small = !sorted.isEmpty && sorted[sorted.count/2]<=0.15
        if nearPixels>=6 {return small ? "mostlyNearSmallOffset" : "mostlyNearLargeOffset"}
        if farPixels>=6 {return small ? "mostlyFarSmallOffset" : "mostlyFarLargeOffset"}
        return nearPixels>0 ? "sparseNearConflict" : farPixels>0 ? "sparseFarConflict" : "undetermined"
    }
}
struct SurfaceVertexDepthEvidence {
    var conflicts=0
    var near=false,far=false,mixedWithinView=false
    mutating func record(_ evidence: SurfaceDepthEvidence) {
        conflicts+=1;near = near || evidence.nearPixels>0;far = far || evidence.farPixels>0
        mixedWithinView = mixedWithinView || (evidence.nearPixels>0 && evidence.farPixels>0)
    }
}

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
    /// Optional so version 1/2 reports continue to decode. Counts are disjoint (0 / 1 / 2+ accepted views).
    public var observationCounts: [String:Int]?=[:]
    public var capture: SurfaceColorCaptureDiagnostics?
    /// Version 4: observational depth evidence only; never used to accept colors or allow inference.
    public var depthAnalysis: SurfaceDepthDiagnostics?
    public var alignment: SurfaceColorAlignmentDiagnostics?
    public var coverageScope="mesh"
    public var eligibleTriangles=0, coloredTriangles=0
    public var grayTrianglesByMissingVertices: [String:Int]=[:]
    public var eligibleAreaSquareMeters=0.0, coloredAreaSquareMeters=0.0
    public var directColoredTriangles: Int?=0
    public var directColoredAreaSquareMeters: Double?=0
    /// Optional for reports written before upper-surface inference existed. coloredVertices stays DIRECT only.
    public var upperFill: UpperSurfaceColorFill.Diagnostics?

    public init(policy: String) {version=5;self.policy=policy}
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
                } else {
                    directColoredTriangles?+=1;directColoredAreaSquareMeters?+=length/2
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
            "directTriangles=\(directColoredTriangles ?? 0) directAreaM2=\(directColoredAreaSquareMeters ?? 0) " +
            "rejected={\(counts(rejectedObservations))} missingVertices={\(counts(missingVertices))} " +
            "grayTrianglesByMissingVertices={\(counts(grayTrianglesByMissingVertices))} " +
            "observationCounts={\(counts(observationCounts ?? [:]))} upperFill={\(upperFill?.summary ?? "disabled")} " +
            "capture={\(capture?.summary ?? "unavailable")} depthAnalysis={\(depthAnalysis?.summary ?? "disabled")} " +
            "alignment={\(alignment?.summary ?? "unavailable")}"
    }
}
