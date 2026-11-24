import Darwin
import Foundation
import Observation
import Vision

enum PresentationOCR {
    static func recognize(_ image: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(data: image)
        do {
            try handler.perform([request])
        } catch {
            request.usesCPUOnly = true
            try handler.perform([request])
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

enum MeetingPlatform: String, Codable, Sendable {
    case googleMeet
    case microsoftTeams

    var label: String {
        switch self {
        case .googleMeet: "Google Meet"
        case .microsoftTeams: "Microsoft Teams"
        }
    }
}

enum SessionVisualState: Equatable, Sendable {
    case idle
    case standby
    case active
    case followUp
    case interrupted
    case error
}

enum SessionPresentation: Equatable, Sendable {
    case ready, signingIn, joining, standby, listening, processing, speaking, finishing, finished, interrupted, error

    static func phase(for event: String) -> SessionPresentation? {
        switch event {
        case "joined", "voice-standby", "voice-followup": .standby
        case "voice-recording": .listening
        case "voice-processing", "voice-codex-connecting", "voice-codex-listening", "voice-codex-heard", "voice-codex-delegating": .processing
        case "voice-sending": .speaking
        case "left": .finishing
        case let event where event.hasPrefix("voice-result "): .standby
        case let event where event.hasPrefix("voice-wake "): .processing
        default: nil
        }
    }

    var label: String {
        switch self {
        case .ready: "Siap"
        case .signingIn: "Login Google"
        case .joining: "Bergabung"
        case .standby: "Siaga"
        case .listening: "Menyimak"
        case .processing: "Menyiapkan jawaban"
        case .speaking: "Berbicara"
        case .finishing: "Menyelesaikan"
        case .finished: "Selesai"
        case .interrupted: "Suara dipotong"
        case .error: "Gangguan"
        }
    }

    var symbol: String {
        switch self {
        case .ready, .finished: "checkmark.circle"
        case .signingIn: "person.crop.circle"
        case .joining: "arrow.triangle.2.circlepath"
        case .standby: "waveform.circle"
        case .listening: "ear"
        case .processing: "ellipsis.circle"
        case .speaking: "speaker.wave.2"
        case .finishing: "hourglass"
        case .interrupted: "speaker.slash"
        case .error: "exclamationmark.triangle"
        }
    }

    static func isActivelyListening(
        presentation: SessionPresentation,
        visualState: SessionVisualState,
        voiceBusy: Bool,
        isSpeaking: Bool
    ) -> Bool {
        guard !isSpeaking else { return false }
        return presentation == .listening
            || visualState == .followUp
            || (voiceBusy && presentation != .processing && presentation != .speaking)
    }

    static func dialHeadline(
        presentation: SessionPresentation,
        visualState: SessionVisualState,
        voiceBusy: Bool
    ) -> String {
        switch presentation {
        case .listening:
            return "Nail mendengarkan…"
        case .processing:
            return "Menyiapkan jawaban…"
        case .speaking:
            return "Nail berbicara…"
        case .joining:
            return "Bergabung ke rapat…"
        case .signingIn:
            return "Login Google…"
        case .interrupted:
            return "Suara dipotong"
        case .error:
            return "Gangguan sesi"
        case .standby:
            return (voiceBusy || visualState == .followUp) ? "Nail mendengarkan…" : "Nail siaga"
        case .ready:
            return "Nail siap"
        case .finishing:
            return "Menutup sesi…"
        case .finished:
            return "Sesi selesai"
        }
    }
}

private struct VoiceResultPayload: Decodable {
    let heard: String?
    let reply: String?
    let heardAtMs: Double?
    let replyAtMs: Double?
    let latencyMs: Double?
}

struct LiveVoiceTranscript: Decodable, Equatable {
    var heard: String?
    var reply: String?
}

private struct MeetingLinePayload: Decodable {
    let text: String
    let speaker: String?
    let timestampMs: Double?
}

private struct PresentationOCRRequest: Decodable {
    let id: UUID
    let image: Data
}

private struct PresentationOCRResponse: Encodable {
    let id: UUID
    let text: String?
    let error: String?
}

@MainActor @Observable
final class MeetSession {
    static let shared = MeetSession()

    private(set) var active = false
    private(set) var joiningMeeting = false
    private(set) var browserWindowVisible = false
    private(set) var status = ""
    private(set) var visualState: SessionVisualState = .idle
    private var lastErrorAt: Date?
    private var presentationPhase: SessionPresentation = .ready
    var presentation: SessionPresentation {
        if visualState == .error { return .error }
        if visualState == .interrupted { return .interrupted }
        return presentationPhase
    }
    private(set) var voiceReady = false
    private(set) var voiceBusy = false
    private(set) var isSpeaking = false
    var isActivelyListening: Bool {
        SessionPresentation.isActivelyListening(
            presentation: presentation,
            visualState: visualState,
            voiceBusy: voiceBusy,
            isSpeaking: isSpeaking
        )
    }
    private(set) var voiceTranscript = ""
    private(set) var voiceReply = ""
    private(set) var liveVoice = LiveVoiceTranscript()
    private(set) var lastHeardAt: Date?
    private(set) var lastReplyAt: Date?
    private(set) var lastLatencySeconds: Double?
    private(set) var currentNotulenURL: URL?
    private(set) var notulenError = ""
    private(set) var currentMeetingTitle = ""
    private(set) var currentMeetingLink = ""
    private(set) var sessionStartedAt: Date?

    let transcriptStore = SessionTranscriptStore()

    private var activeProvider: VoiceProvider?
    private(set) var activePlatform: MeetingPlatform?
    private var activeMode: ListeningMode = .standby
    private var input: FileHandle?
    private var workerProcess: Process?
    private var lastWorkerExitNormal = true
    private var leaveRequested = false
    private var leaveTerminationTask: Task<Void, Never>?
    private(set) var meetingAvatarAvailable = false
    private var avatarRequest = MeetingAvatarRequest()
    var meetingAvatarState: MeetingAvatarState { avatarRequest.state }
    var meetingAvatarRequested: Bool { avatarRequest.enabled }
    @ObservationIgnored private let avatarTransport = MeetAvatarTransport()
    @ObservationIgnored private var avatarDirectory: URL?
    @ObservationIgnored private var avatarRender: Task<Void, Never>?
    @ObservationIgnored private var avatarSpeech = AvatarSpeechEnvelope()
    @ObservationIgnored private var avatarLastTurn: UInt64 = 0

    nonisolated static func shouldPreserveErrorStatus(
        visualState: SessionVisualState,
        lastErrorAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard visualState == .error, let lastErrorAt else { return false }
        return now.timeIntervalSince(lastErrorAt) < 4.0
    }

    nonisolated static func shouldMarkNotulenInterrupted(
        leaveRequested: Bool,
        lastWorkerExitNormal: Bool,
        exitCode: Int32
    ) -> Bool {
        !leaveRequested && !lastWorkerExitNormal && exitCode != 0
    }

    nonisolated static func detectPlatform(_ text: String) -> MeetingPlatform? {
        if text.wholeMatch(of: #/https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}/#) != nil {
            return .googleMeet
        }
        guard let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else {
            return nil
        }
        let path = components.path
        if host == "teams.microsoft.com",
           path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/")
            || path.hasPrefix("/dl/launcher/") || path.hasPrefix("/v2/") {
            return .microsoftTeams
        }
        if host == "teams.live.com" || host == "teams.cloud.microsoft",
           path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/")
            || path.hasPrefix("/dl/launcher/") || path.hasPrefix("/v2/") {
            return .microsoftTeams
        }
        return nil
    }

    nonisolated static func validLink(_ text: String) -> Bool {
        detectPlatform(text) != nil
    }

    func join(_ text: String, title: String = "", settings: VoiceSettings = .shared) {
        guard !active else { return }
        let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let platform = Self.detectPlatform(link) else {
            visualState = .error
            status = "Tempel link Google Meet atau Microsoft Teams yang valid."
            return
        }
        activePlatform = platform
        currentMeetingTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        currentMeetingLink = link
        sessionStartedAt = Date()
        currentNotulenURL = nil
        launch(link, settings: settings)
    }

    func signIn() {
        launch("--login", settings: nil)
    }

    func answerMeeting() {
        guard voiceReady, let input else { return }
        presentationPhase = .listening
        do {
            try input.write(contentsOf: Data("voice-turn\n".utf8))
            voiceBusy = true
            lastErrorAt = nil
        visualState = .active
            status = "Menyimak audio Meet sekarang…"
        } catch {
            visualState = .error
            status = "Tidak dapat mengirim perintah suara ke Nail."
        }
    }

    func interrupt() {
        guard active else { return }
        guard let input else { return }
        try? input.write(contentsOf: Data("interrupt\n".utf8))
        avatarSpeech.stop(throughTurn: avatarLastTurn)
        avatarTransport.clearPending()
        voiceBusy = false
        isSpeaking = false
        visualState = .interrupted
        status = "Suara Nail dipotong (Panic Mute)."
    }

    func setListeningMode(_ mode: ListeningMode) {
        activeMode = mode
        if mode == .notulen {
            persistNotulen()
        }
        guard active, let input else { return }
        try? input.write(contentsOf: Data("mode \(mode.rawValue)\n".utf8))
    }

    func setPresentationReading(_ enabled: Bool) {
        guard active, let input else { return }
        try? input.write(contentsOf: Data("presentation-reading \(enabled ? "on" : "off")\n".utf8))
    }

    func toggleBrowserWindow() {
        guard joiningMeeting, let input else { return }
        try? input.write(contentsOf: Data("toggle-window\n".utf8))
    }

    func setMeetingAvatarEnabled(_ enabled: Bool) {
        guard meetingAvatarAvailable, let input, !leaveRequested else { return }
        if !enabled { stopAvatarRendering() }
        avatarRequest.request(enabled)
        let revision = avatarRequest.revision
        guard avatarDirectory != nil else {
            avatarRequest.confirm(.unavailable, revision: revision)
            return
        }
        do {
            try input.write(contentsOf: Data("avatar-set {\"revision\":\(revision),\"enabled\":\(enabled)}\n".utf8))
        } catch {
            failMeetingAvatar()
        }
    }

    private func stopAvatarRendering() {
        avatarRender?.cancel()
        avatarRender = nil
        avatarTransport.clearPending()
        avatarSpeech = AvatarSpeechEnvelope()
        avatarLastTurn = 0
    }

    private func clearMeetingAvatar() {
        meetingAvatarAvailable = false
        avatarRequest = MeetingAvatarRequest()
        stopAvatarRendering()
        avatarTransport.close()
        if let directory = avatarDirectory {
            try? FileManager.default.removeItem(at: directory)
            avatarDirectory = nil
        }
    }

    private func failMeetingAvatar() {
        guard avatarRequest.enabled else { return }
        let revision = avatarRequest.revision
        stopAvatarRendering()
        avatarTransport.close()
        avatarRequest.confirm(.unavailable, revision: revision)
        try? input?.write(contentsOf: Data("avatar-fail \(revision)\n".utf8))
    }

    private func startAvatarRendering(revision: UInt32) {
        guard let directory = avatarDirectory else {
            failMeetingAvatar()
            return
        }
        stopAvatarRendering()
        avatarTransport.onFailure = { [weak self] in self?.failMeetingAvatar() }
        avatarTransport.connect(path: directory.appendingPathComponent("frames").path)
        avatarRender = Task { @MainActor [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self, self.avatarRequest.enabled, self.avatarRequest.revision == revision else { return }
                let time = ProcessInfo.processInfo.systemUptime
                let phase = time - started
                let blink = phase.truncatingRemainder(dividingBy: 3.8)
                let blinkScale = 1 - 0.86 * max(0, 1 - abs(blink - 3.45) / 0.14)
                let mood = NailBotMood.forSession(
                    self.presentation,
                    visualState: self.visualState,
                    isSpeaking: self.isSpeaking,
                    isActivelyListening: self.isActivelyListening,
                    hasNotesError: !self.notulenError.isEmpty
                )
                let frame = MeetAvatarFrame(
                    mood: mood,
                    phase: phase,
                    speakingEnergy: mood == .speaking ? self.avatarSpeech.energy(at: time) : 0,
                    listeningEnergy: mood == .listening ? 0.7 : 0,
                    pose: .init(blinkScaleY: blinkScale, glanceX: 0)
                )
                guard let jpeg = MeetAvatarRenderer.renderJPEG(frame) else {
                    self.failMeetingAvatar()
                    return
                }
                self.avatarTransport.offer(revision: revision, jpeg: jpeg)
                let remaining = max(0.001, 0.05 - (ProcessInfo.processInfo.systemUptime - time))
                try? await Task.sleep(for: .seconds(remaining))
            }
        }
    }

    func leave() {
        guard active || workerProcess != nil else { return }
        let forceImmediate = leaveRequested
        leaveRequested = true
        meetingAvatarAvailable = false
        stopAvatarRendering()
        avatarTransport.close()
        if joiningMeeting { presentationPhase = .finishing }
        voiceReady = false
        isSpeaking = false
        voiceBusy = false
        status = forceImmediate ? "Menghentikan sesi Meet…" : "Menutup sesi Meet…"
        if let input {
            try? input.close()
            self.input = nil
        }
        guard let proc = workerProcess else { return }
        leaveTerminationTask?.cancel()
        leaveTerminationTask = Task { @MainActor [weak self] in
            if !forceImmediate {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
            }
            if proc.isRunning {
                proc.terminate()
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if let self, self.workerProcess === proc, !proc.isRunning {
                self.finished(exitCode: proc.terminationStatus)
            }
        }
    }

    static func buildWorkerEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        settings: VoiceSettings,
        apiKeyLoader: () -> String? = { ElevenLabsKeychain.load() }
    ) -> [String: String] {
        var env = base
        env["NAIL_VOICE_CONFIG"] = settings.encodedRuntimeConfig()
        if settings.provider == .antigravity,
           settings.ttsEngine == .elevenlabs,
           let apiKey = apiKeyLoader()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            env["ELEVENLABS_API_KEY"] = apiKey
        } else {
            env.removeValue(forKey: "ELEVENLABS_API_KEY")
        }
        return env
    }

    private func launch(_ target: String, settings: VoiceSettings?) {
        guard !active else { return }
        let bundle = Bundle.main.bundleURL
        let runtime = bundle.appendingPathComponent("Contents/Frameworks/Electron.app/Contents/MacOS/Electron")
        let worker = bundle.appendingPathComponent("Contents/Resources/meet.cjs")
        guard FileManager.default.isExecutableFile(atPath: runtime.path),
              FileManager.default.isReadableFile(atPath: worker.path) else {
            visualState = .error
            status = "Runtime Electron / meet.cjs belum terpasang di Meet Nail.app."
            return
        }

        let profile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nail/Meet Chromium")
        let process = Process()
        let pipe = Pipe()
        let stderrPipe = Pipe()
        let commands = Pipe()
        process.executableURL = runtime

        var args = [worker.path, target, profile.path]
        if let settings {
            let provider = settings.provider
            args.append(provider.rawValue)
            switch provider {
            case .antigravity:
                let script = bundle.appendingPathComponent("Contents/Resources/agy-voice.py")
                args.append(script.path)
            case .deepseek:
                let script = bundle.appendingPathComponent("Contents/Resources/nail-loop.py")
                args.append(script.path)
            case .codex:
                break
            }
            var environment = Self.buildWorkerEnvironment(settings: settings)
            environment.removeValue(forKey: "NAIL_AVATAR_SOCKET_PATH")
            if activePlatform == .googleMeet {
                var template = Array("/tmp/nail-avatar-XXXXXX".utf8CString)
                if mkdtemp(&template) != nil {
                    let directory = URL(fileURLWithPath: String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self), isDirectory: true)
                    avatarDirectory = directory
                    environment["NAIL_AVATAR_SOCKET_PATH"] = directory.appendingPathComponent("frames").path
                }
            }
            process.environment = environment
            activeProvider = provider
            activeMode = settings.listeningMode
        } else {
            activeProvider = nil
        }

        process.arguments = args
        process.standardInput = commands
        process.standardOutput = pipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            clearMeetingAvatar()
            visualState = .error
            status = "Chromium Nail tidak bisa dijalankan."
            return
        }

        leaveTerminationTask?.cancel()
        leaveTerminationTask = nil
        leaveRequested = false
        workerProcess = process
        input = commands.fileHandleForWriting
        voiceTranscript = ""
        voiceReply = ""
        liveVoice = LiveVoiceTranscript()
        lastHeardAt = nil
        lastReplyAt = nil
        lastLatencySeconds = nil
        transcriptStore.clear()
        notulenError = ""
        active = true
        presentationPhase = target == "--login" ? .signingIn : .joining
        browserWindowVisible = false
        lastWorkerExitNormal = false
        joiningMeeting = target != "--login"
        if !joiningMeeting {
            activePlatform = nil
            currentMeetingTitle = ""
            currentMeetingLink = ""
            sessionStartedAt = nil
            currentNotulenURL = nil
        }
        lastErrorAt = nil
        visualState = .active
        status = joiningMeeting
            ? (activePlatform == .microsoftTeams ? "Membuka Microsoft Teams (tamu)…" : "Membuka Google Meet…")
            : "Membuka login Google…"
        if joiningMeeting {
            HUDPanel.shared.show()
        }

        let stderrReader = stderrPipe.fileHandleForReading
        Task.detached {
            let maxLogBytes = 256 * 1024
            var written = 0
            let logsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Nail", isDirectory: true)
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let logURL = logsDir.appendingPathComponent("electron-stderr.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let logHandle = try? FileHandle(forWritingTo: logURL)
            defer {
                try? stderrReader.close()
                try? logHandle?.close()
            }
            while true {
                let data = stderrReader.availableData
                if data.isEmpty { break }
                if let logHandle, written < maxLogBytes {
                    let remaining = maxLogBytes - written
                    let chunk = data.count <= remaining ? data : data.prefix(remaining)
                    try? logHandle.write(contentsOf: chunk)
                    written += chunk.count
                }
            }
        }

        let reader = pipe.fileHandleForReading
        Task.detached { [weak self] in
            var pending = Data()
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                pending.append(data)
                while let newline = pending.firstIndex(of: 10) {
                    let event = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    await self?.receive(event)
                }
            }
            process.waitUntilExit()
            await self?.finished(exitCode: process.terminationStatus)
        }
    }

