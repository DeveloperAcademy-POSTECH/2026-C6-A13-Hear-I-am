import SceneKit
import SwiftUI
import HearIAmCore

/// Rebuild the saved plan in stage coordinates; later stage edits or deletion cannot alter a record.
@MainActor final class GuidanceReplayScene {
    /// Figma 971:31085: the replay fills the page on #21262A, as the saved stage does on its own dark ground.
    static let background=UIColor(red:33/255,green:38/255,blue:42/255,alpha:1)
    let scene=SCNScene(),camera=SCNNode()
    let walkingFigure=ReplayWalkingFigure()
    var person: SCNNode {walkingFigure.node}
    private let walkingTimeline: GuidanceWalkTimeline?
    let record: GuidanceRecord
    weak var view: SCNView?
    private var played=SCNNode(),playedElement: SCNGeometryElement?
    private var lastMode: ReplayCamera = .overview
    private var revision = -1
    private var bounds=(SIMD3<Float>.zero,SIMD3<Float>.zero)
    init(record: GuidanceRecord) {
        self.record=record
        walkingTimeline=record.replay.map {GuidanceWalkTimeline(replay:$0)}
        scene.background.contents=Self.background
        scene.rootNode.addChildNode(camera)
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=650
        let key=SCNNode();key.light=SCNLight();key.light?.type = .directional;key.light?.intensity=900
        key.eulerAngles=SCNVector3(-0.8,-0.6,0)
        scene.rootNode.addChildNode(ambient);scene.rootNode.addChildNode(key)
        let route=record.route
        scene.rootNode.addChildNode(ReplaySurfaceFactory.stageFloor(route.area))
        scene.rootNode.addChildNode(ReplayModelFactory.stageBoundary(route.area))
        for object in route.obstacles {scene.rootNode.addChildNode(ReplayModelFactory.object(object))}
        let pathPoints=record.guidancePath,pathHeights=record.guidancePathHeights
        for (index,p) in pathPoints.enumerated() {
            let marker: SCNNode
            if index==0 {
                let next=pathPoints[1]
                marker=ReplayModelFactory.startMarker(heading:Float(atan2(next.x-p.x,-(next.y-p.y))))
            } else if index==pathPoints.count-1 {marker=ReplayModelFactory.arrivalMarker()}
            else {marker=ReplayModelFactory.waypoint(index+1)}
            marker.position=SCNVector3(p.x,pathHeights[index]+0.015,-p.y)
            scene.rootNode.addChildNode(marker)
            if index>0, pathPoints[index-1].distance(to:p)>0.0001 {
                let a=pathPoints[index-1]
                let from=SCNVector3(a.x,pathHeights[index-1]+0.035,-a.y),to=SCNVector3(p.x,pathHeights[index]+0.035,-p.y)
                let path=ReplayModelFactory.dashedRoute(from:from,to:to)
                ReplayModelFactory.routeOverlay(path,order:4);scene.rootNode.addChildNode(path)
                scene.rootNode.addChildNode(ReplayModelFactory.routeChevron(from:from,to:to))
            }
        }
        let ring=ReplayModelFactory.part(SCNTorus(ringRadius:0.30,pipeRadius:0.018),.init(0,0.025,0),color:.systemBlue)
        person.addChildNode(ring);scene.rootNode.addChildNode(person)
        buildTrace()
        var points=[SIMD3<Float>(0,0,0),.init(Float(route.area.width),1.8,-Float(route.area.depth))]
        for p in pathPoints {points.append(.init(Float(p.x),1.8,-Float(p.y)))}
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
    /// Height follows this run's planned segment, never a measured foot elevation. Practice origin is on the stage floor.
    func height(_ p: FloorPoint,target: Int) -> Double {
        let path=record.guidancePath,heights=record.guidancePathHeights
        let offset=record.practiceOrigin != nil ? (record.firstGuidedPointIndex ?? 1)-1 : 0
        let index=max(1,min(target-offset,path.count-1))
        let a=path[index-1],b=path[index]
        let dx=b.x-a.x,dy=b.y-a.y,length=dx*dx+dy*dy
        let t=length>0 ? max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/length)) : 0
        return heights[index-1]+(heights[index]-heights[index-1])*t
    }
    /// One smoothed ribbon per tracked stretch. Each trail point carries its side vertices, colour and time, so the
    /// played part can stop between two points and grow continuously while the figure walks.
    private struct TrailPoint {
        var left: SCNVector3,right: SCNVector3
        var color: SIMD4<Float>
        var time: Double
    }
    private var trailPoints=[TrailPoint]()
    /// For each drawn segment, its end point's index into `trailPoints` (segments never cross a gap between stretches).
    private var segmentEnds=[Int]()
    private let head=SCNNode()

    private func buildTrace() {
        guard let replay=record.replay else {return}
        // Green where the walk followed the route, easing through yellow to orange where it strayed or lingered (#165).
        let strain=GuidanceReplayStrain.values(replay:replay,path:record.guidancePath)
        // Split into stretches the recording actually tracked, dropping repeats where the person stood still.
        var stretches=[[ReplayTrailKnot]](),current=[ReplayTrailKnot]()
        for (i,s) in replay.samples.enumerated() {
            guard let p=s.position else {if current.count>1 {stretches.append(current)};current=[];continue}
            if i>0,!replay.connects(replay.samples[i-1],s),!current.isEmpty {
                if current.count>1 {stretches.append(current)};current=[]
            }
            let knot=ReplayTrailKnot(x:p.x,z:-p.y,y:height(p,target:s.targetIndex)+0.065,time:s.time,strain:strain[i])
            if let last=current.last,hypot(last.x-knot.x,last.z-knot.z)<0.01 {continue}
            current.append(knot)
        }
        if current.count>1 {stretches.append(current)}
        var vertices=[SCNVector3](),colors=[SIMD4<Float>](),indices=[UInt32]()
        for stretch in stretches {
            let knots=ReplayTrailKnot.smoothed(stretch,steps:4)
            let first=trailPoints.count
            for (j,k) in knots.enumerated() {
                // Side offsets follow the curve's direction at each point, so neighbouring pieces share their edge.
                let a=knots[max(0,j-1)],b=knots[min(knots.count-1,j+1)]
                let dx=b.x-a.x,dz=b.z-a.z,length=max(hypot(dx,dz),0.0001)
                let nx = -dz/length*Self.trailHalfWidth,nz=dx/length*Self.trailHalfWidth
                let point=TrailPoint(left:.init(k.x+nx,k.y,k.z+nz),right:.init(k.x-nx,k.y,k.z-nz),
                                     color:Self.trailColor(k.strain),time:k.time)
                trailPoints.append(point)
                vertices += [point.left,point.right];colors += [point.color,point.color]
                if j>0 {
                    let index=UInt32(2*(first+j-1))
                    indices += [index,index+1,index+2,index+1,index+3,index+2]
                    segmentEnds.append(first+j)
                }
            }
        }
        guard !indices.isEmpty else {return}
        let full=Self.trailNode(vertices:vertices,colors:colors,indices:indices,opacity:0.22)
        full.name="record-entire-trace";scene.rootNode.addChildNode(full)
        played=Self.trailNode(vertices:vertices,colors:colors,indices:indices,opacity:1)
        playedElement=played.geometry?.elements.first
        played.name="record-played-trace";played.renderingOrder=8;scene.rootNode.addChildNode(played)
        head.renderingOrder=8;scene.rootNode.addChildNode(head)
    }
    private static let trailHalfWidth=0.025
    private static func trailNode(vertices: [SCNVector3],colors: [SIMD4<Float>],indices: [UInt32],opacity: CGFloat) -> SCNNode {
        let colorSource=SCNGeometrySource(data:colors.withUnsafeBufferPointer {Data(buffer:$0)},semantic:.color,
            vectorCount:colors.count,usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:MemoryLayout<Float>.size,
            dataOffset:0,dataStride:MemoryLayout<SIMD4<Float>>.stride)
        let element=SCNGeometryElement(indices:indices,primitiveType:.triangles)
        let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),colorSource],elements:[element]),material=SCNMaterial()
        material.diffuse.contents=UIColor.white;material.transparency=opacity
        material.lightingModel = .constant;material.isDoubleSided=true
        material.readsFromDepthBuffer=false;material.writesToDepthBuffer=false
        geometry.firstMaterial=material
        let node=SCNNode(geometry:geometry);node.renderingOrder=7
        return node
    }
    /// The played trail: every segment that ended by `time`, then the next one drawn only as far as `time` has reached.
    private func showTrail(time: Double) {
        var low=0,high=segmentEnds.count
        while low<high {let mid=(low+high)/2;if trailPoints[segmentEnds[mid]].time<=time {low=mid+1} else {high=mid}}
        played.isHidden=low==0;playedElement?.primitiveRange=NSRange(location:0,length:low*2)
        head.geometry=nil
        guard low<segmentEnds.count else {return}
        let b=trailPoints[segmentEnds[low]],a=trailPoints[segmentEnds[low]-1]
        guard time>a.time,b.time>a.time else {return}
        let f=Float(min(1,(time-a.time)/(b.time-a.time)))
        func mix(_ p: SCNVector3,_ q: SCNVector3) -> SCNVector3 {SCNVector3(p.x+(q.x-p.x)*f,p.y+(q.y-p.y)*f,p.z+(q.z-p.z)*f)}
        let color=a.color+(b.color-a.color)*f
        head.geometry=Self.trailNode(vertices:[a.left,a.right,mix(a.left,b.left),mix(a.right,b.right)],
                                     colors:[a.color,a.color,color,color],indices:[0,1,2,1,3,2],opacity:1).geometry
    }
    /// Green (on the route) → yellow → orange (off it), the system's dark-mode hues. Blended in sRGB, then handed to
    /// SceneKit in linear values: vertex colours are read as linear, so sRGB numbers would come out washed pale.
    static func trailColor(_ strain: Double) -> SIMD4<Float> {
        let green=SIMD3<Float>(48,209,88)/255,yellow=SIMD3<Float>(255,214,10)/255,orange=SIMD3<Float>(255,120,10)/255
        let t=Float(max(0,min(1,strain)))
        let c=t<0.5 ? green+(yellow-green)*(t/0.5) : yellow+(orange-yellow)*((t-0.5)/0.5)
        func linear(_ v: Float) -> Float {v<=0.04045 ? v/12.92 : pow((v+0.055)/1.055,2.4)}
        return SIMD4(linear(c.x),linear(c.y),linear(c.z),1)
    }
    func show(time: Double) {
        SCNTransaction.begin();SCNTransaction.disableActions=true
        defer {SCNTransaction.commit()}
        if let pose=record.replay?.pose(at:time),let p=pose.position {
            if let gait=walkingTimeline?.pose(at:time) {walkingFigure.show(distance:gait.gaitDistance,blend:gait.blend,strideScale:gait.strideScale)}
            person.isHidden=false;person.position=SCNVector3(p.x,height(p,target:pose.targetIndex),-p.y)
            person.eulerAngles.y=Float(-(pose.heading ?? 0) * .pi/180)
        } else {person.isHidden=true}
        showTrail(time:time)
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
        view.backgroundColor=GuidanceReplayScene.background;view.allowsCameraControl=true;view.antialiasingMode = .multisampling4X
        view.onLayout={ [weak controller] in controller?.frame() }
        return view
    }
    func updateUIView(_ view: SCNView,context: Context) {
        player.scene.update(time:player.time,mode:player.cameraMode,revision:player.cameraRevision)
    }
}

