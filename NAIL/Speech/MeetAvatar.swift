import AppKit
import Foundation
import ImageIO
import Network
import SwiftUI
import UniformTypeIdentifiers

struct NailBotFacePose: Equatable, Sendable {
    var blinkScaleY: CGFloat
    var glanceX: CGFloat
}

struct MeetAvatarFrame: Sendable {
    var mood: NailBotMood
    var phase: Double
    var speakingEnergy: Double
    var listeningEnergy: Double
    var pose: NailBotFacePose
}

struct MeetAvatarFrameKey: Hashable, Sendable {
    let mood: NailBotMood
    let phaseBucket: Int
    let speakingBucket: Int
    let listeningBucket: Int
    let blinkBucket: Int
    let glanceBucket: Int

    var isCacheableStaticPose: Bool {
        switch mood {
        case .interrupted:
            return true
        case .standby, .error:
            return blinkBucket == 200 && glanceBucket == 0
        case .listening, .processing, .speaking:
            return false
        }
    }
}

extension MeetAvatarFrame {
    var renderKey: MeetAvatarFrameKey {
        let blinkBucket = Int((pose.blinkScaleY * 200).rounded())
        let glanceBucket = Int((pose.glanceX * 100).rounded())
        switch mood {
        case .interrupted:
            return MeetAvatarFrameKey(
                mood: .interrupted,
                phaseBucket: 0,
                speakingBucket: 0,
                listeningBucket: 0,
                blinkBucket: 200,
                glanceBucket: 0
            )
        case .standby, .error:
            return MeetAvatarFrameKey(
                mood: mood,
                phaseBucket: 0,
                speakingBucket: 0,
                listeningBucket: 0,
                blinkBucket: blinkBucket,
                glanceBucket: glanceBucket
            )
        case .listening:
            return MeetAvatarFrameKey(
                mood: .listening,
                phaseBucket: Int((phase * 1000).rounded()),
                speakingBucket: 0,
                listeningBucket: Int((listeningEnergy * 200).rounded()),
                blinkBucket: blinkBucket,
                glanceBucket: glanceBucket
            )
        case .processing:
            return MeetAvatarFrameKey(
                mood: .processing,
                phaseBucket: Int((phase * 1000).rounded()),
                speakingBucket: 0,
                listeningBucket: 0,
                blinkBucket: blinkBucket,
                glanceBucket: glanceBucket
            )
        case .speaking:
            return MeetAvatarFrameKey(
                mood: .speaking,
                phaseBucket: Int((phase * 1000).rounded()),
                speakingBucket: Int((speakingEnergy * 200).rounded()),
                listeningBucket: 0,
                blinkBucket: blinkBucket,
                glanceBucket: glanceBucket
            )
        }
    }
}

enum MeetAvatarRenderPolicy {
    static func blinkScale(forPhase phase: Double) -> CGFloat {
        let blink = phase.truncatingRemainder(dividingBy: 3.8)
        return 1 - 0.86 * max(0, 1 - abs(blink - 3.45) / 0.14)
    }

    static func frameInterval(for mood: NailBotMood, blinkScale: CGFloat) -> TimeInterval {
        switch mood {
        case .speaking:
            return 0.05
        case .processing:
            return 0.083
        case .listening:
            return blinkScale < 0.999 ? 0.05 : 0.10
        case .standby, .error:
            return blinkScale < 0.999 ? 0.05 : 0.06
        case .interrupted:
            return 0.08
        }
    }
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

private struct MeetAvatarScene: View {
    let frame: MeetAvatarFrame

    var body: some View {
        ZStack {
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
        .frame(width: MeetAvatarRenderer.faceBoxSize, height: MeetAvatarRenderer.faceBoxSize)
        .clipped()
    }
}

@MainActor
enum MeetAvatarRenderer {
    static let canvasWidth = 1280
    static let canvasHeight = 720
    fileprivate static let faceBoxSize: CGFloat = 640

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let backgroundColor = CGColor(
        colorSpace: colorSpace,
        components: [10.0 / 255.0, 10.0 / 255.0, 10.0 / 255.0, 1.0]
    )
    private static var cachedContext: CGContext?
    private static var cachedRenderer: ImageRenderer<MeetAvatarScene>?

    private static func makeOrReuseContext() -> CGContext? {
        if let cachedContext {
            return cachedContext
        }
        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: canvasWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        if let backgroundColor {
            context.setFillColor(backgroundColor)
            context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        }
        cachedContext = context
        return context
    }

    static func resetCache() {
        cachedContext = nil
        cachedRenderer = nil
    }

    static func renderCGImage(_ frame: MeetAvatarFrame) -> CGImage? {
        guard let context = makeOrReuseContext() else { return nil }
        let scene = MeetAvatarScene(frame: frame)
        let renderer: ImageRenderer<MeetAvatarScene>
        if let cachedRenderer {
            cachedRenderer.content = scene
            renderer = cachedRenderer
        } else {
            let created = ImageRenderer(content: scene)
            created.scale = 1.0
            created.isOpaque = true
            cachedRenderer = created
            renderer = created
        }

        let originX = (CGFloat(canvasWidth) - faceBoxSize) * 0.5
        let originY = (CGFloat(canvasHeight) - faceBoxSize) * 0.5
        if let backgroundColor {
            context.setFillColor(backgroundColor)
            context.fill(CGRect(x: originX, y: originY, width: faceBoxSize, height: faceBoxSize))
        }
        context.saveGState()
        context.translateBy(x: originX, y: originY)
        renderer.render { _, draw in
            draw(context)
        }
        context.restoreGState()
        return context.makeImage()
    }

    nonisolated static func encodeJPEG(_ image: CGImage, quality: CGFloat = 0.92) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func renderJPEG(_ frame: MeetAvatarFrame) -> Data? {
        guard let image = renderCGImage(frame) else { return nil }
        return encodeJPEG(image)
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
    var hasInflightFrame: Bool { busy || pending != nil }

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
        var packet = Data(capacity: 8 + jpeg.count)
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
