import SwiftUI
import HearIAmCore

/// Presented only after a scan is saved, or to reclassify existing scans. Dismissing cannot lose a scan.
struct StageClassificationView: View {
    @ObservedObject var library:StageLibrary
    let scanIDs:[UUID]
    let wasJustSaved:Bool
    let onClassified:(UUID?)->Void
    @State private var performanceID:UUID?
    @State private var venueID:UUID?
    @State private var stageName:String
    @State private var choosingPerformance=false
    @State private var choosingVenue=false
    @State private var completed=false
    @State private var busy=false
    @State private var error:String?
    @Environment(\.dismiss) private var dismiss
    init(library:StageLibrary,scanIDs:[UUID],initialPerformanceID:UUID?=nil,initialVenueID:UUID?=nil,wasJustSaved:Bool=false,onClassified:@escaping (UUID?)->Void) {
        self.library=library;self.scanIDs=scanIDs;self.wasJustSaved=wasJustSaved;self.onClassified=onClassified
        _performanceID=State(initialValue:initialPerformanceID);_venueID=State(initialValue:initialVenueID)
        _stageName=State(initialValue:scanIDs.count == 1 ? library.records.first {$0.id==scanIDs.first}?.name ?? "" : "")
    }
    private var folder:PerformanceFolder? {library.performanceFolders.first {$0.id==performanceID}}
    private var venueName:String {folder?.venues.first {$0.id==venueID}?.name ?? "공연장 미지정"}
    private var scans:[ScanManifest] {library.records.filter {scanIDs.contains($0.id)}}
    var body:some View {
        NavigationStack {
            Group {
                if completed {completion}
                else {classification}
            }.v3Screen().navigationTitle(completed ? "분류 완료" : "무대 분류").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button(wasJustSaved && !completed ? "나중에" : "닫기") {dismiss()}.disabled(busy)}}
                .interactiveDismissDisabled(busy)
                .sheet(isPresented:$choosingPerformance) {
                    PerformanceChoiceSheet(library:library,selection:performanceID) {id in
                        if performanceID != id {venueID=nil};performanceID=id
                    }.suspendsVoiceWake()
                }
                .sheet(isPresented:$choosingVenue) {
                    if let performanceID {VenueChoiceSheet(library:library,performanceID:performanceID,selection:venueID) {venueID=$0}.suspendsVoiceWake()}
                }
        }.v3Screen()
    }
    private var classification:some View {
        Form {
            Section {
                if wasJustSaved {Label("무대 저장 완료",systemImage:"checkmark.circle.fill").foregroundStyle(HearV3.accent)}
                Text(wasJustSaved ? "저장한 무대를\n어느 공연에 담을까요?" : "무대의 분류를 변경해요").font(.title2.bold())
                Text("\(scans.count)개 무대 · 스캔, 동선, 기물, 사진과 기록은 그대로 유지돼요.").font(.subheadline).foregroundStyle(.secondary)
            }.listRowBackground(HearV3.canvas)
            if scans.count == 1,let scan=scans.first {
                Section {
                    HStack(spacing:12) {
                        PerformanceStageThumbnail(record:scan,library:library).frame(width:84,height:84).clipShape(RoundedRectangle(cornerRadius:16)).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:5) {
                            Text(scan.name).font(.headline)
                            Text("\(scan.route?.points.count ?? 0)지점 · 기물 \(scan.route?.obstacles.count ?? 0)개").font(.caption).foregroundStyle(.secondary)
                            Text("확인점 \(scan.secondCheckpoint == nil ? 1 : 2)개 · 사진 \(scan.photos.count)장").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("공연") {
                Button {choosingPerformance=true} label:{choiceRow(folder?.name ?? "공연 선택",symbol:"folder")}.buttonStyle(.plain).accessibilityIdentifier("classification.performance")
                if performanceID == nil {Text("공연을 지정하지 않으면 미분류 무대로 보관해요.").font(.caption).foregroundStyle(.secondary)}
            }
            if performanceID != nil {
                Section("공연장 태그") {
                    Button {choosingVenue=true} label:{choiceRow(venueName,symbol:"building.2")}.buttonStyle(.plain).accessibilityIdentifier("classification.venue")
                    Text("같은 공연장을 다시 스캔해도 별도 무대로 저장해요.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if scans.count == 1 {
                Section("무대 이름 · 필요하면 수정") {
                    TextField("무대 이름",text:$stageName).autocorrectionDisabled()
                    Text("같은 공연장의 다른 저장본과 구분하는 이름이에요.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if scans.count != scanIDs.count || scanIDs.isEmpty {
                Section {Text("저장한 무대 정보를 다시 불러와주세요. 이 창을 닫고 목록을 새로고침한 뒤 분류를 이어갈 수 있어요.").foregroundStyle(.red)}
            }
            if scans.count==1 && stageName.count>80 {Section {Text("무대 이름은 80자 이내로 입력해주세요.").foregroundStyle(.red)}}
            if let error {Section {Text(error).foregroundStyle(.red)}}
            Section {Text(wasJustSaved ? "지금 닫아도 저장한 무대는 사라지지 않아요. 공연 관리의 미분류 무대에서 다시 정리할 수 있어요." : "분류만 변경합니다. 저장한 동선과 사진, 안내 기록은 수정하지 않아요.").font(.footnote).foregroundStyle(.secondary)}
        }.scrollContentBackground(.hidden)
            .safeAreaInset(edge:.bottom) {
                Button(busy ? "분류 중…" : "분류 완료") {apply()}.buttonStyle(V3PrimaryButtonStyle()).accessibilityIdentifier("classification.save")
                    .disabled(busy || scanIDs.isEmpty || scans.count != scanIDs.count || (scans.count==1 && (stageName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || stageName.count>80)))
                    .padding(20).background(HearV3.canvas)
            }
    }
    private var completion:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Image(systemName:"checkmark.circle.fill").font(.system(size:40)).foregroundStyle(HearV3.accent).accessibilityHidden(true)
                Text(folder.map {"\($0.name)에\n무대를 정리했어요."} ?? "미분류 무대로\n보관했어요.").font(.title.bold())
                VStack(alignment:.leading,spacing:8) {
                    Text("저장 위치").font(.caption).foregroundStyle(HearV3.secondary)
                    Text(folder.map {"\($0.name) / \(venueName)"} ?? "공연 관리 / 미분류 무대").font(.headline)
                    Text("\(scanIDs.count)개 무대 · 동선과 사진을 함께 보관했어요.").font(.subheadline).foregroundStyle(HearV3.secondary)
                }.v3Card()
                if let performanceID {
                    NavigationLink("공연장 태그 관리") {PerformanceTagManagementView(library:library,performanceID:performanceID,onStartGuidance:nil)}.buttonStyle(.bordered)
                }
                Button(folder == nil ? "완료" : "저장한 공연 보기") {dismiss();onClassified(performanceID)}.buttonStyle(V3PrimaryButtonStyle()).accessibilityIdentifier("classification.finish")
            }.padding(20)
        }
    }
    private func choiceRow(_ title:String,symbol:String)->some View {
        HStack {Label(title,systemImage:symbol);Spacer();Image(systemName:"chevron.right").font(.caption)}.frame(minHeight:48).contentShape(Rectangle())
    }
    private func apply() {
        busy=true;error=nil
        Task {
            do {
                if scans.count==1,let scan=scans.first,scan.name != stageName.trimmingCharacters(in:.whitespacesAndNewlines) {try await library.renameStage(scan.id,to:stageName)}
                try await library.assignScans(scanIDs,to:performanceID,venueID:venueID)
                completed=true
            } catch {self.error=error.localizedDescription}
            busy=false
        }
    }
}

struct PerformanceChoiceSheet:View {
    @ObservedObject var library:StageLibrary
    let selection:UUID?
    let onSelect:(UUID?)->Void
    @State private var query=""
    @State private var creating=false
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            List {
                Section {
                    ForEach(library.performanceFolders.filter {query.isEmpty || $0.name.localizedStandardContains(query)}) {folder in
                        Button {onSelect(folder.id);dismiss()} label:{HStack {Label(folder.name,systemImage:"folder");Spacer();if selection==folder.id {Image(systemName:"checkmark")}}.frame(minHeight:48)}.buttonStyle(.plain)
                    }
                }
                Section {Button("새 공연 만들기",systemImage:"plus") {creating=true};Button("공연을 지정하지 않기",systemImage:"tray") {onSelect(nil);dismiss()}}
            }.scrollContentBackground(.hidden).v3Screen().navigationTitle("공연 선택").navigationBarTitleDisplayMode(.inline)
                .searchable(text:$query,prompt:"공연 이름 검색")
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("닫기",systemImage:"xmark") {dismiss()}.labelStyle(.iconOnly)}}
                .sheet(isPresented:$creating) {PerformanceEditorSheet(library:library) {id in onSelect(id);dismiss()}}
        }.v3Screen()
    }
}