/// A recorded trail position in scene space, with when it was reached and how far off the walk was there.
struct ReplayTrailKnot: Equatable {
    var x: Double,z: Double,y: Double
    var time: Double,strain: Double

    /// Centripetal Catmull-Rom through every knot, `steps` pieces per stretch between two knots. It passes through
    /// the recorded positions, rounds the corners between them, and does not loop where spacing changes sharply
    /// (stop-and-go walking). Height, time and strain follow linearly.
    static func smoothed(_ knots: [ReplayTrailKnot],steps: Int) -> [ReplayTrailKnot] {
        guard knots.count>2,steps>1 else {return knots}
        var out=[ReplayTrailKnot]()
        for i in 0..<knots.count-1 {
            let p0=knots[max(0,i-1)],p1=knots[i],p2=knots[i+1],p3=knots[min(knots.count-1,i+2)]
            func gap(_ a: ReplayTrailKnot,_ b: ReplayTrailKnot) -> Double {max(pow(hypot(b.x-a.x,b.z-a.z),0.5),1e-4)}
            let t1=gap(p0,p1),t2=t1+gap(p1,p2),t3=t2+gap(p2,p3)
            for step in 0..<steps {
                let u=Double(step)/Double(steps),t=t1+(t2-t1)*u
                func curve(_ a: Double,_ b: Double,_ c: Double,_ d: Double) -> Double {
                    let a1=(t1-t)/t1*a+t/t1*b,a2=(t2-t)/(t2-t1)*b+(t-t1)/(t2-t1)*c,a3=(t3-t)/(t3-t2)*c+(t-t2)/(t3-t2)*d
                    let b1=(t2-t)/t2*a1+t/t2*a2,b2=(t3-t)/(t3-t1)*a2+(t-t1)/(t3-t1)*a3
                    return (t2-t)/(t2-t1)*b1+(t-t1)/(t2-t1)*b2
                }
                out.append(.init(x:curve(p0.x,p1.x,p2.x,p3.x),z:curve(p0.z,p1.z,p2.z,p3.z),y:p1.y+(p2.y-p1.y)*u,
                                 time:p1.time+(p2.time-p1.time)*u,strain:p1.strain+(p2.strain-p1.strain)*u))
            }
        }
        out.append(knots[knots.count-1])
        return out
    }
}
