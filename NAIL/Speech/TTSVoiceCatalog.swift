import Foundation
import Security

enum ElevenLabsKeychain {
    nonisolated static let service = "nail.elevenlabs"
    nonisolated static let account = "api_key"

    @discardableResult
    nonisolated static func save(_ apiKey: String) -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return false
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        let key = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    @discardableResult
    nonisolated static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    nonisolated static func hasKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

struct ElevenLabsVoice: Codable, Equatable, Identifiable, Hashable, Sendable {
    let voiceId: String
    let name: String
    let category: String?

    var id: String { voiceId }

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name
        case category
    }

    init(voiceId: String, name: String, category: String? = nil) {
        self.voiceId = voiceId
        self.name = name
        self.category = category
    }
}

struct ElevenLabsSubscription: Codable, Equatable, Sendable {
    let characterCount: Int
    let characterLimit: Int
    let tier: String?
    let nextCharacterCountResetUnix: Int?

    var remainingCharacters: Int {
        max(0, characterLimit - characterCount)
    }

    enum CodingKeys: String, CodingKey {
        case characterCount = "character_count"
        case characterLimit = "character_limit"
        case tier
        case nextCharacterCountResetUnix = "next_character_count_reset_unix"
    }

    init(
        characterCount: Int,
        characterLimit: Int,
        tier: String? = nil,
        nextCharacterCountResetUnix: Int? = nil
    ) {
        self.characterCount = characterCount
        self.characterLimit = characterLimit
        self.tier = tier
        self.nextCharacterCountResetUnix = nextCharacterCountResetUnix
    }
}

enum ElevenLabsAPIError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case httpError(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "API key ElevenLabs belum diisi."
        case .invalidAPIKey:
            "API key ElevenLabs tidak valid atau ditolak (HTTP 401)."
        case .rateLimited:
            "Batas permintaan ElevenLabs tercapai (HTTP 429). Coba lagi sebentar."
        case let .httpError(statusCode, message):
            message.isEmpty
                ? "Permintaan ke ElevenLabs gagal (HTTP \(statusCode))."
                : "ElevenLabs error (HTTP \(statusCode)): \(message)"
        case .invalidResponse:
            "Respons server ElevenLabs tidak dapat dibaca."
        }
    }
}

private struct ElevenLabsVoicesResponse: Decodable {
    let voices: [ElevenLabsVoice]
}

private final class PreviewProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var activeProcess: Process?

    func beginNewPreview() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        if let activeProcess, activeProcess.isRunning {
            activeProcess.terminate()
        }
        activeProcess = nil
        return generation
    }

    func setActiveProcess(_ process: Process, for expectedGeneration: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expectedGeneration else { return false }
        activeProcess = process
        return true
    }

    func clearProcess(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if activeProcess === process {
            activeProcess = nil
        }
    }

    func isCurrentGeneration(_ expectedGeneration: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == expectedGeneration
    }
}

