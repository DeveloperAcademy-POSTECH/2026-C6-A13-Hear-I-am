import SceneKit
import SwiftUI
import HearIAmCore

/// Rebuild the saved plan in stage coordinates; later stage edits or deletion cannot alter a record.
@MainActor final class GuidanceReplayScene {
    let scene=SCNScene(),camera=SCNNode(),person=ReplayModelFactory.cleanPerson()
    let record: GuidanceRecord
    weak var view: SCNView?
    private var played=SCNNode(),playedElement: SCNGeometryElement?
    private var segmentTimes=[Double]()
    private var lastMode: ReplayCamera = .overview
    private var revision = -1
    private var bounds=(SIMD3<Float>.zero,SIMD3<Float>.zero)
    init(record: GuidanceRecord) {
        self.record=record
        scene.background.contents=ReplaySurfaceFactory.background
        scene.rootNode.addChildNode(camera)
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=650
        let key=SCNNode();key.light=SCNLight();key.light?.type = .directional;key.light?.intensity=900
        key.eulerAngles=SCNVector3(-0.8,-0.6,0)
        scene.rootNode.addChildNode(ambient);scene.rootNode.addChildNode(key)
        let route=record.route
        scene.rootNode.addChildNode(ReplaySurfaceFactory.stageFloor(route.area))
        scene.rootNode.addChildNode(ReplayModelFactory.stageBoundary(route.area))
        for object in route.obstacles {scene.rootNode.addChildNode(ReplayModelFactory.object(object))}
        for (index,p) in route.points.enumerated() {
            let marker: SCNNode
            if index==0 {
                let next=route.points[1]
                marker=ReplayModelFactory.startMarker(heading:Float(atan2(next.x-p.x,-(next.y-p.y))))
            } else if index==route.points.count-1 {marker=ReplayModelFactory.arrivalMarker()}
            else {marker=ReplayModelFactory.waypoint(index+1)}
            marker.position=SCNVector3(p.x,routeHeight(index)+0.015,-p.y)
            scene.rootNode.addChildNode(marker)
            if index>0 {
                let a=route.points[index-1]
                let from=SCNVector3(a.x,routeHeight(index-1)+0.035,-a.y),to=SCNVector3(p.x,routeHeight(index)+0.035,-p.y)
                let path=ReplayModelFactory.dashedRoute(from:from,to:to)
                ReplayModelFactory.routeOverlay(path,order:4);scene.rootNode.addChildNode(path)
                scene.rootNode.addChildNode(ReplayModelFactory.routeChevron(from:from,to:to))
            }
        }
        let ring=ReplayModelFactory.part(SCNTorus(ringRadius:0.30,pipeRadius:0.018),.init(0,0.025,0),color:.systemBlue)
        person.addChildNode(ring);scene.rootNode.addChildNode(person)
        buildTrace()
        var points=[SIMD3<Float>(0,0,0),.init(Float(route.area.width),1.8,-Float(route.area.depth))]
        for p in route.points {points.append(.init(Float(p.x),1.8,-Float(p.y)))}
        for object in route.obstacles {
            for p in object.vertices {points.append(.init(Float(p.x),Float(ObjectPlacement(object).height),-Float(p.y)))}
        }
        for sample in record.replay?.samples ?? [] {
            if let p=sample.position {points.append(.init(Float(p.x),Float(height(p,target:sample.targetIndex)+1.8),-Float(p.y)))}
        }
        bounds=(.init(points.map(\.x).min()!,0,points.map(\.z).min()!),
                .init(points.map(\.x).max()!,max(points.map(\.y).max()!,Float(route.pointHeights?.max() ?? 0)+1.8),points.map(\.z).max()!))
        show(time:0)
    }
    private func routeHeight(_ index: Int) -> Double {record.route.pointHeights?[index] ?? 0}
    /// Height is a display estimate along the saved segment, never a measured foot elevation.
    func height(_ p: FloorPoint,target: Int) -> Double {
        let index=max(1,min(target,record.route.points.count-1))
        let a=record.route.points[index-1],b=record.route.points[index]
        let dx=b.x-a.x,dy=b.y-a.y,length=dx*dx+dy*dy
        let t=length>0 ? max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/length)) : 0
        return routeHeight(index-1)+(routeHeight(index)-routeHeight(index-1))*t
    }
    private func buildTrace() {
        guard let replay=record.replay else {return}
        var vertices=[SCNVector3](),indices=[UInt32]()
        for (a,b) in zip(replay.samples,replay.samples.dropFirst()) {
            guard replay.connects(a,b),let p=a.position,let q=b.position else {continue}
            let dx=q.x-p.x,dz=p.y-q.y,length=hypot(dx,dz)
            guard length>0.001 else {continue}
            let x = -dz/length*0.025,z=dx/length*0.025,index=UInt32(vertices.count)
            let y1=height(p,target:a.targetIndex)+0.065,y2=height(q,target:b.targetIndex)+0.065
            vertices += [.init(p.x+x,y1,-p.y+z),.init(p.x-x,y1,-p.y-z),
                         .init(q.x+x,y2,-q.y+z),.init(q.x-x,y2,-q.y-z)]
            indices += [index,index+1,index+2,index+1,index+3,index+2]
            segmentTimes.append(b.time)
        }
        guard !indices.isEmpty else {return}
        let source=SCNGeometrySource(vertices:vertices)
        func makeNode(_ color: UIColor) -> (SCNNode,SCNGeometryElement) {
            let element=SCNGeometryElement(indices:indices,primitiveType:.triangles)
            let geometry=SCNGeometry(sources:[source],elements:[element]),material=SCNMaterial()
            material.diffuse.contents=color;material.lightingModel = .constant;material.isDoubleSided=true
            material.readsFromDepthBuffer=false;material.writesToDepthBuffer=false
            geometry.firstMaterial=material
            let node=SCNNode(geometry:geometry);node.renderingOrder=7
            return (node,element)
        }
        let full=makeNode(UIColor.systemBlue.withAlphaComponent(0.22)).0
        full.name="record-entire-trace";scene.rootNode.addChildNode(full)
        (played,playedElement)=makeNode(.systemBlue)
        played.name="record-played-trace";played.renderingOrder=8;scene.rootNode.addChildNode(played)
    }
    func show(time: Double) {
        SCNTransaction.begin();SCNTransaction.disableActions=true
        defer {SCNTransaction.commit()}
        if let pose=record.replay?.pose(at:time),let p=pose.position {
            person.isHidden=false;person.position=SCNVector3(p.x,height(p,target:pose.targetIndex),-p.y)
            person.eulerAngles.y=Float(-(pose.heading ?? 0) * .pi/180)
        } else {person.isHidden=true}
        var low=0,high=segmentTimes.count
        while low<high {let mid=(low+high)/2;if segmentTimes[mid]<=time {low=mid+1} else {high=mid}}
        played.isHidden=low==0;playedElement?.primitiveRange=NSRange(location:0,length:low*2)
    }
    func update(time: Double,mode: ReplayCamera,revision: Int) {
        show(time:time)
        if lastMode != mode || self.revision != revision {lastMode=mode;self.revision=revision;frame()}
    }
    func frame() {
        guard let view else {return}
        SCNTransaction.begin();SCNTransaction.disableActions=true
        defer {SCNTransaction.commit()}
        let controls=view.defaultCameraController;controls.stopInertia()
        let lo=bounds.0,hi=bounds.1,center=(lo+hi)/2,radius=max(simd_length(hi-lo)/2,1.5)
        let aspect=Float(max(view.bounds.width,1)/max(view.bounds.height,1))
        camera.simdTransform=matrix_identity_float4x4
        camera.camera=SCNCamera();camera.camera?.zNear=0.02;camera.camera?.zFar=2000
        camera.camera?.fieldOfView=55;camera.camera?.projectionDirection = .vertical
        camera.camera?.usesOrthographicProjection=lastMode == .overhead
        camera.camera?.orthographicScale=Double(max((hi.z-lo.z)/2,(hi.x-lo.x)/(2*max(aspect,0.1)),1)*1.18)
        if lastMode == .overhead {
            let height=max(radius*3,5)
            camera.simdPosition=center+SIMD3(0,height,height*tan(Float.pi/180))
            camera.look(at:SCNVector3(center),up:SCNVector3(0,0,-1),localFront:SCNVector3(0,0,-1))
        } else {
            let axis=simd_normalize(SIMD3<Float>(1,1.4,1)),right=simd_normalize(simd_cross(SIMD3<Float>(0,1,0),axis))
            let up=simd_normalize(simd_cross(axis,right)),tangent=tan(Float(55*Double.pi/360))
            var distance: Float=2
            for x in [lo.x-0.2,hi.x+0.2] {for y in [lo.y,hi.y] {for z in [lo.z-0.2,hi.z+0.2] {
                let q=SIMD3(x,y,z)-center,depth=simd_dot(q,axis)
                distance=max(distance,depth+abs(simd_dot(q,right))/(tangent*max(aspect,0.1)),depth+abs(simd_dot(q,up))/tangent)
            }}}
            camera.simdPosition=center+axis*distance*1.08
            camera.look(at:SCNVector3(center),up:.init(0,1,0),localFront:.init(0,0,-1))
        }
        controls.worldUp = .init(0,1,0);controls.target=SCNVector3(center);controls.pointOfView=camera
        controls.interactionMode = .orbitTurntable;controls.minimumVerticalAngle=15;controls.maximumVerticalAngle=89.5
        view.pointOfView=camera
    }
}

struct GuidanceReplaySceneView: UIViewRepresentable {
    @ObservedObject var player: GuidanceReplayPlayer
    func makeUIView(context: Context) -> SCNView {
        let view=ReplaySCNView(),controller=player.scene
        controller.view=view;view.scene=controller.scene;view.pointOfView=controller.camera
        view.backgroundColor=ReplaySurfaceFactory.background;view.allowsCameraControl=true;view.antialiasingMode = .multisampling4X
        view.onLayout={ [weak controller] in controller?.frame() }
        return view
    }
    func updateUIView(_ view: SCNView,context: Context) {
        player.scene.update(time:player.time,mode:player.cameraMode,revision:player.cameraRevision)
    }
}