    private func receive(_ event: String) {
        if event.hasPrefix("voice-preview ") {
            if let update = try? JSONDecoder().decode(
                LiveVoiceTranscript.self,
                from: Data(event.dropFirst("voice-preview ".count).utf8)
            ) {
                if let heard = update.heard { liveVoice.heard = heard }
                if let reply = update.reply { liveVoice.reply = reply }
            }
            return
        }
        if event == "voice-preview-end" || event == "voice-interrupted" || event.hasPrefix("voice-result ") {
            liveVoice = LiveVoiceTranscript()
        }
        if event.hasPrefix("avatar-state ") {
            struct Payload: Decodable {
                let revision: UInt32
                let state: MeetingAvatarState
            }
            if meetingAvatarAvailable,
               let payload = try? JSONDecoder().decode(Payload.self, from: Data(event.dropFirst("avatar-state ".count).utf8)),
               avatarRequest.confirm(payload.state, revision: payload.revision) {
                switch payload.state {
                case .starting: startAvatarRendering(revision: payload.revision)
                case .stopping, .off, .unavailable: stopAvatarRendering()
                case .on: break
                }
            }
            return
        }
        if event.hasPrefix("avatar-audio ") {
            struct Payload: Decodable {
                let revision: UInt32
                let turn: UInt64
                let rms: Double
                let sending: Bool
            }
            if meetingAvatarState == .on,
               let payload = try? JSONDecoder().decode(Payload.self, from: Data(event.dropFirst("avatar-audio ".count).utf8)),
               payload.revision == avatarRequest.revision,
               presentation != .interrupted {
                avatarLastTurn = max(avatarLastTurn, payload.turn)
                avatarSpeech.ingest(rms: payload.sending ? payload.rms : 0, turn: payload.turn, at: ProcessInfo.processInfo.systemUptime)
            }
            return
        }
        if event.hasPrefix("presentation-ocr ") {
            receivePresentationOCR(String(event.dropFirst("presentation-ocr ".count)))
            return
        }
        if let phase = SessionPresentation.phase(for: event) {
            presentationPhase = phase
        }
        switch event {
        case "login-panel":
            lastErrorAt = nil
        visualState = .active
            status = "Selesaikan login di panel Nail."
        case "browser-window shown":
            browserWindowVisible = true
        case "browser-window hidden":
            browserWindowVisible = false
        case "submitted":
            lastErrorAt = nil
        visualState = .active
            status = "Menunggu konfirmasi \(activePlatform?.label ?? "rapat")…"
        case "teams-launcher":
            lastErrorAt = nil
        visualState = .active
            status = "Memilih 'Continue on this browser' di Teams…"
        case "teams-prejoin":
            lastErrorAt = nil
        visualState = .active
            status = "Mengisi nama 'Nail' di lobi Teams…"
        case "waiting":
            lastErrorAt = nil
        visualState = .active
            status = "Menunggu host mengizinkan Nail."
        case "joined":
            voiceReady = activeProvider != nil && input != nil
            visualState = .standby
            let platformName = activePlatform?.label ?? "rapat"
            status = activeProvider.map { "Nail masuk \(platformName). Suara: \($0.label)." } ?? "Nail masuk \(platformName)."
            meetingAvatarAvailable = activePlatform == .googleMeet && activeProvider != nil
            if meetingAvatarAvailable { setMeetingAvatarEnabled(true) }
        case "notes-error":
            notulenError = "Notulen terhenti. Periksa Whisper, uv, dan ruang penyimpanan."
        case "notes-gap":
            notulenError = "Audio rapat terputus; sebagian notulen mungkin terlewat."
        case "notes-ready":
            notulenError = ""
        case "voice-standby":
            voiceBusy = false
            isSpeaking = false
            visualState = .standby
            if !status.hasPrefix("Jawaban diputar") && !status.hasPrefix("Suara Nail dipotong") {
                let platformName = activePlatform?.label ?? "rapat"
                status = activeMode == .notulen
                    ? "Mode Notulen aktif — menunggu panggilan 'Nail'…"
                    : "Siaga di \(platformName) — menunggu panggilan 'Nail'…"
            }
        case "voice-followup":
            voiceBusy = false
            isSpeaking = false
            visualState = .followUp
            status = "Jendela lanjutan aktif (langsung bicara tanpa 'Nail')…"
        case "voice-recording":
            voiceBusy = true
            lastErrorAt = nil
        visualState = .active
            status = "Menyimak audio Meet (maks 8 detik)…"
        case "voice-processing":
            voiceBusy = true
            lastErrorAt = nil
        visualState = .active
            status = "Memproses audio dan menyiapkan jawaban…"
        case "voice-sending":
            voiceBusy = true
            isSpeaking = true
            lastErrorAt = nil
        visualState = .active
            status = "Mengirim suara Nail ke Meet…"
        case "voice-interrupted":
            avatarSpeech.stop(throughTurn: avatarLastTurn)
            avatarTransport.clearPending()
            voiceBusy = false
            isSpeaking = false
            visualState = .interrupted
            status = "Suara Nail dipotong (Panic Mute)."
        case "voice-codex-connecting":
            lastErrorAt = nil
        visualState = .active
            status = "Menyambungkan suara ke Codex…"
        case "voice-codex-listening":
            lastErrorAt = nil
        visualState = .active
            status = "Codex sedang memproses ucapan…"
        case "voice-codex-heard":
            lastErrorAt = nil
        visualState = .active
            status = "Codex sudah menangkap ucapan. Menunggu jawabannya…"
        case "voice-codex-delegating":
            lastErrorAt = nil
        visualState = .active
            status = "Codex sedang menyiapkan jawaban lengkap…"
        case "voice-no-mic":
            voiceBusy = false
            isSpeaking = false
            visualState = .error
            status = "Meet belum memakai mic virtual Nail."
        case "voice-failed":
            voiceBusy = false
            isSpeaking = false
            visualState = .error
            status = "Audio atau jawaban gagal diproses."
        case "voice-codex-quota":
            voiceBusy = false; isSpeaking = false; visualState = .error
            status = "Kuota Codex habis."
        case "voice-codex-login":
            voiceBusy = false; isSpeaking = false; visualState = .error
            status = "Login Codex lewat ChatGPT: jalankan codex login."
        case "voice-codex-missing":
            voiceBusy = false; isSpeaking = false; visualState = .error
            status = "Codex CLI tidak ditemukan."
        case "voice-codex-timeout":
            voiceBusy = false; isSpeaking = false; visualState = .error
            status = "Codex tidak merespons tepat waktu — koneksi suara direset, silakan tanya lagi."
        case "voice-codex-connection":
            voiceBusy = false; isSpeaking = false; visualState = .error
            status = "Koneksi suara ke Codex tidak terbentuk."
        case "voice-codex-no-transcript":
            voiceBusy = false; isSpeaking = false; visualState = .error
            status = "Codex belum membaca ucapan."
        case "voice-codex-error":
            voiceBusy = false; isSpeaking = false; visualState = .error
            status = "Sesi Codex Live Voice gagal."
        case "voice-codex-wake-unavailable":
            visualState = .standby
            status = "Hands-free 'Nail' tidak aktif (Whisper lokal belum siap) — pakai tombol Tanya."
        case "voice-unavailable":
            visualState = .error
            status = "Mic virtual Nail gagal disiapkan."
        case "left":
            clearMeetingAvatar()
            lastWorkerExitNormal = true
            visualState = .idle
            status = "Nail tidak lagi di rapat."
        case "login-required":
            visualState = .error
            status = "Login dulu lewat menu Nail → Login Google untuk Nail."
        case "teams-login-required":
            visualState = .error
            status = "Rapat Teams ini mewajibkan login Microsoft (mode tamu dinonaktifkan host)."
        case "rejected":
            visualState = .error
            status = "\(activePlatform?.label ?? "Rapat") menolak Nail masuk."
        case "admission-timeout":
            visualState = .error
            status = "\(activePlatform?.label ?? "Rapat") belum mengizinkan Nail masuk."
        case "lobby-timeout":
            visualState = .error
            status = "Tombol Gabung tidak aktif di lobi \(activePlatform?.label ?? "rapat")."
        case "failed":
            visualState = .error
            status = "Nail tidak dapat membuka sesi \(activePlatform?.label ?? "rapat")."
        default:
            if event.hasPrefix("mode-changed ") {
                let raw = String(event.dropFirst(13))
                if let mode = ListeningMode(rawValue: raw) {
                    activeMode = mode
                }
            } else if event.hasPrefix("voice-wake ") {
                voiceBusy = true
                lastErrorAt = nil
        visualState = .active
                if let info = try? JSONDecoder().decode([String: String].self, from: Data(event.dropFirst(11).utf8)),
                   let heard = info["heard"], !heard.isEmpty {
                    voiceTranscript = heard
                }
                status = "Nail terpanggil — menyiapkan jawaban…"
            } else if event.hasPrefix("voice-notulen-codex ") {
                if let lines = try? JSONDecoder().decode([MeetingLinePayload].self, from: Data(event.dropFirst(20).utf8)) {
                    for line in lines {
                        let timestamp = line.timestampMs.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
                        transcriptStore.recordMeetingLine(line.text, mode: .notulen, speaker: line.speaker, timestamp: timestamp)
                    }
                    persistNotulen(force: true)
                }
            } else if event.hasPrefix("voice-notulen ") {
                if let info = try? JSONDecoder().decode([String: String].self, from: Data(event.dropFirst(14).utf8)),
                   let line = info["text"] {
                    transcriptStore.recordMeetingLine(line, mode: activeMode)
                    persistNotulen()
                }
            } else if event.hasPrefix("voice-no-audio") {
                voiceBusy = false
                isSpeaking = false
                visualState = .error
                if event.count > 15,
                   let diag = try? JSONDecoder().decode([String: Double].self, from: Data(event.dropFirst(15).utf8)) {
                    let tracks = Int(diag["tracks"] ?? 0)
                    let live = Int(diag["live"] ?? 0)
                    let muted = Int(diag["muted"] ?? 0)
                    let rx = Int(diag["rxPackets"] ?? 0)
                    let energy = diag["rxEnergy"] ?? 0
                    if let peak = diag["peak"] {
                        status = energy < 0.001
                            ? "Meet hanya mengirim hening (\(rx) pkt, energi \(energy))."
                            : "Tidak ada ucapan dari Meet (puncak \(Int(peak)) dBFS, \(live)/\(tracks) track, \(muted) mute)."
                    } else {
                        status = "Tidak ada ucapan dari Meet (\(live)/\(tracks) track audio)."
                    }
                } else {
                    status = "Tidak ada ucapan yang terbaca dari Meet."
                }
            } else if event.hasPrefix("voice-result "), input != nil {
                voiceBusy = false
                isSpeaking = false
                visualState = .standby
                if let result = try? JSONDecoder().decode(VoiceResultPayload.self, from: Data(event.dropFirst(13).utf8)) {
                    let heard = result.heard ?? ""
                    let cleanHeard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawReply = (result.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let reply = rawReply.isEmpty && !cleanHeard.isEmpty
                        ? "(Jawaban suara diputar — transkrip belum tersedia)"
                        : rawReply
                    let now = Date()
                    let heardAt = result.heardAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? now
                    let replyAt = result.replyAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? now
                    let latency = result.latencyMs.map { max(0, $0 / 1000.0) }
                    voiceTranscript = heard
                    voiceReply = reply
                    lastHeardAt = heardAt
                    lastReplyAt = replyAt
                    lastLatencySeconds = latency
                    transcriptStore.recordExchange(
                        heard: heard,
                        reply: reply,
                        heardAt: heardAt,
                        replyAt: replyAt,
                        latencySeconds: latency
                    )
                    if activeMode == .notulen {
                        persistNotulen()
                    }
                    if let latency {
                        status = "Jawaban diputar ke mic virtual Meet (\(TranscriptEntry.formatLatency(latency)))."
                    } else {
                        status = "Jawaban diputar ke mic virtual Meet."
                    }
                }
            }
        }
    }

    private func receivePresentationOCR(_ payload: String) {
        guard payload.utf8.count <= 12_000_000,
              let request = try? JSONDecoder().decode(PresentationOCRRequest.self, from: Data(payload.utf8)),
              request.image.count <= 8_000_000,
              active, activePlatform == .googleMeet,
              VoiceSettings.shared.presentationReadingEnabled,
              let worker = workerProcess else { return }

        Task { [weak self] in
            let text = await Task.detached(priority: .userInitiated) {
                try? PresentationOCR.recognize(request.image)
            }.value
            guard let self, self.active, self.workerProcess === worker,
                  VoiceSettings.shared.presentationReadingEnabled,
                  let input = self.input else { return }
            let response = PresentationOCRResponse(
                id: request.id,
                text: text,
                error: text == nil ? "ocr-failed" : nil
            )
            guard let data = try? JSONEncoder().encode(response),
                  let json = String(data: data, encoding: .utf8) else { return }
            try? input.write(contentsOf: Data("presentation-ocr-result \(json)\n".utf8))
        }
    }

    private func persistNotulen(endedAt: Date? = nil, interrupted: Bool = false, force: Bool = false) {
        guard !transcriptStore.entries.isEmpty else { return }
        guard force || activeMode == .notulen || currentNotulenURL != nil else { return }
        let startedAt = sessionStartedAt ?? Date()
        let fileURL: URL
        if let existing = currentNotulenURL {
            fileURL = existing
        } else {
            let created = NotulenExporter.uniqueSessionURL(
                title: currentMeetingTitle,
                meetLink: currentMeetingLink,
                startedAt: startedAt
            )
            currentNotulenURL = created
            fileURL = created
        }
        do {
            try NotulenExporter.writeSession(
                to: fileURL,
                title: currentMeetingTitle,
                meetLink: currentMeetingLink,
                startedAt: startedAt,
                endedAt: endedAt,
                interrupted: interrupted,
                entries: transcriptStore.entries
            )
        } catch {
            notulenError = "Notulen gagal disimpan: \(error.localizedDescription)"
        }
    }

    private func finished(exitCode: Int32) {
        guard active || workerProcess != nil else { return }
        clearMeetingAvatar()
        leaveTerminationTask?.cancel()
        leaveTerminationTask = nil
        let intentionalLeave = leaveRequested
        leaveRequested = false
        try? input?.close()
        input = nil
        workerProcess = nil
        voiceReady = false
        voiceBusy = false
        isSpeaking = false
        liveVoice = LiveVoiceTranscript()
        persistNotulen(
            endedAt: Date(),
            interrupted: Self.shouldMarkNotulenInterrupted(
                leaveRequested: intentionalLeave,
                lastWorkerExitNormal: lastWorkerExitNormal,
                exitCode: exitCode
            )
        )
        if !joiningMeeting {
            visualState = .idle
            status = "Panel login ditutup."
        } else if exitCode == 0 || intentionalLeave {
            visualState = .idle
            status = "Nail tidak lagi di rapat."
        } else if visualState != .error {
            visualState = .error
            status = "Proses Chromium Nail berhenti sebelum sesi selesai."
        }
        presentationPhase = joiningMeeting ? .finished : .ready
        active = false
        joiningMeeting = false
        browserWindowVisible = false
    }
}
