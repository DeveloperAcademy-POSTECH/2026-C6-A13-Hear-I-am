import SwiftUI
import HearIAmCore

/// Audience-facing floor plan. World +Y (backstage) is up on screen.
struct StageMap: View {
    var showsLabels = true
    var width = 12.0
    var depth = 8.0
    var points: [FloorPoint] = []
    var finished = true
    var objects: [StageObstacle] = []
    var dangerZones: [StageDangerZone] = []
    var checkpoint: FloorPoint?
    var secondCheckpoint: FloorPoint? = nil
    var cornerStates: [Bool]? = nil
    var activeCorner: Int? = nil
    var selectedObject: UUID? = nil
    /// When set, blocking objects are drawn grown by this route clearance in red (#38).
    var clearance: Double? = nil
    /// Crosshair floor point while placing route points; red when it cannot be placed.
    var aim: FloorPoint? = nil
    var aimBlocked = false
    var reference: StagePlanReference? = nil
    var onTap: ((FloorPoint) -> Void)? = nil
    var v3Style = false
    var objectFacings: [UUID: StageFacing] = [:]
    var onDrag: ((FloorPoint, FloorPoint) -> Void)? = nil
    private var bounds: (Double, Double, Double, Double) {
        let allPoints=points+(reference?.points ?? [])
        let x = allPoints.map(\.x), y = allPoints.map(\.y)
        if v3Style {return (min(-width*0.08,(x.min() ?? 0)-0.3),max(width*1.08,(x.max() ?? width)+0.3),min(-depth*0.12,(y.min() ?? 0)-0.3),max(depth*1.16,(y.max() ?? depth)+0.3))}
        return (min(-width*0.25, (x.min() ?? 0)-0.6), max(width*1.25, (x.max() ?? width)+0.6),
                min(-depth*0.16, (y.min() ?? 0)-0.6), max(depth*1.16, (y.max() ?? depth)+0.6))
    }
    var body: some View {
        GeometryReader { geometry in
            let b = bounds
            let inset = 12.0
            let scale = min((geometry.size.width-inset*2)/(b.1-b.0), (geometry.size.height-inset*2)/(b.3-b.2))
            let ox = (geometry.size.width-(b.1-b.0)*scale)/2
            let oy = (geometry.size.height-(b.3-b.2)*scale)/2
            let project: (FloorPoint) -> CGPoint = { p in CGPoint(x: ox+(p.x-b.0)*scale, y: oy+(b.3-p.y)*scale) }
            Canvas { context, _ in
                let topLeft=project(FloorPoint(0,depth)), bottomRight=project(FloorPoint(width,0))
                let rect=CGRect(x:topLeft.x,y:topLeft.y,width:bottomRight.x-topLeft.x,height:bottomRight.y-topLeft.y)
                context.fill(Path(roundedRect:rect,cornerRadius:v3Style ? 16 : 0), with: .color(v3Style ? HearV3.raised : .white))
                if v3Style {
                    var grid=Path()
                    for x in 1..<Int(width) {grid.move(to:project(.init(Double(x),0)));grid.addLine(to:project(.init(Double(x),depth)))}
                    for y in 1..<Int(depth) {grid.move(to:project(.init(0,Double(y))));grid.addLine(to:project(.init(width,Double(y))))}
                    context.stroke(grid,with:.color(HearV3.selected.opacity(0.35)),lineWidth:0.5)
                    var audience=Path();audience.move(to:.init(x:rect.minX,y:rect.maxY+7));audience.addLine(to:.init(x:rect.maxX,y:rect.maxY+7))
                    context.stroke(audience,with:.color(HearV3.secondary),lineWidth:1.5)
                }
                if !v3Style {context.stroke(Path(rect), with: .color(.gray.opacity(0.4)), lineWidth: 1.5)}
                if showsLabels { context.draw(Text(v3Style ? "무대 뒤쪽" : "무대").font(.caption.bold()).foregroundColor(.secondary), at: CGPoint(x:rect.midX,y:rect.minY+13))
                context.draw(Text(v3Style ? "관객석 · 앞쪽" : "객석 ↓").font(.system(size:10)).foregroundColor(.secondary), at: CGPoint(x:rect.midX,y:rect.maxY+14)) }
                if let reference {
                    var ghost=context; ghost.opacity=0.30
                    for object in reference.objects {
                        var outline=Path(); outline.addLines(object.vertices.map(project)); outline.closeSubpath()
                        ghost.stroke(outline,with:.color(.blue),style:StrokeStyle(lineWidth:1.5,dash:[4,3]))
                    }
                    for (i,point) in reference.points.enumerated() {
                        let p=project(point)
                        ghost.stroke(Path(ellipseIn:CGRect(x:p.x-5,y:p.y-5,width:10,height:10)),with:.color(.blue),lineWidth:1.5)
                        if i>0 {
                            var line=Path(); line.move(to:project(reference.points[i-1])); line.addLine(to:p)
                            ghost.stroke(line,with:.color(.blue),style:StrokeStyle(lineWidth:1.5,dash:[4,3]))
                        }
                    }
                }
                for zone in dangerZones {
                    var polygon=Path()
                    polygon.addLines(zone.vertices(width:width,depth:depth).map(project)); polygon.closeSubpath()
                    context.fill(polygon,with:.color(.orange.opacity(0.28)))
                    context.stroke(polygon,with:.color(.orange),style:StrokeStyle(lineWidth:1,dash:[4,3]))
                }
                for object in objects {
                    var polygon=Path(); polygon.addLines(object.vertices.map(project)); polygon.closeSubpath()
                    if let clearance, object.blocksPath {
                        // A round-joined stroke as wide as twice the clearance is the outline grown by it.
                        var band=context; band.opacity=0.28
                        band.drawLayer { layer in
                            layer.fill(polygon, with:.color(.red))
                            layer.stroke(polygon, with:.color(.red), style:StrokeStyle(lineWidth:2*clearance*scale,lineJoin:.round))
                        }
                    }
                    let selected=object.id == selectedObject
                    if v3Style {
                        context.fill(polygon,with:.color(object.isStep ? HearV3.secondary : HearV3.selected))
                        if selected {for vertex in object.vertices {let p=project(vertex);context.fill(Path(ellipseIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(HearV3.text))}}
                    } else {
                    context.fill(polygon, with:.color(selected ? .orange.opacity(0.3) : (object.isStep ? .blue.opacity(0.2) : .gray.opacity(0.3))))
                    context.stroke(polygon, with:.color(selected ? .orange : (object.isStep ? .blue : .hearInk)), lineWidth:2)
                    }
                    if object.isStep && !v3Style {
                        for i in object.vertices.indices {
                            var edge=Path(); edge.move(to:project(object.vertices[i])); edge.addLine(to:project(object.vertices[(i+1)%object.vertices.count]))
                            let isFacing = object.facingEdge == i
                            context.stroke(edge,with:.color(isFacing ? .green : .blue),lineWidth:isFacing ? 3.5 : 2.5)
                        }
                    }
                }
                for object in objects where objectFacings[object.id] != nil {
                    let heading=objectFacings[object.id]!.headingDegrees * .pi / 180
                    let center=FloorPoint(object.vertices.map(\.x).reduce(0,+)/Double(object.vertices.count),object.vertices.map(\.y).reduce(0,+)/Double(object.vertices.count))
                    let start=project(center),end=project(.init(center.x+sin(heading)*1.15,center.y-cos(heading)*1.15))
                    var arrow=Path();arrow.move(to:start);arrow.addLine(to:end)
                    let angle=atan2(end.y-start.y,end.x-start.x)
                    arrow.move(to:CGPoint(x:end.x-cos(angle-0.6)*7,y:end.y-sin(angle-0.6)*7));arrow.addLine(to:end)
                    arrow.addLine(to:CGPoint(x:end.x-cos(angle+0.6)*7,y:end.y-sin(angle+0.6)*7))
                    context.stroke(arrow,with:.color(v3Style ? HearV3.text : .hearInk),lineWidth:2)
                }
                let labels=StageRoute.pointLabels(points:points,obstacles:objects,finished:finished)
                for i in points.indices {
                    let p=project(points[i])
                    if i>0 {
                        var line=Path(); line.move(to:project(points[i-1])); line.addLine(to:p)
                        let entryExit = i == 1 || (finished && i == points.count-1)
                        context.stroke(line, with:.color(.hearGreen), style: StrokeStyle(lineWidth:2, dash:entryExit ? [5,4] : []))
                    }
                    context.fill(Path(ellipseIn:CGRect(x:p.x-5,y:p.y-5,width:10,height:10)),with:.color(v3Style && finished && i==points.count-1 ? .yellow : .hearGreen))
                    let label=labels.indices.contains(i) ? labels[i] : "P\(i)"
                    if showsLabels { context.draw(Text(label).font(.system(size:11,weight:.bold)).foregroundColor(.hearGreen),at:CGPoint(x:p.x,y:p.y-13)) }
                }
                if let states=cornerStates {
                    let corners=[FloorPoint(0,0),FloorPoint(width,0),FloorPoint(width,depth),FloorPoint(0,depth)]
                    for i in corners.indices {
                        let p=project(corners[i]); let done=states.indices.contains(i) && states[i]
                        context.fill(Path(ellipseIn:CGRect(x:p.x-5,y:p.y-5,width:10,height:10)),with:.color(done ? .hearGreen : .red))
                        if activeCorner == i {context.stroke(Path(ellipseIn:CGRect(x:p.x-10,y:p.y-10,width:20,height:20)),with:.color(.red),lineWidth:2)}
                    }
                }
                if let aim {
                    let p=project(aim)
                    context.stroke(Path(ellipseIn:CGRect(x:p.x-6,y:p.y-6,width:12,height:12)),with:.color(aimBlocked ? .red : .hearGreen),lineWidth:2)
                }
                for (index,point) in [checkpoint,secondCheckpoint].enumerated() {
                    if let point {
                        let p=project(point)
                        context.fill(Path(ellipseIn:CGRect(x:p.x-6,y:p.y-6,width:12,height:12)),with:.color(.red))
                        context.draw(Text("확인점 \(index+1)").font(.system(size:10)).foregroundColor(.red),at:CGPoint(x:p.x,y:p.y-15))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { event in
                guard scale > 0 else {return}
                onTap?(FloorPoint(b.0+(event.location.x-ox)/scale,b.3-(event.location.y-oy)/scale))
            })
            .simultaneousGesture(DragGesture(minimumDistance:5).onEnded {event in
                guard scale>0 else {return}
                let start=FloorPoint(b.0+(event.startLocation.x-ox)/scale,b.3-(event.startLocation.y-oy)/scale)
                let end=FloorPoint(b.0+(event.location.x-ox)/scale,b.3-(event.location.y-oy)/scale)
                onDrag?(start,end)
            })
            .allowsHitTesting(onTap != nil || onDrag != nil)
        }.background(v3Style ? HearV3.canvas : Color(.systemGray6), in: RoundedRectangle(cornerRadius:16))
    }
}
