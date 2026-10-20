import SceneKit
import UIKit
import HearIAmCore

enum ReplaySelection: Hashable { case point(Int), object(UUID), photo(UUID) }
enum ReplayCamera: String, CaseIterable { case overview="전체", overhead="동선 위에서", close="구간 가까이" }
enum ReplayDisplay: String, CaseIterable { case clean="정리해서 보기", scan="스캔 보기" }

@MainActor
final class ReplaySceneController: NSObject {
    let scene=SCNScene()
    let camera=SCNNode()
    let mesh=SCNNode(), stage=SCNNode(), floor=SCNNode(), objects=SCNNode(), photos=SCNNode()
    let person=ReplayModelFactory.person()
    let selectionOverlay=SCNNode()
    let scan: LoadedScan
    var onSelect: ((ReplaySelection) -> Void)?
    var targets: [ReplaySelection:SCNVector3]=[:]
    var names: [String:ReplaySelection]=[:]
    var pointLabels: [Int:SCNNode]=[:]
    var revision = -1
    var lastMode: ReplayCamera = .overview
    var lastSelection: ReplaySelection?
    weak var view: SCNView?
    init(scan: LoadedScan) {
        self.scan=scan; super.init()
        scene.rootNode.addChildNode(mesh); scene.rootNode.addChildNode(stage)
        scene.rootNode.addChildNode(photos); scene.rootNode.addChildNode(camera)
        for part in scan.meshes {mesh.addChildNode(part.node(saved:true,solid:true))}
        camera.camera=SCNCamera(); camera.camera?.zNear=0.02; camera.camera?.zFar=2000
        camera.camera?.fieldOfView=55;camera.camera?.projectionDirection = .vertical
        let ambient=SCNNode(); ambient.light=SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity=650; scene.rootNode.addChildNode(ambient)
        let key=SCNNode(); key.light=SCNLight(); key.light?.type = .directional
        key.light?.intensity=900; key.eulerAngles=SCNVector3(-0.8,-0.6,0)
        scene.rootNode.addChildNode(key)
        buildStage()
        buildPhotos()
    }
    func world(_ p: FloorPoint, height: Double=0) -> SCNVector3 {
        guard let area=scan.manifest.route?.area else {return .init(p.x,height,-p.y)}
        let v=area.world(p); return .init(v.x,v.y+height,v.z)
    }
    func selectable(_ node: SCNNode, _ value: ReplaySelection) {
        let name="pick-\(names.count)"; node.name=name; names[name]=value
    }
    func buildStage() {
        guard let route=scan.manifest.route else {return}
        let area=route.area
        stage.position=SCNVector3(area.frontLeft.x,area.floorHeight,area.frontLeft.z)
        stage.eulerAngles.y=Float(atan2(-area.right.y,area.right.x))
        stage.addChildNode(floor); stage.addChildNode(objects)
        floor.addChildNode(ReplayModelFactory.box(area.width,0.035,area.depth,area.width/2,-0.035,-area.depth/2,color:UIColor(white:0.91,alpha:1)))
        for object in route.obstacles {
            let node=ReplayModelFactory.object(object); objects.addChildNode(node); selectable(node,.object(object.id))
            let p=ObjectPlacement(object)
            targets[.object(object.id)]=world(p.center,height:p.height/2)
        }
        for zone in route.dangerZones {scene.rootNode.addChildNode(StageDangerZoneOverlay.node(zone,in:area))}
        for (index,p) in route.points.enumerated() {
            let node=ReplayModelFactory.part(SCNSphere(radius:0.09),SCNVector3(p.x,0.08,-p.y),color:ReplayModelFactory.green)
            selectable(node,.point(index)); stage.addChildNode(node)
            let label=ReplayModelFactory.label("\(index+1)",at:.init(p.x,0.24,-p.y))
            pointLabels[index]=label
            selectable(label,.point(index)); stage.addChildNode(label)
            targets[.point(index)]=world(p)
            if index>0 {
                let a=route.points[index-1], b=p
                let line=ReplayModelFactory.line(.init(a.x,0.06,-a.y),.init(b.x,0.06,-b.y),color:ReplayModelFactory.green)
                line.geometry?.firstMaterial?.readsFromDepthBuffer=false; line.renderingOrder=5
                stage.addChildNode(line)
                let arrow=ReplayModelFactory.part(SCNCone(topRadius:0,bottomRadius:0.09,height:0.22),.init((a.x+b.x)/2,0.065,-(a.y+b.y)/2),color:ReplayModelFactory.green)
                let direction=SIMD3<Float>(Float(b.x-a.x),0,Float(-(b.y-a.y)))
                if simd_length(direction)>0.001 {arrow.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:simd_normalize(direction))}
                arrow.geometry?.firstMaterial?.readsFromDepthBuffer=false; arrow.renderingOrder=6
                stage.addChildNode(arrow)
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
            targets[.photo(photo.id)]=node.position
        }
    }
    func movePerson(to index: Int) {
        guard let route=scan.manifest.route, route.points.indices.contains(index) else {person.isHidden=true;return}
        person.isHidden=false
        let p=route.points[index]
        let height=route.obstacles.filter {$0.kind == .platform && $0.contains(p)}.compactMap(\.height).filter {$0.isFinite && $0>0}.max() ?? 0
        person.position=SCNVector3(p.x,height,-p.y)
        for (i,label) in pointLabels {label.position.y=Float(i==index ? height+1.8 : 0.24)}
        let next=route.points.indices.contains(index+1) ? route.points[index+1] : p
        let previous=index>0 ? route.points[index-1] : p
        let dx=index==route.points.count-1 ? p.x-previous.x : next.x-p.x
        let dz=index==route.points.count-1 ? -(p.y-previous.y) : -(next.y-p.y)
        if hypot(dx,dz)>0.001 {person.eulerAngles.y=Float(atan2(dx,dz))}
    }
    func update(display: ReplayDisplay, wireframe: Bool, showPhotos: Bool, selection: ReplaySelection?, cameraMode: ReplayCamera, revision: Int) {
        lastMode=cameraMode;lastSelection=selection
        mesh.isHidden=display == .clean && scan.manifest.route != nil
        floor.isHidden=display == .scan
        objects.opacity=display == .scan ? 0.35 : 1
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
        guard self.revision != revision else {return}
        self.revision=revision
        frame(cameraMode,selection:selection)
    }
    func frame(_ mode: ReplayCamera, selection: ReplaySelection?) {
        guard let view else {return}
        var points=[SCNVector3]()
        if let route=scan.manifest.route {
            points=route.area.corners.map {.init($0.x,$0.y,$0.z)}+route.points.map {world($0)}
            for object in route.obstacles {
                points.append(world(ObjectPlacement(object).center,height:ObjectPlacement(object).height))
            }
        } else {
            // Mesh bounds are in world because each mesh node retains its saved transform.
            let b=mesh.boundingBox; points=[b.min,b.max]
        }
        if mode == .close, let selection {
            switch selection {
            case .point(let i):
                if let route=scan.manifest.route, route.points.indices.contains(i) {
                    points=[world(route.points[i])]
                    if route.points.indices.contains(i+1) {points.append(world(route.points[i+1]))}
                }
            case .object(let id):
                if let object=scan.manifest.route?.obstacles.first(where:{$0.id==id}) {
                    points=object.vertices.map {world($0)}+object.vertices.map {world($0,height:ObjectPlacement(object).height)}
                }
            case .photo:
                if let p=targets[selection] {points=[p]}
            }
        }
        guard !points.isEmpty else {return}
        let lo=SIMD3<Float>(points.map(\.x).min()!,points.map(\.y).min()!,points.map(\.z).min()!)
        let hi=SIMD3<Float>(points.map(\.x).max()!,points.map(\.y).max()!,points.map(\.z).max()!)
        let center=(lo+hi)/2, radius=max(simd_length(hi-lo)/2, mode == .close ? 0.8 : 1.5)
        let aspect=Float(max(view.bounds.width,1)/max(view.bounds.height,1))
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
            camera.simdPosition=center+SIMD3(0,max(radius*3,5),0)
            let back=scan.manifest.route?.area.back ?? FloorPoint(0,-1)
            camera.look(at:SCNVector3(center),up:SCNVector3(back.x,0,back.y),localFront:SCNVector3(0,0,-1))
        } else {
            let axis=simd_normalize(direction)
            let cameraRight=simd_normalize(simd_cross(SIMD3<Float>(0,1,0),axis))
            let cameraUp=simd_normalize(simd_cross(axis,cameraRight))
            let tangent=tan(Float(55 * Double.pi/360))
            var distance: Float=2
            let padding: Float=mode == .close ? 0.6 : 0.15
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
            camera.look(at:SCNVector3(center))
        }
        view.pointOfView=camera
        view.defaultCameraController.target=SCNVector3(center)
        view.defaultCameraController.stopInertia()
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
