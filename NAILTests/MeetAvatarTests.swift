import AppKit
import XCTest
@testable import NAIL

final class MeetAvatarTests: XCTestCase {
    func testSessionMoodKeepsExistingPriority() {
        XCTAssertEqual(NailBotMood.forSession(.standby, visualState: .standby, isSpeaking: false, isActivelyListening: false, hasNotesError: false), .standby)
        XCTAssertEqual(NailBotMood.forSession(.listening, visualState: .active, isSpeaking: false, isActivelyListening: true, hasNotesError: false), .listening)
        XCTAssertEqual(NailBotMood.forSession(.processing, visualState: .active, isSpeaking: false, isActivelyListening: true, hasNotesError: false), .processing)
        XCTAssertEqual(NailBotMood.forSession(.processing, visualState: .active, isSpeaking: true, isActivelyListening: false, hasNotesError: false), .speaking)
        XCTAssertEqual(NailBotMood.forSession(.speaking, visualState: .interrupted, isSpeaking: true, isActivelyListening: false, hasNotesError: false), .interrupted)
        XCTAssertEqual(NailBotMood.forSession(.speaking, visualState: .interrupted, isSpeaking: true, isActivelyListening: false, hasNotesError: true), .error)
    }

    @MainActor
    func testAvatarRenderChangesWithBlinkPose() throws {
        var frame = MeetAvatarFrame(mood: .standby, phase: 0, speakingEnergy: 0, listeningEnergy: 0, pose: .init(blinkScaleY: 1, glanceX: 0))
        let open = try XCTUnwrap(MeetAvatarRenderer.renderJPEG(frame))
        frame.pose.blinkScaleY = 0.14
        let closed = try XCTUnwrap(MeetAvatarRenderer.renderJPEG(frame))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: open))
        XCTAssertEqual(bitmap.pixelsWide, 1280)
        XCTAssertEqual(bitmap.pixelsHigh, 720)
        XCTAssertEqual(Array(open.prefix(2)), [0xff, 0xd8])
        XCTAssertLessThan(open.count, 1_048_576)
        XCTAssertLessThan(closed.count, 1_048_576)
        XCTAssertNotEqual(open, closed)
    }

    func testSpeechEnvelopeClosesOnSilenceAndInterrupt() {
        var envelope = AvatarSpeechEnvelope()
        envelope.ingest(rms: 0.025, turn: 1, at: 1)
        let low = envelope.energy(at: 1)
        XCTAssertGreaterThan(low, 0)
        envelope.ingest(rms: 0.15, turn: 1, at: 1.05)
        XCTAssertGreaterThan(envelope.energy(at: 1.05), low)
        XCTAssertEqual(envelope.energy(at: 1.21), 0)
        envelope.ingest(rms: 0, turn: 1, at: 1.1)
        XCTAssertEqual(envelope.energy(at: 1.1), 0)
        envelope.stop(throughTurn: 1)
        envelope.ingest(rms: 0.19, turn: 1, at: 1.15)
        XCTAssertEqual(envelope.energy(at: 1.15), 0)
        envelope.ingest(rms: 0.19, turn: 2, at: 1.2)
        XCTAssertGreaterThan(envelope.energy(at: 1.2), 0)
    }

    func testAvatarStateIgnoresConfirmationsFromSupersededRequests() {
        var request = MeetingAvatarRequest()
        request.request(true)
        let opening = request.revision
        request.request(false)
        XCTAssertFalse(request.confirm(.on, revision: opening))
        XCTAssertEqual(request.state, .stopping)
        XCTAssertTrue(request.confirm(.off, revision: request.revision))
        XCTAssertFalse(request.enabled)
    }

    func testAvatarFrameKeyDeduplicatesStaticStandbyAndInterruptedFrames() {
        let standbyA = MeetAvatarFrame(mood: .standby, phase: 0.2, speakingEnergy: 0, listeningEnergy: 0, pose: .init(blinkScaleY: 1, glanceX: 0))
        let standbyB = MeetAvatarFrame(mood: .standby, phase: 2.8, speakingEnergy: 0, listeningEnergy: 0, pose: .init(blinkScaleY: 1, glanceX: 0))
        let standbyBlink = MeetAvatarFrame(mood: .standby, phase: 3.45, speakingEnergy: 0, listeningEnergy: 0, pose: .init(blinkScaleY: 0.14, glanceX: 0))
        XCTAssertEqual(standbyA.renderKey, standbyB.renderKey)
        XCTAssertTrue(standbyA.renderKey.isCacheableStaticPose)
        XCTAssertNotEqual(standbyA.renderKey, standbyBlink.renderKey)
        XCTAssertFalse(standbyBlink.renderKey.isCacheableStaticPose)

        let interruptedA = MeetAvatarFrame(mood: .interrupted, phase: 0.1, speakingEnergy: 0.9, listeningEnergy: 0.7, pose: .init(blinkScaleY: 1, glanceX: 0))
        let interruptedB = MeetAvatarFrame(mood: .interrupted, phase: 4.5, speakingEnergy: 0.1, listeningEnergy: 0.2, pose: .init(blinkScaleY: 0.14, glanceX: 0.5))
        XCTAssertEqual(interruptedA.renderKey, interruptedB.renderKey)
        XCTAssertTrue(interruptedA.renderKey.isCacheableStaticPose)

        let speakingA = MeetAvatarFrame(mood: .speaking, phase: 0.1, speakingEnergy: 0.2, listeningEnergy: 0, pose: .init(blinkScaleY: 1, glanceX: 0))
        let speakingB = MeetAvatarFrame(mood: .speaking, phase: 0.15, speakingEnergy: 0.6, listeningEnergy: 0, pose: .init(blinkScaleY: 1, glanceX: 0))
        XCTAssertNotEqual(speakingA.renderKey, speakingB.renderKey)
        XCTAssertFalse(speakingA.renderKey.isCacheableStaticPose)
    }

    func testAvatarRenderPolicyAdaptiveCadence() {
        XCTAssertEqual(MeetAvatarRenderPolicy.frameInterval(for: .speaking, blinkScale: 1), 0.05)
        XCTAssertGreaterThan(MeetAvatarRenderPolicy.frameInterval(for: .listening, blinkScale: 1), 0.05)
        XCTAssertGreaterThan(MeetAvatarRenderPolicy.frameInterval(for: .processing, blinkScale: 1), 0.05)
        XCTAssertEqual(MeetAvatarRenderPolicy.frameInterval(for: .standby, blinkScale: 0.5), 0.05)
    }

    @MainActor
    func testAvatarRendererCenteredSceneMatchesBackgroundAndEncodesOffMainActor() async throws {
        defer { MeetAvatarRenderer.resetCache() }
        let frame = MeetAvatarFrame(mood: .speaking, phase: 0.4, speakingEnergy: 0.8, listeningEnergy: 0, pose: .init(blinkScaleY: 1, glanceX: 0))
        let cgImage = try XCTUnwrap(MeetAvatarRenderer.renderCGImage(frame))
        XCTAssertEqual(cgImage.width, 1280)
        XCTAssertEqual(cgImage.height, 720)

        let rep = NSBitmapImageRep(cgImage: cgImage)
        let outerCorner = try XCTUnwrap(rep.colorAt(x: 10, y: 10))
        let faceBoxCorner = try XCTUnwrap(rep.colorAt(x: 321, y: 41))
        XCTAssertEqual(Int((outerCorner.redComponent * 255).rounded()), 10)
        XCTAssertEqual(Int((faceBoxCorner.redComponent * 255).rounded()), 10)
        XCTAssertEqual(Int((outerCorner.greenComponent * 255).rounded()), 10)
        XCTAssertEqual(Int((faceBoxCorner.greenComponent * 255).rounded()), 10)

        let porcelainForehead = try XCTUnwrap(rep.colorAt(x: 640, y: 240))
        XCTAssertGreaterThan(porcelainForehead.redComponent, 0.7)

        let encodedJPEG = await Task.detached {
            MeetAvatarRenderer.encodeJPEG(cgImage)
        }.value
        let jpeg = try XCTUnwrap(encodedJPEG)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xff, 0xd8])
        XCTAssertLessThan(jpeg.count, 1_048_576)
    }
}
