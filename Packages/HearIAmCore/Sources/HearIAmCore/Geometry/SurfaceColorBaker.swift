import Foundation
import simd

/// Projects FINAL mesh vertices into saved camera observations, independent of changing AR mesh indices.
public enum SurfaceColorBaker {
    public enum SamplingPolicy: String, Sendable {
        /// Previous 9/9 rule, retained for same-input comparisons in tests and optional Debug runs.
        case strict
        case relaxed
    }
    public struct BakeResult: Sendable {
        public let meshes: [MeshSnapshot]
        public let diagnostics: SurfaceColorDiagnostics
    }
    private struct View {
        let frame: SurfaceColorFrame
        let inverse: simd_float4x4
    }
    private enum Sample {
        case accepted(SIMD3<Float>,Float,Int)
        case rejected(SurfaceColorDiagnostics.Rejection)
        case depthRejected(SurfaceColorDiagnostics.Rejection,SurfaceDepthEvidence)
    }
    public static func bake(_ meshes: [MeshSnapshot], frames: [SurfaceColorFrame]) -> [MeshSnapshot] {
        bakeWithDiagnostics(meshes,frames:frames).meshes
    }
    public static func bakeWithDiagnostics(_ meshes: [MeshSnapshot],frames: [SurfaceColorFrame],
                                           route: StageRoute? = nil,policy: SamplingPolicy = .relaxed,
                                           fillUpperSurfaces: Bool = true, improveUpperFill: Bool = true,
                                           collectDepthDiagnostics: Bool = true) -> BakeResult {
        let views=frames.filter(\.valid).map {View(frame:$0,inverse:simd_inverse($0.cameraTransform))}
        var diagnostics=SurfaceColorDiagnostics(policy:policy.rawValue)
        diagnostics.validFrames=views.count;diagnostics.invalidFrames=frames.count-views.count
        if collectDepthDiagnostics {
            diagnostics.depthAnalysis=SurfaceDepthDiagnostics()
            diagnostics.depthAnalysis?.framesWithPersonMask=views.filter {$0.frame.personMask != nil}.count
            diagnostics.depthAnalysis?.framesWithoutPersonMask=views.filter {$0.frame.personMask == nil}.count
        }
        let infer=fillUpperSurfaces && policy == .relaxed && views.count>=2
        if infer {diagnostics.upperFill=UpperSurfaceColorFill.Diagnostics()}
        let baked=meshes.map {mesh in
            guard !Task.isCancelled, (try? mesh.validate()) != nil else {diagnostics.skippedMeshes+=1;return mesh}
            let t=mesh.transform
            let transform=simd_float4x4(columns:(SIMD4(t[0],t[1],t[2],t[3]),SIMD4(t[4],t[5],t[6],t[7]),
                                                SIMD4(t[8],t[9],t[10],t[11]),SIMD4(t[12],t[13],t[14],t[15])))
            let world=mesh.vertices.map {p -> SIMD3<Float> in
                let v=transform*SIMD4(Float(p.x),Float(p.y),Float(p.z),1)
                return SIMD3(v.x,v.y,v.z)
            }
            var normals=Array(repeating:SIMD3<Float>.zero,count:world.count)
            var eligible=Array(repeating:false,count:world.count)
            for i in stride(from:0,to:mesh.indices.count,by:3) {
                let a=Int(mesh.indices[i]),b=Int(mesh.indices[i+1]),c=Int(mesh.indices[i+2])
                let cross=simd_cross(world[b]-world[a],world[c]-world[a]),length=simd_length(cross)
                // Vertical/near-vertical surfaces include unclassified curtains. Floors and ramps stay untouched.
                guard length>1e-8, abs(cross.y)/length<0.65 else {continue}
                let normal=cross/length
                for v in [a,b,c] {
                    normals[v] += simd_dot(normals[v],normal)<0 ? -normal : normal
                    eligible[v]=true
                }
            }
            var rgba=Array(repeating:UInt8(0),count:world.count*4),covered=false
            var inferenceBlocked=Set<Int>()
            var blockedReasons=[Int:Set<String>](),singleObservations=[Int:SIMD3<Float>]()
            func block(_ vertex: Int,_ reason: String) {
                inferenceBlocked.insert(vertex);blockedReasons[vertex,default:[]].insert(reason)
            }
            for i in world.indices where eligible[i] {
                if i%1024==0 && Task.isCancelled {return mesh}
                diagnostics.eligibleVertices+=1
                let normal=simd_normalize(normals[i])
                var observations=[(color:SIMD3<Float>,weight:Float,time:Double)]()
                var vertexDepth=SurfaceVertexDepthEvidence()
                defer {diagnostics.depthAnalysis?.record(vertexDepth,accepted:observations.count,direct:rgba[i*4+3]==255)}
                for view in views {
                    diagnostics.attemptedObservations+=1
                    switch sample(world[i],normal:normal,view:view,policy:policy,collectDepthDiagnostics:collectDepthDiagnostics) {
                    case .accepted(let color,let weight,let neighbors):
                        diagnostics.acceptedObservations+=1
                        if neighbors<9 {diagnostics.partialNeighborhoodObservations+=1}
                        observations.append((color,weight,view.frame.time))
                    case .rejected(let reason):
                        diagnostics.reject(reason)
                        switch reason {
                        case .personMask,.foregroundOcclusion,.depthMismatch,.clippedColor: block(i,reason.rawValue)
                        default: break
                        }
                    case .depthRejected(let reason,let evidence):
                        // Same rejection and hard inference veto as before; evidence never affects a decision.
                        diagnostics.reject(reason);block(i,reason.rawValue)
                        diagnostics.depthAnalysis?.record(evidence,reason:reason)
                        vertexDepth.record(evidence)
                    }
                }
                let countKey=observations.isEmpty ? "zero" : observations.count==1 ? "one" : "twoOrMore"
                diagnostics.observationCounts?[countKey,default:0]+=1
                guard observations.count>=2 else {
                    // One clean observation can constrain an estimate, but never becomes a direct donor.
                    if let observation=observations.first {
                        singleObservations[i]=observation.color
                        if !improveUpperFill {block(i,"singleObservation")}
                    }
                    diagnostics.miss(.insufficientObservations);continue
                }
                // Robust channel median rejects a transient different-colored observation.
                let middle=observations.count/2
                let median=SIMD3(observations.map {$0.color.x}.sorted()[middle],
                                 observations.map {$0.color.y}.sorted()[middle],
                                 observations.map {$0.color.z}.sorted()[middle])
                let stable=observations.filter {simd_length($0.color-median)<0.22}
                guard stable.count>=2 else {block(i,"inconsistentColor");diagnostics.miss(.inconsistentColor);continue}
                guard let first=stable.map(\.time).min(),let last=stable.map(\.time).max(),last-first>=0.3 else {
                    block(i,"insufficientTimeSeparation");diagnostics.miss(.insufficientTimeSeparation);continue
                }
                let weight=stable.reduce(Float(0)) {$0+$1.weight}
                let color=stable.reduce(SIMD3<Float>.zero) {$0+$1.color*$1.weight}/weight
                for channel in 0..<3 {rgba[i*4+channel]=UInt8(clamping:Int((color[channel]*255).rounded()))}
                rgba[i*4+3]=255;covered=true
                diagnostics.coloredVertices+=1
            }
            if views.count<2 {return mesh} // Preserve the previous no-observations behavior.
            let observedMesh=MeshSnapshot(id:mesh.id,transform:mesh.transform,vertices:mesh.vertices,indices:mesh.indices,
                                         surfaceColors:covered ? Data(rgba) : nil)
            guard infer else {return observedMesh}
            let result=UpperSurfaceColorFill.fill(observedMesh,blockedVertices:inferenceBlocked,
                blockedReasons:blockedReasons,singleObservations:improveUpperFill ? singleObservations : [:],
                improvePlaneChecks:improveUpperFill)
            diagnostics.upperFill?.merge(result.diagnostics)
            return result.mesh
        }
        diagnostics.measureCoverage(baked,route:route)
        return BakeResult(meshes:baked,diagnostics:diagnostics)
    }
    private static func sample(_ world: SIMD3<Float>,normal: SIMD3<Float>,view: View,policy: SamplingPolicy,
                               collectDepthDiagnostics: Bool) -> Sample {
        let f=view.frame,p=view.inverse*SIMD4(world,1),z = -p.z
        guard z>=0.25,z<=5 else {return .rejected(.outOfRange)}
        let camera=f.cameraTransform.columns.3
        let direction=simd_normalize(SIMD3(camera.x,camera.y,camera.z)-world)
        let facing=abs(simd_dot(normal,direction))
        guard facing>=0.4 else {return .rejected(.grazingAngle)}
        // AR camera looks along -Z, +Y up; camera image has +Y down. No UI rotation is applied.
        let u=f.fx*p.x/z+f.cx,v=f.cy-f.fy*p.y/z
        guard u>=1,v>=1,u<Float(f.width-1),v<Float(f.height-1) else {return .rejected(.outsideImage)}
        let x=Int(u.rounded()),y=Int(v.rounded())
        guard x>=1,y>=1,x<f.width-1,y<f.height-1 else {return .rejected(.outsideImage)}
        // A person anywhere in the footprint is a veto, even if their depth confidence is zero.
        if let mask=f.personMask {
            for dy in -1...1 {for dx in -1...1 {
                if mask[(y+dy)*f.width+x+dx]>0 {return .rejected(.personMask)}
            }}
        }
        let center=y*f.width+x
        guard f.confidence[center]>=1,f.depth[center].isFinite,f.depth[center]>0 else {
            return .rejected(.centerDepthUnavailable)
        }
        let n4=view.inverse*SIMD4(normal,0),n=SIMD3(n4.x,n4.y,n4.z)
        let plane=simd_dot(n,SIMD3(p.x,p.y,p.z))
        func expectedDepth(_ px: Int,_ py: Int) -> Float {
            if policy == .strict {return z}
            // Each ray intersects the local surface plane; a slanted wall needn't have constant image depth.
            let ray=SIMD3((Float(px)-f.cx)/f.fx,(f.cy-Float(py))/f.fy,-1)
            let denominator=simd_dot(n,ray)
            return abs(denominator)>1e-5 ? plane/denominator : .nan
        }
        func mismatch(_ depth: Float,_ expected: Float) -> SurfaceColorDiagnostics.Rejection? {
            guard expected.isFinite,expected>=0.25,expected<=5.25 else {return .depthMismatch}
            let tolerance: Float=0.035+expected*0.015
            if depth<expected-tolerance {return .foregroundOcclusion}
            if depth>expected+tolerance {return .depthMismatch}
            return nil
        }
        func depthFailure(_ reason: SurfaceColorDiagnostics.Rejection,_ px: Int,_ py: Int) -> Sample {
            guard collectDepthDiagnostics else {return .rejected(reason)}
            let first=py*f.width+px,expected=expectedDepth(px,py)
            let predictionValid=expected.isFinite && expected>=0.25 && expected<=5.25
            var evidence=SurfaceDepthEvidence(isCenter:px==x && py==y,confidence:f.confidence[first],
                cameraDepth:z,facing:facing,residual:predictionValid ? f.depth[first]-expected : nil,
                tolerance:predictionValid ? 0.035+expected*0.015 : nil)
            // Inspect the rest of the footprint ONLY after the original rejection is decided.
            // No RGB is sampled here, and none of these diagnostic thresholds change the veto.
            for dy in -1...1 {for dx in -1...1 {
                let i=(y+dy)*f.width+x+dx,depth=f.depth[i]
                guard f.confidence[i]>=1,depth.isFinite,depth>0 else {continue}
                evidence.reliablePixels+=1
                let expected=expectedDepth(x+dx,y+dy)
                guard expected.isFinite,expected>=0.25,expected<=5.25 else {evidence.invalidPredictions+=1;continue}
                evidence.residualMagnitudes.append(abs(depth-expected))
                switch mismatch(depth,expected) {
                case .foregroundOcclusion: evidence.nearPixels+=1
                case .depthMismatch: evidence.farPixels+=1
                default:
                    evidence.matchedPixels+=1
                    if dx==0 && dy==0 {evidence.centerMatches=true}
                }
            }}
            return .depthRejected(reason,evidence)
        }
        if let reason=mismatch(f.depth[center],expectedDepth(x,y)) {return depthFailure(reason,x,y)}
        var colors=[SIMD3<Float>]()
        for dy in -1...1 {for dx in -1...1 {
            let index=(y+dy)*f.width+x+dx,depth=f.depth[index]
            guard f.confidence[index]>=1,depth.isFinite,depth>0 else {
                if policy == .strict {return .rejected(.neighborhoodDepthUnavailable)}
                continue // Unknown neighbors contribute NO color; central depth was already required.
            }
            // Reliable foreground/background disagreement is still a veto, even with eight matching neighbors.
            if let reason=mismatch(depth,expectedDepth(x+dx,y+dy)) {return depthFailure(reason,x+dx,y+dy)}
            let color=SIMD3(Float(f.rgb[index*3]),Float(f.rgb[index*3+1]),Float(f.rgb[index*3+2]))/255
            colors.append(color)
        }}
        guard colors.count >= (policy == .strict ? 9 : 6) else {return .rejected(.insufficientNeighbors)}
        let middle=colors.count/2
        let median=SIMD3(colors.map(\.x).sorted()[middle],colors.map(\.y).sorted()[middle],colors.map(\.z).sorted()[middle])
        // Clipped black/white provide no reliable color. Real dark curtains above the noise floor remain usable.
        guard median.max()>0.008,median.min()<0.995 else {return .rejected(.clippedColor)}
        return .accepted(median,facing*facing/max(1,z*z),colors.count)
    }
}
