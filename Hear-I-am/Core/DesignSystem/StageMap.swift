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
    var checkpoint: FloorPoint?
    var cornerStates: [Bool]? = nil
    var activeCorner: Int? = nil
    var selectedObject: UUID? = nil
    /// When set, blocking objects are drawn grown by this route clearance in red (#38).
    var clearance: Double? = nil
    /// Crosshair floor point while placing route points; red when it cannot be placed.
    var aim: FloorPoint? = nil
    var aimBlocked = false
    var onTap: ((FloorPoint) -> Void)? = nil
    private var bounds: (Double, Double, Double, Double) {
        let x = points.map(\.x), y = points.map(\.y)
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
                context.fill(Path(rect), with: .color(.white))
                context.stroke(Path(rect), with: .color(.gray.opacity(0.4)), lineWidth: 1.5)
                if showsLabels { context.draw(Text("무대").font(.caption.bold()).foregroundColor(.secondary), at: CGPoint(x:rect.midX,y:rect.minY+13))
                context.draw(Text("객석 ↓").font(.system(size:10)).foregroundColor(.secondary), at: CGPoint(x:rect.midX,y:rect.maxY+14)) }
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
                    context.fill(polygon, with:.color(selected ? .orange.opacity(0.3) : (object.isStep ? .blue.opacity(0.2) : .gray.opacity(0.3))))
                    context.stroke(polygon, with:.color(selected ? .orange : (object.isStep ? .blue : .hearInk)), lineWidth:2)
                }
                for i in points.indices {
                    let p=project(points[i])
                    if i>0 {
                        var line=Path(); line.move(to:project(points[i-1])); line.addLine(to:p)
                        let entryExit = i == 1 || (finished && i == points.count-1)
                        context.stroke(line, with:.color(.hearGreen), style: StrokeStyle(lineWidth:2, dash:entryExit ? [5,4] : []))
                    }
                    context.fill(Path(ellipseIn:CGRect(x:p.x-5,y:p.y-5,width:10,height:10)),with:.color(.hearGreen))
                    let label=i == 0 ? "출발" : (finished && i == points.count-1 ? "도착" : "P\(i)")
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
                if let checkpoint {
                    let p=project(checkpoint)
                    context.fill(Path(ellipseIn:CGRect(x:p.x-6,y:p.y-6,width:12,height:12)),with:.color(.red))
                    context.draw(Text("확인점").font(.system(size:10)).foregroundColor(.red),at:CGPoint(x:p.x,y:p.y-15))
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { event in
                guard scale > 0 else {return}
                onTap?(FloorPoint(b.0+(event.location.x-ox)/scale,b.3-(event.location.y-oy)/scale))
            })
        }.background(Color(.systemGray6), in: RoundedRectangle(cornerRadius:16))
    }
}
