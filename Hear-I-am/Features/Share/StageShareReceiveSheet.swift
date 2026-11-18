import SwiftUI
import HearIAmCore

/// A received .heariam file: choose what to keep, then the performance and the space each shared space goes into.
/// Nothing is written until 저장하기; what is left unchosen is never unpacked, and the received copy goes when the
/// sheet closes.
struct StageShareReceiveSheet: View {
    enum Step: Hashable { case performance, spaces }
    @ObservedObject var library: StageLibrary
    let incoming: StageShareIncoming
    let onSaved: (StageShareResult, String) -> Void
    @State private var file: StageShareFile?
    @State private var fileBytes: Int64=0
    @State private var loadError: String?
    @State private var path: [Step]=[]
    @State private var choices=StageShareChoices(performance:.new(""),venues:[:],sceneIDs:[],includePlans:false)
    @State private var newName=""
    @State private var existingID: UUID?
    @State private var venuesFor: StageShareChoices.Performance?
    @State private var naming: UUID??
    @State private var customVenue=""
    @State private var conflicts: [StageShareIndex.Scene]=[]
    @State private var sameForRest=false
    @State private var saving=false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path:$path) {
            Group {
                if let file { contents(file) }
                else if let loadError {
                    ContentUnavailableView {
                        Label(L("파일을 열 수 없어요"),systemImage:"exclamationmark.triangle")
                    } description: {Text(loadError)}.padding(.top,60)
                } else { ProgressView(L("파일을 확인하는 중이에요")).frame(maxWidth:.infinity,minHeight:300) }
            }
            .hearTopBar(L("받은 공연"),sheet:true) {closeButton} trailing: {EmptyView()}
            .navigationDestination(for:Step.self) { step in
                if let file {
                    switch step {
                    case .performance: performanceStep(file)
                    case .spaces: spacesStep(file)
                    }
                }
            }
        }
        .hearSheet()
        .interactiveDismissDisabled(saving)
        .overlay { if let scene=conflicts.first { conflictAlert(scene) } }
        .alert(L("새 공간 만들기"),isPresented:Binding(get:{naming != nil},set:{if !$0 {naming=nil}})) {
            TextField(L("공간 이름"),text:$customVenue)
            Button(L("취소"),role:.cancel) {naming=nil}
            Button(L("확인")) {
                let name=customVenue.trimmingCharacters(in:.whitespacesAndNewlines)
                if let key=naming, !name.isEmpty { choices.venues[key] = .new(String(name.prefix(80))) }
                naming=nil
            }
        }
        .alert(L("저장하지 못했어요"),isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) {
            Button(L("확인"),role:.cancel) {error=nil}
        } message: {Text(error ?? "")}
        .task { await load() }
        .onDisappear { StageLibrary.finishReceiving(incoming) }
    }

    private var closeButton: some View {
        Button {dismiss()} label: {HearTopButtonLabel(systemImage:"xmark")}
            .buttonStyle(.plain).disabled(saving).accessibilityLabel(L("닫기"))
    }
    private var backButton: some View {
        Button {path.removeLast()} label: {HearTopButtonLabel(systemImage:"chevron.left")}
            .buttonStyle(.plain).disabled(saving).accessibilityLabel(L("뒤로"))
    }

    private func load() async {
        guard file == nil, loadError == nil else { return }
        let url=incoming.url
        do {
            let opened=try await Task.detached(priority:.userInitiated) {try StageShareFile(url:url)}.value
            fileBytes=(try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            choices=StageShareChoices.suggested(for:opened.index,catalog:library.catalog)
            if case let .new(name)=choices.performance { newName=name }
            venuesFor=choices.performance
            file=opened
        } catch { loadError=error.localizedDescription }
    }

    // MARK: - 받은 내용

    /// The sender's spaces in their order, then the stages they kept without one.
    private func groups(_ index: StageShareIndex) -> [(key: UUID?, name: String, scenes: [StageShareIndex.Scene])] {
        var out=index.venues.map { venue in (key:Optional(venue.id),name:venue.name,scenes:index.scenes.filter {$0.venueID==venue.id}) }
        let unfiled=index.scenes.filter {$0.venueID==nil}
        if !unfiled.isEmpty { out.append((key:nil,name:L("공간 미지정"),scenes:unfiled)) }
        return out.filter {!$0.scenes.isEmpty}
    }
    private var chosenScenes: [StageShareIndex.Scene] { file?.index.scenes.filter {choices.sceneIDs.contains($0.id)} ?? [] }

    private func contents(_ file: StageShareFile) -> some View {
        let index=file.index
        let allChosen=choices.sceneIDs.count==index.scenes.count && (index.planIDs.isEmpty || choices.includePlans)
        return ScrollView {
            VStack(alignment:.leading,spacing:16) {
                StageShareHeaderCard(title:index.kind == .performance ? index.performanceName : index.scenes.first?.name ?? "",
                                     detail:summaryLine(index),systemImage:index.kind == .performance ? "folder" : "cube")
                HStack {
                    Text(L("저장할 것 고르기")).font(HearFont.pretendard(.semibold,size:14)).foregroundStyle(HearV3.secondary)
                    Spacer()
                    Button(allChosen ? L("모두 해제") : L("모두 선택")) {
                        if allChosen { choices.sceneIDs=[]; choices.includePlans=false }
                        else { choices.sceneIDs=Set(index.scenes.map(\.id)); choices.includePlans = !index.planIDs.isEmpty }
                    }.font(HearFont.pretendard(.medium,size:14)).foregroundStyle(HearV3.accent)
                }.padding(.horizontal,4)
                VStack(alignment:.leading,spacing:0) {
                    if !index.planIDs.isEmpty {
                        checkRow(L("기본 동선"),trailing:L("%@개", index.planIDs.count),on:choices.includePlans,bold:true) {choices.includePlans.toggle()}
                        Divider().overlay(.white.opacity(0.08))
                    }
                    ForEach(Array(groups(index).enumerated()),id:\.offset) { offset,group in
                        Text(group.name).font(HearFont.pretendard(.semibold,size:16)).padding(.horizontal,18).padding(.top,14).padding(.bottom,2)
                        ForEach(group.scenes) { scene in
                            checkRow(scene.name,trailing:StageShareSendSheet.size(file.bytes(of:scene.id)),on:choices.sceneIDs.contains(scene.id)) {
                                if choices.sceneIDs.contains(scene.id) { choices.sceneIDs.remove(scene.id) } else { choices.sceneIDs.insert(scene.id) }
                            }
                        }
                        if offset<groups(index).count-1 { Divider().overlay(.white.opacity(0.08)).padding(.top,6) }
                    }
                    Spacer().frame(height:8)
                }.background(HearV3.surface,in:RoundedRectangle(cornerRadius:18,style:.continuous))
                StageShareNote(text:L("고르지 않은 장면은 풀지 않아서 저장 공간을 쓰지 않아요. 저장할 때 장면마다 파일이 온전한지 확인하고, 안내는 같은 공연장에서 확인점을 찾은 뒤 시작할 수 있어요."))
            }.padding(.horizontal,16).padding(.top,12).padding(.bottom,24)
        }
        .safeAreaInset(edge:.bottom,spacing:0) {
            footerButton(L("저장 위치 고르기"),enabled:!choices.sceneIDs.isEmpty) {path=[.performance]}
        }
    }
    private func summaryLine(_ index: StageShareIndex) -> String {
        let size=StageShareSendSheet.size(fileBytes)
        if index.kind == .scene { return [index.performanceName,index.venues.first?.name,size].compactMap {$0}.joined(separator:" · ") }
        return L("공간 %@ · 장면 %@ · 기본 동선 %@", index.venues.count, index.scenes.count, index.planIDs.count)+" · "+size
    }

    private func checkRow(_ title: String, trailing: String, on: Bool, bold: Bool=false, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack(spacing:12) {
                Image(systemName:on ? "checkmark.circle.fill" : "circle").font(.system(size:20))
                    .foregroundStyle(on ? HearV3.accent : HearV3.secondary)
                Text(title).font(HearFont.pretendard(bold ? .semibold : .regular,size:bold ? 16 : 15)).lineLimit(2)
                Spacer()
                Text(trailing).font(.caption).foregroundStyle(HearV3.secondary)
            }.padding(.horizontal,18).padding(.vertical,9).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - 저장할 공연

    private var nameProblem: String? {
        let name=newName.trimmingCharacters(in:.whitespacesAndNewlines)
        if name.isEmpty { return L("공연 이름을 입력해주세요.") }
        if name.count>80 { return L("공연 이름은 80자 이내로 입력해주세요.") }
        if library.catalog.performances.contains(where:{PlaceSearch.normalized($0.name)==PlaceSearch.normalized(name)}) {
            return L("같은 이름의 공연이 있어요. ‘기존 공연에 합치기’에서 고르거나 이름을 바꿔주세요.")
        }
        return nil
    }

    private func performanceStep(_ file: StageShareFile) -> some View {
        let creating=existingID == nil
        let folders=library.performanceFolders.sorted {$0.updatedAt>$1.updatedAt}
        let title=file.index.kind == .performance ? file.index.performanceName : file.index.scenes.first?.name ?? ""
        return ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text(L("받은 ‘%@’을 어디에 저장할까요?", title)).font(HearFont.pretendard(.regular,size:15)).foregroundStyle(HearV3.secondary).padding(.horizontal,4)
                VStack(alignment:.leading,spacing:12) {
                    radioLabel(L("새 공연으로 저장"),on:creating) {existingID=nil}
                    if creating {
                        TextField("",text:$newName,prompt:Text(L("공연 이름")).foregroundStyle(PerformanceSearchField.grey))
                            .font(HearFont.pretendard(.regular,size:16)).autocorrectionDisabled()
                            .padding(.horizontal,16).frame(height:48).background(PerformanceEditorSheet.field,in:Capsule())
                        if let nameProblem { Text(nameProblem).font(.caption).foregroundStyle(.orange) }
                    }
                }.padding(16).background(HearV3.surface,in:RoundedRectangle(cornerRadius:18,style:.continuous))
                if !folders.isEmpty {
                    Text(L("기존 공연에 합치기")).font(HearFont.pretendard(.semibold,size:14)).foregroundStyle(HearV3.secondary).padding(.horizontal,4).padding(.top,8)
                    LazyVStack(spacing:6) {
                        ForEach(folders) { folder in
                            Button {existingID=folder.id} label: {
                                HStack(spacing:12) {
                                    Image(systemName:existingID==folder.id ? "checkmark.circle.fill" : "circle").font(.system(size:20))
                                        .foregroundStyle(existingID==folder.id ? HearV3.accent : HearV3.secondary)
                                    PerformanceFolderRow(name:folder.name,date:folder.updatedAt,count:library.scans(in:folder.id).count)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityAddTraits(existingID==folder.id ? .isSelected : [])
                        }
                    }
                }
            }.padding(.horizontal,16).padding(.top,12).padding(.bottom,24)
        }
        .hearTopBar(L("저장할 공연"),sheet:true) {backButton} trailing: {EmptyView()}
        .safeAreaInset(edge:.bottom,spacing:0) {
            footerButton(L("다음"),enabled:existingID != nil || nameProblem == nil) {
                let target: StageShareChoices.Performance=existingID.map {.existing($0)} ?? .new(newName.trimmingCharacters(in:.whitespacesAndNewlines))
                choices.performance=target
                // Spaces are suggested again only when the performance changed, so going back keeps the choices.
                if venuesFor != target || choices.venues.isEmpty {
                    choices.suggestVenues(for:file.index,catalog:library.catalog); venuesFor=target
                }
                path.append(.spaces)
            }
        }
    }

    private func radioLabel(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack(spacing:12) {
                Image(systemName:on ? "checkmark.circle.fill" : "circle").font(.system(size:20)).foregroundStyle(on ? HearV3.accent : HearV3.secondary)
                Text(title).font(HearFont.pretendard(.semibold,size:16))
                Spacer()
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - 저장할 공간

    private var targetName: String {
        switch choices.performance {
        case .new(let name): name
        case .existing(let id): library.catalog.performances.first {$0.id==id}?.name ?? ""
        }
    }
    private var targetVenues: [PerformanceVenueTag] {
        guard case let .existing(id)=choices.performance else { return [] }
        return (library.catalog.performances.first {$0.id==id}?.venues ?? []).sorted {$0.updatedAt>$1.updatedAt}
    }

    private func spacesStep(_ file: StageShareFile) -> some View {
        let chosen=chosenScenes
        let rows=groups(file.index).compactMap { group -> (key: UUID?, name: String, count: Int)? in
            let count=group.scenes.filter {choices.sceneIDs.contains($0.id)}.count
            return count>0 ? (key:group.key,name:group.name,count:count) : nil
        }
        let creating: Bool={ if case .new=choices.performance { true } else { false } }()
        return ScrollView {
            VStack(alignment:.leading,spacing:12) {
                Text(creating ? L("새 공연 ‘%@’으로 저장해요. 받은 공간마다 넣을 곳을 골라 주세요.", targetName)
                              : L("‘%@’에 합쳐요. 받은 공간마다 넣을 곳을 골라 주세요.", targetName))
                    .font(HearFont.pretendard(.regular,size:15)).foregroundStyle(HearV3.secondary).padding(.horizontal,4)
                ForEach(Array(rows.enumerated()),id:\.offset) { _,row in
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            Text(row.name).font(HearFont.pretendard(.semibold,size:17))
                            Spacer()
                            Text(L("받은 장면 %@개", row.count)).font(.caption).foregroundStyle(HearV3.secondary)
                        }
                        venueMenu(key:row.key,senderName:row.key == nil ? L("받은 장면") : row.name)
                    }.padding(16).background(HearV3.surface,in:RoundedRectangle(cornerRadius:18,style:.continuous))
                }
            }.padding(.horizontal,16).padding(.top,12).padding(.bottom,24)
        }
        .hearTopBar(L("저장할 공간"),sheet:true) {backButton} trailing: {EmptyView()}
        .safeAreaInset(edge:.bottom,spacing:0) {
            footerButton(saving ? nil : L("장면 %@개 저장하기", chosen.count),enabled:!saving && rows.allSatisfy {choices.venues[$0.key] != nil}) {
                Task { await startSaving(file) }
            }
        }
    }

    private func venueLabel(_ choice: StageShareChoices.Venue?) -> String {
        switch choice {
        case .new(let name)?:
            if let same=targetVenues.first(where:{PlaceSearch.normalized($0.name)==PlaceSearch.normalized(name)}) { return L("기존 공간 ‘%@’에 넣기", same.name) }
            return L("새 공간 ‘%@’ 만들기", name)
        case .existing(let id)?: return L("기존 공간 ‘%@’에 넣기", targetVenues.first {$0.id==id}?.name ?? "")
        case nil: return L("공간을 골라주세요")
        }
    }

    private func venueMenu(key: UUID?, senderName: String) -> some View {
        Menu {
            Button(L("새 공간 ‘%@’ 만들기", senderName)) {choices.venues[key] = .new(senderName)}
            if !targetVenues.isEmpty {
                Section(L("기존 공간")) {
                    ForEach(targetVenues) { venue in Button(venue.name) {choices.venues[key] = .existing(venue.id)} }
                }
            }
            Button(L("새 공간 만들기…"),systemImage:"plus") {customVenue=""; naming = .some(key)}
        } label: {
            HStack {
                Text(venueLabel(choices.venues[key])).font(HearFont.pretendard(.medium,size:15)).lineLimit(1)
                Spacer()
                Image(systemName:"chevron.up.chevron.down").font(.system(size:13,weight:.semibold))
            }.foregroundStyle(.white).padding(.horizontal,16).frame(height:46)
                .background(PerformanceEditorSheet.field,in:Capsule())
        }
    }

    // MARK: - 같은 장면 · 저장

    private func startSaving(_ file: StageShareFile) async {
        var present=[StageShareIndex.Scene]()
        for scene in chosenScenes where await library.scans.contains(scene.id) { present.append(scene) }
        choices.replacing=[]
        sameForRest=false
        if present.isEmpty { await save(file) } else { conflicts=present }
    }

    private func resolve(_ replace: Bool) {
        guard let scene=conflicts.first else { return }
        let targets=sameForRest ? conflicts : [scene]
        if replace { choices.replacing.formUnion(targets.map(\.id)) }
        conflicts.removeFirst(targets.count)
        if conflicts.isEmpty, let file { Task { await save(file) } }
    }

    private func save(_ file: StageShareFile) async {
        saving=true
        defer {saving=false}
        do {
            let result=try await library.importShare(file,choices:choices)
            let name=library.catalog.performances.first {$0.id==result.performanceID}?.name ?? targetName
            onSaved(result,name)
            dismiss()
        } catch { self.error=error.localizedDescription }
    }

    private func conflictAlert(_ scene: StageShareIndex.Scene) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture {}
            VStack(alignment:.leading,spacing:0) {
                Text(L("‘%@’이 이미 있어요", scene.name)).font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
                Text(L("같은 장면을 전에 받았거나 이 폰에서 스캔했어요.\n받은 장면으로 바꾸면 지금 동선과 사진이 바뀌어요."))
                    .font(.system(size:15)).foregroundStyle(.white.opacity(0.7)).lineSpacing(2)
                    .fixedSize(horizontal:false,vertical:true).padding(.top,8)
                if conflicts.count>1 {
                    Toggle(isOn:$sameForRest) {
                        Text(L("남은 장면에도 똑같이 하기 (%@개)", conflicts.count-1)).font(.system(size:15)).foregroundStyle(.white)
                    }.tint(HearV3.accent).padding(.top,14)
                }
                HStack(spacing:8) {
                    Button {resolve(false)} label: {
                        Text(L("건너뛰기")).font(.system(size:17,weight:.medium)).foregroundStyle(.white)
                            .frame(maxWidth:.infinity).frame(height:48).background(.white.opacity(0.14),in:Capsule())
                    }.buttonStyle(.plain)
                    Button {resolve(true)} label: {
                        Text(L("바꾸기")).font(.system(size:17,weight:.semibold)).foregroundStyle(.black)
                            .frame(maxWidth:.infinity).frame(height:48).background(.white,in:Capsule())
                    }.buttonStyle(.plain)
                }.padding(.top,20)
            }.padding(.horizontal,22).padding(.top,22).padding(.bottom,14).frame(width:300)
                .background(Color(white:0.13).opacity(0.92),in:RoundedRectangle(cornerRadius:34,style:.continuous))
                .liquidGlass(RoundedRectangle(cornerRadius:34,style:.continuous))
                .accessibilityElement(children:.contain).accessibilityAddTraits(.isModal)
        }
    }

    private func footerButton(_ title: String?, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            if let title { Text(title) } else { ProgressView().tint(HearV3.canvas) }
        }.buttonStyle(V3PrimaryButtonStyle()).disabled(!enabled)
            .padding(.horizontal,16).padding(.top,12).padding(.bottom,12)
    }
}

