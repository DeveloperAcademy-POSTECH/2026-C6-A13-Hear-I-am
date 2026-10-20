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

// Display-only shapes. Nothing here changes registered footprints or guidance coordinates.
extension ReplayModelFactory {
    static let ivory=UIColor(red:0.96,green:0.94,blue:0.88,alpha:1)
    static let ink=UIColor(red:0.25,green:0.24,blue:0.22,alpha:1)
    static let cobalt=UIColor(red:0.24,green:0.36,blue:0.78,alpha:1)
    static let coral=UIColor(red:0.82,green:0.40,blue:0.29,alpha:1)
    static let waypointGreen=UIColor(red:0.12,green:0.45,blue:0.33,alpha:1)
    static let routeInk=UIColor(white:0.12,alpha:1)
    static let boundaryBronze=UIColor(red:0.78,green:0.58,blue:0.25,alpha:1)

    /// A replaceable, static 1.7 m figure, feet at Y=0 and face towards +Z.
    static func cleanPerson() -> SCNNode {
        let root=SCNNode()
        let skin=UIColor(red:0.80,green:0.65,blue:0.52,alpha:1)
        let trousers=UIColor(red:0.35,green:0.43,blue:0.49,alpha:1)
        func capsule(_ radius: CGFloat,_ height: CGFloat,_ at: SCNVector3,_ color: UIColor) -> SCNNode {
            let geometry=SCNCapsule(capRadius:radius,height:height)
            geometry.radialSegmentCount=16;geometry.capSegmentCount=8
            let node=part(geometry,at,color:color);root.addChildNode(node);return node
        }
        for x in [-0.10,0.10] {
            root.addChildNode(box(0.14,0.09,0.26,x,0.045,0.045,color:ivory))
            _=capsule(0.083,0.80,.init(x,0.47,0),trousers)
            let sleeve=capsule(0.075,0.40,.init(x*2.45,1.12,0),ivory)
            sleeve.eulerAngles.z=Float(x>0 ? 0.10 : -0.10)
            _=capsule(0.053,0.27,.init(x*2.65,0.84,0.025),skin)
        }
        let torso=capsule(0.18,0.51,.init(0,1.10,0),ivory)
        torso.scale=SCNVector3(1.1,1,0.70)
        _=capsule(0.055,0.12,.init(0,1.39,0),skin)
        let head=part(SCNSphere(radius:0.13),.init(0,1.54,0.015),color:skin)
        head.scale=SCNVector3(0.92,1.12,0.94);root.addChildNode(head)
        let hair=part(SCNSphere(radius:0.133),.init(0,1.59,-0.025),color:ink)
        hair.scale=SCNVector3(0.95,0.78,0.93);root.addChildNode(hair)
        return root.flattenedClone()
    }

    /// Low, flat ribbon; its local +Z follows the full saved 3D segment, including slopes.
    private static func routeOrientation(_ direction: SIMD3<Float>) -> simd_quatf {
        let forward=simd_normalize(direction)
        let horizontalRight=simd_cross(SIMD3<Float>(0,1,0),forward)
        let right=simd_length_squared(horizontalRight)>0.000001 ? simd_normalize(horizontalRight) : SIMD3<Float>(1,0,0)
        // A shortest-arc rotation alone adds roll on rising segments heading towards -Z.
        let up=simd_cross(forward,right)
        return simd_quatf(simd_float3x3(columns:(right,up,forward)))
    }
    private static func ribbon(_ a: SIMD3<Float>,_ b: SIMD3<Float>,width: Double,height: Double,color: UIColor) -> SCNNode {
        let delta=b-a, length=simd_length(delta)
        let node=box(width,height,Double(max(length,0.001)),color:color)
        node.simdPosition=(a+b)/2
        if length>0.0001 {node.simdOrientation=routeOrientation(delta)}
        return node
    }

