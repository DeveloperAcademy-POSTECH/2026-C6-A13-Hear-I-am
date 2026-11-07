import SceneKit
import UIKit

/// One warm light follows the selected waypoint in the saved stage's local coordinates.
/// It is presentation-only: route heights, meshes and the user's camera are never changed.
@MainActor
final class ReplayStageLighting {
    static let elevation: Float = 3.4
    private static let moveKey = "stage-spotlight-move"
    let node = SCNNode()
    private(set) var target: SCNVector3?

    init() {
        let light = SCNLight()
        light.type = .spot
        light.color = UIColor(red:1, green:0.92, blue:0.80, alpha:1)
        light.intensity = 0
        // A broad penumbra keeps the edge soft; one light, no additional shadow map.
        light.spotInnerAngle = 8
        light.spotOuterAngle = 58
        light.attenuationStartDistance = CGFloat(Self.elevation)
        light.attenuationEndDistance = 5.8
        light.attenuationFalloffExponent = 2
        light.castsShadow = false
        node.name = "stage-follow-spotlight"
        node.light = light
        node.eulerAngles.x = -.pi / 2 // SceneKit lights point along local -Z.
        node.isHidden = true
    }

    func focus(at point: SCNVector3?, animated: Bool) {
        guard let point else {
            target = nil
            node.removeAnimation(forKey:Self.moveKey)
            node.isHidden = true
            node.light?.intensity = 0
            return
        }
        let destination = SCNVector3(point.x, point.y + Self.elevation, point.z)
        if let target, target.x == destination.x, target.y == destination.y, target.z == destination.z {return}
        let wasVisible = !node.isHidden
        // Sample the visible location before replacing an in-flight move. Rapid selections
        // continue from here instead of jumping to an obsolete waypoint or queuing moves.
        let origin = node.animationKeys.contains(Self.moveKey) ? node.presentation.position : node.position
        node.removeAnimation(forKey:Self.moveKey)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        target = destination
        node.position = destination
        node.isHidden = false
        node.light?.intensity = 850
        SCNTransaction.commit()

        guard wasVisible, animated, !UIAccessibility.isReduceMotionEnabled else {return}
        let move = CABasicAnimation(keyPath:"position")
        move.fromValue = NSValue(scnVector3:origin)
        move.toValue = NSValue(scnVector3:destination)
        move.duration = 0.5
        move.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
        node.addAnimation(move, forKey:Self.moveKey)
    }
}
