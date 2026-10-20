import SceneKit
import UIKit
import HearIAmCore

/// All replaceable visuals use metres, floor origin and +Z as the facing direction.
/// Replace this factory with asset loading later; placement/selection nodes stay unchanged.
enum ReplayModelFactory {
    static let green=UIColor(red:0.06,green:0.52,blue:0.32,alpha:1)
    static let gray=UIColor(red:0.831,green:0.812,blue:0.780,alpha:1) // #D4CFC7
    static let metal=UIColor(red:0.259,green:0.271,blue:0.251,alpha:1)
    static func material(_ color: UIColor) -> SCNMaterial {
        let m=SCNMaterial(); m.diffuse.contents=color; m.roughness.contents=0.85
        m.lightingModel = .physicallyBased
        return m
    }
    static func part(_ geometry: SCNGeometry, _ position: SCNVector3, color: UIColor = gray) -> SCNNode {
        geometry.firstMaterial=material(color)
        let node=SCNNode(geometry:geometry); node.position=position; return node
    }
    static func box(_ w: Double,_ h: Double,_ d: Double,_ x: Double=0,_ y: Double=0,_ z: Double=0, color: UIColor=gray) -> SCNNode {
        part(SCNBox(width:w,height:h,length:d,chamferRadius:min(w,h,d)*0.08),SCNVector3(x,y,z),color:color)
    }
    static func object(_ object: StageObstacle) -> SCNNode {
        let placement=ObjectPlacement(object), root=SCNNode()
        let w=placement.width, d=placement.depth, h=placement.height
        if object.kind == .platform || object.kind == .stairs || placement.appearance.model == .generic {
            // Exact registered footprint; do not invent stair count/entry direction.
            let path=UIBezierPath()
            for (i,p) in object.vertices.enumerated() {
                let point=CGPoint(x:p.x,y:p.y)
                if i==0 {path.move(to:point)} else {path.addLine(to:point)}
            }
            path.close()
            let shape=SCNShape(path:path,extrusionDepth:h)
            let node=part(shape,SCNVector3Zero,color:gray)
            // SCNShape extrudes equally on both sides; lift its centre onto the floor.
            node.position.y=Float(h/2)
            node.eulerAngles.x = -.pi/2; root.addChildNode(node)
        } else {
            let visual=SCNNode()
            visual.position=SCNVector3(placement.center.x,0,-placement.center.y)
            visual.eulerAngles.y=Float(placement.appearance.headingDegrees * .pi/180)
            switch placement.appearance.model {
            case .chair:
                visual.addChildNode(box(w,h*0.08,d,0,h*0.48,0))
                visual.addChildNode(box(w,h*0.45,d*0.08,0,h*0.77,-d*0.45))
                for x in [-w*0.4,w*0.4] {for z in [-d*0.4,d*0.4] {
                    visual.addChildNode(box(w*0.08,h*0.46,d*0.08,x,h*0.23,z,color:metal))
                }}
            case .table:
                visual.addChildNode(box(w,h*0.08,d,0,h*0.96,0))
                for x in [-w*0.4,w*0.4] {for z in [-d*0.4,d*0.4] {
                    visual.addChildNode(box(w*0.07,h*0.92,d*0.07,x,h*0.46,z,color:metal))
                }}
            case .musicStand, .microphone:
                visual.addChildNode(box(w,h*0.025,d,0,h*0.0125,0,color:metal))
                visual.addChildNode(part(SCNCylinder(radius:min(w,d)*0.045,height:h*0.8),SCNVector3(0,h*0.4,0),color:metal))
                if placement.appearance.model == .musicStand {
                    visual.addChildNode(box(w,h*0.28,d*0.12,0,h*0.86,0))
                } else {
                    visual.addChildNode(box(w*0.14,h*0.2,d*0.16,0,h*0.9,0))
                }
            case .speaker:
                visual.addChildNode(box(w,h,d,0,h/2,0))
                visual.addChildNode(box(w*0.82,h*0.82,d*0.02,0,h/2,d*0.51,color:metal))
            case .monitor:
                let node=box(w,h*0.7,d*0.8,0,h*0.5,0)
                node.eulerAngles.x = -.pi/8; visual.addChildNode(node)
            case .generic: break
            }
            root.addChildNode(visual)
        }
        return root
    }
    static func person() -> SCNNode {
        let root=SCNNode()
        let skin=UIColor(red:0.96,green:0.80,blue:0.66,alpha:1)
        let cloth=UIColor.systemOrange, hair=UIColor(white:0.15,alpha:1)
        for x in [-0.07,0.07] {
            root.addChildNode(part(SCNCylinder(radius:0.055,height:0.78),.init(x,0.39,0),color:skin))
        }
        root.addChildNode(part(SCNCone(topRadius:0.13,bottomRadius:0.24,height:0.28),.init(0,0.72,0),color:cloth))
        root.addChildNode(part(SCNCapsule(capRadius:0.13,height:0.48),.init(0,1.04,0),color:cloth))
        for x in [-0.18,0.18] {
            root.addChildNode(part(SCNCylinder(radius:0.04,height:0.56),.init(x,1.0,0),color:skin))
        }
        root.addChildNode(part(SCNCylinder(radius:0.045,height:0.06),.init(0,1.3,0),color:skin))
        root.addChildNode(part(SCNSphere(radius:0.11),.init(0,1.44,0),color:skin))
        root.addChildNode(part(SCNSphere(radius:0.115),.init(0,1.47,-0.025),color:hair))
        root.addChildNode(part(SCNCapsule(capRadius:0.045,height:0.24),.init(0,1.3,-0.11),color:hair))
        return root
    }
    static func line(_ a: SCNVector3,_ b: SCNVector3,color: UIColor,radius: CGFloat=0.025) -> SCNNode {
        let u=SIMD3<Float>(a.x,a.y,a.z), v=SIMD3<Float>(b.x,b.y,b.z), length=simd_length(v-u)
        let node=part(SCNCylinder(radius:radius,height:CGFloat(max(length,0.001))),SCNVector3Zero,color:color)
        node.simdPosition=(u+v)/2
        if length>0.001 {node.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:(v-u)/length)}
        return node
    }
    static func label(_ text: String, at position: SCNVector3, color: UIColor=green) -> SCNNode {
        let geometry=SCNText(string:text,extrusionDepth:0)
        geometry.font=UIFont.systemFont(ofSize:12,weight:.bold)
        geometry.flatness=0.4
        let node=part(geometry,position,color:color)
        let bounds=geometry.boundingBox
        node.pivot=SCNMatrix4MakeTranslation((bounds.min.x+bounds.max.x)/2,bounds.min.y,0)
        node.scale=SCNVector3(0.028,0.028,0.028)
        node.constraints=[SCNBillboardConstraint()]
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.readsFromDepthBuffer=false
        node.renderingOrder=20
        return node
    }
}
