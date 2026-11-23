import CoreGraphics
import Foundation
import Observation
import SwiftUI

enum VoiceProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case antigravity
    case deepseek
    case codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .antigravity: "Antigravity (Google AI Pro)"
        case .deepseek: "DeepSeek"
        case .codex: "Codex Live Voice"
        }
    }

    var shortBadge: String {
        switch self {
        case .antigravity: "Agy"
        case .deepseek: "DeepSeek"
        case .codex: "Codex"
        }
    }

    var recipient: String {
        switch self {
        case .antigravity: "Google (Antigravity)"
        case .deepseek: "DeepSeek"
        case .codex: "OpenAI (ChatGPT)"
        }
    }
}

enum ListeningMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case standby
    case notulen

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .standby: "Siaga"
        case .notulen: "Notulen"
        }
    }

    var description: String {
        switch self {
        case .standby: "Hanya proses saat dipanggil 'Nail' (tidak simpan obrolan lain)"
        case .notulen: "Catat transkrip rapat lokal & pakai sebagai memori saat menjawab pertanyaan"
        }
    }
}

enum SpeakingStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case casual
    case professional
    case brainstorm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .casual: "Santai & Gaul"
        case .professional: "Profesional"
        case .brainstorm: "Brainstorm"
        }
    }

    var description: String {
        switch self {
        case .casual: "Ngobrol santai & cair kayak sama temen deket, akrab, spontan, dan sedikit bercanda."
        case .professional: "Bahasa Indonesia rapi, sopan, dan langsung ke inti."
        case .brainstorm: "Bahasa Indonesia antusias, kasual, dan memancing ide konkret."
        }
    }
}

enum HUDSizePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: "Ringkas"
        case .standard: "Standar"
        case .large: "Besar"
        case .extraLarge: "Ekstra Besar"
        }
    }

    nonisolated var expandedCardWidth: CGFloat {
        switch self {
        case .compact: 356
        case .standard: 404
        case .large: 472
        case .extraLarge: 532
        }
    }

    nonisolated var expandedPanelWidth: CGFloat { expandedCardWidth + 16 }

    nonisolated var expandedExtraHeight: CGFloat {
        switch self {
        case .compact: 172
        case .standard: 194
        case .large: 224
        case .extraLarge: 256
        }
    }

    nonisolated var nonNotchCollapsedWidth: CGFloat {
        switch self {
        case .compact: 210
        case .standard: 234
        case .large: 268
        case .extraLarge: 300
        }
    }

    nonisolated var notchEarAllowance: CGFloat {
        switch self {
        case .compact: 104
        case .standard: 120
        case .large: 148
        case .extraLarge: 176
        }
    }

    nonisolated var waveMaxHeight: CGFloat {
        switch self {
        case .compact: 20
        case .standard: 26
        case .large: 34
        case .extraLarge: 42
        }
    }
}

enum HUDAnimationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case wave
    case aurora
    case minimal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wave: "Gelombang"
        case .aurora: "Aurora"
        case .minimal: "Minimal"
        }
    }
}

enum HUDAccentTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case status
    case ocean
    case violet
    case emerald

    var id: String { rawValue }

    var label: String {
        switch self {
        case .status: "Otomatis (Status)"
        case .ocean: "Ocean Cyan"
        case .violet: "Neon Violet"
        case .emerald: "Emerald"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: "Gelap"
        case .light: "Terang"
        case .system: "Ikuti macOS"
        }
    }

    var systemImage: String {
        switch self {
        case .dark: "moon.stars.fill"
        case .light: "sun.max.fill"
        case .system: "circle.lefthalf.filled"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

enum HUDLayoutStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case notch
    case floatingPill

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notch: "Poni Notch"
        case .floatingPill: "Floating Glass Pill"
        }
    }

    var subtitle: String {
        switch self {
        case .notch: "Menyatu di bagian atas layar"
        case .floatingPill: "Kapsul kaca bebas geser (cocok monitor luar)"
        }
    }

    var systemImage: String {
        switch self {
        case .notch: "menubar.dock.rectangle"
        case .floatingPill: "capsule.portrait.tophalf.filled"
        }
    }
}

