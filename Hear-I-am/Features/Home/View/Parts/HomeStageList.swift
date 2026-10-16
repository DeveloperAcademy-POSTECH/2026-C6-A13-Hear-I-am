import SwiftUI
import HearIAmCore

/// Saved stages that can be renamed, pinned, or long-pressed for deletion.
struct HomeStageList: View {
    @ObservedObject var library: StageLibrary
    @ObservedObject var model: HomeViewModel
    let records: [ScanManifest]
    var body: some View {
        ForEach(records,id:\.id) {record in
            StageRow(record:record,library:library,onRename:{model.startRename(record)})
                .librarySelection(selecting:model.selection.selecting,selected:model.selection.contains(record.id),onSelect:{
                    model.selection.begin(with:record.id)
                },onToggle:{model.selection.toggle(record.id)})
                .disabled(model.selection.deleting || model.renaming)
        }
    }
}
