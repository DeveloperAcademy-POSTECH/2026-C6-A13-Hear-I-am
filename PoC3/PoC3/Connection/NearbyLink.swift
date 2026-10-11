import MultipeerConnectivity
import Combine
import UIKit

@MainActor
final class NearbyLink: NSObject, ObservableObject {
    enum Role { case operatorDevice, wearer }
    struct Device: Identifiable {
        let peer: MCPeerID
        var id: String { peer.displayName }
    }
    @Published private(set) var devices: [Device] = []
    @Published private(set) var connected = false
    @Published private(set) var status = "연결 대기"
    @Published private(set) var code = String(Int.random(in: 100000...999999))
    var onMessage: ((PeerMessage) -> Void)?
    var onDisconnect: (() -> Void)?
    private let peer = MCPeerID(displayName: "PoC3-" + String(UUID().uuidString.prefix(5)))
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var role: Role?
    private var invitedPeer: MCPeerID?
    private var invitationDeadline: Double = 0
    private let service = "poc3-guide"

    func start(_ role: Role) {
        stop()
        self.role = role
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        if role == .wearer {
            code = String(Int.random(in: 100000...999999))
            advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["role": "wearer", "version": "1"], serviceType: service)
            advertiser?.delegate = self
            advertiser?.startAdvertisingPeer()
            status = "운영자에게 연결 코드 \(code)를 알려주세요"
        } else {
            browser = MCNearbyServiceBrowser(peer: peer, serviceType: service)
            browser?.delegate = self
            browser?.startBrowsingForPeers()
            status = "주변 착용 폰 검색 중"
        }
    }
    func invite(_ device: Device, code: String) {
        guard !connected, code.count == 6, code.allSatisfy(\.isNumber),
              invitedPeer == nil || ProcessInfo.processInfo.systemUptime > invitationDeadline else { return }
        invitedPeer = device.peer
        invitationDeadline = ProcessInfo.processInfo.systemUptime + 15
        browser?.invitePeer(device.peer, to: session, withContext: Data(code.utf8), timeout: 15)
        status = "\(device.id) 연결 요청 중 · 실패하면 15초 후 재시도"
    }
    func send(_ message: PeerMessage, reliable: Bool = false) {
        guard connected, let session, session.connectedPeers.count == 1 else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
        } catch { status = "전송 실패: \(error.localizedDescription)" }
    }
    func stop() {
        advertiser?.stopAdvertisingPeer(); advertiser?.delegate = nil; advertiser = nil
        browser?.stopBrowsingForPeers(); browser?.delegate = nil; browser = nil
        session?.delegate = nil; session?.disconnect(); session = nil
        connected = false; invitedPeer = nil; devices = []; role = nil
        status = "연결 종료"
    }
}

extension NearbyLink: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["role"] == "wearer", info?["version"] == "1" else { return }
        Task { @MainActor [weak self] in
            guard let self, self.browser === browser, !self.devices.contains(where: { $0.peer == peerID }) else { return }
            self.devices.append(Device(peer: peerID))
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            guard let self, self.browser === browser else { return }
            self.devices.removeAll { $0.peer == peerID }
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.status = "검색 실패 · 로컬 네트워크 권한 확인: \(message)" }
    }
}

extension NearbyLink: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, self.advertiser === advertiser, !self.connected,
                  self.invitedPeer == nil || ProcessInfo.processInfo.systemUptime > self.invitationDeadline,
                  context.flatMap({ String(data: $0, encoding: .utf8) }) == self.code else {
                invitationHandler(false, nil); return
            }
            self.invitedPeer = peerID
            self.invitationDeadline = ProcessInfo.processInfo.systemUptime + 15
            invitationHandler(true, self.session)
        }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.status = "연결 대기 실패 · 로컬 네트워크 권한 확인: \(message)" }
    }
}

extension NearbyLink: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self, self.session === session else { return }
            switch state {
            case .connected:
                guard peerID == self.invitedPeer, session.connectedPeers.count == 1 else {
                    self.stop(); self.onDisconnect?(); return
                }
                self.connected = true; self.status = "\(peerID.displayName) 연결됨"
            case .notConnected:
                self.connected = false; self.invitedPeer = nil
                self.status = "연결 끊김 · 다시 연결하고 정면 보정하세요"
                self.onDisconnect?()
            case .connecting: self.status = "기기 연결 중"
            @unknown default: break
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count < 64_000 else { return }
        Task { @MainActor [weak self] in
            guard let self, self.session === session, self.connected, peerID == self.invitedPeer,
                  let message = try? JSONDecoder().decode(PeerMessage.self, from: data) else { return }
            self.onMessage?(message)
        }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}
