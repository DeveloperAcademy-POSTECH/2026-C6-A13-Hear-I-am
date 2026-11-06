import SwiftUI
import AVFoundation

/// Only use a product image when the route name identifies it. A renamed Bluetooth device can
/// conceal its model, so an unrecognized name keeps a generic icon instead of guessing AirPods.
enum OutputDeviceKind: Equatable {
    case iPhone, airPods, airPodsMax, headphones, externalAudio

    init(portType: AVAudioSession.Port, name: String) {
        switch portType {
        case .builtInSpeaker, .builtInReceiver:
            self = .iPhone
        case .headphones:
            self = .headphones
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            let normalized=name.lowercased().filter {!$0.isWhitespace}
            let isAirPods=normalized.contains("airpod") || normalized.contains("에어팟")
            if isAirPods {
                self = normalized.contains("max") || normalized.contains("맥스") ? .airPodsMax : .airPods
            } else {
                self = .externalAudio
            }
        default:
            self = .externalAudio
        }
    }
}

/// Read-only route information. The actual output wins over the saved speaker preference:
/// that preference is applied by HearAudioSession, and must not pretend routing has succeeded.
@MainActor final class SoundOutputStatus: ObservableObject {
    private struct Route: Equatable {
        let name: String
        let kind: OutputDeviceKind
    }
    @Published private var route=Route(name:"소리 출력 확인",kind:.externalAudio)
    var name: String {route.name}
    var kind: OutputDeviceKind {route.kind}
    private var observers: [NSObjectProtocol]=[]

    init() {
        refresh()
        for notification in [AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:notification,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }
    deinit {observers.forEach(NotificationCenter.default.removeObserver)}

    func refresh() {
        let ports=AVAudioSession.sharedInstance().currentRoute.outputs
        let next: Route
        if let first=ports.first {
            let names=ports.map { port in
                switch port.portType {
                case .builtInSpeaker: return "iPhone 스피커"
                case .builtInReceiver: return "iPhone 수화부"
                default:
                    let name=port.portName.trimmingCharacters(in:.whitespacesAndNewlines)
                    return name.isEmpty ? "외부 오디오 기기" : name
                }
            }
            // Multiple simultaneous outputs cannot be represented by a single product image.
            let kind: OutputDeviceKind = ports.count == 1 ? .init(portType:first.portType,name:first.portName) : .externalAudio
            next=Route(name:names.joined(separator:", "),kind:kind)
        } else {
            next=Route(name:"소리 출력 확인",kind:.externalAudio)
        }
        if next != route {route=next}
    }
}
