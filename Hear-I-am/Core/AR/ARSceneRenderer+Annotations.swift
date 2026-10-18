import SceneKit
import UIKit
import HearIAmCore

extension ARSceneRenderer {
    func draw(_ content: Annotations) {
        clearAnnotations()
        let preparing: Bool, routeFinished: Bool, target: Int?, completed: Bool
        switch content.style {
        case .preparation(let finished): preparing=true; routeFinished=finished; target=nil; completed=false
        case .guidance(let index, let done): preparing=false; routeFinished=false; target=index; completed=done
        }
        if let p=content.checkpoint {
            let node=SCNNode(geometry:SCNSphere(radius:0.04)); node.geometry?.firstMaterial?.diffuse.contents=UIColor.systemYellow
            node.position=SCNVector3(Float(p.x),Float(p.y)+0.04,Float(p.z)); referenceLayer.addChildNode(node)
            let text=SCNText(string:"확인점",extrusionDepth:0); text.font = .boldSystemFont(ofSize:10)
            let n=SCNNode(geometry:text); n.scale=SCNVector3(0.015,0.015,0.015)
            n.position=SCNVector3(Float(p.x),Float(p.y)+0.12,Float(p.z)); n.constraints=[SCNBillboardConstraint()]
            referenceLayer.addChildNode(n)
        }
        let corners=content.corners
        for (i,p) in corners.enumerated() {
            guard let p else {continue}; cornerMarker(p,label:preparing ? ["앞 왼쪽","앞 오른쪽","뒤 오른쪽","뒤 왼쪽"][i] : "E\(i+1)")
        }
        if preparing {
            let order=PreparationDraft.captureOrder
            for i in 1..<4 {
                if let a=corners[order[i-1]], let b=corners[order[i]] {line(a,b,color:.systemGreen)}
            }
        }
        if content.area == nil, let first=corners[0], let second=corners[1],
           let guide=try? FrontEdgeGuide(frontLeft:first,frontRight:second) {
            line(guide.leftStart,guide.rightStart,color:.systemOrange)
            dashedGuide(guide.leftStart,guide.leftEnd)
            dashedGuide(guide.rightStart,guide.rightEnd)
        }
        guard let area=content.area else { return }
        let edge=[FloorPoint(0,0),FloorPoint(area.width,0),FloorPoint(area.width,area.depth),FloorPoint(0,area.depth)]
        for i in 0..<4 { line(area.world(edge[i]),area.world(edge[(i+1)%4]),color:.systemCyan) }
        for zone in content.dangerZones {
            referenceLayer.addChildNode(StageDangerZoneOverlay.node(zone,in:area,live:true))
        }
        let routePoints=content.routePoints
        for (i,p) in routePoints.enumerated() {
            let active = !preparing && !completed && i == target
            let label=i == 0 ? "출발" : ((!preparing || routeFinished) && i == routePoints.count-1 ? "도착" : "P\(i)")
            let color: UIColor=active ? .systemOrange : .systemGreen
            marker(area.world(p),label:label+(active ? " · 현재 목표" : ""),color:color)
            if active {
                let ring=SCNNode(geometry:SCNTorus(ringRadius:0.12,pipeRadius:0.015))
                let world=area.world(p);ring.position=SCNVector3(Float(world.x),Float(world.y)+0.02,Float(world.z))
                ring.geometry?.firstMaterial?.diffuse.contents=color;referenceLayer.addChildNode(ring)
            }
            if i>0 {line(area.world(routePoints[i-1]),area.world(p),color:active ? .systemOrange : .systemGreen)}
        }
        for o in content.obstacles {
            for i in o.vertices.indices {line(area.world(o.vertices[i]),area.world(o.vertices[(i+1)%o.vertices.count]),color:.systemRed)}
        }
        for p in content.pendingObject {marker(area.world(p),label:"물체",color:.systemOrange)}
    }

    private func cornerMarker(_ p: Point3,label: String) {
        let group=SCNNode()
        group.name="stage-corner-"+label
        group.position=SCNVector3(Float(p.x),Float(p.y),Float(p.z))
        let ring=SCNNode(geometry:SCNTorus(ringRadius:0.08,pipeRadius:0.009))
        ring.geometry?.firstMaterial?.diffuse.contents=UIColor.systemCyan
        ring.position.y=0.012
        group.addChildNode(ring)
        let stem=SCNNode(geometry:SCNCylinder(radius:0.005,height:0.14))
        stem.geometry?.firstMaterial?.diffuse.contents=UIColor.systemCyan
        stem.position.y=0.07
        group.addChildNode(stem)
        let pin=SCNNode(geometry:SCNSphere(radius:0.04))
        pin.geometry?.firstMaterial?.diffuse.contents=UIColor.systemYellow
        pin.position.y=0.15
        group.addChildNode(pin)
        let text=SCNText(string:label,extrusionDepth:0)
        text.font = .boldSystemFont(ofSize:12)
        text.firstMaterial?.diffuse.contents=UIColor.white
        let tag=SCNNode(geometry:text)
//        tag.scale=SCNVector3(0.018,0.018,0.018)
        tag.scale=SCNVector3(0.004,0.004,0.004)
        tag.position=SCNVector3(0,0.24,0)
        tag.constraints=[SCNBillboardConstraint()]
        group.addChildNode(tag)
        referenceLayer.addChildNode(group)
    }
    private func dashedGuide(_ a: Point3,_ b: Point3) {
        let length=hypot(b.x-a.x,b.z-a.z)
        guard length > 0 else {return}
        var start=0.0
        while start < length {
            let end=min(start+0.30,length)
            let u=start/length, v=end/length
            let from=Point3(a.x+(b.x-a.x)*u,a.y,a.z+(b.z-a.z)*u)
            let to=Point3(a.x+(b.x-a.x)*v,a.y,a.z+(b.z-a.z)*v)
            line(from,to,color:.systemOrange)
            start += 0.55
        }
    }
    private func marker(_ p: Point3,label: String,color: UIColor) {
        let n=SCNNode(geometry:SCNSphere(radius:0.05)); n.geometry?.firstMaterial?.diffuse.contents=color
        n.position=SCNVector3(Float(p.x),Float(p.y)+0.05,Float(p.z))
        referenceLayer.addChildNode(n)
        let text=SCNText(string:label,extrusionDepth:0); text.font = .boldSystemFont(ofSize:10)
        text.firstMaterial?.diffuse.contents=color; text.firstMaterial?.lightingModel = .constant
        let t=SCNNode(geometry:text); t.scale=SCNVector3(0.015,0.015,0.015)
        t.position=SCNVector3(Float(p.x),Float(p.y)+0.14,Float(p.z)); t.constraints=[SCNBillboardConstraint()]
        referenceLayer.addChildNode(t)
    }
    private func line(_ a: Point3,_ b: Point3,color: UIColor) {
        let u=SIMD3<Float>(Float(a.x),Float(a.y)+0.025,Float(a.z))
        let v=SIMD3<Float>(Float(b.x),Float(b.y)+0.025,Float(b.z))
        let d=v-u; guard simd_length(d)>0.001 else {return}
        let n=SCNNode(geometry:SCNCylinder(radius:0.012,height:CGFloat(simd_length(d))))
        n.geometry?.firstMaterial?.diffuse.contents=color
        n.simdPosition=(u+v)/2
        n.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:simd_normalize(d))
        referenceLayer.addChildNode(n)
    }
}
