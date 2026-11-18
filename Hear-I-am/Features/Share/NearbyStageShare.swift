import Foundation
import MultipeerConnectivity
import UIKit
import HearIAmCore

/// Sends a share file straight to a phone nearby that has Hear I am open on 「근처에서 받기」. It uses
/// MultipeerConnectivity, the same peer-to-peer Wi-Fi and Bluetooth as AirDrop, so no account or server is involved.
/// The receiver has to accept each file, and the session is encrypted.
@MainActor
final class NearbyStageShare: NSObject, ObservableObject {
    static let serviceType="heariam-share"

    struct Offer: Codable, Equatable {
        let title: String
        let bytes: Int64
    }
    enum Phase: Equatable {
        case idle
        /// Receiver: visible to senders. Sender: looking for receivers.
        case waiting
        /// Receiver: an offer to accept or decline. Sender: waiting for the other phone to accept.
        case asking(from: String, offer: Offer)
        case transferring(Double)
        case done
        case failed(String)
    }

    @Published private(set) var peers: [MCPeerID]=[]
    @Published private(set) var phase: Phase = .idle
    /// Four digits shown on the receiving phone and in its name, so two phones both called 「iPhone」 can be told apart.
    let code=String(format:"%04d",Int.random(in:0...9999))
    /// The receiver's copy of a finished file, in its own temporary folder.
    var onReceived: ((StageShareIncoming) -> Void)?

    private let me: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invitation: ((Bool, MCSession?) -> Void)?
    private var outgoing: (peer: MCPeerID, url: URL)?
    private var observation: NSKeyValueObservation?

    override init() {
        me=MCPeerID(displayName:"\(UIDevice.current.name) \(code)")
        session=MCSession(peer:me,securityIdentity:nil,encryptionPreference:.required)
        super.init()
        session.delegate=self
    }

    var name: String { me.displayName }

    // MARK: Receiving

    func startReceiving() {
        guard advertiser == nil else { return }
        let advertiser=MCNearbyServiceAdvertiser(peer:me,discoveryInfo:nil,serviceType:Self.serviceType)
        advertiser.delegate=self
        advertiser.startAdvertisingPeer()
        self.advertiser=advertiser
        phase = .waiting
    }
    func answer(_ accept: Bool) {
        guard let invitation else { return }
        self.invitation=nil
        invitation(accept,accept ? session : nil)
        phase=accept ? .transferring(0) : .waiting
    }

    // MARK: Sending

    func startBrowsing() {
        guard browser == nil else { return }
        let browser=MCNearbyServiceBrowser(peer:me,serviceType:Self.serviceType)
        browser.delegate=self
        browser.startBrowsingForPeers()
        self.browser=browser
        phase = .waiting
    }
    func send(_ url: URL, offer: Offer, to peer: MCPeerID) {
        guard let browser, let context=try? JSONEncoder().encode(offer) else { return }
        outgoing=(peer,url)
        phase = .asking(from:peer.displayName,offer:offer)
        browser.invitePeer(peer,to:session,withContext:context,timeout:60)
    }
    /// Back to the list of phones after a failed or declined send.
    func reset() {
        observation=nil; outgoing=nil
        session.disconnect()
        phase = .waiting
    }

    func stop() {
        advertiser?.stopAdvertisingPeer(); advertiser=nil
        browser?.stopBrowsingForPeers(); browser=nil
        invitation?(false,nil); invitation=nil
        observation=nil; outgoing=nil
        session.disconnect()
    }

    private func follow(_ progress: Progress?) {
        guard let progress else { return }
        observation=progress.observe(\.fractionCompleted,options:[.initial,.new]) {[weak self] progress,_ in
            let value=progress.fractionCompleted
            Task {@MainActor in
                guard let self, case .transferring=self.phase else { return }
                self.phase = .transferring(value)
            }
        }
    }
    private func fail(_ message: String) {
        observation=nil; outgoing=nil
        phase = .failed(message)
    }

    private func startSending(to peer: MCPeerID) {
        guard let outgoing, outgoing.peer == peer else { return }
        phase = .transferring(0)
        let progress=session.sendResource(at:outgoing.url,withName:"stage.\(StageShare.fileExtension)",toPeer:peer) {[weak self] error in
            Task {@MainActor in
                guard let self else { return }
                if let error { self.fail(L("보내지 못했어요: %@", error.localizedDescription)) }
                else { self.observation=nil; self.outgoing=nil; self.phase = .done }
            }
        }
        follow(progress)
    }
}

extension NearbyStageShare: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let offer=context.flatMap {try? JSONDecoder().decode(Offer.self,from:$0)}
        Task {@MainActor in
            // One file at a time, and only files that say what they are.
            guard let offer, self.phase == .waiting, self.invitation == nil else { invitationHandler(false,nil); return }
            self.invitation=invitationHandler
            self.phase = .asking(from:peerID.displayName,offer:offer)
        }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task {@MainActor in self.fail(L("근처 폰에 이 폰을 보이지 못했어요: %@", error.localizedDescription)) }
    }
}

extension NearbyStageShare: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task {@MainActor in if !self.peers.contains(peerID) { self.peers.append(peerID) } }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task {@MainActor in self.peers.removeAll {$0 == peerID} }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task {@MainActor in self.fail(L("근처 폰을 찾지 못했어요: %@", error.localizedDescription)) }
    }
}

extension NearbyStageShare: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task {@MainActor in
            switch state {
            case .connected: self.startSending(to:peerID)
            case .notConnected:
                // Declined, timed out or dropped before the file was through.
                if self.outgoing?.peer == peerID { self.fail(L("상대 폰이 받지 않았거나 연결이 끊겼어요.")) }
                else if case .transferring=self.phase, self.advertiser != nil { self.fail(L("받는 중에 연결이 끊겼어요.")) }
            default: break
            }
        }
    }
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        Task {@MainActor in self.phase = .transferring(0); self.follow(progress) }
    }
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                             at localURL: URL?, withError error: Error?) {
        // The system removes its copy when this returns, so it is moved out here, before going to the main actor.
        var result: Result<StageShareIncoming, Error>
        if let error { result = .failure(error) }
        else if let localURL {
            do { result = .success(try StageLibrary.adoptReceived(localURL)) } catch { result = .failure(error) }
        } else { result = .failure(StageShareNearbyError.empty) }
        Task {@MainActor in
            self.observation=nil
            switch result {
            case .success(let incoming): self.phase = .done; self.onReceived?(incoming)
            case .failure(let error): self.fail(L("받지 못했어요: %@", error.localizedDescription))
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
}

enum StageShareNearbyError: LocalizedError {
    case empty
    var errorDescription: String? { L("받은 파일이 비어 있어요.") }
}