enum TTSEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case edge
    case elevenlabs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .edge: "Edge Neural / macOS"
        case .elevenlabs: "ElevenLabs (Flash v2.5)"
        }
    }
}

struct VoiceRuntimeConfig: Codable, Equatable, Sendable {
    var agyModel: String
    var whisperModel: String
    var ttsVoice: String
    var ttsRate: Int
    var codexVoice: String
    var speakingStyle: String
    var listeningMode: String
    var disclosure: Bool
    var codexHandsFree: Bool = true
    var presentationReadingEnabled: Bool = false
    var ttsEngine: String = TTSEngine.edge.rawValue
    var elevenLabsModel: String = VoiceSettings.defaultElevenLabsModel
    var elevenLabsVoiceId: String = TTSVoiceCatalog.defaultElevenLabsVoiceId
    var elevenLabsVoiceName: String = TTSVoiceCatalog.defaultElevenLabsVoiceName

    enum CodingKeys: String, CodingKey {
        case agyModel
        case whisperModel
        case ttsVoice
        case ttsRate
        case codexVoice
        case speakingStyle
        case listeningMode
        case disclosure
        case codexHandsFree
        case presentationReadingEnabled
        case ttsEngine
        case elevenLabsModel
        case elevenLabsVoiceId
        case elevenLabsVoiceName
    }

    init(
        agyModel: String,
        whisperModel: String,
        ttsVoice: String,
        ttsRate: Int,
        codexVoice: String,
        speakingStyle: String,
        listeningMode: String,
        disclosure: Bool,
        codexHandsFree: Bool = true,
        presentationReadingEnabled: Bool = false,
        ttsEngine: String = TTSEngine.edge.rawValue,
        elevenLabsModel: String = VoiceSettings.defaultElevenLabsModel,
        elevenLabsVoiceId: String = TTSVoiceCatalog.defaultElevenLabsVoiceId,
        elevenLabsVoiceName: String = TTSVoiceCatalog.defaultElevenLabsVoiceName
    ) {
        self.agyModel = agyModel
        self.whisperModel = whisperModel
        self.ttsVoice = ttsVoice
        self.ttsRate = ttsRate
        self.codexVoice = codexVoice
        self.speakingStyle = speakingStyle
        self.listeningMode = listeningMode
        self.disclosure = disclosure
        self.codexHandsFree = codexHandsFree
        self.presentationReadingEnabled = presentationReadingEnabled
        self.ttsEngine = ttsEngine
        self.elevenLabsModel = elevenLabsModel
        self.elevenLabsVoiceId = elevenLabsVoiceId
        self.elevenLabsVoiceName = elevenLabsVoiceName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.agyModel = try container.decode(String.self, forKey: .agyModel)
        self.whisperModel = try container.decode(String.self, forKey: .whisperModel)
        self.ttsVoice = try container.decode(String.self, forKey: .ttsVoice)
        self.ttsRate = try container.decode(Int.self, forKey: .ttsRate)
        self.codexVoice = try container.decode(String.self, forKey: .codexVoice)
        self.speakingStyle = try container.decode(String.self, forKey: .speakingStyle)
        self.listeningMode = try container.decode(String.self, forKey: .listeningMode)
        self.disclosure = try container.decode(Bool.self, forKey: .disclosure)
        self.codexHandsFree = try container.decodeIfPresent(Bool.self, forKey: .codexHandsFree) ?? true
        self.presentationReadingEnabled = try container.decodeIfPresent(Bool.self, forKey: .presentationReadingEnabled) ?? false
        self.ttsEngine = try container.decodeIfPresent(String.self, forKey: .ttsEngine) ?? TTSEngine.edge.rawValue
        self.elevenLabsModel = try container.decodeIfPresent(String.self, forKey: .elevenLabsModel) ?? VoiceSettings.defaultElevenLabsModel
        self.elevenLabsVoiceId = try container.decodeIfPresent(String.self, forKey: .elevenLabsVoiceId) ?? TTSVoiceCatalog.defaultElevenLabsVoiceId
        self.elevenLabsVoiceName = try container.decodeIfPresent(String.self, forKey: .elevenLabsVoiceName) ?? TTSVoiceCatalog.defaultElevenLabsVoiceName
    }
}

