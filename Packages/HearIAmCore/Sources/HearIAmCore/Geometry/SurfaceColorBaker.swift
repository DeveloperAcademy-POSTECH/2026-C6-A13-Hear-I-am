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
    }
    public static func bake(_ meshes: [MeshSnapshot], frames: [SurfaceColorFrame]) -> [MeshSnapshot] {
        bakeWithDiagnostics(meshes,frames:frames).meshes
    }
    public static func bakeWithDiagnostics(_ meshes: [MeshSnapshot],frames: [SurfaceColorFrame],
                                           route: StageRoute? = nil,policy: SamplingPolicy = .relaxed,
                                           fillUpperSurfaces: Bool = true) -> BakeResult {
        let views=frames.filter(\.valid).map {View(frame:$0,inverse:simd_inverse($0.cameraTransform))}
        var diagnostics=SurfaceColorDiagnostics(policy:policy.rawValue)
        diagnostics.validFrames=views.count;diagnostics.invalidFrames=frames.count-views.count
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
            for i in world.indices where eligible[i] {
                if i%1024==0 && Task.isCancelled {return mesh}
                diagnostics.eligibleVertices+=1
                let normal=simd_normalize(normals[i])
                var observations=[(color:SIMD3<Float>,weight:Float,time:Double)]()
                for view in views {
                    diagnostics.attemptedObservations+=1
                    switch sample(world[i],normal:normal,view:view,policy:policy) {
                    case .accepted(let color,let weight,let neighbors):
                        diagnostics.acceptedObservations+=1
                        if neighbors<9 {diagnostics.partialNeighborhoodObservations+=1}
                        observations.append((color,weight,view.frame.time))
                    case .rejected(let reason):
                        diagnostics.reject(reason)
                        switch reason {
                        case .personMask,.foregroundOcclusion,.depthMismatch,.clippedColor: inferenceBlocked.insert(i)
                        default: break
                        }
                    }
                }
                guard observations.count>=2 else {
                    // A lone measured color isn't established, but must not be overwritten by an assumption.
                    if !observations.isEmpty {inferenceBlocked.insert(i)}
                    diagnostics.miss(.insufficientObservations);continue
                }
                // Robust channel median rejects a transient different-colored observation.
                let middle=observations.count/2
                let median=SIMD3(observations.map {$0.color.x}.sorted()[middle],
                                 observations.map {$0.color.y}.sorted()[middle],
                                 observations.map {$0.color.z}.sorted()[middle])
                let stable=observations.filter {simd_length($0.color-median)<0.22}
                guard stable.count>=2 else {inferenceBlocked.insert(i);diagnostics.miss(.inconsistentColor);continue}
                guard let first=stable.map(\.time).min(),let last=stable.map(\.time).max(),last-first>=0.3 else {
                    inferenceBlocked.insert(i);diagnostics.miss(.insufficientTimeSeparation);continue
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
            let result=UpperSurfaceColorFill.fill(observedMesh,blockedVertices:inferenceBlocked)
            diagnostics.upperFill?.merge(result.diagnostics)
            return result.mesh
        }
        diagnostics.measureCoverage(baked,route:route)
        return BakeResult(meshes:baked,diagnostics:diagnostics)
    }
    private static func sample(_ world: SIMD3<Float>,normal: SIMD3<Float>,view: View,policy: SamplingPolicy) -> Sample {
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
        if let reason=mismatch(f.depth[center],expectedDepth(x,y)) {return .rejected(reason)}
        var colors=[SIMD3<Float>]()
        for dy in -1...1 {for dx in -1...1 {
            let index=(y+dy)*f.width+x+dx,depth=f.depth[index]
            guard f.confidence[index]>=1,depth.isFinite,depth>0 else {
                if policy == .strict {return .rejected(.neighborhoodDepthUnavailable)}
                continue // Unknown neighbors contribute NO color; central depth was already required.
            }
            // Reliable foreground/background disagreement is still a veto, even with eight matching neighbors.
            if let reason=mismatch(depth,expectedDepth(x+dx,y+dy)) {return .rejected(reason)}
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
