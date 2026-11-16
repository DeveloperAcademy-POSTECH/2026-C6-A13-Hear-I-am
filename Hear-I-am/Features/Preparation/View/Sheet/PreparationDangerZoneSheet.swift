import SwiftUI
import HearIAmCore

/// 위험 구역 (Figma 452:12705): a light card rising from the bottom over the camera, the stage plan on the left
/// and the edges with their distances on the right. Shown over the scan screen instead of a system sheet,
/// which covers the whole screen in landscape.
struct PreparationDangerZoneSheet: View {
    @ObservedObject var model: PreparationViewModel
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
    let close: () -> Void

    var body: some View {
        VStack(spacing:0) {
            header
            HStack(alignment:.top,spacing:0) {
                plan
                form
            }
        }
        .padding(.leading,leading).padding(.trailing,trailing)
        .background(Color.white)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius:34,topTrailingRadius:34,style:.continuous))
        .environment(\.colorScheme,.light)
        .tint(Color(red:52/255,green:199/255,blue:89/255))
    }

    private var header: some View {
        ZStack {
            Text(L("위험 구역 (Danger zone)")).font(.system(size:17,weight:.semibold)).foregroundStyle(.black)
            HStack {
                Spacer()
                Button(action:close) {
                    Text(L("완료")).font(.system(size:17,weight:.semibold)).foregroundStyle(.black)
                        .padding(.horizontal,16).frame(height:44)
                        .background(.white,in:Capsule())
                        .shadow(color:.black.opacity(0.12),radius:8,y:2)
                }.buttonStyle(.plain).accessibilityIdentifier("danger.done")
            }
        }.padding(.horizontal,20).padding(.top,14).padding(.bottom,8)
    }

    private var plan: some View {
        VStack(spacing:14) {
            DangerZonePlan(width:model.draft.area?.width ?? 12,depth:model.draft.area?.depth ?? 8,zones:model.draft.dangerZones)
                .frame(maxWidth:.infinity).frame(height:200)
            Text(StageDangerZone.summary(model.draft.dangerZones)).font(.system(size:15)).foregroundStyle(.black)
                .multilineTextAlignment(.center)
        }.padding(.horizontal,20).padding(.top,12).frame(maxWidth:330)
    }

    private var form: some View {
        Form {
            Section {
                ForEach(StageDangerZone.Edge.allCases) { edge in row(edge)}
            } header: { Text(L("변 선택 · 거리")) }
            footer: { Text(L("객석에서 무대를 바라보는 기준입니다. 여러 변을 선택할 수 있으며, 선택한 변에서 무대 안쪽으로 표시됩니다. 작은 무대에서는 구역이 겹치거나 무대 전체를 덮을 수 있습니다.")) }
        }.formStyle(.grouped).disabled(model.busy)
    }

    private func row(_ edge: StageDangerZone.Edge) -> some View {
        let selected=model.draft.dangerZones.first { $0.edge == edge }
        return VStack(alignment:.leading,spacing:8) {
            Toggle(edge.label,isOn:Binding(
                get:{ model.draft.dangerZones.contains { $0.edge == edge } },
                set:{ model.setDangerZone(edge,distance:$0 ? .halfMetre : nil) }))
            if selected != nil {
                Picker(L("%@ 거리", edge.label),selection:Binding(
                    get:{ model.draft.dangerZones.first { $0.edge == edge }?.distance ?? .halfMetre },
                    set:{ model.setDangerZone(edge,distance:$0) })) {
                    ForEach(StageDangerZone.Distance.allCases) { distance in
                        Text(distance.label).tag(distance)
                    }
                }.pickerStyle(.segmented)
            }
        }
    }
}

/// The stage as the danger-zone card draws it: a white rectangle with grey edges and dark green corners on a
/// light grey card, 「무대」 inside and the audience below; the zones as orange bands along their edges.
struct DangerZonePlan: View {
    let width: Double
    let depth: Double
    let zones: [StageDangerZone]
    private static let card=Color(red:242/255,green:242/255,blue:247/255)
    private static let edge=Color(red:199/255,green:199/255,blue:204/255)
    private static let corner=Color(red:36/255,green:105/255,blue:82/255)
    private static let label=Color(red:142/255,green:142/255,blue:147/255)

    var body: some View {
        GeometryReader { geometry in
            Canvas { context,size in draw(&context,size:size) }
                .frame(width:geometry.size.width,height:geometry.size.height)
        }
        .background(Self.card,in:RoundedRectangle(cornerRadius:24,style:.continuous))
        .accessibilityElement().accessibilityLabel(L("무대 평면도. %@", StageDangerZone.summary(zones)))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let scale=min((size.width-64)/max(width,0.1),(size.height-74)/max(depth,0.1))
        let rect=CGRect(x:(size.width-width*scale)/2,y:(size.height-depth*scale)/2-8,width:width*scale,height:depth*scale)
        func project(_ p: FloorPoint) -> CGPoint {CGPoint(x:rect.minX+p.x*scale,y:rect.maxY-p.y*scale)}
        context.fill(Path(rect),with:.color(.white))
        for zone in zones {
            var band=Path(); band.addLines(zone.vertices(width:width,depth:depth).map(project)); band.closeSubpath()
            context.fill(band,with:.color(ScanStageMap.orange.opacity(0.3)))
            context.stroke(band,with:.color(ScanStageMap.orange),style:StrokeStyle(lineWidth:1,dash:[4,3]))
        }
        context.stroke(Path(rect),with:.color(Self.edge),lineWidth:1.5)
        let corners=[CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)]
        for point in corners {
            context.fill(Path(ellipseIn:CGRect(x:point.x-6,y:point.y-6,width:12,height:12)),with:.color(Self.corner))
        }
        context.draw(Text(L("무대")).font(.system(size:13)).foregroundColor(Self.label),at:CGPoint(x:rect.midX,y:rect.midY))
        context.draw(Text(L("객석 ↓")).font(.system(size:11)).foregroundColor(Self.label),at:CGPoint(x:rect.midX,y:rect.maxY+16))
    }
}
