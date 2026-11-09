import SceneKit
import UIKit
import HearIAmCore

/// Rendering uses separate geometry/materials so clean-view styling cannot alter the raw mesh.
enum ReplaySurfaceFactory {
    static let background=UIColor(red:0.95,green:0.94,blue:0.92,alpha:1)
    static let woodColor=UIColor(red:0.604,green:0.439,blue:0.306,alpha:1)
    static let wood: SCNMaterial = {
        let material=ReplayModelFactory.material(woodColor)
        material.diffuse.contents=UIImage(named:"ReplayOakFloor") ?? woodColor as Any
        material.diffuse.wrapS = .repeat;material.diffuse.wrapT = .repeat
        material.diffuse.minificationFilter = .linear;material.diffuse.magnificationFilter = .linear
        material.diffuse.mipFilter = .linear;material.diffuse.maxAnisotropy=8
        material.roughness.contents=0.92;material.metalness.contents=0
        material.isDoubleSided=true
        return material
    }()
    static let surrounding: SCNMaterial = {
        let material=ReplayModelFactory.material(ReplayModelFactory.gray)
        material.isDoubleSided=true
        return material
    }()

    static func nodes(_ mesh: ReplaySurfaceMesh, useCapturedColors: Bool = false) -> [SCNNode] {
        var nodes=[SCNNode]()
        if !mesh.floorIndices.isEmpty {
            let vertices=mesh.vertices.map {SCNVector3($0.x,0,$0.z)}
            nodes.append(node(vertices:vertices,indices:mesh.floorIndices,wood:true))
        }
        if !mesh.surfaceIndices.isEmpty {
            let vertices=mesh.vertices.map {SCNVector3($0.x,$0.y,$0.z)}
            var colored=[UInt32](),gray=[UInt32]()
            if useCapturedColors,let colors=mesh.displaySurfaceColors,colors.count==vertices.count*4 {
                for i in stride(from:0,to:mesh.surfaceIndices.count,by:3) {
                    let ids=Array(mesh.surfaceIndices[i..<i+3])
                    let a=SIMD3<Float>(vertices[Int(ids[0])]),b=SIMD3<Float>(vertices[Int(ids[1])]),c=SIMD3<Float>(vertices[Int(ids[2])])
                    let normal=simd_cross(b-a,c-a),length=simd_length(normal)
                    if length>1e-8,abs(normal.y)/length<0.65,ids.allSatisfy({colors[Int($0)*4+3]==255}) {
                        colored.append(contentsOf:ids)
                    } else {gray.append(contentsOf:ids)}
                }
            } else {gray=mesh.surfaceIndices}
            if !gray.isEmpty {nodes.append(node(vertices:vertices,indices:gray,wood:false))}
            if !colored.isEmpty {nodes.append(node(vertices:vertices,indices:colored,wood:false,colors:mesh.displaySurfaceColors))}
        }
        return nodes
    }
    static func stageFloor(_ area: StageArea) -> SCNNode {
        // Only the user-registered rectangle gets a continuous backing surface.
        // Scanned extensions retain their actual boundary, including disconnected patches.
        // A 2 mm offset avoids depth fighting with the flattened scanned floor.
        node(vertices:[.init(0,-0.002,0),.init(area.width,-0.002,0),
                       .init(area.width,-0.002,-area.depth),.init(0,-0.002,-area.depth)],
             indices:[0,1,2,0,2,3],wood:true)
    }
    private static func node(vertices: [SCNVector3],indices: [UInt32],wood: Bool,colors: Data? = nil) -> SCNNode {
        var sources=[SCNGeometrySource(vertices:vertices)]
        if wood {
            sources.append(SCNGeometrySource(normals:Array(repeating:SCNVector3(0,1,0),count:vertices.count)))
            sources.append(SCNGeometrySource(textureCoordinates:vertices.map {
                let uv=ReplaySurfaceMesh.textureCoordinate(.init(Double($0.x),0,Double($0.z)))
                return CGPoint(x:uv.x,y:uv.y)
            }))
        } else {
            var normals=Array(repeating:SIMD3<Float>.zero,count:vertices.count)
            for i in stride(from:0,to:indices.count,by:3) {
                let a=Int(indices[i]),b=Int(indices[i+1]),c=Int(indices[i+2])
                let normal=simd_cross(SIMD3<Float>(vertices[b])-SIMD3<Float>(vertices[a]),SIMD3<Float>(vertices[c])-SIMD3<Float>(vertices[a]))
                normals[a]+=normal;normals[b]+=normal;normals[c]+=normal
            }
            sources.append(SCNGeometrySource(normals:normals.map {
                SCNVector3(simd_length_squared($0)>1e-10 ? simd_normalize($0) : SIMD3<Float>(0,1,0))
            }))
        }
        let geometry=SCNGeometry(sources:sources,elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        geometry.firstMaterial=wood ? self.wood : surrounding
        if let colors,!wood {
            // Float components avoid ambiguity about normalized integer color attributes in SceneKit.
            // Geometry color attributes are linear; camera bytes are sRGB. Without decoding gamma,
            // SceneKit makes dark curtains and saturated colors visibly too bright.
            let rgba=colors.enumerated().map {index,byte -> Float in
                let s=Float(byte)/255
                return index%4==3 ? s : s<=0.04045 ? s/12.92 : pow((s+0.055)/1.055,2.4)
            }
            let data=rgba.withUnsafeBufferPointer {Data(buffer:$0)}
            sources.append(SCNGeometrySource(data:data,semantic:.color,vectorCount:vertices.count,
                                             usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,
                                             dataOffset:0,dataStride:16))
            let coloredGeometry=SCNGeometry(sources:sources,elements:geometry.elements)
            let material=SCNMaterial()
            // Camera colors already include real-world lighting. Avoid adding the folder's blue stage lights.
            material.diffuse.contents=UIColor.white;material.lightingModel = .constant;material.isDoubleSided=true
            coloredGeometry.firstMaterial=material
            let node=SCNNode(geometry:coloredGeometry);node.name="captured-scan-surroundings"
            return node
        }
        let node=SCNNode(geometry:geometry)
        node.name=wood ? "clean-oak-floor" : "clean-scan-surroundings"
        return node
    }
}
