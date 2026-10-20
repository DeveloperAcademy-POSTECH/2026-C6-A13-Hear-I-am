import SceneKit
import UIKit
import HearIAmCore

enum ReplaySelection: Hashable { case point(Int), object(UUID), photo(UUID) }
enum ReplayCamera: String, CaseIterable { case overview="전체", overhead="동선 위에서" }
enum ReplayDisplay: String, CaseIterable { case scan="스캔 보기", clean="정리해서 보기" }

@MainActor
final class ReplaySceneController: NSObject {
    let scene=SCNScene()
    let camera=SCNNode()
    let mesh=SCNNode(), stage=SCNNode(), floor=SCNNode(), objects=SCNNode(), photos=SCNNode()
    let person=ReplayModelFactory.person()
    let surroundings=SCNNode(), key=SCNNode(), ambient=SCNNode()
    private let cleanSurfaces: [ReplaySurfaceMesh]
    private var builtCleanSurfaces=false
    private var scanBounds=(min:SCNVector3Zero,max:SCNVector3Zero)
    let selectionOverlay=SCNNode(), scanAnnotations=SCNNode(), routeNodes=SCNNode()
    let scan: LoadedScan
    var onSelect: ((ReplaySelection) -> Void)?
    var names: [String:ReplaySelection]=[:]
    var pointLabels: [Int:SCNNode]=[:]
    var revision = -1
    var lastMode: ReplayCamera = .overview
    var lastDisplay: ReplayDisplay = .scan
    weak var view: SCNView?
    init(scan: LoadedScan, cleanSurfaces: [ReplaySurfaceMesh]) {
        self.scan=scan;self.cleanSurfaces=cleanSurfaces; super.init()
        scene.rootNode.addChildNode(mesh); scene.rootNode.addChildNode(stage)
        scene.rootNode.addChildNode(photos); scene.rootNode.addChildNode(camera)
        for part in scan.meshes {
            let node=part.node(saved:true,solid:true)
            node.geometry?.firstMaterial?.diffuse.contents=UIColor(white:0.72,alpha:1)
            mesh.addChildNode(node)
        }
        // SceneKit reports zero bounds for a hidden node. Cache before switching modes.
        scanBounds=mesh.boundingBox
        camera.camera=SCNCamera(); camera.camera?.zNear=0.02; camera.camera?.zFar=2000
        camera.camera?.fieldOfView=55;camera.camera?.projectionDirection = .vertical
        ambient.light=SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity=650; scene.rootNode.addChildNode(ambient)
        key.light=SCNLight(); key.light?.type = .directional
        key.light?.intensity=900; key.eulerAngles=SCNVector3(-0.8,-0.6,0)
        key.light?.shadowColor=UIColor(white:0,alpha:0.16)
        key.light?.shadowRadius=4;key.light?.shadowSampleCount=8
        scene.rootNode.addChildNode(key)
        buildStage()
        buildPhotos()
        let p=scan.manifest.checkpoint
        scanAnnotations.addChildNode(ReplayModelFactory.part(SCNSphere(radius:0.07),.init(p.x,p.y+0.06,p.z),color:.systemYellow))
        scene.rootNode.addChildNode(scanAnnotations)
    }
    func world(_ p: FloorPoint, height: Double=0) -> SCNVector3 {
        guard let area=scan.manifest.route?.area else {return .init(p.x,height,-p.y)}
        let v=area.world(p); return .init(v.x,v.y+height,v.z)
    }
    /// Match develop: saved route heights are authoritative; older saves without heights remain at floor level.
    private func routeHeight(_ index: Int) -> Double {
        guard let heights=scan.manifest.route?.pointHeights, heights.indices.contains(index) else {return 0}
        return heights[index]
    }
    func selectable(_ node: SCNNode, _ value: ReplaySelection) {
        let name="pick-\(names.count)"; node.name=name; names[name]=value
    }
    func buildStage() {
        guard let route=scan.manifest.route else {return}
        let area=route.area
        stage.position=SCNVector3(area.frontLeft.x,area.floorHeight,area.frontLeft.z)
        stage.eulerAngles.y=Float(atan2(-area.right.y,area.right.x))
        stage.addChildNode(floor); stage.addChildNode(objects); stage.addChildNode(routeNodes)
        stage.addChildNode(surroundings)
        for i in area.corners.indices {
            let a=area.corners[i], b=area.corners[(i+1)%area.corners.count]
            scanAnnotations.addChildNode(ReplayModelFactory.line(.init(a.x,a.y+0.04,a.z),.init(b.x,b.y+0.04,b.z),color:.systemCyan))
        }
        floor.addChildNode(ReplaySurfaceFactory.stageFloor(area))
        for object in route.obstacles {
            let node=ReplayModelFactory.object(object); objects.addChildNode(node); selectable(node,.object(object.id))
            let outline=SCNNode()
            for i in object.vertices.indices {
                let a=area.world(object.vertices[i]), b=area.world(object.vertices[(i+1)%object.vertices.count])
                outline.addChildNode(ReplayModelFactory.line(.init(a.x,a.y+0.04,a.z),.init(b.x,b.y+0.04,b.z),color:.systemRed))
            }
            selectable(outline,.object(object.id));scanAnnotations.addChildNode(outline)
        }
        for zone in route.dangerZones {scene.rootNode.addChildNode(StageDangerZoneOverlay.node(zone,in:area))}
        for (index,p) in route.points.enumerated() {
            let height=routeHeight(index)
            let node=ReplayModelFactory.part(SCNSphere(radius:0.09),SCNVector3(p.x,height+0.08,-p.y),color:ReplayModelFactory.green)
            selectable(node,.point(index)); routeNodes.addChildNode(node)
            let label=ReplayModelFactory.label("\(index+1)",at:.init(p.x,height+0.24,-p.y))
            pointLabels[index]=label
            selectable(label,.point(index)); routeNodes.addChildNode(label)
            if index>0 {
                let a=route.points[index-1], b=p, previousHeight=routeHeight(index-1)
                let line=ReplayModelFactory.line(.init(a.x,previousHeight+0.06,-a.y),.init(b.x,height+0.06,-b.y),color:ReplayModelFactory.green)
                line.geometry?.firstMaterial?.readsFromDepthBuffer=false; line.renderingOrder=5
                routeNodes.addChildNode(line)
                let arrow=ReplayModelFactory.part(SCNCone(topRadius:0,bottomRadius:0.09,height:0.22),.init((a.x+b.x)/2,(previousHeight+height)/2+0.065,-(a.y+b.y)/2),color:ReplayModelFactory.green)
                let direction=SIMD3<Float>(Float(b.x-a.x),Float(height-previousHeight),Float(-(b.y-a.y)))
                if simd_length(direction)>0.001 {arrow.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:simd_normalize(direction))}
                arrow.geometry?.firstMaterial?.readsFromDepthBuffer=false; arrow.renderingOrder=6
                routeNodes.addChildNode(arrow)
            }
        }
        stage.addChildNode(person); movePerson(to:0)
        stage.addChildNode(selectionOverlay)
    }
    func buildPhotos() {
        for (index,photo) in scan.manifest.photos.enumerated() {
            let p=photo.position
            let node=ReplayModelFactory.part(SCNSphere(radius:0.075),.init(p.x,p.y,p.z),color:.systemBlue)
            selectable(node,.photo(photo.id)); photos.addChildNode(node)
            let label=ReplayModelFactory.label("사진 \(index+1)",at:.init(p.x,p.y+0.12,p.z),color:.systemBlue)
            selectable(label,.photo(photo.id)); photos.addChildNode(label)
        }
    }
    func movePerson(to index: Int) {
        guard let route=scan.manifest.route, route.points.indices.contains(index) else {person.isHidden=true;return}
        person.isHidden=false
        let p=route.points[index]
        let height=routeHeight(index)
        person.position=SCNVector3(p.x,height,-p.y)
        for (i,label) in pointLabels {label.position.y=Float(i==index ? height+1.8 : routeHeight(i)+0.24)}
        let next=route.points.indices.contains(index+1) ? route.points[index+1] : p
        let previous=index>0 ? route.points[index-1] : p
        let dx=index==route.points.count-1 ? p.x-previous.x : next.x-p.x
        let dz=index==route.points.count-1 ? -(p.y-previous.y) : -(next.y-p.y)
        if hypot(dx,dz)>0.001 {person.eulerAngles.y=Float(atan2(dx,dz))}
    }
    func update(display: ReplayDisplay, wireframe: Bool, showPhotos: Bool, selection: ReplaySelection?, cameraMode: ReplayCamera, revision: Int) {
        let displayChanged=lastDisplay != display
        lastMode=cameraMode;lastDisplay=display
        let raw=display == .scan || scan.manifest.route == nil
        if !raw && !builtCleanSurfaces {
            for part in cleanSurfaces {
                for node in ReplaySurfaceFactory.nodes(part) {surroundings.addChildNode(node)}
            }
            builtCleanSurfaces=true
        }
        mesh.isHidden = !raw
        surroundings.isHidden=raw
        floor.isHidden=raw
        objects.isHidden=raw
        scanAnnotations.isHidden=false
        ambient.light?.intensity=raw ? 650 : 800
        key.light?.intensity=raw ? 900 : 650
        key.light?.castsShadow = !raw
        view?.backgroundColor=raw ? UIColor(white:0.10,alpha:1) : ReplaySurfaceFactory.background
        routeNodes.enumerateChildNodes {node,_ in
            node.geometry?.firstMaterial?.diffuse.contents=raw ? UIColor.systemGreen : ReplayModelFactory.green
        }
        photos.isHidden = !showPhotos
        for node in mesh.childNodes {node.geometry?.firstMaterial?.fillMode=wireframe ? .lines : .fill}
        selectionOverlay.childNodes.forEach {$0.removeFromParentNode()}
        scene.rootNode.childNodes.filter {$0.name=="photo-direction"}.forEach {$0.removeFromParentNode()}
        if let selection {
            switch selection {
            case .point(let i): movePerson(to:i)
            case .object(let id):
                if let object=scan.manifest.route?.obstacles.first(where:{$0.id==id}) {
                    for i in object.vertices.indices {
                        let a=object.vertices[i],b=object.vertices[(i+1)%object.vertices.count]
                        selectionOverlay.addChildNode(ReplayModelFactory.line(.init(a.x,0.04,-a.y),.init(b.x,0.04,-b.y),color:.systemOrange,radius:0.04))
                    }
                }
            case .photo(let id):
                if showPhotos, let photo=scan.manifest.photos.first(where:{$0.id==id}) {
                    let p=photo.position, f=photo.forward
                    let node=ReplayModelFactory.line(.init(p.x,p.y,p.z),.init(p.x+f.x,p.y+f.y,p.z+f.z),color:.systemBlue,radius:0.03)
                    node.name="photo-direction"; scene.rootNode.addChildNode(node)
                }
            }
        }
        guard self.revision != revision || displayChanged else {return}
        self.revision=revision
        frame(cameraMode)
    }
    func frame(_ mode: ReplayCamera) {
        guard let view else {return}
        var points=[SCNVector3]()
        if mode == .overview || scan.manifest.route == nil {
            // Both overviews include the surrounding scan, not only the registered stage.
            let bounds=scanBounds
            for x in [bounds.min.x,bounds.max.x] {
                for y in [bounds.min.y,bounds.max.y] {
                    for z in [bounds.min.z,bounds.max.z] {points.append(.init(x,y,z))}
                }
            }
        }
        if let route=scan.manifest.route {
            points += route.area.corners.map {.init($0.x,$0.y,$0.z)}
            for index in route.points.indices {
                points.append(world(route.points[index],height:routeHeight(index)))
                // Fit every possible selection so moving the figure does not require an automatic zoom.
                points.append(world(route.points[index],height:routeHeight(index)+1.8))
            }
            for object in route.obstacles {
                points += object.vertices.map {world($0,height:ObjectPlacement(object).height)}
            }
        }
        guard !points.isEmpty else {return}
        let lo=SIMD3<Float>(points.map(\.x).min()!,points.map(\.y).min()!,points.map(\.z).min()!)
        let hi=SIMD3<Float>(points.map(\.x).max()!,points.map(\.y).max()!,points.map(\.z).max()!)
        let center=(lo+hi)/2, radius=max(simd_length(hi-lo)/2,1.5)
        let aspect=Float(max(view.bounds.width,1)/max(view.bounds.height,1))
        // Presets must not inherit the roll/up vector from an earlier preset or manual orbit.
        let controls=view.defaultCameraController
        controls.stopInertia()
        SCNTransaction.begin()
        SCNTransaction.disableActions=true
        defer {SCNTransaction.commit()}
        camera.simdTransform=matrix_identity_float4x4
        camera.camera?.usesOrthographicProjection=mode == .overhead
        let area=scan.manifest.route?.area
        let right=SIMD3<Float>(Float(area?.right.x ?? 1),0,Float(area?.right.y ?? 0))
        let back=SIMD3<Float>(Float(area?.back.x ?? 0),0,Float(area?.back.y ?? -1))
        let horizontal=points.map {abs(simd_dot(SIMD3($0.x,$0.y,$0.z)-center,right))}.max() ?? radius
        let vertical=points.map {abs(simd_dot(SIMD3($0.x,$0.y,$0.z)-center,back))}.max() ?? radius
        camera.camera?.orthographicScale=Double(max(vertical,horizontal/max(aspect,0.1),0.8)*1.18)
        let direction: SIMD3<Float>
        if let area=scan.manifest.route?.area {
            direction=SIMD3(Float(area.right.x-area.back.x),1.4,Float(area.right.y-area.back.y))
        } else {direction=SIMD3(1,1.4,1)}
        if mode == .overhead {
            let back=scan.manifest.route?.area.back ?? FloorPoint(0,-1)
            let height=max(radius*3,5), inset=height*tan(Float.pi/180)
            // Start at 89 degrees: the exact 90-degree pole can flip turntable orbit on a later drag.
            camera.simdPosition=center+SIMD3(-Float(back.x)*inset,height,-Float(back.y)*inset)
            camera.look(at:SCNVector3(center),up:SCNVector3(back.x,0,back.y),localFront:SCNVector3(0,0,-1))
        } else {
            let axis=simd_normalize(direction)
            let cameraRight=simd_normalize(simd_cross(SIMD3<Float>(0,1,0),axis))
            let cameraUp=simd_normalize(simd_cross(axis,cameraRight))
            let tangent=tan(Float(55 * Double.pi/360))
            var distance: Float=2
            let padding: Float=0.15
            for x in [lo.x-padding,hi.x+padding] {
                for y in [lo.y, max(hi.y,Float(scan.manifest.route?.area.floorHeight ?? Double(hi.y))+1.8)] {
                    for z in [lo.z-padding,hi.z+padding] {
                        let q=SIMD3(x,y,z)-center, depth=simd_dot(q,axis)
                        distance=max(distance,depth+abs(simd_dot(q,cameraRight))/(tangent*max(aspect,0.1)),
                                     depth+abs(simd_dot(q,cameraUp))/tangent)
                    }
                }
            }
            camera.simdPosition=center+axis*(distance*1.08)
            camera.look(at:SCNVector3(center),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
        }
        controls.worldUp=SCNVector3(0,1,0)
        controls.target=SCNVector3(center)
        controls.pointOfView=camera
        controls.interactionMode = .orbitTurntable
        // SceneKit uses world-space elevation: keep manual orbit in the upper hemisphere.
        // Configure after each preset, with its initial orientation already inside the range.
        controls.minimumVerticalAngle=15
        controls.maximumVerticalAngle=89.5
        view.pointOfView=camera
    }
    @objc func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let view else {return}
        for hit in view.hitTest(recognizer.location(in:view),options:[.ignoreHiddenNodes:true]) {
            var node: SCNNode?=hit.node
            while let current=node {
                if let name=current.name, let target=names[name] {onSelect?(target);return}
                node=current.parent
            }
        }
    }
}
