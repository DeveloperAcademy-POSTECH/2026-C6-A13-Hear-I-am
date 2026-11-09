import Foundation
import simd

/// Keep exact native depth rays when subsampling. Intrinsics use Apple's depth-resolution scaling,
/// with no image-resize half-pixel shift; RGB is sampled at the selected depth ray's image coordinate.
public struct SurfaceColorRasterMapping: Sendable {
    public let stride: Int, width: Int, height: Int
    public let depthWidth: Int, depthHeight: Int, imageWidth: Int, imageHeight: Int
    public let fx: Float, fy: Float, cx: Float, cy: Float
    public init?(imageWidth: Int,imageHeight: Int,depthWidth: Int,depthHeight: Int,intrinsics: simd_float3x3) {
        guard imageWidth>0,imageHeight>0,depthWidth>0,depthHeight>0,
              [intrinsics[0][0],intrinsics[1][1],intrinsics[2][0],intrinsics[2][1]].allSatisfy(\.isFinite),
              intrinsics[0][0]>0,intrinsics[1][1]>0 else {return nil}
        self.imageWidth=imageWidth;self.imageHeight=imageHeight
        self.depthWidth=depthWidth;self.depthHeight=depthHeight
        stride=max(1,(max(depthWidth,depthHeight)+159)/160)
        width=(depthWidth+stride-1)/stride;height=(depthHeight+stride-1)/stride
        let sx=Float(depthWidth)/Float(stride)/Float(imageWidth),sy=Float(depthHeight)/Float(stride)/Float(imageHeight)
        fx=intrinsics[0][0]*sx;fy=intrinsics[1][1]*sy
        cx=intrinsics[2][0]*sx;cy=intrinsics[2][1]*sy
    }
    public func depthX(_ x: Int) -> Int {x*stride}
    public func depthY(_ y: Int) -> Int {y*stride}
    public func imageX(_ x: Int) -> Int {min(imageWidth-1,Int((Double(depthX(x))*Double(imageWidth)/Double(depthWidth)).rounded()))}
    public func imageY(_ y: Int) -> Int {min(imageHeight-1,Int((Double(depthY(y))*Double(imageHeight)/Double(depthHeight)).rounded()))}
    /// Conservatively preserve ANY person pixel in the represented cell, including skipped depth rays.
    public func maskRange(_ index: Int,depthSize: Int,maskSize: Int) -> ClosedRange<Int> {
        let low=max(0,Double(index*stride)-Double(stride)/2)
        let high=min(Double(depthSize),Double(index*stride)+Double(stride)/2)
        let a=max(0,min(maskSize-1,Int(floor(low*Double(maskSize)/Double(depthSize)))))
        let b=max(a,min(maskSize-1,Int(ceil(high*Double(maskSize)/Double(depthSize)))))
        return a...b
    }
}

/// A small, unrotated camera/depth observation. Pixels use the camera sensor's top-left origin.
/// Only used in memory during scanning; the scan archive stores baked vertex colors instead.
public struct SurfaceColorFrame: Sendable {
    public let id: UUID
    public let time: Double
    public let cameraTransform: simd_float4x4
    public let width: Int, height: Int
    public let fx: Float, fy: Float, cx: Float, cy: Float
    public let rgb: [UInt8]
    public let depth: [Float]
    public let confidence: [UInt8]
    /// Kept separate from missing/low-confidence depth: a person must never be treated as a fillable hole.
    public let personMask: [UInt8]?

    public init(id: UUID = UUID(), time: Double, cameraTransform: simd_float4x4,
                width: Int, height: Int, fx: Float, fy: Float, cx: Float, cy: Float,
                rgb: [UInt8], depth: [Float], confidence: [UInt8], personMask: [UInt8]? = nil) {
        self.id=id;self.time=time;self.cameraTransform=cameraTransform
        self.width=width;self.height=height;self.fx=fx;self.fy=fy;self.cx=cx;self.cy=cy
        self.rgb=rgb;self.depth=depth;self.confidence=confidence
        self.personMask=personMask
    }
    public var valid: Bool {
        width>=3 && height>=3 && width<=256 && height<=256 && time.isFinite &&
        [fx,fy,cx,cy].allSatisfy(\.isFinite) && fx>0 && fy>0 &&
        (0..<4).allSatisfy {i in (0..<4).allSatisfy {cameraTransform[i][$0].isFinite}} &&
        abs(simd_determinant(cameraTransform))>0.5 &&
        rgb.count==width*height*3 && depth.count==width*height && confidence.count==width*height &&
        (personMask == nil || personMask?.count==width*height)
    }
    public func withCameraTransform(_ transform: simd_float4x4) -> Self {
        Self(id:id,time:time,cameraTransform:transform,width:width,height:height,
             fx:fx,fy:fy,cx:cx,cy:cy,rgb:rgb,depth:depth,confidence:confidence,personMask:personMask)
    }