enum TTSVoiceCatalog {
    nonisolated static let neuralVoices: [String] = ["id-ID-GadisNeural", "id-ID-ArdiNeural"]
    nonisolated static let defaultVoice = "id-ID-GadisNeural"
    nonisolated static let defaultElevenLabsVoiceId = "EXAVITQu4vr4xnSDxMaL"
    nonisolated static let defaultElevenLabsVoiceName = "Sarah"
    nonisolated static let curatedElevenLabsVoices: [ElevenLabsVoice] = [
        ElevenLabsVoice(voiceId: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", category: "premade"),
        ElevenLabsVoice(voiceId: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", category: "premade"),
        ElevenLabsVoice(voiceId: "CwhRBWXzGAHq8TQ4Fs17", name: "Roger", category: "premade"),
        ElevenLabsVoice(voiceId: "JBFqnCBsd6RMkjVDRZzb", name: "George", category: "premade"),
        ElevenLabsVoice(voiceId: "9BWtsMINqrJLrRacOk9x", name: "Aria", category: "premade"),
    ]

    private nonisolated static let elevenLabsVoicesURL = URL(string: "https://api.elevenlabs.io/v1/voices")!
    private nonisolated static let elevenLabsSubscriptionURL = URL(string: "https://api.elevenlabs.io/v1/user/subscription")!
    private nonisolated static let previewState = PreviewProcessState()
    private nonisolated static let previewSampleText =
        "Halo, aku Nail, asisten rapat kamu. Suaraku sudah pakai pelafalan bahasa Indonesia yang natural."

    nonisolated static func elevenLabsModelDisplayName(for model: String) -> String {
        switch model {
        case "eleven_flash_v2_5": "Flash v2.5 · 0,5 kredit/karakter"
        case "eleven_multilingual_v2": "Multilingual v2 · 1 kredit/karakter"
        default: model
        }
    }

    nonisolated static func parseElevenLabsVoices(data: Data) throws -> [ElevenLabsVoice] {
        let decoded = try JSONDecoder().decode(ElevenLabsVoicesResponse.self, from: data)
        var seen = Set<String>()
        var result: [ElevenLabsVoice] = []
        for voice in decoded.voices {
            let trimmedId = voice.voiceId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty, seen.insert(trimmedId).inserted else { continue }
            let trimmedName = voice.name.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                ElevenLabsVoice(
                    voiceId: trimmedId,
                    name: trimmedName.isEmpty ? trimmedId : trimmedName,
                    category: voice.category
                )
            )
        }
        return result
    }

    nonisolated static func parseElevenLabsSubscription(data: Data) throws -> ElevenLabsSubscription {
        try JSONDecoder().decode(ElevenLabsSubscription.self, from: data)
    }

    private nonisolated static func extractElevenLabsErrorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let detail = object["detail"] as? [String: Any],
           let message = detail["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let detail = object["detail"] as? String {
            return detail.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let message = object["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private nonisolated static func performElevenLabsGET(
        url: URL,
        apiKey: String,
        session: URLSession
    ) async throws -> Data {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ElevenLabsAPIError.missingAPIKey
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsAPIError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw ElevenLabsAPIError.invalidAPIKey
        case 429:
            throw ElevenLabsAPIError.rateLimited
        default:
            throw ElevenLabsAPIError.httpError(
                statusCode: http.statusCode,
                message: extractElevenLabsErrorMessage(from: data)
            )
        }
    }

    nonisolated static func fetchElevenLabsVoices(
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [ElevenLabsVoice] {
        let data = try await performElevenLabsGET(url: elevenLabsVoicesURL, apiKey: apiKey, session: session)
        return try parseElevenLabsVoices(data: data)
    }

    nonisolated static func fetchElevenLabsSubscription(
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> ElevenLabsSubscription {
        let data = try await performElevenLabsGET(url: elevenLabsSubscriptionURL, apiKey: apiKey, session: session)
        return try parseElevenLabsSubscription(data: data)
    }

    nonisolated static func isNeuralVoice(_ voice: String) -> Bool {
        let trimmed = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        return neuralVoices.contains(trimmed)
            || (trimmed.hasPrefix("id-ID-") && trimmed.hasSuffix("Neural"))
    }

    nonisolated static func displayName(for voice: String) -> String {
        switch voice {
        case "id-ID-GadisNeural": "Gadis · Neural Indonesia (Perempuan)"
        case "id-ID-ArdiNeural": "Ardi · Neural Indonesia (Laki-laki)"
        default: voice
        }
    }

    nonisolated static func shortDisplayName(for voice: String) -> String {
        switch voice {
        case "id-ID-GadisNeural": "Gadis Neural (ID)"
        case "id-ID-ArdiNeural": "Ardi Neural (ID)"
        default: voice
        }
    }

    /// Parses `say -v '?'` output and returns sorted Indonesian (`id_ID`) voice names.
    nonisolated static func parseIndonesianVoices(_ output: String) -> [String] {
        var names: [String] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let hashIndex = line.firstIndex(of: "#") else { continue }
            let prefix = String(line[..<hashIndex]).trimmingCharacters(in: .whitespaces)
            let tokens = prefix.split(whereSeparator: \.isWhitespace)
            guard let locale = tokens.last, locale == "id_ID" else { continue }
            let name = tokens.dropLast().joined(separator: " ")
            if !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }
        if names.isEmpty {
            return ["Damayanti"]
        }
        return names.sorted { lhs, rhs in
            if lhs == "Damayanti" { return true }
            if rhs == "Damayanti" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private nonisolated static func listMacOSIndonesianVoices() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "?"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return ["Damayanti"] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return ["Damayanti"] }
        return parseIndonesianVoices(String(decoding: data, as: UTF8.self))
    }

    nonisolated static func listIndonesianVoices() -> [String] {
        var combined = neuralVoices
        for voice in listMacOSIndonesianVoices() where !combined.contains(voice) {
            combined.append(voice)
        }
        return combined
    }

    nonisolated static func hasEnhancedVoice(in voices: [String]) -> Bool {
        voices.contains { $0.localizedCaseInsensitiveContains("Enhanced") || $0.localizedCaseInsensitiveContains("Premium") }
    }

    @discardableResult
    private nonisolated static func runControlledProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        generation: UInt64
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        guard previewState.setActiveProcess(process, for: generation) else {
            return false
        }
        defer { previewState.clearProcess(process) }

        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0 && previewState.isCurrentGeneration(generation)
    }

    nonisolated static func buildSpeakTextArguments(
        scriptPath: String,
        text: String,
        replyWavPath: String,
        voice: String,
        rate: Int,
        ttsEngine: TTSEngine = .edge,
        elevenLabsVoiceId: String = defaultElevenLabsVoiceId,
        elevenLabsModel: String = "eleven_flash_v2_5"
    ) -> [String] {
        var args = [
            "run", "--offline", "--script", scriptPath,
            "--speak-text", text,
            "--reply-wav", replyWavPath,
            "--tts-voice", voice,
            "--tts-rate", String(rate),
            "--tts-engine", ttsEngine.rawValue,
        ]
        let trimmedVoiceId = elevenLabsVoiceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedVoiceId.isEmpty {
            args.append(contentsOf: ["--elevenlabs-voice-id", trimmedVoiceId])
        }
        let trimmedModel = elevenLabsModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            args.append(contentsOf: ["--elevenlabs-model", trimmedModel])
        }
        return args
    }

