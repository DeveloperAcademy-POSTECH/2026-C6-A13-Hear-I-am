import SceneKit
import UIKit
import HearIAmCore

/// Shared floor overlay for live preparation and saved 3D previews.
enum StageDangerZoneOverlay {
    static func node(_ zone: StageDangerZone, in area: StageArea) -> SCNNode {
        let points=zone.vertices(width:area.width,depth:area.depth).map(area.world)
        let source=SCNGeometrySource(vertices:points.map { SCNVector3($0.x,$0.y+0.015,$0.z) })
        let element=SCNGeometryElement(indices:[Int32(0),1,2,0,2,3],primitiveType:.triangles)
        let geometry=SCNGeometry(sources:[source],elements:[element])
        let material=SCNMaterial()
        material.diffuse.contents=UIColor.systemOrange.withAlphaComponent(0.30)
        material.lightingModel = .constant; material.isDoubleSided=true
        material.writesToDepthBuffer=false
        geometry.materials=[material]
        let node=SCNNode(geometry:geometry)
        node.name="danger-zone-"+zone.edge.rawValue
        return node
    }
}