struct VenueChoiceSheet:View {
    @ObservedObject var library:StageLibrary
    let performanceID:UUID
    let selection:UUID?
    let onSelect:(UUID?)->Void
    @State private var query=""
    @State private var creating=false
    @Environment(\.dismiss) private var dismiss
    private var folder:PerformanceFolder? {library.performanceFolders.first {$0.id==performanceID}}
    var body:some View {
        NavigationStack {
            List {
                Section(folder?.name ?? "공연장") {
                    ForEach((folder?.venues ?? []).filter {query.isEmpty || $0.name.localizedStandardContains(query)}) {venue in
                        Button {onSelect(venue.id);dismiss()} label:{HStack {Label(venue.name,systemImage:"building.2");Spacer();if selection==venue.id {Image(systemName:"checkmark")}}.frame(minHeight:48)}.buttonStyle(.plain)
                    }
                }
                Section {Button("새 공연장 태그",systemImage:"plus") {creating=true};Button("공연장 미지정",systemImage:"tray") {onSelect(nil);dismiss()}}
            }.scrollContentBackground(.hidden).v3Screen().navigationTitle("공연장 선택").navigationBarTitleDisplayMode(.inline)
                .searchable(text:$query,prompt:"공연장 이름 검색")
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("닫기",systemImage:"xmark") {dismiss()}.labelStyle(.iconOnly)}}
                .sheet(isPresented:$creating) {VenueEditorSheet(library:library,performanceID:performanceID) {id in onSelect(id);dismiss()}}
        }.v3Screen()
    }
}

