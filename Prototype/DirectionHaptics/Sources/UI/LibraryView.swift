import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var favoritesOnly = false
    @State private var settings = false
    private var displayed: [PatternSet] { store.sets.filter { !favoritesOnly || store.archive.favorites.contains($0.id) } }
    var body: some View {
        List {
            Section {
                Text("진동으로 네 방향을 익혀보세요.").font(.headline)
                Text("길이·횟수·리듬 등 여덟 가지 방식을 비교하고 나에게 맞게 조정할 수 있습니다.").foregroundStyle(.secondary)
                DeviceBanner()
            }
            Section { Toggle("즐겨찾기만 보기", isOn: $favoritesOnly) }
            Section(favoritesOnly ? "즐겨찾는 패턴" : "패턴 세트") {
                ForEach(displayed) { set in
                    NavigationLink { SetDetailView(setID: set.id) } label: {
                        HStack(spacing: 12) {
                            CodeBadge(code: set.code)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(set.name).font(.headline)
                                Text(set.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if store.archive.favorites.contains(set.id) { Image(systemName: "star.fill").foregroundStyle(.secondary).accessibilityLabel("즐겨찾기") }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("preset_\(set.code)")
                }
                if displayed.isEmpty {
                    ContentUnavailableView("즐겨찾기가 없습니다", systemImage: "star", description: Text("패턴 상세에서 별 버튼을 눌러 추가하세요."))
                }
            }
            Section {
                Label("앞·뒤·왼쪽·오른쪽은 몸을 기준으로 합니다.", systemImage: "figure.stand")
                Text("진동이 나는 위치가 아니라 패턴의 차이로 방향을 표현합니다.").foregroundStyle(.secondary)
            }
        }.navigationTitle("패턴 탐색")
            .toolbar { SettingsToolbar(isPresented: $settings) }
            .sheet(isPresented: $settings) { SettingsView() }
    }
}

struct SetDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var haptics: HapticService
    @EnvironmentObject private var preferences: PreferencesStore
    let setID: UUID
    @State private var direction: Direction = .front
    @State private var editor: PatternSet?
    @State private var share: SharedFile?
    @State private var settings = false
    private var set: PatternSet? { store.sets.first { $0.id == setID } }
    var body: some View {
        List {
            if let set {
                Section {
                    Text(set.detail).foregroundStyle(.secondary)
                    DeviceBanner()
                }
                Section {
                    DirectionPad(enabled: haptics.canPlay && !haptics.isPlaying) { selected in
                        direction = selected; haptics.preview(set.pattern(for: selected), gain: preferences.values.gain)
                    }.padding(.vertical, 8)
                    if haptics.isPlaying { Button("재생 중지", role: .destructive) { haptics.stop() } }
                } header: { Text("방향을 눌러 느껴보기") } footer: {
                    Text("전체 세기 \(Int(preferences.values.gain * 100))%. 상단 설정에서 변경할 수 있습니다.")
                }
                Section("\(direction.title) 패턴") {
                    PatternTimeline(pattern: set.pattern(for: direction))
                    Text(set.pattern(for: direction).summary).font(.subheadline).foregroundStyle(.secondary)
                    LabeledContent("전체 길이", value: String(format: "%.2f초", set.pattern(for: direction).duration))
                }
                Section {
                    Button("이 세트 편집", systemImage: "slider.horizontal.3") { haptics.stop(); editor = set }.accessibilityIdentifier("editSet")
                    Button("패턴 JSON 내보내기", systemImage: "square.and.arrow.up") {
                        if let url = store.export(set, name: "pattern-\(set.code)-v\(set.revision)") { share = SharedFile(url: url) }
                    }
                }
            }
        }.navigationTitle(set?.name ?? "패턴").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("즐겨찾기 전환", systemImage: store.archive.favorites.contains(setID) ? "star.fill" : "star") { store.toggleFavorite(setID) }
                }
                SettingsToolbar(isPresented: $settings)
            }
            .sheet(item: $editor) { EditorView(original: $0) }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
            .sheet(isPresented: $settings) { SettingsView() }
            .onDisappear { haptics.stop() }
    }
}

struct UserSetsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editor: PatternSet?
    @State private var deleting: PatternSet?
    @State private var settings = false
    var body: some View {
        List {
            Section {
                Menu {
                    ForEach(Presets.all) { set in Button("\(set.code). \(set.name)") { editor = set } }
                } label: { Label("새 세트 만들기", systemImage: "plus") }.accessibilityIdentifier("newSet")
            } footer: { Text("기본 세트를 복제해 진동의 길이·간격·강도·촉감을 바꿀 수 있습니다.") }
            if store.archive.userSets.isEmpty {
                ContentUnavailableView("나의 패턴이 없습니다", systemImage: "slider.horizontal.3", description: Text("새 세트를 만들어 원하는 진동을 조합해 보세요."))
            } else {
                Section("저장한 패턴") {
                    ForEach(store.sets.filter { !$0.isBuiltIn }) { set in
                        Button { editor = set } label: {
                            HStack(spacing: 12) {
                                CodeBadge(code: set.code)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(set.name).font(.headline).foregroundStyle(.primary)
                                    Text("v\(set.revision) · \(set.updatedAt.formatted(date: .abbreviated, time: .omitted))").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                        }.accessibilityLabel("\(set.name) 편집하기").accessibilityIdentifier("editUserSet")
                            .swipeActions {
                                Button("삭제", role: .destructive) { deleting = set }
                                Button("복제") { editor = set.userCopy() }.tint(.blue)
                            }
                            .contextMenu {
                                Button("복제", systemImage: "doc.on.doc") { editor = set.userCopy() }
                                Button("삭제", systemImage: "trash", role: .destructive) { deleting = set }
                            }
                    }
                }
            }
        }.navigationTitle("나의 패턴")
            .toolbar { SettingsToolbar(isPresented: $settings) }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(item: $editor) { EditorView(original: $0) }
            .alert("이 세트를 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("취소", role: .cancel) { deleting = nil }
                Button("삭제", role: .destructive) { if let deleting { store.deleteSet(deleting) }; deleting = nil }
            } message: { Text("저장한 사용자 패턴을 삭제합니다. 기본 세트는 유지됩니다.") }
    }
}
