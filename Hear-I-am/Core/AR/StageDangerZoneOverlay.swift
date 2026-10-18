import SceneKit
import UIKit
import HearIAmCore

/// Shared floor overlay for live preparation and saved 3D previews.
enum StageDangerZoneOverlay {
    static func node(_ zone: StageDangerZone, in area: StageArea, live: Bool = false) -> SCNNode {
        let points=zone.vertices(width:area.width,depth:area.depth).map(area.world)
        // A filled plane gives the whole strip a translucent surface, independent of its border.
        let vertices=zone.vertices(width:area.width,depth:area.depth)
        let geometry=SCNPlane(width:CGFloat(vertices[1].x-vertices[0].x),
                              height:CGFloat(vertices[3].y-vertices[0].y))
        let material=SCNMaterial()
        material.diffuse.contents=UIColor.systemOrange
        material.fillMode = .fill
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.transparency=0.30
        material.lightingModel = .constant; material.isDoubleSided=true
        // Live overlays are annotations: reconstructed floor geometry must not hide them.
        material.readsFromDepthBuffer = !live
        material.writesToDepthBuffer=false
        geometry.materials=[material]
        let node=SCNNode()
        node.name="danger-zone-"+zone.edge.rawValue
        let fill=SCNNode(geometry:geometry)
        let center=area.world(FloorPoint((vertices[0].x+vertices[2].x)/2,
                                         (vertices[0].y+vertices[2].y)/2))
        fill.simdPosition=SIMD3(Float(center.x),Float(center.y)+0.015,Float(center.z))
        // Plane X/Y axes follow stage right/back; its normal points up from the floor.
        fill.simdOrientation=simd_quatf(simd_float3x3(columns:(
            SIMD3(Float(area.right.x),0,Float(area.right.y)),
            SIMD3(Float(area.back.x),0,Float(area.back.y)),
            SIMD3(0,1,0))))
        fill.renderingOrder = live ? 100 : 0
        node.addChildNode(fill)
        for i in points.indices {
            let a=points[i], b=points[(i+1)%points.count]
            let u=SIMD3<Float>(Float(a.x),Float(a.y)+0.03,Float(a.z))
            let v=SIMD3<Float>(Float(b.x),Float(b.y)+0.03,Float(b.z))
            let border=SCNNode(geometry:SCNCylinder(radius:0.012,height:CGFloat(simd_length(v-u))))
            border.simdPosition=(u+v)/2
            border.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:simd_normalize(v-u))
            let ink=SCNMaterial()
            ink.diffuse.contents=UIColor.systemOrange
            ink.lightingModel = .constant
            ink.readsFromDepthBuffer = !live; ink.writesToDepthBuffer=false
            border.geometry?.materials=[ink]; border.renderingOrder = live ? 101 : 0
            node.addChildNode(border)
        }
        return node
    }
}
