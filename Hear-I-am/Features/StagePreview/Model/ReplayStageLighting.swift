import SceneKit
import UIKit

/// One warm light is attached above the replay figure. Sharing the figure's transform
/// keeps the spotlight in step with it, including mid-move selections and raised points.
@MainActor
final class ReplayStageLighting {
    static let elevation: Float = 3.4
    let node = SCNNode()

    init() {
        let light = SCNLight()
        light.type = .spot
        light.color = UIColor(red:1, green:0.92, blue:0.80, alpha:1)
        light.intensity = 0
        // A broad penumbra keeps the edge soft; one light, no additional shadow map.
        light.spotInnerAngle = 6
        light.spotOuterAngle = 46
        light.attenuationStartDistance = CGFloat(Self.elevation)
        light.attenuationEndDistance = 5.8
        light.attenuationFalloffExponent = 2
        light.castsShadow = false
        node.name = "stage-follow-spotlight"
        node.light = light
        node.position = SCNVector3(0, Self.elevation, 0)
        node.eulerAngles.x = -.pi / 2 // SceneKit lights point along local -Z.
        node.isHidden = true
    }

    func setVisible(_ visible: Bool) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        node.isHidden = !visible
        node.light?.intensity = visible ? 300 : 0
        SCNTransaction.commit()
    }
}
