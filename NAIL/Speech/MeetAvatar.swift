import AppKit
import Foundation
import Network
import SwiftUI

struct NailBotFacePose {
    var blinkScaleY: CGFloat
    var glanceX: CGFloat
}

struct MeetAvatarFrame {
    var mood: NailBotMood
    var phase: Double
    var speakingEnergy: Double
    var listeningEnergy: Double
    var pose: NailBotFacePose
}

extension NailBotMood {
    static func forSession(
        _ presentation: SessionPresentation,
        visualState: SessionVisualState,
        isSpeaking: Bool,
        isActivelyListening: Bool,
        hasNotesError: Bool
    ) -> Self {
        if visualState == .error || hasNotesError { return .error }
        if visualState == .interrupted || presentation == .interrupted { return .interrupted }
        if isSpeaking || presentation == .speaking { return .speaking }
        if presentation == .processing { return .processing }
        return isActivelyListening ? .listening : .standby
    }
}

@MainActor
enum MeetAvatarRenderer {
    static func renderJPEG(_ frame: MeetAvatarFrame) -> Data? {
        let content = ZStack {
            Color(hex: 0x0A0A0A)
            NailBotFaceView(
                mood: frame.mood,
                phase: frame.phase,
                speakingEnergy: frame.speakingEnergy,
                listeningEnergy: frame.listeningEnergy,
                size: CGSize(width: 400, height: 400),
                framePose: frame.pose,
                speechLevel: frame.speakingEnergy
            )
        }
        .frame(width: 1280, height: 720)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1.0
        renderer.isOpaque = true
        guard let context = CGContext(
            data: nil,
            width: 1280,
            height: 720,
            bitsPerComponent: 8,
            bytesPerRow: 1280 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        renderer.render { _, draw in
            draw(context)
        }
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }
}

struct AvatarSpeechEnvelope {
    private var latestTurn: UInt64 = 0
    private var stoppedThrough: UInt64 = 0
    private var receivedAt: TimeInterval = -.infinity
    private var level: Double = 0

    mutating func ingest(rms: Double, turn: UInt64, at time: TimeInterval) {
        guard turn > stoppedThrough, turn >= latestTurn, time >= receivedAt, rms.isFinite else { return }
        let prior = turn == latestTurn ? energy(at: time) : 0
        latestTurn = turn
        receivedAt = time
        let target = min(1, max(0, (rms - 0.006) / 0.12))
        level = target == 0 ? 0 : prior + (target - prior) * 0.7
    }

    mutating func stop(throughTurn turn: UInt64) {
        stoppedThrough = max(stoppedThrough, turn)
        if turn >= latestTurn { level = 0 }
    }

    func energy(at time: TimeInterval) -> Double {
        time - receivedAt <= 0.15 ? level : 0
    }
}

enum MeetingAvatarState: String, Decodable {
    case off, starting, on, stopping, unavailable
}

struct MeetingAvatarRequest {
    private(set) var revision: UInt32 = 0
    private(set) var enabled = false
    private(set) var state: MeetingAvatarState = .off

    mutating func request(_ enabled: Bool) {
        revision += 1
        self.enabled = enabled
        state = enabled ? .starting : .stopping
    }

    @discardableResult
    mutating func confirm(_ state: MeetingAvatarState, revision: UInt32) -> Bool {
        guard revision == self.revision, revision != 0 else { return false }
        self.state = state
        if state == .off || state == .unavailable { enabled = false }
        return true
    }
}

@MainActor
final class MeetAvatarTransport {
    private var connection: NWConnection?
    private var pending: Data?
    private var busy = false
    var onFailure: (() -> Void)?

    func connect(path: String) {
        guard connection == nil else { return }
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                switch state {
                case .failed, .waiting:
                    self.close()
                    self.onFailure?()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    func offer(revision: UInt32, jpeg: Data) {
        guard !jpeg.isEmpty, jpeg.count <= 1_048_576 else { return }
        var packet = Data()
        for var field in [revision.bigEndian, UInt32(jpeg.count).bigEndian] {
            withUnsafeBytes(of: &field) { packet.append(contentsOf: $0) }
        }
        packet.append(jpeg)
        pending = packet
        sendNext()
    }

    func clearPending() {
        pending = nil
    }

    func close() {
        let previous = connection
        connection = nil
        pending = nil
        busy = false
        previous?.cancel()
    }

    private func sendNext() {
        guard !busy, let connection, let packet = pending else { return }
        pending = nil
        busy = true
        connection.send(content: packet, completion: .contentProcessed { [weak self, weak connection] error in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                if error != nil {
                    self.close()
                    self.onFailure?()
                    return
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self, weak connection] data, _, _, _ in
                    Task { @MainActor in
                        guard let self, let connection, self.connection === connection else { return }
                        guard data?.count == 1 else {
                            self.close()
                            self.onFailure?()
                            return
                        }
                        self.busy = false
                        self.sendNext()
                    }
                }
            }
        })
    }
}
