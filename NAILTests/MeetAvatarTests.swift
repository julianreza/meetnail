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
}
