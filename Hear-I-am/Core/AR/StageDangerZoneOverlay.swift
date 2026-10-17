import SceneKit
import UIKit
import HearIAmCore

/// Shared floor overlay for live preparation and saved 3D previews.
enum StageDangerZoneOverlay {
    static func node(_ zone: StageDangerZone, in area: StageArea, live: Bool = false) -> SCNNode {
        let points=zone.vertices(width:area.width,depth:area.depth).map(area.world)
        let source=SCNGeometrySource(vertices:points.map { SCNVector3($0.x,$0.y+0.015,$0.z) })
        let element=SCNGeometryElement(indices:[Int32(0),1,2,0,2,3],primitiveType:.triangles)
        let geometry=SCNGeometry(sources:[source],elements:[element])
        let material=SCNMaterial()
        material.diffuse.contents=UIColor.systemOrange.withAlphaComponent(0.30)
        material.lightingModel = .constant; material.isDoubleSided=true
        // Live overlays are annotations: reconstructed floor geometry must not hide them.
        material.readsFromDepthBuffer = !live
        material.writesToDepthBuffer=false
        geometry.materials=[material]
        let node=SCNNode(geometry:geometry)
        node.name="danger-zone-"+zone.edge.rawValue
        node.renderingOrder = live ? 100 : 0
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
