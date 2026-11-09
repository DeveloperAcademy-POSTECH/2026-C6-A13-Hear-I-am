import SwiftUI
import HearIAmCore

/// Floor plan of the current draft, re-projected onto the latest stage rectangle, in the scan screen's style.
struct PreparationMiniMap: View {
    @ObservedObject var model: PreparationViewModel
    var style: ScanStageMap.Style = .editing
    var selectedObject: UUID?
    var selectedPoint: Int?
    var body: some View {
        let draft=model.draft, area=draft.area, boundary=model.step == .boundary
        let placing=model.step == .route && !draft.routeFinished
        ScanStageMap(style:style,width:area?.width ?? 12,depth:area?.depth ?? 8,
                     points:area.map {a in draft.route.map(a.floor)} ?? [],finished:draft.routeFinished,
                     objects:area.map {a in draft.objects.compactMap {try? $0.projected(in:a)}} ?? [],
                     dangerZones:area == nil ? [] : draft.dangerZones,
                     checkpoint:area.flatMap {a in draft.checkpoint.map(a.floor)},
                     secondCheckpoint:area.flatMap {a in draft.secondCheckpoint.map(a.floor)},
                     cornerStates:boundary || style == .review ? draft.corners.map {$0 != nil} : nil,
                     activeCorner:boundary ? model.nextCorner : nil,
                     selectedObject:selectedObject,selectedPoint:selectedPoint,
                     aim:placing ? area.flatMap {a in model.session.aimPoint.map(a.floor)} : nil,aimBlocked:model.aimBlocked,
                     reference:model.visiblePlanReference,tight:style != .review)
    }
}

/// The scan screen's floor plan, drawn as the design draws it (Figma 452:12768 · 11604 · 11714 · 12184 · 12063 and
/// the intro cards): a translucent white rectangle with the audience below, 8pt corner dots, objects as square
/// outlines, the route in green and the two checkpoints as green dots. Audience-facing; world +Y is up.
struct ScanStageMap: View {
    enum Style {
        /// Green route and checkpoints; objects grey unless selected.
        case editing
        /// Route greyed so the two checkpoints stand out (452:11714).
        case checkpoint
        /// Everything shown at once before saving (452:12063): orange corners, yellow checkpoints.
        case review
    }
    var style: Style = .editing
    var showsLabel=true
    var width=12.0
    var depth=8.0
    var points: [FloorPoint] = []
    var finished=true
    var objects: [StageObstacle] = []
    var dangerZones: [StageDangerZone] = []
    var checkpoint: FloorPoint?
    var secondCheckpoint: FloorPoint?
    /// Per corner, whether it has been captured; nil hides the corner dots.
    var cornerStates: [Bool]?
    var activeCorner: Int?
    var selectedObject: UUID?
    var selectedPoint: Int?
    var aim: FloorPoint?
    var aimBlocked=false
    var reference: StagePlanReference?
    /// The intro cards after the boundary step show the corners already fixed, in grey (452:12291 · 11746).
    var dimCorners=false
    /// Narrower margins, for the side panel where the stage should fill the space (Figma 971:15599).
    var tight=false
    /// The intro cards' looping drawings (#163). How much of the selected object's outline is drawn (0–1), then
    /// of its facing edge in red; how far along the route the drawing is, in points (nil: all of it); and the
    /// opacity of what is being drawn, which fades before the loop starts over.
    var objectReveal=1.0
    var facingReveal=1.0
    var routeReveal: Double?
    var revealOpacity=1.0

    static let green=Color(red:48/255,green:209/255,blue:88/255)
    static let mint=Color(red:0,green:200/255,blue:179/255)
    static let red=Color(red:1,green:56/255,blue:60/255)
    static let blue=Color(red:10/255,green:132/255,blue:1)
    static let yellow=Color(red:1,green:214/255,blue:10/255)
    static let orange=Color(red:1,green:149/255,blue:0)
    static let grey=Color(red:142/255,green:142/255,blue:147/255)
    static let objectOutline=Color(red:74/255,green:74/255,blue:74/255)