    /// Distance and view direction together retain coverage when the camera turns in place.
    public func viewpointDistance(to other: Self) -> Float {
        let delta=cameraTransform.columns.3-other.cameraTransform.columns.3
        let a=cameraTransform.columns.2,b=other.cameraTransform.columns.2
        return simd_length_squared(delta)+2*max(0,1-simd_dot(a,b))
    }
}

/// Capture counters are separate from final-mesh sampling failures. No camera content is persisted.
public struct SurfaceColorCaptureDiagnostics: Codable, Equatable, Sendable {
    public var attemptedFrames=0, trackingRejected=0, motionRejected=0, copyRejected=0
    public var capturedFrames=0, evictedFrames=0, retainedFrames=0, missingPoseFrames=0
    public var coveredRegions=0, pairedRegions=0
    public var selectionMilliseconds=0.0, maximumSelectionMilliseconds=0.0
    public init() {}
    public var summary: String {
        "attempts=\(attemptedFrames),trackingRejected=\(trackingRejected),motionRejected=\(motionRejected),copyRejected=\(copyRejected)," +
        "captured=\(capturedFrames),evicted=\(evictedFrames),retained=\(retainedFrames),missingPose=\(missingPoseFrames)," +
        "regions=\(coveredRegions),pairedRegions=\(pairedRegions),selectionMs=\(selectionMilliseconds),maxSelectionMs=\(maximumSelectionMilliseconds)"
    }
}

/// Bounded keyframes. Depth-supported wall regions retain a time-separated, color-consistent pair.
/// These coarse witnesses only select frames; final mesh sampling still performs every safety check.
public struct SurfaceColorFrames: Sendable {
    public enum SelectionPolicy: Sendable {case pairedCoverage, viewpointDiversity}
    public static let capacity=48
    public private(set) var frames: [SurfaceColorFrame]=[]
    private var regions: [[SIMD3<Int>:SIMD3<Float>]]=[]
    private let policy: SelectionPolicy
    public init(policy: SelectionPolicy = .pairedCoverage) {self.policy=policy}
    public var coverage: (regions: Int, paired: Int) {
        let support=regionSupport()
        return (support.count,support.filter {pairDegrees($0.value,key:$0.key).total>0}.count)
    }
    private func regionSupport() -> [SIMD3<Int>:[Int]] {
        var result=[SIMD3<Int>:[Int]]()
        for i in regions.indices {for key in regions[i].keys {result[key,default:[]].append(i)}}
        return result
    }
    private func pairDegrees(_ ids: [Int],key: SIMD3<Int>? = nil) -> (total: Int, degrees: [Int:Int]) {
        var total=0,degrees=[Int:Int]()
        for a in ids.indices {for b in ids.indices where b>a {
            let i=ids[a],j=ids[b]
            guard abs(frames[i].time-frames[j].time)>=0.3 else {continue}
            if let key,let first=regions[i][key],let second=regions[j][key],simd_distance(first,second)>=0.22 {continue}
            total+=1;degrees[i,default:0]+=1;degrees[j,default:0]+=1
        }}
        return (total,degrees)
    }
    @discardableResult public mutating func append(_ frame: SurfaceColorFrame) -> UUID? {
        guard frame.valid else {return frame.id}
        frames.append(frame)
        regions.append(policy == .pairedCoverage ? Self.wallRegions(frame) : [:])
        guard frames.count>Self.capacity else {return nil}
        var losses=[Int](repeating:0,count:frames.count)
        var exploresNewRegion=false
        if policy == .pairedCoverage {
            for (key,ids) in regionSupport() {
                if ids.count==1 {
                    losses[ids[0]]+=1
                    if ids[0]==frames.count-1 {exploresNewRegion=true}
                }
                let pairs=pairDegrees(ids,key:key)
                if pairs.total>0 {for (id,degree) in pairs.degrees where degree==pairs.total {losses[id]+=4}}
            }
        }
        // Reserve one admission opportunity for a newly seen wall; otherwise an already paired
        // full buffer could discard its first view forever, preventing a second view from pairing.
        if exploresNewRegion {losses[frames.count-1]=(losses.max() ?? 0)+1}
        // Equal coverage loss: remove the most redundant viewpoint, oldest first.
        var nearest=[Float](repeating:.infinity,count:frames.count)
        for i in 0..<frames.count-1 {
            for j in i+1..<frames.count {
                let distance=frames[i].viewpointDistance(to:frames[j])
                nearest[i]=min(nearest[i],distance);nearest[j]=min(nearest[j],distance)
            }
        }
        let discard=frames.indices.min {
            if losses[$0] != losses[$1] {return losses[$0]<losses[$1]}
            if nearest[$0] != nearest[$1] {return nearest[$0]<nearest[$1]}
            return $0<$1
        }!
        regions.remove(at:discard)
        return frames.remove(at:discard).id
    }