/// What the app does once a received file is saved: open its performance and say what was saved. Set by the root.
private struct HearShareSavedKey: EnvironmentKey { static let defaultValue: ((StageShareResult) -> Void)? = nil }
extension EnvironmentValues {
    var hearShareSaved: ((StageShareResult) -> Void)? {
        get {self[HearShareSavedKey.self]}
        set {self[HearShareSavedKey.self]=newValue}
    }
}

/// Opens a picked or received .heariam file in the 받은 공연 steps. Set by the root, which shows that sheet.
private struct HearOpenShareKey: EnvironmentKey { static let defaultValue: ((URL) -> Void)? = nil }
extension EnvironmentValues {
    var hearOpenShare: ((URL) -> Void)? {
        get {self[HearOpenShareKey.self]}
        set {self[HearOpenShareKey.self]=newValue}
    }
}

/// The line that slides down after a received file is saved.
struct StageShareToast: View {
    let text: String
    var body: some View {
        HStack(spacing:10) {
            Image(systemName:"checkmark.circle.fill").foregroundStyle(HearV3.accent)
            Text(text).font(HearFont.pretendard(.medium,size:15)).foregroundStyle(.white).fixedSize(horizontal:false,vertical:true)
        }.padding(.horizontal,18).padding(.vertical,12)
            .liquidGlass(Capsule(),tint:.black.opacity(0.35))
            .padding(.horizontal,24).padding(.top,6)
            .accessibilityElement(children:.combine).accessibilityAddTraits(.updatesFrequently)
    }

    static func message(_ result: StageShareResult) -> String {
        var text: String
        if result.installed.isEmpty && result.planCount==0 { text=L("새로 저장한 장면이 없어요") }
        else if result.planCount>0 { text=L("장면 %@개와 기본 동선 %@개를 저장했어요", result.installed.count, result.planCount) }
        else { text=L("장면 %@개를 저장했어요", result.installed.count) }
        if !result.skipped.isEmpty { text+=" · "+L("건너뛴 장면 %@개", result.skipped.count) }
        return text
    }
}
