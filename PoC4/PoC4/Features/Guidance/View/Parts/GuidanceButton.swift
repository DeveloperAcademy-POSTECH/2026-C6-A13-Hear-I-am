import SwiftUI

struct GuidanceButton: View {
    let title: String
    var secondary=false
    var enabled=true
    let action: ()->Void
    var body: some View {
        Button(action:action) {
            Text(title).font(.headline).frame(maxWidth:.infinity,minHeight:56)
                .foregroundStyle(secondary ? Color.hearInk : .white)
                .background(secondary ? Color(.systemGray6) : .hearInk,in:RoundedRectangle(cornerRadius:16))
                .opacity(enabled ? 1 : 0.35)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}