    private static func wallRegions(_ f: SurfaceColorFrame) -> [SIMD3<Int>:SIMD3<Float>] {
        var sums=[SIMD3<Int>:(SIMD3<Float>,Int)]()
        func point(_ x: Int,_ y: Int) -> SIMD3<Float> {
            let z=f.depth[y*f.width+x]
            return SIMD3((Float(x)-f.cx)*z/f.fx,(f.cy-Float(y))*z/f.fy,-z)
        }
        for y in stride(from:2,to:f.height-2,by:4) {for x in stride(from:2,to:f.width-2,by:4) {
            let center=y*f.width+x,z=f.depth[center]
            guard z.isFinite,z>=0.25,z<=5 else {continue}
            var valid=true
            for dy in -1...1 {for dx in -1...1 {
                let i=(y+dy)*f.width+x+dx
                if f.confidence[i]<1 || !f.depth[i].isFinite || abs(f.depth[i]-z)>0.035+z*0.015 || (f.personMask?[i] ?? 0)>0 {valid=false}
            }}
            guard valid else {continue}
            let p=point(x,y),cross=simd_cross(point(x+1,y)-point(x-1,y),point(x,y+1)-point(x,y-1))
            guard simd_length_squared(cross)>1e-10 else {continue}
            let n=simd_normalize(cross),wn=f.cameraTransform*SIMD4(n,0)
            guard abs(wn.y)<0.65,abs(simd_dot(n,simd_normalize(-p)))>=0.4 else {continue}
            let rgb=SIMD3(Float(f.rgb[center*3]),Float(f.rgb[center*3+1]),Float(f.rgb[center*3+2]))/255
            guard rgb.max()>0.008,rgb.min()<0.995 else {continue}
            let world=f.cameraTransform*SIMD4(p,1)
            let key=SIMD3(Int(floor(world.x/0.35)),Int(floor(world.y/0.35)),Int(floor(world.z/0.35)))
            let old=sums[key] ?? (.zero,0);sums[key]=(old.0+rgb,old.1+1)
        }}
        return sums.mapValues {$0.0/Float($0.1)}
    }
}

/// Camera YCbCr to sRGB-encoded components. Matrix coefficients come from the pixel-buffer attachment.
public enum SurfaceCameraColor {
    public static func rgb(y: UInt8, cb: UInt8, cr: UInt8, fullRange: Bool, kr: Float, kb: Float) -> SIMD3<Float> {
        let luma=fullRange ? Float(y)/255 : (Float(y)-16)/219
        let blue=(Float(cb)-128)/(fullRange ? 255 : 224)
        let red=(Float(cr)-128)/(fullRange ? 255 : 224)
        let kg=1-kr-kb
        let value=SIMD3(luma+2*(1-kr)*red,
                        luma-2*kb*(1-kb)/kg*blue-2*kr*(1-kr)/kg*red,
                        luma+2*(1-kb)*blue)
        return simd_clamp(value,SIMD3(repeating:0),SIMD3(repeating:1))
    }
}
