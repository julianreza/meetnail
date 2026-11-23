import AppKit
import Foundation
import QuartzCore
import SwiftUI
import XCTest
@testable import NAIL

final class MeetLinkAndSettingsTests: XCTestCase {
    func testPresentationOCRReadsTextFromImage() throws {
        let image = NSImage(size: NSSize(width: 900, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 180).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 55, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        "ERROR CODE 7249".draw(at: NSPoint(x: 30, y: 65), withAttributes: attributes)
        image.unlockFocus()
        let data = try XCTUnwrap(image.tiffRepresentation)
        let text = try PresentationOCR.recognize(data)
        XCTAssertTrue(text.contains("7249"), "OCR output: \(text)")
    }

    func testPresentationOCRRejectsInvalidImage() {
        XCTAssertThrowsError(try PresentationOCR.recognize(Data("invalid".utf8)))
    }

    func testSessionPresentationFollowsWorkerEvents() {
        XCTAssertEqual(SessionPresentation.phase(for: "joined"), .standby)
        XCTAssertEqual(SessionPresentation.phase(for: "voice-recording"), .listening)
        XCTAssertEqual(SessionPresentation.phase(for: "voice-codex-listening"), .processing)
        XCTAssertEqual(SessionPresentation.phase(for: "voice-processing"), .processing)
        XCTAssertEqual(SessionPresentation.phase(for: "voice-sending"), .speaking)
        XCTAssertEqual(SessionPresentation.phase(for: "voice-result {}"), .standby)
        XCTAssertEqual(SessionPresentation.phase(for: "left"), .finishing)
        XCTAssertEqual(SessionPresentation.finishing.label, "Menyelesaikan")
        XCTAssertNil(SessionPresentation.phase(for: "browser-window shown"))
    }

    func testDialHeadlineAndListeningStateDistinguishStandbyFromActiveListening() {
        // Standby without clicking Dengar & Jawab or calling Nail must NOT report listening.
        XCTAssertFalse(
            SessionPresentation.isActivelyListening(
                presentation: .standby,
                visualState: .standby,
                voiceBusy: false,
                isSpeaking: false
            )
        )
        XCTAssertEqual(
            SessionPresentation.dialHeadline(presentation: .standby, visualState: .standby, voiceBusy: false),
            "Nail siaga"
        )

        // Joining or signing in has visualState == .active, but is not listening for voice.
        XCTAssertFalse(
            SessionPresentation.isActivelyListening(
                presentation: .joining,
                visualState: .active,
                voiceBusy: false,
                isSpeaking: false
            )
        )
        XCTAssertEqual(
            SessionPresentation.dialHeadline(presentation: .joining, visualState: .active, voiceBusy: false),
            "Bergabung ke rapat…"
        )

        // Manual Dengar & Jawab / voice-recording / 3s follow-up window are actively listening.
        XCTAssertTrue(
            SessionPresentation.isActivelyListening(
                presentation: .listening,
                visualState: .active,
                voiceBusy: true,
                isSpeaking: false
            )
        )
        XCTAssertEqual(
            SessionPresentation.dialHeadline(presentation: .listening, visualState: .active, voiceBusy: true),
            "Nail mendengarkan…"
        )
        XCTAssertTrue(
            SessionPresentation.isActivelyListening(
                presentation: .standby,
                visualState: .followUp,
                voiceBusy: false,
                isSpeaking: false
            )
        )
        XCTAssertEqual(
            SessionPresentation.dialHeadline(presentation: .standby, visualState: .followUp, voiceBusy: false),
            "Nail mendengarkan…"
        )

        // Processing and speaking must not fall back to listening.
        XCTAssertFalse(
            SessionPresentation.isActivelyListening(
                presentation: .processing,
                visualState: .active,
                voiceBusy: true,
                isSpeaking: false
            )
        )
        XCTAssertFalse(
            SessionPresentation.isActivelyListening(
                presentation: .speaking,
                visualState: .active,
                voiceBusy: true,
                isSpeaking: true
            )
        )
    }

    func testLeaveRequestedDoesNotMarkNotulenInterruptedOnForcedTerminate() {
        XCTAssertFalse(MeetSession.shouldMarkNotulenInterrupted(leaveRequested: true, lastWorkerExitNormal: false, exitCode: 15))
        XCTAssertFalse(MeetSession.shouldMarkNotulenInterrupted(leaveRequested: false, lastWorkerExitNormal: true, exitCode: 15))
        XCTAssertFalse(MeetSession.shouldMarkNotulenInterrupted(leaveRequested: false, lastWorkerExitNormal: false, exitCode: 0))
        XCTAssertTrue(MeetSession.shouldMarkNotulenInterrupted(leaveRequested: false, lastWorkerExitNormal: false, exitCode: 1))
    }

    func testOnlyCanonicalMeetLinksMayLaunchWorker() {
        XCTAssertTrue(MeetSession.validLink("https://meet.google.com/abc-defg-hij"))
        XCTAssertFalse(MeetSession.validLink("http://meet.google.com/abc-defg-hij"))
        XCTAssertFalse(MeetSession.validLink("https://meet.google.com.evil.example/abc-defg-hij"))
        XCTAssertFalse(MeetSession.validLink("https://meet.google.com/abc-defg-hij/other"))
        XCTAssertFalse(MeetSession.validLink("--login"))
        XCTAssertFalse(MeetSession.validLink(""))
    }

    @MainActor
    func testVoiceSettingsPersistenceAndRuntimeConfigEncoding() throws {
        let suite = "dev.nail.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceSettings(defaults: defaults)
        XCTAssertEqual(settings.provider, .antigravity)
        XCTAssertEqual(settings.listeningMode, .standby)
        XCTAssertEqual(settings.agyModel, "gemini-3.8-flash-low")
        XCTAssertEqual(settings.whisperModel, "small")
        XCTAssertEqual(settings.ttsVoice, "id-ID-GadisNeural")
        XCTAssertEqual(settings.ttsRate, 185)
        XCTAssertEqual(settings.codexVoice, "cove")
        XCTAssertEqual(settings.speakingStyle, .casual)
        XCTAssertTrue(settings.disclosureEnabled)
        XCTAssertFalse(settings.presentationReadingEnabled)
        XCTAssertFalse(settings.runtimeConfig().presentationReadingEnabled)

        settings.provider = .deepseek
        settings.listeningMode = .notulen
        settings.agyModel = "gemini-4-argon-low"
        settings.whisperModel = "base"
        settings.ttsVoice = "Damayanti (Enhanced)"
        settings.ttsRate = 205
        settings.codexVoice = "juniper"
        settings.speakingStyle = .professional
        settings.disclosureEnabled = false
        settings.presentationReadingEnabled = true

        let reloaded = VoiceSettings(defaults: defaults)
        XCTAssertEqual(reloaded.provider, .deepseek)
        XCTAssertEqual(reloaded.listeningMode, .notulen)
        XCTAssertEqual(reloaded.agyModel, "gemini-4-argon-low")
        XCTAssertEqual(reloaded.whisperModel, "base")
        XCTAssertEqual(reloaded.ttsVoice, "Damayanti (Enhanced)")
        XCTAssertEqual(reloaded.ttsRate, 205)
        XCTAssertEqual(reloaded.codexVoice, "juniper")
        XCTAssertEqual(reloaded.speakingStyle, .professional)
        XCTAssertFalse(reloaded.disclosureEnabled)
        XCTAssertTrue(reloaded.presentationReadingEnabled)

        let json = reloaded.encodedRuntimeConfig()
        let decoded = try JSONDecoder().decode(VoiceRuntimeConfig.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.agyModel, "gemini-4-argon-low")
        XCTAssertEqual(decoded.whisperModel, "base")
        XCTAssertEqual(decoded.ttsVoice, "Damayanti (Enhanced)")
        XCTAssertEqual(decoded.ttsRate, 205)
        XCTAssertEqual(decoded.codexVoice, "juniper")
        XCTAssertEqual(decoded.speakingStyle, "professional")
        XCTAssertEqual(decoded.listeningMode, "notulen")
        XCTAssertFalse(decoded.disclosure)
        XCTAssertTrue(decoded.presentationReadingEnabled)
    }

    @MainActor
    func testCodexVoiceCatalogAndInvalidFallback() throws {
        XCTAssertEqual(VoiceSettings.codexVoiceOptions.count, 25)
        for expected in ["cove", "breeze", "juniper", "viola"] {
            XCTAssertTrue(VoiceSettings.codexVoiceOptions.contains(expected))
        }

        let suite = "dev.nail.tests.codex.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("invalid-voice", forKey: "nail.voice.codexVoice")
        defaults.set("invalid-style", forKey: "nail.voice.speakingStyle")
        let settings = VoiceSettings(defaults: defaults)
        XCTAssertEqual(settings.codexVoice, "cove")
        XCTAssertEqual(settings.speakingStyle, .casual)
    }

    func testTTSVoiceCatalogParsesIndonesianVoicesAndFallsBack() {
        let sample = """
        Alex                en_US    # Most people recognize me by my voice.
        Damayanti           id_ID    # Halo! Nama saya Damayanti.
        Damayanti (Enhanced) id_ID   # Halo! Nama saya Damayanti.
        Samantha            en_US    # Hello, my name is Samantha.
        Siti (Enhanced)     id_ID    # Halo! Nama saya Siti.
        """
        let parsed = TTSVoiceCatalog.parseIndonesianVoices(sample)
        XCTAssertEqual(parsed, ["Damayanti", "Damayanti (Enhanced)", "Siti (Enhanced)"])
        XCTAssertTrue(TTSVoiceCatalog.hasEnhancedVoice(in: parsed))

        let fallback = TTSVoiceCatalog.parseIndonesianVoices("Samantha en_US # Hello\n")
        XCTAssertEqual(fallback, ["Damayanti"])
        XCTAssertFalse(TTSVoiceCatalog.hasEnhancedVoice(in: fallback))
    }

    func testTTSVoiceCatalogNeuralVoicesAndDisplayNames() {
        XCTAssertEqual(TTSVoiceCatalog.neuralVoices, ["id-ID-GadisNeural", "id-ID-ArdiNeural"])
        XCTAssertEqual(TTSVoiceCatalog.defaultVoice, "id-ID-GadisNeural")
        XCTAssertTrue(TTSVoiceCatalog.isNeuralVoice("id-ID-GadisNeural"))
        XCTAssertTrue(TTSVoiceCatalog.isNeuralVoice("id-ID-ArdiNeural"))
        XCTAssertFalse(TTSVoiceCatalog.isNeuralVoice("Damayanti"))

        XCTAssertEqual(
            TTSVoiceCatalog.displayName(for: "id-ID-GadisNeural"),
            "Gadis · Neural Indonesia (Perempuan)"
        )
        XCTAssertEqual(
            TTSVoiceCatalog.displayName(for: "id-ID-ArdiNeural"),
            "Ardi · Neural Indonesia (Laki-laki)"
        )
        XCTAssertEqual(TTSVoiceCatalog.displayName(for: "Damayanti"), "Damayanti")

        XCTAssertEqual(TTSVoiceCatalog.shortDisplayName(for: "id-ID-GadisNeural"), "Gadis Neural (ID)")
        XCTAssertEqual(TTSVoiceCatalog.shortDisplayName(for: "id-ID-ArdiNeural"), "Ardi Neural (ID)")
        XCTAssertEqual(TTSVoiceCatalog.shortDisplayName(for: "Damayanti"), "Damayanti")

        let available = TTSVoiceCatalog.listIndonesianVoices()
        XCTAssertEqual(Array(available.prefix(2)), ["id-ID-GadisNeural", "id-ID-ArdiNeural"])
    }

    @MainActor
    func testTranscriptStoreRespectsStandbyVsNotulenAndExportsMarkdown() throws {
        let store = SessionTranscriptStore()

        // Mode Siaga must discard ambient meeting chatter.
        store.recordMeetingLine("Obrolan biasa sebelum panggil Nail", mode: .standby)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.notulenLineCount, 0)

        // Mode Notulen records meeting chatter and exchanges with timestamps and latency.
        let heardAt = Date(timeIntervalSince1970: 1_763_654_400)
        let replyAt = Date(timeIntervalSince1970: 1_763_654_401.84)
        XCTAssertTrue(TranscriptEntry.formatTime(heardAt).wholeMatch(of: #/\d{2}:\d{2}:\d{2}/#) != nil)
        XCTAssertEqual(TranscriptEntry.formatLatency(1.84), "1.8 dtk")

        store.recordMeetingLine("Target rilis hari Jumat.", mode: .notulen)
        store.recordExchange(
            heard: "Nail, kapan target rilis?",
            reply: "Target rilis adalah hari Jumat.",
            heardAt: heardAt,
            replyAt: replyAt,
            latencySeconds: 1.84
        )
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.notulenLineCount, 2)
        XCTAssertEqual(store.entries.last?.latencySeconds, 1.84)

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("nail-notulen-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fixedDate = Date(timeIntervalSince1970: 1_763_654_400)
        try NotulenExporter.exportSession(entries: store.entries, interrupted: false, date: fixedDate, baseDir: tmpDir)

        let fileURL = NotulenExporter.todayURL(date: fixedDate, baseDir: tmpDir)
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Notulen "))
        XCTAssertTrue(markdown.contains("Target rilis hari Jumat."))
        XCTAssertTrue(markdown.contains("**Dengar ("))
        XCTAssertTrue(markdown.contains("**Nail ("))
        XCTAssertTrue(markdown.contains("1.8 dtk"))
    }

    func testPolicyZoneCases() {
        XCTAssertEqual(Set(PolicyZone.allCases.map(\.rawValue)), Set(["green", "yellow", "red"]))
    }

    func testNotulenExporterListsAndReadsMarkdownFilesNewestFirst() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("nail-list-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let older = tmpDir.appendingPathComponent("2026-11-19.md")
        let newer = tmpDir.appendingPathComponent("2026-11-21.md")
        let nonMd = tmpDir.appendingPathComponent("notes.txt")
        try "# Notulen 2026-11-19\nLama".write(to: older, atomically: true, encoding: .utf8)
        try "# Notulen 2026-11-21\nBaru".write(to: newer, atomically: true, encoding: .utf8)
        try "ignore".write(to: nonMd, atomically: true, encoding: .utf8)

        let files = NotulenExporter.listFiles(baseDir: tmpDir)
        XCTAssertEqual(files.map(\.name), ["2026-11-21", "2026-11-19"])
        XCTAssertEqual(NotulenExporter.readContent(of: files[0].url), "# Notulen 2026-11-21\nBaru")
    }

    func testHUDPanelNotchFrameCentersAtTopEdge() {
        let frame = HUDPanel.panelFrame(
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            width: 300,
            height: 44
        )
        XCTAssertEqual(frame.midX, 756)
        XCTAssertEqual(frame.maxY, 982)
        XCTAssertEqual(frame.width, 300)
        XCTAssertEqual(frame.height, 44)
    }

    func testFloatingHUDPositionRemainsVisibleOnChangedDisplay() {
        let visibleFrame = NSRect(x: -1200, y: 40, width: 1200, height: 760)
        let savedOffscreen = NSPoint(x: 600, y: 900)
        let frame = HUDPanel.floatingFrame(
            visibleFrame: visibleFrame,
            width: 404,
            height: 232,
            savedOrigin: savedOffscreen
        )

        XCTAssertEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertEqual(frame.maxY, visibleFrame.maxY)
        XCTAssertTrue(visibleFrame.contains(frame))

        let defaultFrame = HUDPanel.floatingFrame(
            visibleFrame: visibleFrame,
            width: 300,
            height: 40
        )
        XCTAssertEqual(defaultFrame.midX, visibleFrame.midX)
        XCTAssertEqual(defaultFrame.maxY, visibleFrame.maxY - 2)
    }

    @MainActor
    func testHUDSettingsPersistenceClampingAndSizeProgression() throws {
        XCTAssertLessThan(HUDSizePreset.compact.expandedCardWidth, HUDSizePreset.standard.expandedCardWidth)
        XCTAssertLessThan(HUDSizePreset.standard.expandedCardWidth, HUDSizePreset.large.expandedCardWidth)
        XCTAssertLessThan(HUDSizePreset.large.expandedCardWidth, HUDSizePreset.extraLarge.expandedCardWidth)

        let suite = "dev.nail.tests.hud.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceSettings(defaults: defaults)
        XCTAssertEqual(settings.hudSize, .standard)
        XCTAssertEqual(settings.hudAnimationStyle, .wave)
        XCTAssertEqual(settings.hudAccentTheme, .status)
        XCTAssertTrue(settings.hudExpandOnHover)
        XCTAssertTrue(settings.hudAutoExpandOnVoice)
        XCTAssertTrue(settings.hudShowTranscript)
        XCTAssertEqual(settings.hudReplyHoldSeconds, 5)
        XCTAssertEqual(settings.hudOpacity, 1.0, accuracy: 0.001)

        settings.hudSize = .extraLarge
        settings.hudAnimationStyle = .aurora
        settings.hudAccentTheme = .violet
        settings.hudExpandOnHover = false
        settings.hudAutoExpandOnVoice = false
        settings.hudShowTranscript = false
        settings.hudReplyHoldSeconds = 12
        settings.hudOpacity = 0.85

        let reloaded = VoiceSettings(defaults: defaults)
        XCTAssertEqual(reloaded.hudSize, .extraLarge)
        XCTAssertEqual(reloaded.hudAnimationStyle, .aurora)
        XCTAssertEqual(reloaded.hudAccentTheme, .violet)
        XCTAssertFalse(reloaded.hudExpandOnHover)
        XCTAssertFalse(reloaded.hudAutoExpandOnVoice)
        XCTAssertFalse(reloaded.hudShowTranscript)
        XCTAssertEqual(reloaded.hudReplyHoldSeconds, 12)
        XCTAssertEqual(reloaded.hudOpacity, 0.85, accuracy: 0.001)

        defaults.set("invalid-size", forKey: "nail.hud.size")
        defaults.set("invalid-anim", forKey: "nail.hud.animationStyle")
        defaults.set("invalid-theme", forKey: "nail.hud.accentTheme")
        defaults.set(99, forKey: "nail.hud.replyHoldSeconds")
        defaults.set(0.1, forKey: "nail.hud.opacity")

        let clamped = VoiceSettings(defaults: defaults)
        XCTAssertEqual(clamped.hudSize, .standard)
        XCTAssertEqual(clamped.hudAnimationStyle, .wave)
        XCTAssertEqual(clamped.hudAccentTheme, .status)
        XCTAssertEqual(clamped.hudReplyHoldSeconds, 15)
        XCTAssertEqual(clamped.hudOpacity, 0.75, accuracy: 0.001)
    }

    @MainActor
    func testNotchMetricsSmoothAttackAndDecayEnvelope() {
        let metrics = NotchMetrics()
        metrics.updateVoiceTargets(speaking: true, listening: false)
        for _ in 0..<3 {
            metrics.step(dt: 0.05)
        }
        XCTAssertGreaterThan(metrics.speakingEnergy, 0.3)
        XCTAssertLessThan(metrics.speakingEnergy, 0.95)
        XCTAssertGreaterThan(metrics.phase, 0)

        for _ in 0..<12 {
            metrics.step(dt: 0.05)
        }
        XCTAssertGreaterThan(metrics.speakingEnergy, 0.98)

        metrics.updateVoiceTargets(speaking: false, listening: false)
        for _ in 0..<4 {
            metrics.step(dt: 0.05)
        }
        XCTAssertGreaterThan(metrics.speakingEnergy, 0.2)
        XCTAssertLessThan(metrics.speakingEnergy, 0.85)

        for _ in 0..<30 {
            metrics.step(dt: 0.05)
        }
        XCTAssertEqual(metrics.speakingEnergy, 0)
        metrics.stopAnimations()
    }

    @MainActor
    func testPerMeetingNotulenSessionURLAndAtomicWriteSession() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("nail-meeting-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let fixedDate = Date(timeIntervalSince1970: 1_763_654_400)
        let titledURL = NotulenExporter.sessionURL(
            title: "Sprint Review #1!",
            meetLink: "https://meet.google.com/abc-defg-hij",
            startedAt: fixedDate,
            baseDir: tmpDir
        )
        XCTAssertTrue(titledURL.lastPathComponent.hasSuffix("_Sprint-Review-1.md"))

        let untitledURL = NotulenExporter.sessionURL(
            title: "   ",
            meetLink: "https://meet.google.com/abc-defg-hij",
            startedAt: fixedDate,
            baseDir: tmpDir
        )
        XCTAssertTrue(untitledURL.lastPathComponent.hasSuffix("_abc-defg-hij.md"))

        try Data().write(to: titledURL)
        let collisionURL = NotulenExporter.uniqueSessionURL(
            title: "Sprint Review #1!",
            meetLink: "https://meet.google.com/abc-defg-hij",
            startedAt: fixedDate,
            baseDir: tmpDir
        )
        XCTAssertTrue(collisionURL.lastPathComponent.hasSuffix("_Sprint-Review-1-2.md"))

        let store = SessionTranscriptStore()
        store.recordMeetingLine("Membahas target rilis.", mode: .notulen, speaker: "Rina [QA]", timestamp: fixedDate)
        store.recordMeetingLine("Targetnya Jumat.", mode: .notulen, speaker: "Pembicara 2", timestamp: fixedDate.addingTimeInterval(2))
        store.recordExchange(
            heard: "Nail, kapan target rilisnya?",
            reply: "Target rilis disepakati hari Jumat.",
            heardAt: fixedDate.addingTimeInterval(5),
            replyAt: fixedDate.addingTimeInterval(6.84),
            latencySeconds: 1.84
        )

        try NotulenExporter.writeSession(
            to: collisionURL,
            title: "Sprint Review #1",
            meetLink: "https://meet.google.com/abc-defg-hij",
            startedAt: fixedDate,
            endedAt: nil,
            interrupted: false,
            entries: store.entries
        )
        try NotulenExporter.writeSession(
            to: collisionURL,
            title: "Sprint Review #1",
            meetLink: "https://meet.google.com/abc-defg-hij",
            startedAt: fixedDate,
            endedAt: fixedDate.addingTimeInterval(120),
            interrupted: false,
            entries: store.entries
        )

        let markdown = try String(contentsOf: collisionURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Sprint Review #1"))
        XCTAssertTrue(markdown.contains("Link Meet:"))
        XCTAssertTrue(markdown.contains("Selesai ("))
        XCTAssertTrue(markdown.contains("1.8 dtk"))
        XCTAssertTrue(markdown.contains("**Rina \\[QA\\]:** Membahas target rilis."))
        XCTAssertTrue(markdown.contains("**Pembicara 2:** Targetnya Jumat."))
        let occurrences = markdown.components(separatedBy: "Nail, kapan target rilisnya?").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testMicrosoftTeamsLinksValidationAndNotulenSlug() throws {
        XCTAssertEqual(
            MeetSession.detectPlatform("https://teams.microsoft.com/meet/9341234567890?p=abcDEF"),
            .microsoftTeams
        )
        XCTAssertEqual(
            MeetSession.detectPlatform("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=%7b%7d"),
            .microsoftTeams
        )
        XCTAssertEqual(
            MeetSession.detectPlatform("https://teams.live.com/meet/9341234567890?p=xyz"),
            .microsoftTeams
        )
        XCTAssertEqual(
            MeetSession.detectPlatform("https://teams.live.com/dl/launcher/launcher.html?url=abc"),
            .microsoftTeams
        )
        XCTAssertEqual(
            MeetSession.detectPlatform("https://teams.cloud.microsoft/meet/9341234567890?p=abc"),
            .microsoftTeams
        )
        XCTAssertEqual(
            MeetSession.detectPlatform("https://meet.google.com/abc-defg-hij"),
            .googleMeet
        )
        XCTAssertFalse(MeetSession.validLink("http://teams.microsoft.com/meet/9341234567890"))
        XCTAssertFalse(MeetSession.validLink("https://teams.microsoft.com.evil.example/meet/9341234567890"))
        XCTAssertFalse(MeetSession.validLink("https://teams.microsoft.com/settings"))
        XCTAssertFalse(MeetSession.validLink("msteams://teams.microsoft.com/meet/9341234567890"))

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("nail-teams-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let fixedDate = Date(timeIntervalSince1970: 1_763_654_400)
        let untitledTeamsURL = NotulenExporter.sessionURL(
            title: "",
            meetLink: "https://teams.microsoft.com/meet/9341234567890?p=abc",
            startedAt: fixedDate,
            baseDir: tmpDir
        )
        XCTAssertTrue(untitledTeamsURL.lastPathComponent.hasSuffix("_teams-9341234567890.md"))

        let cloudTeamsURL = NotulenExporter.sessionURL(
            title: "",
            meetLink: "https://teams.cloud.microsoft/meet/9341234567890?p=abc",
            startedAt: fixedDate,
            baseDir: tmpDir
        )
        XCTAssertTrue(cloudTeamsURL.lastPathComponent.hasSuffix("_teams-9341234567890.md"))

        let titledTeamsURL = NotulenExporter.sessionURL(
            title: "Sprint Teams",
            meetLink: "https://teams.live.com/meet/9341234567890",
            startedAt: fixedDate,
            baseDir: tmpDir
        )
        XCTAssertTrue(titledTeamsURL.lastPathComponent.hasSuffix("_Sprint-Teams.md"))

        try NotulenExporter.writeSession(
            to: titledTeamsURL,
            title: "",
            meetLink: "https://teams.microsoft.com/meet/9341234567890?p=abc",
            startedAt: fixedDate,
            entries: [TranscriptEntry(kind: .command, text: "Nail, halo?")]
        )
        let md = try String(contentsOf: titledTeamsURL, encoding: .utf8)
        XCTAssertTrue(md.contains("# Rapat Microsoft Teams"))
        XCTAssertTrue(md.contains("Link Teams:"))
    }

    @MainActor
    func testAgyNeonModelAndCodexHandsFreePersistence() throws {
        XCTAssertTrue(VoiceSettings.agyModelOptions.contains("gemini-4-neon-low"))
        XCTAssertEqual(VoiceSettings.agyModelOptions.first, "gemini-4-neon-low")

        let suite = "dev.nail.tests.neon.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceSettings(defaults: defaults)
        XCTAssertEqual(settings.agyModel, "gemini-3.8-flash-low")
        XCTAssertTrue(settings.codexHandsFree)

        settings.agyModel = "gemini-4-neon-low"
        settings.codexHandsFree = false

        let reloaded = VoiceSettings(defaults: defaults)
        XCTAssertEqual(reloaded.agyModel, "gemini-4-neon-low")
        XCTAssertFalse(reloaded.codexHandsFree)

        let json = reloaded.encodedRuntimeConfig()
        let decoded = try JSONDecoder().decode(VoiceRuntimeConfig.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.agyModel, "gemini-4-neon-low")
        XCTAssertFalse(decoded.codexHandsFree)
    }

    @MainActor
    func testAppAppearanceHUDLayoutStyleAndNotulenDelete() throws {
        let suite = "dev.nail.tests.appearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceSettings(defaults: defaults)
        XCTAssertEqual(settings.appAppearance, .dark)
        XCTAssertEqual(settings.appAppearance.colorScheme, .dark)
        XCTAssertEqual(settings.hudLayoutStyle, .notch)

        settings.appAppearance = .light
        settings.hudLayoutStyle = .floatingPill
        var reloaded = VoiceSettings(defaults: defaults)
        XCTAssertEqual(reloaded.appAppearance, .light)
        XCTAssertEqual(reloaded.appAppearance.colorScheme, .light)
        XCTAssertEqual(reloaded.hudLayoutStyle, .floatingPill)

        settings.appAppearance = .system
        reloaded = VoiceSettings(defaults: defaults)
        XCTAssertEqual(reloaded.appAppearance, .system)
        XCTAssertNil(reloaded.appAppearance.colorScheme)

        defaults.set("invalid-appearance", forKey: "nail.ui.appAppearance")
        defaults.set("invalid-layout", forKey: "nail.hud.layoutStyle")
        let fallback = VoiceSettings(defaults: defaults)
        XCTAssertEqual(fallback.appAppearance, .dark)
        XCTAssertEqual(fallback.hudLayoutStyle, .notch)

        let visibleFrame = NSRect(x: 0, y: 40, width: 1512, height: 917)
        let centered = HUDPanel.floatingFrame(visibleFrame: visibleFrame, width: 240, height: 48, savedOrigin: nil)
        XCTAssertEqual(centered.midX, visibleFrame.midX)
        XCTAssertLessThan(centered.maxY, visibleFrame.maxY)
        XCTAssertGreaterThanOrEqual(centered.minY, visibleFrame.minY)
        XCTAssertEqual(centered.width, 240)
        XCTAssertEqual(centered.height, 48)

        let clampedLow = HUDPanel.floatingFrame(
            visibleFrame: visibleFrame,
            width: 240,
            height: 48,
            savedOrigin: NSPoint(x: -500, y: -200)
        )
        XCTAssertGreaterThanOrEqual(clampedLow.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(clampedLow.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(clampedLow.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(clampedLow.maxY, visibleFrame.maxY)

        let clampedHigh = HUDPanel.floatingFrame(
            visibleFrame: visibleFrame,
            width: 240,
            height: 48,
            savedOrigin: NSPoint(x: 5000, y: 5000)
        )
        XCTAssertGreaterThanOrEqual(clampedHigh.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(clampedHigh.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(clampedHigh.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(clampedHigh.maxY, visibleFrame.maxY)

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("nail-delete-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let mdURL = tmpDir.appendingPathComponent("meeting.md")
        let txtURL = tmpDir.appendingPathComponent("notes.txt")
        try "# Notulen".write(to: mdURL, atomically: true, encoding: .utf8)
        try "keep me".write(to: txtURL, atomically: true, encoding: .utf8)

        try NotulenExporter.deleteFile(at: mdURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mdURL.path))

        XCTAssertThrowsError(try NotulenExporter.deleteFile(at: txtURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: txtURL.path))
    }

    @MainActor
    func testHUDHideFromScreenShareDefaultAndPersistence() throws {
        let suite = "dev.nail.tests.stealth.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceSettings(defaults: defaults)
        XCTAssertTrue(settings.hudHideFromScreenShare)

        settings.hudHideFromScreenShare = false
        let disabled = VoiceSettings(defaults: defaults)
        XCTAssertFalse(disabled.hudHideFromScreenShare)

        settings.hudHideFromScreenShare = true
        let enabled = VoiceSettings(defaults: defaults)
        XCTAssertTrue(enabled.hudHideFromScreenShare)
    }

    @MainActor
    func testHUDPanelHostingViewDisablesConstraintSizingAndTransitionsSafely() throws {
        let panel = HUDPanel.shared
        defer { panel.hide() }

        XCTAssertFalse(panel.contentView is NSHostingView<HUDView>)

        let hostingView = panel.hostingView
        XCTAssertTrue(hostingView.sizingOptions.isEmpty)
        XCTAssertTrue(hostingView.safeAreaRegions.isEmpty)
        XCTAssertTrue(hostingView.sceneBridgingOptions.isEmpty)
        XCTAssertEqual(
            hostingView.intrinsicContentSize,
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        )
        XCTAssertTrue(hostingView.translatesAutoresizingMaskIntoConstraints)

        panel.show()
        let sequence: [HUDDisplayMode] = [.commandTray, .collapsed, .liveActivity, .commandTray, .collapsed]
        for _ in 0..<3 {
            for mode in sequence {
                panel.setDisplayMode(mode)
                panel.layoutIfNeeded()
                panel.displayIfNeeded()
                CATransaction.flush()
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            }
        }
        panel.refreshLayout()
        panel.setDisplayMode(.collapsed)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    }

    @MainActor
    func testFloatingDynamicIslandDefaultsToTopCenterAndStaysCenteredOnResize() throws {
        let visibleFrame = NSRect(x: 0, y: 40, width: 1512, height: 900)
        let collapsed = HUDPanel.floatingFrame(
            visibleFrame: visibleFrame,
            width: 78,
            height: 56,
            savedOrigin: nil
        )
        XCTAssertEqual(collapsed.midX, visibleFrame.midX)
        XCTAssertEqual(collapsed.maxY, visibleFrame.maxY - 2)

        let expanded = HUDPanel.floatingFrame(
            visibleFrame: visibleFrame,
            width: 344,
            height: 90,
            savedOrigin: nil
        )
        XCTAssertEqual(expanded.midX, visibleFrame.midX)
        XCTAssertEqual(expanded.maxY, visibleFrame.maxY - 2)

        let suite = "dev.nail.tests.floating.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceSettings(defaults: defaults)
        settings.hudLayoutStyle = .floatingPill
        settings.hudSize = .standard

        let metrics = NotchMetrics()
        let standbyCard = HUDPanel.cardSize(
            for: .collapsed,
            metrics: metrics,
            settings: settings,
            meet: MeetSession.shared
        )
        XCTAssertEqual(standbyCard, CGSize(width: 46, height: 36))
        XCTAssertLessThan(standbyCard.width / standbyCard.height, 1.35)

        let hoverCard = HUDPanel.cardSize(
            for: .commandTray,
            metrics: metrics,
            settings: settings,
            meet: MeetSession.shared
        )
        XCTAssertEqual(hoverCard, CGSize(width: 148, height: 188))
    }

    func testAppBundleConfiguresNokoOwlAppIcon() throws {
        let appBundle = Bundle.main
        XCTAssertEqual(appBundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String, "AppIcon")

        let iconURL = try XCTUnwrap(appBundle.url(forResource: "AppIcon", withExtension: "icns"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))

        let iconImage = try XCTUnwrap(NSImage(contentsOf: iconURL))
        XCTAssertGreaterThan(iconImage.size.width, 0)
        XCTAssertGreaterThan(iconImage.size.height, 0)
    }

    @MainActor
    func testNokoOwlBrandMenuBarImageAndBotFaceInstantiation() throws {
        let idleImage = NailBrandLogo.menuBarTemplateImage(isActive: false)
        XCTAssertTrue(idleImage.isTemplate)
        XCTAssertGreaterThan(idleImage.size.width, 0)
        XCTAssertGreaterThan(idleImage.size.height, 0)
        XCTAssertNotNil(idleImage.tiffRepresentation)

        let activeImage = NailBrandLogo.menuBarTemplateImage(isActive: true)
        XCTAssertTrue(activeImage.isTemplate)
        XCTAssertGreaterThan(activeImage.size.width, 0)
        XCTAssertGreaterThan(activeImage.size.height, 0)
        XCTAssertNotNil(activeImage.tiffRepresentation)

        let allMoods: [NailBotMood] = [
            .standby,
            .listening,
            .processing,
            .speaking,
            .interrupted,
            .error,
        ]
        let allForms: [NailBotForm] = [.miniEyes, .fullFace]

        for form in allForms {
            for mood in allMoods {
                let faceView = NailBotFaceView(
                    mood: mood,
                    form: form,
                    phase: 1.25,
                    speakingEnergy: 0.7,
                    listeningEnergy: 0.6,
                    isPaused: true
                )
                XCTAssertEqual(faceView.mood, mood)
                XCTAssertEqual(faceView.form, form)

                let hosting = NSHostingView(rootView: faceView)
                let size = hosting.fittingSize
                XCTAssertGreaterThan(size.width, 0, "Expected non-zero width for \(form)/\(mood)")
                XCTAssertGreaterThan(size.height, 0, "Expected non-zero height for \(form)/\(mood)")
            }
        }
    }

    @MainActor
    func testH4BoxlessFloatingNokoGeometryPreviewStageAndCompanionStage() throws {
        let suite = "dev.nail.tests.h4.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceSettings(defaults: defaults)
        let metrics = NotchMetrics()

        settings.hudLayoutStyle = .floatingPill
        settings.hudSize = .standard
        let liveActivitySize = HUDPanel.cardSize(
            for: .liveActivity,
            metrics: metrics,
            settings: settings,
            meet: MeetSession.shared
        )
        XCTAssertEqual(liveActivitySize, CGSize(width: 148, height: 154))

        settings.hudLayoutStyle = .notch
        metrics.hasHardwareNotch = true
        metrics.hardwareNotchWidth = 190
        metrics.notchHeight = 34
        let hardwareNotchCollapsed = HUDPanel.cardSize(
            for: .collapsed,
            metrics: metrics,
            settings: settings,
            meet: MeetSession.shared
        )
        XCTAssertEqual(hardwareNotchCollapsed, CGSize(width: 282, height: 34))

        metrics.hasHardwareNotch = false
        metrics.hardwareNotchWidth = 0
        metrics.notchHeight = 34
        let nonNotchCollapsed = HUDPanel.cardSize(
            for: .collapsed,
            metrics: metrics,
            settings: settings,
            meet: MeetSession.shared
        )
        XCTAssertEqual(nonNotchCollapsed, CGSize(width: 58, height: 34))

        let processingStage: HUDPreviewStage = .processing
        metrics.previewStage = processingStage
        XCTAssertEqual(metrics.previewStage, .processing)

        let allMoods: [NailBotMood] = [
            .standby,
            .listening,
            .processing,
            .speaking,
            .interrupted,
            .error,
        ]
        for mood in allMoods {
            let stage = NokoFloatingCompanionStage(
                mood: mood,
                phase: 1.25,
                speakingEnergy: 0.7,
                listeningEnergy: 0.6,
                isPaused: true
            )
            XCTAssertEqual(stage.mood, mood)

            let hosting = NSHostingView(rootView: stage)
            let size = hosting.fittingSize
            XCTAssertGreaterThan(size.width, 0, "Expected non-zero stage width for \(mood)")
            XCTAssertGreaterThan(size.height, 0, "Expected non-zero stage height for \(mood)")
        }
    }

    @MainActor
    func testElevenLabsDefaultsPersistenceAndInvalidFallbacks() throws {
        XCTAssertEqual(
            VoiceSettings.elevenLabsModelOptions,
            ["eleven_flash_v2_5", "eleven_multilingual_v2"]
        )

        let suite = "dev.nail.tests.elevenlabs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceSettings(defaults: defaults)
        XCTAssertEqual(settings.ttsEngine, .edge)
        XCTAssertEqual(settings.elevenLabsModel, "eleven_flash_v2_5")
        XCTAssertEqual(settings.elevenLabsVoiceId, "EXAVITQu4vr4xnSDxMaL")
        XCTAssertEqual(settings.elevenLabsVoiceName, "Sarah")

        settings.ttsEngine = .elevenlabs
        settings.elevenLabsModel = "eleven_multilingual_v2"
        settings.elevenLabsVoiceId = "21m00Tcm4TlvDq8ikWAM"
        settings.elevenLabsVoiceName = "Rachel"

        let reloaded = VoiceSettings(defaults: defaults)
        XCTAssertEqual(reloaded.ttsEngine, .elevenlabs)
        XCTAssertEqual(reloaded.elevenLabsModel, "eleven_multilingual_v2")
        XCTAssertEqual(reloaded.elevenLabsVoiceId, "21m00Tcm4TlvDq8ikWAM")
        XCTAssertEqual(reloaded.elevenLabsVoiceName, "Rachel")

        let json = reloaded.encodedRuntimeConfig()
        let decoded = try JSONDecoder().decode(VoiceRuntimeConfig.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.ttsEngine, "elevenlabs")
        XCTAssertEqual(decoded.elevenLabsModel, "eleven_multilingual_v2")
        XCTAssertEqual(decoded.elevenLabsVoiceId, "21m00Tcm4TlvDq8ikWAM")
        XCTAssertEqual(decoded.elevenLabsVoiceName, "Rachel")

        defaults.set("invalid-engine", forKey: "nail.voice.ttsEngine")
        defaults.set("unknown_model", forKey: "nail.voice.elevenLabsModel")
        defaults.set("   ", forKey: "nail.voice.elevenLabsVoiceId")
        defaults.set("", forKey: "nail.voice.elevenLabsVoiceName")
        let fallback = VoiceSettings(defaults: defaults)
        XCTAssertEqual(fallback.ttsEngine, .edge)
        XCTAssertEqual(fallback.elevenLabsModel, "eleven_flash_v2_5")
        XCTAssertEqual(fallback.elevenLabsVoiceId, "EXAVITQu4vr4xnSDxMaL")
        XCTAssertEqual(fallback.elevenLabsVoiceName, "Sarah")
    }

    func testVoiceRuntimeConfigLegacyJSONBackwardsCompatibility() throws {
        let legacyJSON = """
        {
          "agyModel": "gemini-3.8-flash-low",
          "whisperModel": "small",
          "ttsVoice": "id-ID-GadisNeural",
          "ttsRate": 185,
          "codexVoice": "cove",
          "speakingStyle": "casual",
          "listeningMode": "standby",
          "disclosure": true
        }
        """
        let decoded = try JSONDecoder().decode(VoiceRuntimeConfig.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.agyModel, "gemini-3.8-flash-low")
        XCTAssertEqual(decoded.whisperModel, "small")
        XCTAssertEqual(decoded.ttsVoice, "id-ID-GadisNeural")
        XCTAssertEqual(decoded.ttsRate, 185)
        XCTAssertTrue(decoded.codexHandsFree)
        XCTAssertFalse(decoded.presentationReadingEnabled)
        XCTAssertEqual(decoded.ttsEngine, "edge")
        XCTAssertEqual(decoded.elevenLabsModel, "eleven_flash_v2_5")
        XCTAssertEqual(decoded.elevenLabsVoiceId, "EXAVITQu4vr4xnSDxMaL")
        XCTAssertEqual(decoded.elevenLabsVoiceName, "Sarah")
    }

    func testTTSVoiceCatalogElevenLabsHelpersAndArgumentBuilders() throws {
        let expectedPresets: [(String, String)] = [
            ("EXAVITQu4vr4xnSDxMaL", "Sarah"),
            ("21m00Tcm4TlvDq8ikWAM", "Rachel"),
            ("CwhRBWXzGAHq8TQ4Fs17", "Roger"),
            ("JBFqnCBsd6RMkjVDRZzb", "George"),
            ("9BWtsMINqrJLrRacOk9x", "Aria"),
        ]
        XCTAssertEqual(
            TTSVoiceCatalog.curatedElevenLabsVoices.map { [$0.voiceId, $0.name] },
            expectedPresets.map { [$0.0, $0.1] }
        )

        XCTAssertEqual(
            TTSVoiceCatalog.elevenLabsModelDisplayName(for: "eleven_flash_v2_5"),
            "Flash v2.5 · 0,5 kredit/karakter"
        )
        XCTAssertEqual(
            TTSVoiceCatalog.elevenLabsModelDisplayName(for: "eleven_multilingual_v2"),
            "Multilingual v2 · 1 kredit/karakter"
        )
        XCTAssertEqual(TTSVoiceCatalog.elevenLabsModelDisplayName(for: "custom_v1"), "custom_v1")

        let voicesJSON = """
        {
          "voices": [
            {"voice_id": "EXAVITQu4vr4xnSDxMaL", "name": "Sarah", "category": "premade"},
            {"voice_id": "EXAVITQu4vr4xnSDxMaL", "name": "Duplicate Sarah", "category": "premade"},
            {"voice_id": " ", "name": "Blank"},
            {"voice_id": "21m00Tcm4TlvDq8ikWAM", "name": "Rachel", "category": "cloned"}
          ]
        }
        """
        let voices = try TTSVoiceCatalog.parseElevenLabsVoices(data: Data(voicesJSON.utf8))
        XCTAssertEqual(voices.count, 2)
        XCTAssertEqual(voices[0], ElevenLabsVoice(voiceId: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", category: "premade"))
        XCTAssertEqual(voices[1], ElevenLabsVoice(voiceId: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", category: "cloned"))

        let subJSON = """
        {
          "character_count": 1250,
          "character_limit": 10000,
          "tier": "free",
          "next_character_count_reset_unix": 1765000000
        }
        """
        let sub = try TTSVoiceCatalog.parseElevenLabsSubscription(data: Data(subJSON.utf8))
        XCTAssertEqual(sub.characterCount, 1250)
        XCTAssertEqual(sub.characterLimit, 10000)
        XCTAssertEqual(sub.remainingCharacters, 8750)
        XCTAssertEqual(sub.tier, "free")

        let overLimitJSON = #"{"character_count": 12000, "character_limit": 10000}"#
        let overLimit = try TTSVoiceCatalog.parseElevenLabsSubscription(data: Data(overLimitJSON.utf8))
        XCTAssertEqual(overLimit.remainingCharacters, 0)

        let args = TTSVoiceCatalog.buildSpeakTextArguments(
            scriptPath: "/tmp/agy-voice.py",
            text: "Halo",
            replyWavPath: "/tmp/out.wav",
            voice: "id-ID-GadisNeural",
            rate: 185,
            ttsEngine: .elevenlabs,
            elevenLabsVoiceId: "21m00Tcm4TlvDq8ikWAM",
            elevenLabsModel: "eleven_multilingual_v2"
        )
        XCTAssertTrue(args.contains("--tts-engine"))
        XCTAssertTrue(args.contains("elevenlabs"))
        XCTAssertTrue(args.contains("--elevenlabs-voice-id"))
        XCTAssertTrue(args.contains("21m00Tcm4TlvDq8ikWAM"))
        XCTAssertTrue(args.contains("--elevenlabs-model"))
        XCTAssertTrue(args.contains("eleven_multilingual_v2"))
        XCTAssertFalse(args.contains("secret-api-key"))

        let elevenEnv = TTSVoiceCatalog.buildPreviewEnvironment(
            base: ["PATH": "/usr/bin"],
            ttsEngine: .elevenlabs,
            apiKeyLoader: { "xi-test-key" }
        )
        XCTAssertEqual(elevenEnv["ELEVENLABS_API_KEY"], "xi-test-key")

        let edgeEnv = TTSVoiceCatalog.buildPreviewEnvironment(
            base: ["PATH": "/usr/bin", "ELEVENLABS_API_KEY": "stale-key"],
            ttsEngine: .edge,
            apiKeyLoader: { "xi-test-key" }
        )
        XCTAssertNil(edgeEnv["ELEVENLABS_API_KEY"])
    }

    func testElevenLabsAPIClientHeadersAndErrorHandling() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockElevenLabsURLProtocol.self]
        let session = URLSession(configuration: config)

        MockElevenLabsURLProtocol.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "xi-mock-123")
            let url = try XCTUnwrap(request.url)
            if url.path == "/v1/voices" {
                let body = Data(#"{"voices":[{"voice_id":"EXAVITQu4vr4xnSDxMaL","name":"Sarah"}]}"#.utf8)
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, body)
            }
            if url.path == "/v1/user/subscription" {
                let body = Data(#"{"character_count":400,"character_limit":10000,"tier":"free"}"#.utf8)
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, body)
            }
            XCTFail("Unexpected URL: \(url)")
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let voices = try await TTSVoiceCatalog.fetchElevenLabsVoices(apiKey: "  xi-mock-123  ", session: session)
        XCTAssertEqual(voices.map(\.name), ["Sarah"])

        let sub = try await TTSVoiceCatalog.fetchElevenLabsSubscription(apiKey: "xi-mock-123", session: session)
        XCTAssertEqual(sub.remainingCharacters, 9600)

        do {
            _ = try await TTSVoiceCatalog.fetchElevenLabsVoices(apiKey: "   ", session: session)
            XCTFail("Expected missingAPIKey error")
        } catch let error as ElevenLabsAPIError {
            XCTAssertEqual(error, .missingAPIKey)
        }

        MockElevenLabsURLProtocol.setHandler { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"detail":{"message":"Invalid API key"}}"#.utf8))
        }
        do {
            _ = try await TTSVoiceCatalog.fetchElevenLabsSubscription(apiKey: "bad-key", session: session)
            XCTFail("Expected invalidAPIKey error")
        } catch let error as ElevenLabsAPIError {
            XCTAssertEqual(error, .invalidAPIKey)
        }
    }

    @MainActor
    func testMeetSessionWorkerEnvironmentInjectsElevenLabsKeyOnlyWhenActive() throws {
        let suite = "dev.nail.tests.meetenv.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = VoiceSettings(defaults: defaults)
        settings.provider = .antigravity
        settings.ttsEngine = .elevenlabs

        let envWithKey = MeetSession.buildWorkerEnvironment(
            base: [:],
            settings: settings,
            apiKeyLoader: { "xi-secret-value" }
        )
        XCTAssertEqual(envWithKey["ELEVENLABS_API_KEY"], "xi-secret-value")
        let configJSON = try XCTUnwrap(envWithKey["NAIL_VOICE_CONFIG"])
        XCTAssertFalse(configJSON.contains("xi-secret-value"))

        settings.ttsEngine = .edge
        let envEdge = MeetSession.buildWorkerEnvironment(
            base: ["ELEVENLABS_API_KEY": "stale"],
            settings: settings,
            apiKeyLoader: { "xi-secret-value" }
        )
        XCTAssertNil(envEdge["ELEVENLABS_API_KEY"])

        settings.provider = .codex
        settings.ttsEngine = .elevenlabs
        let envCodex = MeetSession.buildWorkerEnvironment(
            base: ["ELEVENLABS_API_KEY": "stale"],
            settings: settings,
            apiKeyLoader: { "xi-secret-value" }
        )
        XCTAssertNil(envCodex["ELEVENLABS_API_KEY"])
    }
}

private final class MockElevenLabsHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    func set(_ newHandler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    func get() -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}

private final class MockElevenLabsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handlerBox = MockElevenLabsHandlerBox()

    static func setHandler(_ newHandler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        handlerBox.set(newHandler)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let current = Self.handlerBox.get() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try current(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