    /// Spacing scales only for very long segments; at most 160 dashes per segment.
    /// Trim both ends so the line cannot run through the waypoint discs.
    static func dashedRoute(from a: SCNVector3,to b: SCNVector3,footprint: Bool=false) -> SCNNode {
        let root=SCNNode(), start=SIMD3<Float>(a), end=SIMD3<Float>(b)
        let delta=end-start,length=simd_length(delta)
        guard length>0.001 else {return root}
        let direction=delta/length,trim: Float=footprint ? 0 : min(0.25,length/2)
        let usable=length-2*trim
        guard usable>0.02 else {return root}
        let count=max(1,min(160,Int(ceil(usable/(footprint ? 0.16 : 0.23)))))
        let spacing=usable/Float(count), dash=spacing*0.58
        for index in 0..<count {
            let center=trim+(Float(index)+0.5)*spacing
            if !footprint,length>0.65,abs(center-length/2)<0.12 {continue}
            let p=start+direction*(center-dash/2),q=start+direction*(center+dash/2)
            if !footprint {
                let down=SIMD3<Float>(0,0.008,0)
                root.addChildNode(ribbon(p-down,q-down,width:0.075,height:0.006,color:ink))
            }
            root.addChildNode(ribbon(p,q,width:footprint ? 0.035 : 0.055,height:0.012,color:footprint ? boundaryBronze : routeInk))
        }
        return root.flattenedClone()
    }

