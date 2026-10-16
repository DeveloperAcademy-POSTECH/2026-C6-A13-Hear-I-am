import SwiftUI

struct LibrarySelectionBar: View {
    let count: Int
    let busy: Bool
    let cancel: () -> Void
    let delete: () -> Void
    var body: some View {
        HStack(spacing:0) {
            Button("취소",action:cancel).frame(minHeight:44)
                .frame(maxWidth:.infinity,alignment:.leading)
            Group {
                if busy {ProgressView()}
                else {Text("\(count)개 선택").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)}
            }.frame(maxWidth:.infinity,minHeight:44)
            Button(role:.destructive,action:delete) {Label("삭제",systemImage:"trash").frame(minHeight:44)}
                .disabled(count == 0)
                .frame(maxWidth:.infinity,alignment:.trailing)
        }.padding(.horizontal,24).padding(.vertical,6).background(.regularMaterial).disabled(busy)
    }
}
