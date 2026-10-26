import SceneKit
import UIKit
import HearIAmCore

/// Draws the scanned mesh and stage annotations into the AR view. It never reads the AR session.
@MainActor
final class ARSceneRenderer {
    /// What the reference overlay shows. Labels and colors follow the screen that owns the session.
    struct Annotations {
        enum Style {
            case preparation(routeFinished: Bool)
            case guidance(target: Int?, completed: Bool)
        }
        var style: Style
        var checkpoint: Point3?
        var secondCheckpoint: Point3? = nil
        var corners: [Point3?]
        var area: StageArea?
        var routePoints: [FloorPoint]
        var routeHeights: [Double]? = nil
        var obstacles: [StageObstacle]
        var pendingObject: [FloorPoint]
        var pendingFacingEdge: Int? = nil
        /// Route clearance around blocking objects, filled in red in both preparation and guidance (#38).
        var clearance: Double
        var dangerZones: [StageDangerZone] = []
        var planReference: StagePlanReference? = nil
    }

    let meshLayer=SCNNode()
    let referenceLayer=SCNNode()
    private var meshNodes: [UUID:SCNNode]=[:]

    func applyAlignment(_ alignment: CheckpointAlignment?) {
        var transform=matrix_identity_float4x4
        if let alignment {
            let c=Float(cos(alignment.yaw)), s=Float(sin(alignment.yaw))
            transform.columns.0=SIMD4(c,0,-s,0)
            transform.columns.2=SIMD4(s,0,c,0)
            let offset=alignment.apply(Point3(0,0,0))
            transform.columns.3=SIMD4(Float(offset.x),0,Float(offset.z),1)
        }
        meshLayer.simdTransform=transform; referenceLayer.simdTransform=transform
    }
    func attach(to scene: SCNScene) {
        scene.rootNode.addChildNode(meshLayer)
        scene.rootNode.addChildNode(referenceLayer)
    }
    func updateMeshes(_ parts: [MeshSnapshot], removed: [UUID]) {
        for id in removed { meshNodes.removeValue(forKey:id)?.removeFromParentNode() }
        for part in parts {
            meshNodes.removeValue(forKey:part.id)?.removeFromParentNode()
            let node=part.node(saved:false); meshNodes[part.id]=node; meshLayer.addChildNode(node)
        }
    }
    func rebuildMeshes(_ meshes: some Sequence<MeshSnapshot>, saved: Bool) {
        clearMeshes()
        for m in meshes { let n=m.node(saved:saved); meshNodes[m.id]=n; meshLayer.addChildNode(n) }
    }
    func clearMeshes() { meshNodes.values.forEach {$0.removeFromParentNode()}; meshNodes=[:] }
    func clearAnnotations() { referenceLayer.childNodes.forEach {$0.removeFromParentNode()} }
}
