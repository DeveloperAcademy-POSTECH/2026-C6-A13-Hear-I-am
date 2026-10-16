import SwiftUI

extension View {
    func librarySelection(selecting: Bool, selected: Bool, onSelect: @escaping () -> Void, onToggle: @escaping () -> Void) -> some View {
        self.allowsHitTesting(!selecting)
            .overlay {
                if selecting {
                    Button(action:onToggle) {Color.clear.contentShape(Rectangle())}
                        .buttonStyle(.plain).accessibilityLabel(selected ? "선택 해제" : "선택")
                }
            }
            .overlay(alignment:.topLeading) {
                if selecting {
                    Image(systemName:selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(selected ? Color.hearGreen : .secondary)
                        .background(.white,in:Circle()).padding(8).allowsHitTesting(false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius:20).stroke(selected ? Color.hearGreen : .clear,lineWidth:2).allowsHitTesting(false))
            .contentShape(RoundedRectangle(cornerRadius:20))
            .highPriorityGesture(LongPressGesture(minimumDuration:0.45).onEnded {_ in onSelect()})
            .accessibilityAction(named:"삭제할 항목으로 선택",onSelect)
    }
}
