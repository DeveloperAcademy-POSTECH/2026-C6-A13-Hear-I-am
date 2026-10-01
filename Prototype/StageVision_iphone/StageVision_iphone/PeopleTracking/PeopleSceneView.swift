import SwiftUI
import SceneKit

struct PeopleSceneView: UIViewRepresentable {
    let people: [TrackedPerson]
    let camera: simd_float4x4
    let range: Double
    let selectedID: Int?

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.025, green: 0.055, blue: 0.09, alpha: 1)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        view.accessibilityLabel = "감지된 사람의 위치를 보여주는 3D 모형. 아래 목록에서 거리와 위치를 확인하세요."
        view.isAccessibilityElement = true
        return view
    }
    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.update(people, camera: camera, range: range, selected: selectedID)
    }
    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) { uiView.isPlaying = false }

    final class Coordinator {
        let scene = SCNScene()
        let cameraNode = SCNNode()
        var nodes: [Int: SCNNode] = [:]
        init() {
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.usesOrthographicProjection = true
            scene.rootNode.addChildNode(cameraNode)
            let floor = SCNFloor()
            floor.reflectivity = 0
            floor.firstMaterial?.diffuse.contents = UIColor(red: 0.035, green: 0.075, blue: 0.10, alpha: 1)
            scene.rootNode.addChildNode(SCNNode(geometry: floor))
            for i in -5...5 {
                let line = SCNBox(width: 0.012, height: 0.008, length: 5, chamferRadius: 0)
                line.firstMaterial?.diffuse.contents = UIColor.systemMint.withAlphaComponent(0.18)
                let node = SCNNode(geometry: line)
                node.position = SCNVector3(Float(i), 0.01, -2.5)
                scene.rootNode.addChildNode(node)
            }
            for i in 0...5 {
                let line = SCNBox(width: 10, height: 0.008, length: 0.012, chamferRadius: 0)
                line.firstMaterial?.diffuse.contents = UIColor.systemMint.withAlphaComponent(0.18)
                let node = SCNNode(geometry: line)
                node.position = SCNVector3(0, 0.01, -Float(i))
                scene.rootNode.addChildNode(node)
            }
            let phone = SCNNode(geometry: SCNBox(width: 0.22, height: 0.05, length: 0.4, chamferRadius: 0.04))
            phone.geometry?.firstMaterial?.diffuse.contents = UIColor.white
            phone.position = SCNVector3(0, 0.05, 0)
            scene.rootNode.addChildNode(phone)
            let label = textNode("내 iPhone", size: 0.12)
            label.position = SCNVector3(-0.35, 0.3, 0.2)
            scene.rootNode.addChildNode(label)
        }
        func update(_ people: [TrackedPerson], camera: simd_float4x4, range: Double, selected: Int?) {
            cameraNode.position = SCNVector3(0, Float(range + 2.5), Float(range * 0.75 + 1))
            cameraNode.look(at: SCNVector3(0, 0.5, -Float(range * 0.45)))
            let widest = people.compactMap { PeopleTrackingMath.relative($0.position, camera: camera) }.map { Double(abs($0.x)) }.max() ?? 0
            cameraNode.camera?.orthographicScale = max(2.4, range * 0.5 + 0.6, widest + 0.7)
            let ids = Set(people.map(\.id))
            for id in Array(nodes.keys) where !ids.contains(id) { nodes.removeValue(forKey: id)?.removeFromParentNode() }
            for person in people {
                guard let p = PeopleTrackingMath.relative(person.position, camera: camera) else { continue }
                let node: SCNNode
                if let existing = nodes[person.id] { node = existing } else {
                    node = mannequin(id: person.id)
                    nodes[person.id] = node
                    scene.rootNode.addChildNode(node)
                }
                node.position = SCNVector3(p.x, 0, -p.z)
                let color = UIColor(peopleColor(person.id))
                node.enumerateChildNodes { part, _ in
                    if part.name != "label" { part.geometry?.firstMaterial?.diffuse.contents = color }
                }
                node.childNode(withName: "halo", recursively: false)?.opacity = selected == person.id ? 1 : 0.25
                if let label = node.childNode(withName: "label", recursively: false), let text = label.geometry as? SCNText {
                    text.string = String(format: "P%02d  %.2f m", person.id, simd_length(p))
                }
                for (index, name) in ["leftLeg", "rightLeg", "leftArm", "rightArm"].enumerated() {
                    guard let limb = node.childNode(withName: name, recursively: false) else { continue }
                    if person.moving && limb.action(forKey: "walk") == nil {
                        let sign: CGFloat = index % 2 == 0 ? 1 : -1
                        let stride = SCNAction.sequence([.rotateTo(x: sign * 0.32, y: 0, z: 0, duration: 0.35),
                                                        .rotateTo(x: -sign * 0.32, y: 0, z: 0, duration: 0.35)])
                        limb.runAction(.repeatForever(stride), forKey: "walk")
                    } else if !person.moving { limb.removeAction(forKey: "walk"); limb.eulerAngles = SCNVector3Zero }
                }
            }
        }
        private func mannequin(id: Int) -> SCNNode {
            let root = SCNNode()
            func part(_ geometry: SCNGeometry, _ position: SCNVector3) {
                let node = SCNNode(geometry: geometry); node.position = position; root.addChildNode(node)
            }
            part(SCNSphere(radius: 0.13), SCNVector3(0, 1.58, 0))
            part(SCNCapsule(capRadius: 0.18, height: 0.57), SCNVector3(0, 1.13, 0))
            for (name, x, y, length) in [("leftLeg", Float(-0.11), Float(0.86), CGFloat(0.76)),
                ("rightLeg", 0.11, 0.86, 0.76), ("leftArm", -0.27, 1.37, 0.6), ("rightArm", 0.27, 1.37, 0.6)] {
                let pivot = SCNNode(); pivot.name = name; pivot.position = SCNVector3(x, y, 0)
                let limb = SCNNode(geometry: SCNCapsule(capRadius: name.contains("Leg") ? 0.075 : 0.055, height: length))
                limb.position.y = -Float(length) / 2
                pivot.addChildNode(limb); root.addChildNode(pivot)
            }
            let halo = SCNNode(geometry: SCNTorus(ringRadius: 0.3, pipeRadius: 0.014))
            halo.name = "halo"; halo.position.y = 0.025; root.addChildNode(halo)
            let label = textNode("P\(id)", size: 0.15)
            label.name = "label"; label.position = SCNVector3(-0.5, 1.95, 0)
            root.addChildNode(label)
            return root
        }
        private func textNode(_ string: String, size: CGFloat) -> SCNNode {
            let geometry = SCNText(string: string, extrusionDepth: 0)
            geometry.font = .monospacedSystemFont(ofSize: 1, weight: .semibold)
            geometry.flatness = 0.2
            geometry.firstMaterial?.diffuse.contents = UIColor.white
            geometry.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: geometry)
            node.scale = SCNVector3(size, size, size)
            node.constraints = [SCNBillboardConstraint()]
            return node
        }
    }
}

func peopleColor(_ id: Int) -> Color { [.mint, .cyan, .orange, .purple, .pink][(id - 1) % 5] }
