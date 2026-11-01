import SwiftUI

struct GuidanceButton: View {
    let title: String
    var secondary=false
    var enabled=true
    let action: ()->Void
    var body: some View {
        Button(action:action) {
            Text(title).font(.headline).frame(maxWidth:.infinity,minHeight:56)
                .foregroundStyle(secondary ? Color.primary : Color(.systemBackground))
                .background(secondary ? Color(.secondarySystemBackground) : Color.primary,in:Capsule())
                .opacity(enabled ? 1 : 0.35)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}