struct VenueEditorSheet:View {
    @ObservedObject var library:StageLibrary
    let performanceID:UUID
    let venue:PerformanceVenueTag?
    let onSaved:(UUID)->Void
    @State private var name:String
    @State private var busy=false
    @State private var error:String?
    @Environment(\.dismiss) private var dismiss
    init(library:StageLibrary,performanceID:UUID,venue:PerformanceVenueTag?=nil,onSaved:@escaping (UUID)->Void) {
        self.library=library;self.performanceID=performanceID;self.venue=venue;self.onSaved=onSaved;_name=State(initialValue:venue?.name ?? "")
    }
    var body:some View {
        NavigationStack {
            Form {
                Section {Text(venue == nil ? "공연장 이름을 등록해주세요." : "공연장 이름을 바꿔요.").font(.title2.bold())}
                Section("공연장 이름") {TextField("예: 효자아트홀",text:$name).autocorrectionDisabled()}
                Section {Text("같은 공연장은 같은 태그로 정리해요. 이름을 변경하면 연결된 무대의 공연장 이름도 함께 바뀌며, 동선과 사진은 유지돼요.").font(.subheadline).foregroundStyle(.secondary)}
                if let error {Section {Text(error).foregroundStyle(.red)}}
            }.scrollContentBackground(.hidden).v3Screen().navigationTitle(venue == nil ? "새 공연장 태그" : "공연장 이름 수정").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("닫기",systemImage:"xmark") {dismiss()}.labelStyle(.iconOnly).disabled(busy)}}
                .safeAreaInset(edge:.bottom) {Button(busy ? "저장 중…" : "저장") {save()}.buttonStyle(V3PrimaryButtonStyle()).disabled(busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).padding(20).background(HearV3.canvas)}
                .interactiveDismissDisabled(busy)
        }.v3Screen()
    }
    private func save() {
        busy=true;error=nil
        Task {
            do {
                let id:UUID
                if let venue {try await library.renameVenue(venue.id,in:performanceID,to:name);id=venue.id}
                else {id=try await library.createVenue(name:name,in:performanceID).id}
                dismiss();onSaved(id)
            } catch {self.error=error.localizedDescription}
            busy=false
        }
    }
}
