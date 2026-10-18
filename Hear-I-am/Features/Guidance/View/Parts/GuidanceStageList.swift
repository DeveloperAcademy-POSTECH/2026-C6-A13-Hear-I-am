import SwiftUI
import HearIAmCore

/// 1 / 4 · 무대 선택: pinned and recent scanned stages. Stages without a usable route are disabled.
struct GuidanceStageList: View {
    @ObservedObject var library: StageLibrary
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("저장한 공연장에서\n안내를 시작해요").font(.largeTitle.bold())
                if library.loading {ProgressView("저장한 무대를 불러오고 있어요")}
                if library.records.isEmpty && library.plans.isEmpty && !library.loading {
                    Image("StageEmpty").resizable().scaledToFit().frame(height:180).accessibilityHidden(true)
                    Text("저장된 무대가 아직 없어요").font(.title2.bold())
                    Text("홈에서 공연 사전 저장 또는 무대 준비하기를 통해 동선을 먼저 저장해주세요.").foregroundStyle(.secondary)
                }
                if !library.plans.isEmpty { planGroup("공연 사전 저장 동선 (스캔 없이 안내)",items:library.plans) }
                if !library.groups.pinned.isEmpty { stageGroup("고정한 무대",items:library.groups.pinned) }
                if !library.groups.recent.isEmpty { stageGroup("최근 저장한 무대",items:library.groups.recent) }
                if let error=library.error { Text(error).font(.footnote).foregroundStyle(.red);Button("목록 다시 불러오기") {Task {await library.refresh()}} }
                Text("사전 저장 동선은 현장 스캔 없이 현재 출발 위치와 정면 방향을 영점(0,0)으로 삼아 실제 무대 치수로 안내해요.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private func planGroup(_ title: String,items: [PerformancePlan]) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text(title).font(.headline)
            ForEach(items,id:\.id) { plan in
                let selected = model.selectedPlan?.id == plan.id
                let dimensionText = String(format:"무대 %.1f×%.1fm",plan.stageWidth,plan.stageDepth)
                Button {model.selectPlan(plan)} label: {
                    VStack(alignment:.leading,spacing:12) {
                        HStack(alignment:.top,spacing:12) {
                            Image(systemName:selected ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(Color.hearGreen)
                            VStack(alignment:.leading,spacing:6) {
                                Text(plan.name).font(.headline).multilineTextAlignment(.leading)
                                Text("\(dimensionText) · 내부 지점 \(max(0,plan.points.count-2))개 · 기물 \(plan.objects.count)개")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                let segments = plan.scaledSegments()
                                if !segments.isEmpty {
                                    Text(segments.map { String(format:"%.2fm(%+.0f°)",$0.distanceMeters,$0.angleDegrees) }.joined(separator:" → "))
                                        .font(.caption.monospacedDigit()).foregroundStyle(Color.hearGreen)
                                }
                            }
                            Spacer(minLength:0)
                        }
                        if selected {
                            StageMap(width:plan.stageWidth,depth:plan.stageDepth,points:plan.scaledPoints(),objects:(try? plan.scaledObjects()) ?? [])
                                .frame(height:140).accessibilityHidden(true)
                        }
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
                        .overlay(RoundedRectangle(cornerRadius:18).stroke(selected ? Color.hearGreen : .clear,lineWidth:2))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
    private func stageGroup(_ title: String,items: [ScanManifest]) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text(title).font(.headline)
            ForEach(items,id:\.id) { item in
                let usable=item.route.map {$0.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty} ?? false
                Button {model.select(item)} label: {
                    VStack(alignment:.leading,spacing:12) {
                    HStack(alignment:.top,spacing:12) {
                        Image(systemName:model.selected?.id == item.id ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(Color.hearGreen)
                        VStack(alignment:.leading,spacing:8) {
                            Text(item.name).font(.headline).multilineTextAlignment(.leading)
                            Text(usable ? "내부 지점 \(max(0,(item.route?.points.count ?? 2)-2))개 · 기물 \(item.route?.obstacles.count ?? 0)개" : "사용할 동선이 없어요 · 무대 다시 준비 필요")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(item.date.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute())+" 저장").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength:0)
                        if library.pins.ids.contains(item.id) {Image(systemName:"star.fill").accessibilityLabel("고정한 무대")}
                    }
                    if model.selected?.id == item.id, let route=item.route {
                        StageMap(width:route.area.width,depth:route.area.depth,points:route.points,objects:route.obstacles)
                            .frame(height:140).accessibilityHidden(true)
                    }
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
                        .overlay(RoundedRectangle(cornerRadius:18).stroke(model.selected?.id == item.id ? Color.hearGreen : .clear,lineWidth:2))
                }.buttonStyle(.plain).disabled(!usable)
                    .accessibilityAddTraits(model.selected?.id == item.id ? [.isSelected] : [])
            }
        }
    }
}