    var body: some View {
        GeometryReader { geometry in
            let all=points+(reference?.points ?? [])
            let xs=all.map(\.x), ys=all.map(\.y)
            let m=tight ? 0.06 : 0.1, n=tight ? 0.06 : 0.12
            let b=(min(-width*m,(xs.min() ?? 0)-0.4),max(width*(1+m),(xs.max() ?? width)+0.4),min(-depth*n,(ys.min() ?? 0)-0.4),max(depth*(1+n),(ys.max() ?? depth)+0.4))
            let labelRoom: CGFloat = showsLabel ? 22 : 0
            let inset: CGFloat = tight ? 4 : 8
            let scale=min((geometry.size.width-inset*2)/(b.1-b.0),(geometry.size.height-inset*2-labelRoom)/(b.3-b.2))
            let ox=(geometry.size.width-(b.1-b.0)*scale)/2
            let oy=(geometry.size.height-labelRoom-(b.3-b.2)*scale)/2
            let project: (FloorPoint) -> CGPoint = {p in CGPoint(x:ox+(p.x-b.0)*scale,y:oy+(b.3-p.y)*scale)}
            Canvas { context,_ in
                let topLeft=project(FloorPoint(0,depth)), bottomRight=project(FloorPoint(width,0))
                let rect=CGRect(x:topLeft.x,y:topLeft.y,width:bottomRight.x-topLeft.x,height:bottomRight.y-topLeft.y)
                context.fill(Path(rect),with:.color(.white.opacity(0.2)))
                context.stroke(Path(rect),with:.color(.white),lineWidth:1)
                if showsLabel {
                    context.draw(Text("객석").font(.system(size:16,weight:.medium)).foregroundColor(.white),at:CGPoint(x:rect.midX,y:rect.maxY+14))
                }
                if let reference {
                    var ghost=context; ghost.opacity=0.3
                    for object in reference.objects {
                        var outline=Path(); outline.addLines(object.vertices.map(project)); outline.closeSubpath()
                        ghost.stroke(outline,with:.color(Self.blue),style:StrokeStyle(lineWidth:1.5,dash:[4,3]))
                    }
                    var line=Path(); line.addLines(reference.points.map(project))
                    ghost.stroke(line,with:.color(Self.blue),style:StrokeStyle(lineWidth:1.5,dash:[4,3]))
                }
                for zone in dangerZones {
                    var polygon=Path(); polygon.addLines(zone.vertices(width:width,depth:depth).map(project)); polygon.closeSubpath()
                    context.fill(polygon,with:.color(Self.orange.opacity(0.28)))
                    context.stroke(polygon,with:.color(Self.orange),style:StrokeStyle(lineWidth:1,dash:[4,3]))
                }
                for object in objects {
                    let selected=object.id == selectedObject
                    var polygon=Path(); polygon.addLines(object.vertices.map(project)); polygon.closeSubpath()
                    if selected || style == .review {
                        // Mint outline with the facing edge in red (452:11604); the review colours every object.
                        var layer=context
                        if selected {layer.opacity=revealOpacity}
                        layer.stroke(selected ? polygon.trimmedPath(from:0,to:objectReveal) : polygon,with:.color(Self.mint),lineWidth:3)
                        if let facing=object.facingEdge, object.vertices.indices.contains(facing), !selected || facingReveal > 0 {
                            var edge=Path(); edge.move(to:project(object.vertices[facing])); edge.addLine(to:project(object.vertices[(facing+1)%object.vertices.count]))
                            // Square ends cover the corners, so the whole side is red, not cut short at both ends (11/09).
                            layer.stroke(selected ? edge.trimmedPath(from:0,to:facingReveal) : edge,with:.color(Self.red),
                                         style:StrokeStyle(lineWidth:3,lineCap:.square))
                        }
                    } else {
                        context.stroke(polygon,with:.color(dimCorners ? Self.grey.opacity(0.9) : Self.objectOutline.opacity(0.5)),lineWidth:3)
                    }
                }
                let routeColor: Color = style == .checkpoint ? Self.grey : (style == .review ? .white : Self.green)
                let dotColor: Color = style == .checkpoint ? Self.grey : Self.green
                // Drawn one point at a time on the route card: the line runs to the next point, then its dot appears.
                let shown=routeReveal ?? Double(points.count+1)
                var route=context
                if routeReveal != nil {route.opacity=revealOpacity}
                for i in points.indices {
                    let p=project(points[i])
                    if i > 0 {
                        let drawn=min(1,max(0,(shown-Double(i))/0.6))
                        if drawn > 0 {
                            var line=Path(); line.move(to:project(points[i-1])); line.addLine(to:p)
                            route.stroke(line.trimmedPath(from:0,to:drawn),with:.color(routeColor),lineWidth:2)
                        }
                    }
                    guard shown >= (i == 0 ? 0.3 : Double(i)+0.6) else {continue}
                    let color: Color = style == .checkpoint ? Self.grey : (i == 0 ? Self.blue : (finished && i == points.count-1 ? Self.yellow : dotColor))
                    route.fill(Path(ellipseIn:CGRect(x:p.x-4,y:p.y-4,width:8,height:8)),with:.color(color))
                    if selectedPoint == i {
                        context.fill(Path(ellipseIn:CGRect(x:p.x-4,y:p.y-4,width:8,height:8)),with:.color(.white))
                        context.stroke(Path(ellipseIn:CGRect(x:p.x-7,y:p.y-7,width:14,height:14)),with:.color(.white),lineWidth:1.5)
                    }
                }
                if let states=cornerStates {
                    let corners=[FloorPoint(0,0),FloorPoint(width,0),FloorPoint(width,depth),FloorPoint(0,depth)]
                    for i in corners.indices {
                        let p=project(corners[i]); let done=states.indices.contains(i) && states[i]
                        let color: Color = dimCorners ? Self.grey : (style == .review ? Self.orange : (done ? Self.green : .white))
                        context.fill(Path(ellipseIn:CGRect(x:p.x-4.3,y:p.y-4.3,width:8.7,height:8.7)),with:.color(color))
                        if activeCorner == i {
                            context.stroke(Path(ellipseIn:CGRect(x:p.x-8,y:p.y-8,width:16,height:16)),with:.color(Self.green),lineWidth:2)
                        }
                    }
                }
                if let aim {
                    let p=project(aim)
                    context.stroke(Path(ellipseIn:CGRect(x:p.x-6,y:p.y-6,width:12,height:12)),with:.color(aimBlocked ? Self.red : Self.green),lineWidth:2)
                }
                var checkpoints=context
                checkpoints.opacity=revealOpacity
                for point in [checkpoint,secondCheckpoint].compactMap({$0}) {
                    let p=project(point)
                    checkpoints.fill(Path(ellipseIn:CGRect(x:p.x-5,y:p.y-5,width:10,height:10)),with:.color(style == .review ? Self.yellow : Self.green))
                }
            }
        }
    }
}
