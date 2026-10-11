import SwiftUI

struct ConnectionView: View {
    @ObservedObject var link: NearbyLink
    var wearer = false
    @State private var enteredCode = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(link.status, systemImage: link.connected ? "link" : "antenna.radiowaves.left.and.right")
                .foregroundStyle(link.connected ? .mint : .orange)
            if wearer && !link.connected {
                Text(link.code).font(.system(size: 42, weight: .bold, design: .monospaced))
                    .accessibilityLabel("연결 코드 " + link.code.map(String.init).joined(separator: " "))
                Text("운영자 기기에 이 코드를 입력하세요").font(.caption)
            } else if !wearer && !link.connected {
                TextField("착용 폰의 6자리 코드", text: $enteredCode)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .onChange(of: enteredCode) { _, value in enteredCode = String(value.filter(\.isNumber).prefix(6)) }
                ForEach(link.devices) { device in
                    Button("\(device.id)에 연결") { link.invite(device, code: enteredCode) }
                        .disabled(enteredCode.count != 6)
                }
                if link.devices.isEmpty { Text("착용 폰에서 ‘착용자 P’를 열면 여기에 표시됩니다.").font(.caption) }
            }
        }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
