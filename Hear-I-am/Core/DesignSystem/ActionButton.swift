import SwiftUI

struct ActionButton: View {
    let title: String
    var primary = true
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold)).frame(minHeight: 44).padding(.horizontal, 18)
                .foregroundStyle(primary ? .white : Color.hearInk)
                .background(primary ? Color.hearInk : .white.opacity(0.92), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.gray.opacity(primary ? 0 : 0.3)))
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}