    private static func shape(_ path: UIBezierPath,depth: CGFloat,color: UIColor) -> SCNNode {
        // Paths use metres, not UIKit points; the default tolerance makes small curves polygonal.
        path.flatness=0.002
        let geometry=SCNShape(path:path,extrusionDepth:depth)
        geometry.chamferRadius=min(depth/3,0.006)
        return part(geometry,SCNVector3Zero,color:color)
    }
    private static func stroke(_ points: [CGPoint],width: CGFloat,color: UIColor) -> SCNNode {
        let path=UIBezierPath()
        for (i,p) in points.enumerated() {if i==0 {path.move(to:p)} else {path.addLine(to:p)}}
        return shape(UIBezierPath(cgPath:path.cgPath.copy(strokingWithWidth:width,lineCap:.round,lineJoin:.round,miterLimit:1)),depth:0.012,color:color)
    }
    /// A flat chevron whose tip points along local +Z after laying it on the floor.
    static func routeChevron(from a: SCNVector3,to b: SCNVector3) -> SCNNode {
        let root=SCNNode(),delta=SIMD3<Float>(b)-SIMD3<Float>(a)
        guard simd_length(delta)>0.65 else {return root}
        let glyph=stroke([.init(x:-0.09,y:0.07),.init(x:0,y:-0.07),.init(x:0.09,y:0.07)],width:0.045,color:routeInk)
        glyph.eulerAngles.x = -.pi/2
        root.addChildNode(glyph)
        root.simdPosition=(SIMD3<Float>(a)+SIMD3<Float>(b))/2+SIMD3(0,0.014,0)
        root.simdOrientation=routeOrientation(delta)
        return root
    }
    static func routeOverlay(_ node: SCNNode,order: Int) {
        func configure(_ part: SCNNode) {
            part.renderingOrder=order
            for material in part.geometry?.materials ?? [] {
                material.readsFromDepthBuffer=false;material.writesToDepthBuffer=false
            }
        }
        configure(node);node.enumerateChildNodes {part,_ in configure(part)}
    }
    private static func disc(radius: CGFloat,height: CGFloat,color: UIColor) -> SCNNode {
        let geometry=SCNCylinder(radius:radius,height:height)
        geometry.radialSegmentCount=48
        return part(geometry,.init(0,Float(height/2),0),color:color)
    }
    static func startMarker(heading: Float) -> SCNNode {
        let root=SCNNode()
        root.addChildNode(disc(radius:0.24,height:0.045,color:cobalt))
        root.addChildNode(part(SCNTorus(ringRadius:0.22,pipeRadius:0.02),.init(0,0.025,0),color:cobalt))
        let path=UIBezierPath()
        let points: [CGPoint]=[.init(x:0,y:-0.15),.init(x:0.12,y:-0.015),.init(x:0.075,y:0.025),
            .init(x:0.032,y:-0.025),.init(x:0.032,y:0.14),.init(x:-0.032,y:0.14),
            .init(x:-0.032,y:-0.025),.init(x:-0.075,y:0.025),.init(x:-0.12,y:-0.015)]
        for (i,p) in points.enumerated() {if i==0 {path.move(to:p)} else {path.addLine(to:p)}}
        path.close()
        let arrow=shape(path,depth:0.012,color:ivory)
        arrow.eulerAngles.x = -.pi/2;arrow.position.y=0.052
        root.addChildNode(arrow);root.eulerAngles.y=heading
        return root
    }
    static func waypoint(_ number: Int) -> SCNNode {
        let root=SCNNode();root.addChildNode(disc(radius:0.17,height:0.035,color:waypointGreen))
        let geometry=SCNText(string:String(number),extrusionDepth:0.001)
        geometry.font=UIFont.systemFont(ofSize:12,weight:.bold);geometry.flatness=0.3
        let text=part(geometry,.init(0,0.04,0),color:ivory),bounds=geometry.boundingBox
        text.pivot=SCNMatrix4MakeTranslation((bounds.min.x+bounds.max.x)/2,(bounds.min.y+bounds.max.y)/2,0)
        text.scale=SCNVector3(0.018,0.018,0.018);text.eulerAngles.x = -.pi/2
        root.addChildNode(text)
        return root
    }
    static func arrivalMarker() -> SCNNode {
        let root=SCNNode()
        root.addChildNode(disc(radius:0.24,height:0.025,color:ivory))
        root.addChildNode(part(SCNTorus(ringRadius:0.22,pipeRadius:0.022),.init(0,0.032,0),color:coral))
        let face=SCNNode();face.position.y=0.065
        // Only the symbol faces the camera; the ring remains fixed at the saved floor coordinate.
        face.constraints=[SCNBillboardConstraint()]
        let path=UIBezierPath()
        path.move(to:.zero)
        path.addCurve(to:.init(x:-0.23,y:0.44),controlPoint1:.init(x:-0.07,y:0.14),controlPoint2:.init(x:-0.23,y:0.28))
        path.addCurve(to:.init(x:0,y:0.69),controlPoint1:.init(x:-0.23,y:0.59),controlPoint2:.init(x:-0.14,y:0.69))
        path.addCurve(to:.init(x:0.23,y:0.44),controlPoint1:.init(x:0.14,y:0.69),controlPoint2:.init(x:0.23,y:0.59))
        path.addCurve(to:.zero,controlPoint1:.init(x:0.23,y:0.28),controlPoint2:.init(x:0.07,y:0.14));path.close()
        face.addChildNode(shape(path,depth:0.065,color:coral))
        let inset=part(SCNCylinder(radius:0.165,height:0.016),.init(0,0.45,0.041),color:ivory)
        inset.eulerAngles.x = .pi/2;face.addChildNode(inset)
        let check=stroke([.init(x:-0.09,y:0.45),.init(x:-0.025,y:0.385),.init(x:0.10,y:0.52)],width:0.035,color:ink)
        check.position.z=0.058;face.addChildNode(check);root.addChildNode(face)
        return root
    }
    static func stageBoundary(_ area: StageArea) -> SCNNode {
        let root=SCNNode()
        let corners: [SIMD3<Float>]=[.init(0,0.018,0),.init(Float(area.width),0.018,0),
                                     .init(Float(area.width),0.018,-Float(area.depth)),.init(0,0.018,-Float(area.depth))]
        for i in corners.indices {
            let a=corners[i],b=corners[(i+1)%4]
            root.addChildNode(ribbon(a-SIMD3(0,0.008,0),b-SIMD3(0,0.008,0),width:0.05,height:0.006,color:ink))
            root.addChildNode(ribbon(a,b,width:0.032,height:0.009,color:boundaryBronze))
            for neighbor in [corners[(i+3)%4],b] {
                let delta=neighbor-a,length=simd_length(delta)
                guard length>0.001 else {continue}
                let end=a+delta/length*min(0.23,length/3)
                root.addChildNode(ribbon(a+SIMD3(0,0.005,0),end+SIMD3(0,0.005,0),width:0.08,height:0.018,color:boundaryBronze))
            }
        }
        return root.flattenedClone()
    }
    static func caption(_ text: String,at position: SCNVector3) -> SCNNode {
        let root=SCNNode();root.position=position;root.constraints=[SCNBillboardConstraint()]
        let geometry=SCNText(string:text,extrusionDepth:0)
        geometry.font=UIFont.systemFont(ofSize:12,weight:.semibold);geometry.flatness=0.4
        let bounds=geometry.boundingBox,scale: Float=0.018
        let width=Double((bounds.max.x-bounds.min.x)*scale)+0.14
        let plate=shape(UIBezierPath(roundedRect:CGRect(x:-width/2,y:-0.125,width:width,height:0.25),cornerRadius:0.125),depth:0.012,color:ink)
        plate.geometry?.firstMaterial?.lightingModel = .constant
        let glyph=part(geometry,.init(0,0,0.009),color:ivory)
        glyph.pivot=SCNMatrix4MakeTranslation((bounds.min.x+bounds.max.x)/2,(bounds.min.y+bounds.max.y)/2,0)
        glyph.scale=SCNVector3(scale,scale,scale);glyph.geometry?.firstMaterial?.lightingModel = .constant
        root.addChildNode(plate);root.addChildNode(glyph)
        return root
    }
}