    nonisolated static func buildPreviewEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        ttsEngine: TTSEngine,
        apiKeyLoader: () -> String? = { ElevenLabsKeychain.load() }
    ) -> [String: String] {
        var env = base
        let basePath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(basePath)"
        if ttsEngine == .elevenlabs, let key = apiKeyLoader(), !key.isEmpty {
            env["ELEVENLABS_API_KEY"] = key
        } else {
            env.removeValue(forKey: "ELEVENLABS_API_KEY")
        }
        return env
    }

    nonisolated static func preview(voice: String, rate: Int) {
        preview(
            voice: voice,
            rate: rate,
            ttsEngine: .edge,
            elevenLabsVoiceId: defaultElevenLabsVoiceId,
            elevenLabsModel: "eleven_flash_v2_5"
        )
    }

    nonisolated static func preview(
        voice: String,
        rate: Int,
        ttsEngine: TTSEngine,
        elevenLabsVoiceId: String,
        elevenLabsModel: String
    ) {
        let generation = previewState.beginNewPreview()
        let text = previewSampleText

        if ttsEngine == .elevenlabs || isNeuralVoice(voice) {
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let uvPath = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv"].first {
                    fm.isExecutableFile(atPath: $0)
                }
                let scriptURL = Bundle.main.url(forResource: "agy-voice", withExtension: "py")
                let tmpWav = fm.temporaryDirectory.appendingPathComponent("nail-preview-\(UUID().uuidString).wav")
                defer { try? fm.removeItem(at: tmpWav) }

                if let uvPath, let scriptURL {
                    let env = buildPreviewEnvironment(ttsEngine: ttsEngine)
                    let args = buildSpeakTextArguments(
                        scriptPath: scriptURL.path,
                        text: text,
                        replyWavPath: tmpWav.path,
                        voice: voice,
                        rate: rate,
                        ttsEngine: ttsEngine,
                        elevenLabsVoiceId: elevenLabsVoiceId,
                        elevenLabsModel: elevenLabsModel
                    )

                    let synthesized = runControlledProcess(
                        executablePath: uvPath,
                        arguments: args,
                        environment: env,
                        generation: generation
                    )
                    if synthesized, fm.fileExists(atPath: tmpWav.path) {
                        _ = runControlledProcess(
                            executablePath: "/usr/bin/afplay",
                            arguments: [tmpWav.path],
                            generation: generation
                        )
                        return
                    }
                }

                guard previewState.isCurrentGeneration(generation) else { return }
                let fallbackVoice = isNeuralVoice(voice) ? "Damayanti" : voice
                _ = runControlledProcess(
                    executablePath: "/usr/bin/say",
                    arguments: ["-v", fallbackVoice, "-r", String(rate), text],
                    generation: generation
                )
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            _ = runControlledProcess(
                executablePath: "/usr/bin/say",
                arguments: ["-v", voice, "-r", String(rate), text],
                generation: generation
            )
        }
    }
}
