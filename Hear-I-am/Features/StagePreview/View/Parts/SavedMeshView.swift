import SwiftUI
import SceneKit
import HearIAmCore

struct SavedMeshView: UIViewRepresentable {
    let scan: LoadedScan
    let wireframe: Bool
    let fit: Int
    final class Coordinator {var fit = -1; let camera=SCNNode(); let mesh=SCNNode()}
    func makeCoordinator() -> Coordinator {Coordinator()}
    func makeUIView(context:Context) -> SCNView {
        let v=SCNView(); let scene=SCNScene(); v.scene=scene
        v.backgroundColor=UIColor(white:0.10,alpha:1); v.autoenablesDefaultLighting=true
        v.allowsCameraControl=true; v.antialiasingMode = .multisampling4X
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.worldUp=SCNVector3(0,1,0)
        let mesh=context.coordinator.mesh
        scene.rootNode.addChildNode(mesh)
        for part in scan.meshes {
            let node=part.node(saved:true,solid:true)
            node.geometry?.firstMaterial?.diffuse.contents=UIColor(white:0.72,alpha:1)
            mesh.addChildNode(node)
        }
        func marker(_ p:Point3,_ color:UIColor) {
            let n=SCNNode(geometry:SCNSphere(radius:0.07)); n.position=SCNVector3(p.x,p.y+0.06,p.z)
            n.geometry?.firstMaterial?.diffuse.contents=color; scene.rootNode.addChildNode(n)
        }
        func line(_ a:Point3,_ b:Point3,_ color:UIColor) {
            let u=SIMD3<Float>(Float(a.x),Float(a.y)+0.04,Float(a.z)), w=SIMD3<Float>(Float(b.x),Float(b.y)+0.04,Float(b.z))
            guard simd_length(w-u)>0.001 else {return}
            let n=SCNNode(geometry:SCNCylinder(radius:0.025,height:CGFloat(simd_length(w-u))))
            n.simdPosition=(u+w)/2; n.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:simd_normalize(w-u))
            n.geometry?.firstMaterial?.diffuse.contents=color; scene.rootNode.addChildNode(n)
        }
        if let route=scan.manifest.route {
            for zone in route.dangerZones { scene.rootNode.addChildNode(StageDangerZoneOverlay.node(zone,in:route.area)) }
            for i in 0..<4 {line(route.area.corners[i],route.area.corners[(i+1)%4],.systemCyan)}
            for i in route.points.indices {
                let p=route.area.world(route.points[i]); marker(p,.systemGreen)
                if i>0 {line(route.area.world(route.points[i-1]),p,.systemGreen)}
            }
            for o in route.obstacles {for i in o.vertices.indices {line(route.area.world(o.vertices[i]),route.area.world(o.vertices[(i+1)%o.vertices.count]),.systemRed)}}
            if let start=route.points.first {
                scene.rootNode.addChildNode(PerformerFigure.node(at:route.area.world(start),facing:route.points.dropFirst().first.map(route.area.world)))
            }
        }
        marker(scan.manifest.checkpoint,.systemYellow)
        context.coordinator.camera.camera=SCNCamera(); context.coordinator.camera.camera?.zFar=2000
        v.pointOfView=context.coordinator.camera
        return v
    }
    func updateUIView(_ v:SCNView,context:Context) {
        for n in context.coordinator.mesh.childNodes {n.geometry?.firstMaterial?.fillMode=wireframe ? .lines : .fill}
        guard context.coordinator.fit != fit else {return}
        context.coordinator.fit=fit
        let bounds=context.coordinator.mesh.boundingBox
        let a=SIMD3<Float>(bounds.min.x,bounds.min.y,bounds.min.z), b=SIMD3<Float>(bounds.max.x,bounds.max.y,bounds.max.z)
        let center=(a+b)/2, radius=max(simd_length(b-a)/2,1)
        let camera=context.coordinator.camera
        camera.simdPosition=center+simd_normalize(SIMD3<Float>(1,0.9,1))*radius*3.5
        let target=SCNVector3(center.x,center.y,center.z)
        camera.look(at:target); v.defaultCameraController.target=target
    }
}

/// A 155 cm female figure standing on the start point of a saved stage, facing the first leg of the
/// route, so the scale of the scanned space is easy to read. Shown only in the saved-stage 3D view.
private enum PerformerFigure {
    static let height: Float=1.55

    /// `start` and `next` are world points (y up). The figure faces from `start` toward `next`.
    static func node(at start: Point3, facing next: Point3?) -> SCNNode {
        let root=SCNNode(); root.name="performer"
        root.simdPosition=SIMD3<Float>(Float(start.x),Float(start.y),Float(start.z))
        if let next {
            let dx=Float(next.x-start.x), dz=Float(next.z-start.z)
            if dx*dx+dz*dz > 1e-6 { root.eulerAngles.y=atan2(dx,dz) }
        }
        let skin=material(UIColor(red:0.96,green:0.80,blue:0.66,alpha:1))
        let cloth=material(UIColor.systemOrange), hair=material(UIColor(white:0.15,alpha:1))
        // Heights in metres from the floor; total 1.55.
        for x: Float in [-0.07,0.07] { root.addChildNode(part(SCNCylinder(radius:0.055,height:0.78),skin,SIMD3(x,0.39,0))) }
        root.addChildNode(part(SCNCone(topRadius:0.13,bottomRadius:0.24,height:0.28),cloth,SIMD3(0,0.72,0)))
        root.addChildNode(part(SCNCapsule(capRadius:0.13,height:0.48),cloth,SIMD3(0,1.04,0)))
        for x: Float in [-0.18,0.18] { root.addChildNode(part(SCNCylinder(radius:0.04,height:0.56),skin,SIMD3(x,1.0,0))) }
        root.addChildNode(part(SCNCylinder(radius:0.045,height:0.06),skin,SIMD3(0,1.3,0)))
        root.addChildNode(part(SCNSphere(radius:0.11),skin,SIMD3(0,1.44,0)))
        root.addChildNode(part(SCNSphere(radius:0.115),hair,SIMD3(0,1.47,-0.025)))
        root.addChildNode(part(SCNCapsule(capRadius:0.045,height:0.24),hair,SIMD3(0,1.3,-0.11)))
        return root
    }
    private static func material(_ color: UIColor) -> SCNMaterial {
        let m=SCNMaterial(); m.diffuse.contents=color; m.lightingModel = .physicallyBased; return m
    }
    private static func part(_ geometry: SCNGeometry, _ material: SCNMaterial, _ position: SIMD3<Float>) -> SCNNode {
        geometry.firstMaterial=material
        let n=SCNNode(geometry:geometry); n.simdPosition=position; return n
    }
}
