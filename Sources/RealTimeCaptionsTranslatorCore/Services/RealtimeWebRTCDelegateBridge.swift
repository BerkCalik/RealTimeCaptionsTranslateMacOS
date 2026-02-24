import Foundation
import WebRTC

final class RealtimeWebRTCDelegateBridge: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    weak var owner: RealtimeWebRTCService?

    init(owner: RealtimeWebRTCService) {
        self.owner = owner
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCPeerConnectionState) {
        Task { [weak owner] in
            await owner?.handlePeerConnectionStateChanged(stateChanged)
        }
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Task { [weak owner] in
            await owner?.handleDataChannelStateChanged(dataChannel.readyState)
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        Task { [weak owner] in
            await owner?.handleDataChannelMessage(buffer.data)
        }
    }
}