@MainActor @Observable
final class VoiceSettings {
    static let shared = VoiceSettings()

    nonisolated static let defaultElevenLabsModel = "eleven_flash_v2_5"
    nonisolated static let elevenLabsModelOptions: [String] = [
        "eleven_flash_v2_5",
        "eleven_multilingual_v2",
    ]

    static let agyModelOptions: [String] = [
        "gemini-4-neon-low",
        "gemini-3.8-flash-low",
        "gemini-3.8-flash-medium",
        "gemini-4-hydrogen-low",
        "gemini-4-argon-low",
    ]

    enum SummaryModelBackend: String, Codable, Equatable, Sendable {
        case antigravity
        case codex
        case local
    }

    struct SummaryModelOption: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let group: String
        let backend: SummaryModelBackend
    }

    nonisolated static let defaultSummaryModel = "gemini-4-hydrogen-high"
    nonisolated static let defaultBackendSummaryEndpoint = NotulenBackendClient.defaultEndpointURLString

    nonisolated static let summaryModelOptions: [SummaryModelOption] = [
        // Antigravity (Google AI Pro)
        SummaryModelOption(id: "gemini-4-hydrogen-high", label: "Gemini 4 Hydrogen (High)", group: "Gemini 4 Hydrogen", backend: .antigravity),
        SummaryModelOption(id: "gemini-4-hydrogen-medium", label: "Gemini 4 Hydrogen (Medium)", group: "Gemini 4 Hydrogen", backend: .antigravity),
        SummaryModelOption(id: "gemini-4-hydrogen-low", label: "Gemini 4 Hydrogen (Low)", group: "Gemini 4 Hydrogen", backend: .antigravity),
        SummaryModelOption(id: "gemini-4-neon-high", label: "Gemini 4 Neon (High)", group: "Gemini 4 Neon & Argon", backend: .antigravity),
        SummaryModelOption(id: "gemini-4-neon-medium", label: "Gemini 4 Neon (Medium)", group: "Gemini 4 Neon & Argon", backend: .antigravity),
        SummaryModelOption(id: "gemini-4-neon-low", label: "Gemini 4 Neon (Low)", group: "Gemini 4 Neon & Argon", backend: .antigravity),
        SummaryModelOption(id: "gemini-4-argon-high", label: "Gemini 4 Argon (High)", group: "Gemini 4 Neon & Argon", backend: .antigravity),
        SummaryModelOption(id: "gemini-4-argon-medium", label: "Gemini 4 Argon (Medium)", group: "Gemini 4 Neon & Argon", backend: .antigravity),
        SummaryModelOption(id: "gemini-4-argon-low", label: "Gemini 4 Argon (Low)", group: "Gemini 4 Neon & Argon", backend: .antigravity),
        SummaryModelOption(id: "gemini-3.8-flash-high", label: "Gemini 3.8 Flash (High)", group: "Gemini 3.8 Flash", backend: .antigravity),
        SummaryModelOption(id: "gemini-3.8-flash-medium", label: "Gemini 3.8 Flash (Medium)", group: "Gemini 3.8 Flash", backend: .antigravity),
        SummaryModelOption(id: "gemini-3.8-flash-low", label: "Gemini 3.8 Flash (Low)", group: "Gemini 3.8 Flash", backend: .antigravity),
        SummaryModelOption(id: "claude-sonnet-5-5-high", label: "Claude Sonnet 5.5 (High)", group: "Claude 5.5", backend: .antigravity),
        SummaryModelOption(id: "claude-sonnet-5-5-medium", label: "Claude Sonnet 5.5 (Medium)", group: "Claude 5.5", backend: .antigravity),
        SummaryModelOption(id: "claude-opus-5-5-high", label: "Claude Opus 5.5 (High)", group: "Claude 5.5", backend: .antigravity),
        SummaryModelOption(id: "claude-opus-5-5-medium", label: "Claude Opus 5.5 (Medium)", group: "Claude 5.5", backend: .antigravity),
        // ChatGPT (Codex)
        SummaryModelOption(id: "gpt-6.2-sol", label: "GPT-6.2 Sol", group: "ChatGPT (Codex)", backend: .codex),
        SummaryModelOption(id: "gpt-6.2-astra", label: "GPT-6.2 Astra", group: "ChatGPT (Codex)", backend: .codex),
        SummaryModelOption(id: "gpt-6.1-terra", label: "GPT-6.1 Terra", group: "ChatGPT (Codex)", backend: .codex),
        SummaryModelOption(id: "gpt-6.1-sol", label: "GPT-6.1 Sol", group: "ChatGPT (Codex)", backend: .codex),
        SummaryModelOption(id: "gpt-6-astra", label: "GPT-6 Astra", group: "ChatGPT (Codex)", backend: .codex),
        SummaryModelOption(id: "gpt-6-sol", label: "GPT-6 Sol", group: "ChatGPT (Codex)", backend: .codex),
        SummaryModelOption(id: "gpt-6-luna", label: "GPT-6 Luna", group: "ChatGPT (Codex)", backend: .codex),
        SummaryModelOption(id: "gpt-5.6-sol", label: "GPT-5.6 Sol", group: "ChatGPT (Codex)", backend: .codex),
        // Offline Lokal
        SummaryModelOption(id: "ringkasan-lokal", label: "Offline Lokal (Tanpa AI)", group: "Lokal", backend: .local),
    ]

    nonisolated static let summaryModelGroups: [String] = [
        "ChatGPT (Codex)",
        "Gemini 4 Hydrogen",
        "Gemini 4 Neon & Argon",
        "Gemini 3.8 Flash",
        "Claude 5.5",
        "Lokal",
    ]

    nonisolated static func summaryModelDisplayName(for id: String) -> String {
        summaryModelOptions.first(where: { $0.id == id })?.label ?? id
    }

    nonisolated static func summaryModelBackend(for id: String) -> SummaryModelBackend {
        if let option = summaryModelOptions.first(where: { $0.id == id }) {
            return option.backend
        }
        let lower = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower == "ringkasan-lokal" { return .local }
        if lower.hasPrefix("gpt-") || lower.hasPrefix("codex") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") {
            return .codex
        }
        return .antigravity
    }

    static let whisperModelOptions: [String] = ["small", "base"]

    static let codexPrimaryVoiceOptions: [String] = [
        "cove", "breeze", "ember", "juniper", "maple", "spruce", "arbor", "sol", "vale",
    ]

    static let codexExtendedVoiceOptions: [String] = [
        "aube", "bubbie", "haetsal", "hanul", "himari", "leher", "miko", "neer",
        "porto", "rindo", "rio", "rivage", "selva", "sonna", "tinta", "viola",
    ]

    static let codexVoiceOptions: [String] = codexPrimaryVoiceOptions + codexExtendedVoiceOptions

    private let defaults: UserDefaults

    private enum Keys {
        static let provider = "nail.voice.provider"
        static let listeningMode = "nail.voice.listeningMode"
        static let agyModel = "nail.voice.agyModel"
        static let whisperModel = "nail.voice.whisperModel"
        static let ttsVoice = "nail.voice.ttsVoice"
        static let ttsRate = "nail.voice.ttsRate"
        static let ttsEngine = "nail.voice.ttsEngine"
        static let elevenLabsModel = "nail.voice.elevenLabsModel"
        static let elevenLabsVoiceId = "nail.voice.elevenLabsVoiceId"
        static let elevenLabsVoiceName = "nail.voice.elevenLabsVoiceName"
        static let codexVoice = "nail.voice.codexVoice"
        static let speakingStyle = "nail.voice.speakingStyle"
        static let disclosure = "nail.voice.disclosure"
        static let codexHandsFree = "nail.voice.codexHandsFree"
        static let presentationReadingEnabled = "nail.voice.presentationReadingEnabled"
        static let appAppearance = "nail.ui.appAppearance"
        static let hudLayoutStyle = "nail.hud.layoutStyle"
        static let hudSize = "nail.hud.size"
        static let hudAnimationStyle = "nail.hud.animationStyle"
        static let hudAccentTheme = "nail.hud.accentTheme"
        static let hudExpandOnHover = "nail.hud.expandOnHover"
        static let hudAutoExpandOnVoice = "nail.hud.autoExpandOnVoice"
        static let hudShowTranscript = "nail.hud.showTranscript"
        static let hudReplyHoldSeconds = "nail.hud.replyHoldSeconds"
        static let hudOpacity = "nail.hud.opacity"
        static let hudHideFromScreenShare = "nail.hud.hideFromScreenShare"
        static let backendSummaryEndpoint = "nail.backend.summaryEndpoint"
        static let backendAuthScheme = "nail.backend.authScheme"
        static let backendAuthHeaderName = "nail.backend.authHeaderName"
        static let summaryModel = "nail.notulen.summaryModel"
    }

    var provider: VoiceProvider {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }

    var listeningMode: ListeningMode {
        didSet { defaults.set(listeningMode.rawValue, forKey: Keys.listeningMode) }
    }

    var agyModel: String {
        didSet { defaults.set(agyModel, forKey: Keys.agyModel) }
    }

    var whisperModel: String {
        didSet { defaults.set(whisperModel, forKey: Keys.whisperModel) }
    }

    var ttsVoice: String {
        didSet { defaults.set(ttsVoice, forKey: Keys.ttsVoice) }
    }

    var ttsRate: Int {
        didSet { defaults.set(ttsRate, forKey: Keys.ttsRate) }
    }

    var ttsEngine: TTSEngine {
        didSet { defaults.set(ttsEngine.rawValue, forKey: Keys.ttsEngine) }
    }

    var elevenLabsModel: String {
        didSet { defaults.set(elevenLabsModel, forKey: Keys.elevenLabsModel) }
    }

    var elevenLabsVoiceId: String {
        didSet { defaults.set(elevenLabsVoiceId, forKey: Keys.elevenLabsVoiceId) }
    }

    var elevenLabsVoiceName: String {
        didSet { defaults.set(elevenLabsVoiceName, forKey: Keys.elevenLabsVoiceName) }
    }

    var codexVoice: String {
        didSet { defaults.set(codexVoice, forKey: Keys.codexVoice) }
    }

    var speakingStyle: SpeakingStyle {
        didSet { defaults.set(speakingStyle.rawValue, forKey: Keys.speakingStyle) }
    }

    var disclosureEnabled: Bool {
        didSet { defaults.set(disclosureEnabled, forKey: Keys.disclosure) }
    }

    var codexHandsFree: Bool {
        didSet { defaults.set(codexHandsFree, forKey: Keys.codexHandsFree) }
    }

    var presentationReadingEnabled: Bool {
        didSet { defaults.set(presentationReadingEnabled, forKey: Keys.presentationReadingEnabled) }
    }

    var appAppearance: AppAppearance {
        didSet { defaults.set(appAppearance.rawValue, forKey: Keys.appAppearance) }
    }

    var hudLayoutStyle: HUDLayoutStyle {
        didSet { defaults.set(hudLayoutStyle.rawValue, forKey: Keys.hudLayoutStyle) }
    }

    var hudSize: HUDSizePreset {
        didSet { defaults.set(hudSize.rawValue, forKey: Keys.hudSize) }
    }

    var hudAnimationStyle: HUDAnimationStyle {
        didSet { defaults.set(hudAnimationStyle.rawValue, forKey: Keys.hudAnimationStyle) }
    }

    var hudAccentTheme: HUDAccentTheme {
        didSet { defaults.set(hudAccentTheme.rawValue, forKey: Keys.hudAccentTheme) }
    }

    var hudExpandOnHover: Bool {
        didSet { defaults.set(hudExpandOnHover, forKey: Keys.hudExpandOnHover) }
    }

    var hudAutoExpandOnVoice: Bool {
        didSet { defaults.set(hudAutoExpandOnVoice, forKey: Keys.hudAutoExpandOnVoice) }
    }

    var hudShowTranscript: Bool {
        didSet { defaults.set(hudShowTranscript, forKey: Keys.hudShowTranscript) }
    }

    var hudReplyHoldSeconds: Int {
        didSet { defaults.set(hudReplyHoldSeconds, forKey: Keys.hudReplyHoldSeconds) }
    }

    var hudOpacity: Double {
        didSet { defaults.set(hudOpacity, forKey: Keys.hudOpacity) }
    }

    var hudHideFromScreenShare: Bool {
        didSet { defaults.set(hudHideFromScreenShare, forKey: Keys.hudHideFromScreenShare) }
    }

    var backendSummaryEndpoint: String {
        didSet { defaults.set(backendSummaryEndpoint, forKey: Keys.backendSummaryEndpoint) }
    }

    var backendAuthScheme: BackendAuthScheme {
        didSet { defaults.set(backendAuthScheme.rawValue, forKey: Keys.backendAuthScheme) }
    }

    var backendAuthHeaderName: String {
        didSet { defaults.set(backendAuthHeaderName, forKey: Keys.backendAuthHeaderName) }
    }

    var summaryModel: String {
        didSet { defaults.set(summaryModel, forKey: Keys.summaryModel) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawProvider = defaults.string(forKey: Keys.provider) ?? ""
        self.provider = VoiceProvider(rawValue: rawProvider) ?? .antigravity
        let rawMode = defaults.string(forKey: Keys.listeningMode) ?? ""
        self.listeningMode = ListeningMode(rawValue: rawMode) ?? .standby
        self.agyModel = defaults.string(forKey: Keys.agyModel) ?? "gemini-3.8-flash-low"
        let whisper = defaults.string(forKey: Keys.whisperModel) ?? "small"
        self.whisperModel = Self.whisperModelOptions.contains(whisper) ? whisper : "small"
        self.ttsVoice = defaults.string(forKey: Keys.ttsVoice) ?? TTSVoiceCatalog.defaultVoice
        let storedRate = defaults.object(forKey: Keys.ttsRate) as? Int ?? 185
        self.ttsRate = min(max(storedRate, 130), 260)
        let rawTTSEngine = defaults.string(forKey: Keys.ttsEngine) ?? ""
        self.ttsEngine = TTSEngine(rawValue: rawTTSEngine) ?? .edge
        let storedElevenModel = defaults.string(forKey: Keys.elevenLabsModel) ?? Self.defaultElevenLabsModel
        self.elevenLabsModel = Self.elevenLabsModelOptions.contains(storedElevenModel)
            ? storedElevenModel
            : Self.defaultElevenLabsModel
        let storedElevenVoiceId = (defaults.string(forKey: Keys.elevenLabsVoiceId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.elevenLabsVoiceId = storedElevenVoiceId.isEmpty
            ? TTSVoiceCatalog.defaultElevenLabsVoiceId
            : storedElevenVoiceId
        let storedElevenVoiceName = (defaults.string(forKey: Keys.elevenLabsVoiceName) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.elevenLabsVoiceName = storedElevenVoiceName.isEmpty
            ? TTSVoiceCatalog.defaultElevenLabsVoiceName
            : storedElevenVoiceName
        let storedCodexVoice = (defaults.string(forKey: Keys.codexVoice) ?? "").lowercased()
        self.codexVoice = Self.codexVoiceOptions.contains(storedCodexVoice) ? storedCodexVoice : "cove"
        let rawStyle = defaults.string(forKey: Keys.speakingStyle) ?? ""
        self.speakingStyle = SpeakingStyle(rawValue: rawStyle) ?? .casual
        self.disclosureEnabled = defaults.object(forKey: Keys.disclosure) as? Bool ?? true
        self.codexHandsFree = defaults.object(forKey: Keys.codexHandsFree) as? Bool ?? true
        self.presentationReadingEnabled = defaults.object(forKey: Keys.presentationReadingEnabled) as? Bool ?? false
        let rawAppearance = defaults.string(forKey: Keys.appAppearance) ?? ""
        self.appAppearance = AppAppearance(rawValue: rawAppearance) ?? .dark
        let rawHUDLayout = defaults.string(forKey: Keys.hudLayoutStyle) ?? ""
        self.hudLayoutStyle = HUDLayoutStyle(rawValue: rawHUDLayout) ?? .notch
        let rawHUDSize = defaults.string(forKey: Keys.hudSize) ?? ""
        self.hudSize = HUDSizePreset(rawValue: rawHUDSize) ?? .standard
        let rawHUDAnimation = defaults.string(forKey: Keys.hudAnimationStyle) ?? ""
        self.hudAnimationStyle = HUDAnimationStyle(rawValue: rawHUDAnimation) ?? .wave
        let rawHUDAccent = defaults.string(forKey: Keys.hudAccentTheme) ?? ""
        self.hudAccentTheme = HUDAccentTheme(rawValue: rawHUDAccent) ?? .status
        self.hudExpandOnHover = defaults.object(forKey: Keys.hudExpandOnHover) as? Bool ?? true
        self.hudAutoExpandOnVoice = defaults.object(forKey: Keys.hudAutoExpandOnVoice) as? Bool ?? true
        self.hudShowTranscript = defaults.object(forKey: Keys.hudShowTranscript) as? Bool ?? true
        let storedHold = defaults.object(forKey: Keys.hudReplyHoldSeconds) as? Int ?? 5
        self.hudReplyHoldSeconds = min(max(storedHold, 2), 15)
        let storedOpacity = defaults.object(forKey: Keys.hudOpacity) as? Double ?? 1.0
        self.hudOpacity = min(max(storedOpacity, 0.75), 1.0)
        self.hudHideFromScreenShare = defaults.object(forKey: Keys.hudHideFromScreenShare) as? Bool ?? true
        let storedBackendEndpoint = (defaults.string(forKey: Keys.backendSummaryEndpoint) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.backendSummaryEndpoint = storedBackendEndpoint.isEmpty
            ? Self.defaultBackendSummaryEndpoint
            : storedBackendEndpoint
        let rawAuthScheme = defaults.string(forKey: Keys.backendAuthScheme) ?? ""
        self.backendAuthScheme = BackendAuthScheme(rawValue: rawAuthScheme) ?? .none
        let storedHeaderName = (defaults.string(forKey: Keys.backendAuthHeaderName) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.backendAuthHeaderName = storedHeaderName.isEmpty ? "X-API-Key" : storedHeaderName
        let storedSummaryModel = (defaults.string(forKey: Keys.summaryModel) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.summaryModel = storedSummaryModel.isEmpty ? Self.defaultSummaryModel : storedSummaryModel
    }

    func notulenBackendConfig() -> NotulenBackendConfig {
        NotulenBackendConfig(
            endpointURLString: backendSummaryEndpoint,
            authScheme: backendAuthScheme,
            customAuthHeaderName: backendAuthHeaderName
        )
    }

    func runtimeConfig() -> VoiceRuntimeConfig {
        VoiceRuntimeConfig(
            agyModel: agyModel,
            whisperModel: whisperModel,
            ttsVoice: ttsVoice,
            ttsRate: ttsRate,
            codexVoice: codexVoice,
            speakingStyle: speakingStyle.rawValue,
            listeningMode: listeningMode.rawValue,
            disclosure: disclosureEnabled,
            codexHandsFree: codexHandsFree,
            presentationReadingEnabled: presentationReadingEnabled,
            ttsEngine: ttsEngine.rawValue,
            elevenLabsModel: elevenLabsModel,
            elevenLabsVoiceId: elevenLabsVoiceId,
            elevenLabsVoiceName: elevenLabsVoiceName
        )
    }

    func encodedRuntimeConfig() -> String {
        guard let data = try? JSONEncoder().encode(runtimeConfig()) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
