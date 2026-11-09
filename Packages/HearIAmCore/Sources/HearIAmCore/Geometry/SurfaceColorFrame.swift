import Foundation
import simd

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

/// Bounded, spatially diverse keyframes; discard a redundant older view rather than all early walls.
public struct SurfaceColorFrames: Sendable {
    public static let capacity=48
    public private(set) var frames: [SurfaceColorFrame]=[]
    public init() {}
    @discardableResult public mutating func append(_ frame: SurfaceColorFrame) -> UUID? {
        guard frame.valid else {return frame.id}
        frames.append(frame)
        guard frames.count>Self.capacity else {return nil}
        var closest=Float.infinity,discard=0
        for i in 0..<frames.count-1 {
            for j in i+1..<frames.count {
                let distance=frames[i].viewpointDistance(to:frames[j])
                if distance<closest {closest=distance;discard=i}
            }
        }
        return frames.remove(at:discard).id
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
