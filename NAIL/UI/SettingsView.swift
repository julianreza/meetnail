import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case voiceAI
    case appearanceHUD
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .voiceAI: "Suara & AI"
        case .appearanceHUD: "Tampilan & HUD"
        case .system: "Sistem"
        }
    }

    var systemImage: String {
        switch self {
        case .voiceAI: "waveform.and.mic"
        case .appearanceHUD: "sparkles.rectangle.stack"
        case .system: "gearshape.2.fill"
        }
    }
}

private enum SettingsHUDPreviewStage: String, CaseIterable, Identifiable {
    case standby
    case listening
    case processing
    case speaking
    case interrupted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standby: "Siaga"
        case .listening: "Menyimak"
        case .processing: "Berpikir"
        case .speaking: "Berbicara"
        case .interrupted: "Mute"
        }
    }

    var mood: NailBotMood {
        switch self {
        case .standby: .standby
        case .listening: .listening
        case .processing: .processing
        case .speaking: .speaking
        case .interrupted: .interrupted
        }
    }

    var statusLine: String {
        switch self {
        case .standby: "Meet Nail · Siaga"
        case .listening: "Menyimak percakapan rapat..."
        case .processing: "Merangkai jawaban terbaik..."
        case .speaking: "Nail sedang berbicara..."
        case .interrupted: "Suara Nail dihentikan (Mute)"
        }
    }

    var compactPhase: String {
        switch self {
        case .standby: "Siaga"
        case .listening: "Menyimak"
        case .processing: "Berpikir"
        case .speaking: "Berbicara"
        case .interrupted: "Mute"
        }
    }

    var isAnimated: Bool {
        self == .listening || self == .processing || self == .speaking
    }
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var settings: VoiceSettings
    let isSessionActive: Bool

    @State private var activeTab: SettingsTab = .voiceAI
    @State private var voices: [String] = TTSVoiceCatalog.neuralVoices + ["Damayanti"]
    @State private var prerequisites: PrerequisiteStatus = PrerequisiteChecker.check()
    @State private var previewStage: SettingsHUDPreviewStage = .speaking
    @State private var previewSpeaking = true
    @State private var refreshPulse = 0
    @State private var elevenLabsAPIKeyInput = ""
    @State private var hasElevenLabsKey = false
    @State private var elevenLabsKeyStatus: String?
    @State private var elevenLabsVoices: [ElevenLabsVoice] = TTSVoiceCatalog.curatedElevenLabsVoices
    @State private var elevenLabsSubscription: ElevenLabsSubscription?
    @State private var isLoadingElevenLabs = false
    @State private var elevenLabsErrorMessage: String?
    @State private var customElevenLabsVoiceId = ""

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)

        GeometryReader { proxy in
            let isTwoColumn = proxy.size.width >= 860

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topHeaderSection(palette: palette)

                    Group {
                        switch activeTab {
                        case .voiceAI:
                            voiceAISection(palette: palette, isTwoColumn: isTwoColumn)
                        case .appearanceHUD:
                            appearanceHUDSection(palette: palette, isTwoColumn: isTwoColumn)
                        case .system:
                            systemSection(palette: palette, isTwoColumn: isTwoColumn)
                        }
                    }
                    .id(activeTab)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity
                        )
                    )
                }
                .animation(
                    reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85),
                    value: activeTab
                )
                .padding(22)
                .frame(maxWidth: 1200, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(palette.canvasGradient)
        .frame(minWidth: 540)
        .onAppear {
            customElevenLabsVoiceId = settings.elevenLabsVoiceId
            refreshChecks()
        }
        .onChange(of: settings.elevenLabsVoiceId) { _, newId in
            if customElevenLabsVoiceId != newId {
                customElevenLabsVoiceId = newId
            }
            if let matched = elevenLabsVoices.first(where: { $0.voiceId == newId }) {
                settings.elevenLabsVoiceName = matched.name
            }
        }
        .onChange(of: settings.whisperModel) { _, _ in
            refreshChecks()
        }
        .onChange(of: settings.presentationReadingEnabled) { _, enabled in
            MeetSession.shared.setPresentationReading(enabled)
        }
        .onChange(of: settings.hudSize) { _, _ in
            HUDPanel.shared.scheduleRefreshLayout()
        }
        .onChange(of: settings.hudLayoutStyle) { _, _ in
            HUDPanel.shared.scheduleRefreshLayout()
        }
        .onChange(of: settings.hudHideFromScreenShare) { _, _ in
            HUDPanel.shared.applySharingType()
        }
        .onChange(of: previewStage) { _, newStage in
            previewSpeaking = (newStage == .speaking)
        }
    }

    // MARK: - Top Header & Floating Category Pill

    private func topHeaderSection(palette: NailPalette) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TalmoPageHeader(
                title: "Pengaturan",
                subtitle: "\(settings.provider.shortBadge) · \(settings.speakingStyle.label) · HUD \(settings.hudLayoutStyle.label)"
            ) {
                if isSessionActive {
                    NailStatusBadge(
                        text: "Terkunci saat rapat aktif",
                        color: palette.textSecondary,
                        icon: "lock.fill"
                    )
                }
            }

            HStack(spacing: 12) {
                TalmoSegmentedPill(
                    options: Array(SettingsTab.allCases),
                    selection: $activeTab,
                    icon: { $0.systemImage },
                    label: { $0.label }
                )

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Tab 1: Suara & AI

    @ViewBuilder
    private func voiceAISection(palette: NailPalette, isTwoColumn: Bool) -> some View {
        if isTwoColumn {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    providerSelectionCard(palette: palette)
                    providerConfigurationCard(palette: palette)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 16) {
                    speakingStyleCard(palette: palette)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                providerSelectionCard(palette: palette)
                providerConfigurationCard(palette: palette)
                speakingStyleCard(palette: palette)
            }
        }
    }

    private func providerSelectionCard(palette: NailPalette) -> some View {
        TalmoCard {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Penyedia AI & Suara",
                    subtitle: "Pilih mesin suara & kecerdasan yang digunakan Nail saat rapat",
                    icon: "cpu.fill"
                )

                VStack(spacing: 10) {
                    providerCard(
                        provider: .codex,
                        tag: "Utama · Natural",
                        tagColor: palette.good,
                        subtitle: "Suara real-time ChatGPT yang ekspresif & responsif",
                        palette: palette
                    )
                    providerCard(
                        provider: .antigravity,
                        tag: "Cadangan · Lokal",
                        tagColor: palette.info,
                        subtitle: "Antigravity CLI + Whisper lokal & Neural TTS Indonesia",
                        palette: palette
                    )
                    providerCard(
                        provider: .deepseek,
                        tag: "Opsional",
                        tagColor: palette.textSecondary,
                        subtitle: "Pipeline lokal dengan suara bawaan (stella)",
                        palette: palette
                    )
                }
                .disabled(isSessionActive)
                .opacity(isSessionActive ? 0.6 : 1.0)
            }
        }
    }

    private func providerCard(
        provider: VoiceProvider,
        tag: String,
        tagColor: Color,
        subtitle: String,
        palette: NailPalette
    ) -> some View {
        let selected = settings.provider == provider
        return Button {
            if reduceMotion {
                settings.provider = provider
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    settings.provider = provider
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                selectionCheckCircle(selected: selected, palette: palette)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(provider.label)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        NailStatusBadge(text: tag, color: tagColor)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
            .padding(14)
            .background {
                neuSelectableSurface(selected: selected, cornerRadius: 16, palette: palette)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .nailHoverLift(cornerRadius: 16)
    }

    private func providerConfigurationCard(palette: NailPalette) -> some View {
        TalmoCard {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Konfigurasi Penyedia",
                    subtitle: settings.provider.label,
                    icon: "slider.horizontal.3"
                )

                Group {
                    switch settings.provider {
                    case .codex:
                        codexConfigView(palette: palette)
                    case .antigravity:
                        antigravityConfigView(palette: palette)
                    case .deepseek:
                        deepseekConfigView(palette: palette)
                    }
                }
                .id(settings.provider)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 5)),
                        removal: .opacity
                    )
                )
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84),
                value: settings.provider
            )
        }
    }

    @ViewBuilder
    private func codexConfigView(palette: NailPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NeuWell(padding: 14, cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Suara ChatGPT", selection: $settings.codexVoice) {
                        ForEach(VoiceSettings.codexPrimaryVoiceOptions, id: \.self) { voice in
                            Text(voice == "cove" ? "Cove (Default)" : voice.capitalized).tag(voice)
                        }
                        Divider()
                        ForEach(VoiceSettings.codexExtendedVoiceOptions, id: \.self) { voice in
                            Text(voice.capitalized).tag(voice)
                        }
                    }
                    .disabled(isSessionActive)

                    Divider()
                        .overlay(palette.hairline)

                    Toggle("Panggil otomatis dengan kata \"Nail\" (Hands-Free)", isOn: $settings.codexHandsFree)
                        .disabled(isSessionActive)

                    Divider()
                        .overlay(palette.hairline)

                    Picker("Model Whisper Lokal", selection: $settings.whisperModel) {
                        ForEach(VoiceSettings.whisperModelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .disabled(isSessionActive)
                }
            }

            NeuWell(padding: 12, cornerRadius: 14) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 1)

                    Text("Hands-Free menyimak kata \"Nail\" secara lokal lewat Whisper tanpa memakai kuota Codex sebelum dipanggil. Tombol manual \"Tanya\" tetap tersedia sebagai cadangan. Perubahan suara, gaya bicara, dan Hands-Free berlaku di sesi rapat berikutnya.")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var displayedElevenLabsVoices: [ElevenLabsVoice] {
        let currentId = settings.elevenLabsVoiceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentId.isEmpty,
              !elevenLabsVoices.contains(where: { $0.voiceId == currentId }) else {
            return elevenLabsVoices
        }
        let fallbackName = settings.elevenLabsVoiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let customVoice = ElevenLabsVoice(
            voiceId: currentId,
            name: fallbackName.isEmpty ? "Custom (\(String(currentId.prefix(8))))" : fallbackName,
            category: "custom"
        )
        return elevenLabsVoices + [customVoice]
    }

    @ViewBuilder
    private func antigravityConfigView(palette: NailPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NeuWell(padding: 14, cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Model Antigravity", selection: $settings.agyModel) {
                        ForEach(VoiceSettings.agyModelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .disabled(isSessionActive)

                    Divider()
                        .overlay(palette.hairline)

                    Picker("Model Whisper Lokal", selection: $settings.whisperModel) {
                        ForEach(VoiceSettings.whisperModelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .disabled(isSessionActive)

                    Divider()
                        .overlay(palette.hairline)

                    Picker("Mesin Suara (TTS)", selection: $settings.ttsEngine) {
                        ForEach(TTSEngine.allCases) { engine in
                            Text(engine.label).tag(engine)
                        }
                    }
                    .disabled(isSessionActive)

                    if settings.ttsEngine == .elevenlabs {
                        Divider()
                            .overlay(palette.hairline)

                        elevenLabsConfigSection(palette: palette)

                        Divider()
                            .overlay(palette.hairline)

                        Picker("Suara Cadangan (Edge / macOS)", selection: $settings.ttsVoice) {
                            ForEach(voices, id: \.self) { voice in
                                Text(TTSVoiceCatalog.displayName(for: voice)).tag(voice)
                            }
                        }
                        .disabled(isSessionActive)
                    } else {
                        Divider()
                            .overlay(palette.hairline)

                        Picker("Suara Indonesia (TTS)", selection: $settings.ttsVoice) {
                            ForEach(voices, id: \.self) { voice in
                                Text(TTSVoiceCatalog.displayName(for: voice)).tag(voice)
                            }
                        }
                        .disabled(isSessionActive)
                    }

                    Divider()
                        .overlay(palette.hairline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("Kecepatan (\(settings.ttsRate) wpm)")
                                .font(.callout.weight(.medium))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(palette.textPrimary)
                                .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: settings.ttsRate)

                            Spacer()

                            Button("Uji Suara") {
                                TTSVoiceCatalog.preview(
                                    voice: settings.ttsVoice,
                                    rate: settings.ttsRate,
                                    ttsEngine: settings.ttsEngine,
                                    elevenLabsVoiceId: settings.elevenLabsVoiceId,
                                    elevenLabsModel: settings.elevenLabsModel
                                )
                            }
                            .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
                        }

                        Slider(
                            value: Binding(
                                get: { Double(settings.ttsRate) },
                                set: { settings.ttsRate = Int($0.rounded()) }
                            ),
                            in: 140...230,
                            step: 5
                        )
                    }
                }
            }

            if settings.ttsEngine == .elevenlabs {
                NeuWell(padding: 12, cornerRadius: 14) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.top, 1)

                        Text("ElevenLabs memakai kuota akun (10.000 kredit gratis/bulan di paket Free). Jika kredit habis, API gagal, atau offline, Nail otomatis beralih ke Edge Neural lalu Damayanti macOS.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if TTSVoiceCatalog.isNeuralVoice(settings.ttsVoice) {
                NeuWell(padding: 12, cornerRadius: 14) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "waveform.and.mic")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.top, 1)

                        Text("Suara Neural Bahasa Indonesia memakai pelafalan penutur asli (butuh internet; otomatis kembali ke Damayanti macOS jika offline).")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if !TTSVoiceCatalog.hasEnhancedVoice(in: voices) {
                NeuWell(padding: 12, cornerRadius: 14) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.top, 1)

                        Text("Tip: unduh suara Enhanced Bahasa Indonesia di Pengaturan Sistem → Aksesibilitas → Konten Ucapan untuk suara lebih natural.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func elevenLabsConfigSection(palette: NailPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("ElevenLabs API Key")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                NailStatusBadge(
                    text: hasElevenLabsKey ? "Tersimpan di Keychain" : "Belum tersimpan",
                    color: hasElevenLabsKey ? palette.good : palette.warn,
                    icon: hasElevenLabsKey ? "key.fill" : "exclamationmark.triangle"
                )
            }

            HStack(spacing: 8) {
                SecureField(
                    hasElevenLabsKey
                        ? "API key tersimpan (isi untuk mengganti)"
                        : "Masukkan ElevenLabs API Key",
                    text: $elevenLabsAPIKeyInput
                )
                .textFieldStyle(.roundedBorder)
                .disabled(isSessionActive)

                Button("Simpan") {
                    saveElevenLabsAPIKey()
                }
                .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true))
                .disabled(
                    isSessionActive
                        || elevenLabsAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button("Hapus") {
                    deleteElevenLabsAPIKey()
                }
                .buttonStyle(NailPillButtonStyle(variant: .danger, compact: true))
                .disabled(isSessionActive || !hasElevenLabsKey)
            }

            HStack(spacing: 8) {
                Button {
                    loadElevenLabsAccountData()
                } label: {
                    HStack(spacing: 6) {
                        if isLoadingElevenLabs {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isLoadingElevenLabs ? "Memuat…" : "Cek Kuota & Muat Suara")
                    }
                }
                .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
                .disabled(isLoadingElevenLabs)

                if let subscription = elevenLabsSubscription {
                    let remainingText = "\(subscription.remainingCharacters.formatted()) / \(subscription.characterLimit.formatted()) karakter tersisa"
                    let quotaColor: Color = subscription.remainingCharacters > 1000
                        ? palette.good
                        : (subscription.remainingCharacters > 0 ? palette.warn : palette.bad)
                    NailStatusBadge(
                        text: subscription.tier.map { "\($0.capitalized) · \(remainingText)" } ?? remainingText,
                        color: quotaColor,
                        icon: "gauge.medium"
                    )
                }

                Spacer(minLength: 0)
            }

            if let elevenLabsKeyStatus, !elevenLabsKeyStatus.isEmpty {
                Text(elevenLabsKeyStatus)
                    .font(.caption)
                    .foregroundStyle(palette.good)
            }

            if let elevenLabsErrorMessage, !elevenLabsErrorMessage.isEmpty {
                Text(elevenLabsErrorMessage)
                    .font(.caption)
                    .foregroundStyle(palette.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .overlay(palette.hairline)

            Picker("Model ElevenLabs", selection: $settings.elevenLabsModel) {
                ForEach(VoiceSettings.elevenLabsModelOptions, id: \.self) { model in
                    Text(TTSVoiceCatalog.elevenLabsModelDisplayName(for: model)).tag(model)
                }
            }
            .disabled(isSessionActive)

            Picker("Suara ElevenLabs", selection: $settings.elevenLabsVoiceId) {
                ForEach(displayedElevenLabsVoices) { voice in
                    Text(voice.name).tag(voice.voiceId)
                }
            }
            .disabled(isSessionActive)

            HStack(spacing: 8) {
                Text("Custom Voice ID")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(palette.textPrimary)

                TextField("Opsional (contoh: EXAVITQu4vr4xnSDxMaL)", text: $customElevenLabsVoiceId)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .disabled(isSessionActive)
                    .onChange(of: customElevenLabsVoiceId) { _, rawValue in
                        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed != settings.elevenLabsVoiceId else { return }
                        settings.elevenLabsVoiceId = trimmed
                        if let matched = elevenLabsVoices.first(where: { $0.voiceId == trimmed }) {
                            settings.elevenLabsVoiceName = matched.name
                        } else {
                            settings.elevenLabsVoiceName = "Custom (\(String(trimmed.prefix(8))))"
                        }
                    }
            }
        }
    }

    private func saveElevenLabsAPIKey() {
        let trimmed = elevenLabsAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if ElevenLabsKeychain.save(trimmed) {
            hasElevenLabsKey = true
            elevenLabsAPIKeyInput = ""
            elevenLabsErrorMessage = nil
            elevenLabsKeyStatus = "API key disimpan ke Keychain macOS."
        } else {
            elevenLabsKeyStatus = nil
            elevenLabsErrorMessage = "Gagal menyimpan API key ke Keychain macOS."
        }
    }

    private func deleteElevenLabsAPIKey() {
        if ElevenLabsKeychain.delete() {
            hasElevenLabsKey = false
            elevenLabsAPIKeyInput = ""
            elevenLabsSubscription = nil
            elevenLabsVoices = TTSVoiceCatalog.curatedElevenLabsVoices
            elevenLabsErrorMessage = nil
            elevenLabsKeyStatus = "API key dihapus dari Keychain."
        } else {
            elevenLabsKeyStatus = nil
            elevenLabsErrorMessage = "Gagal menghapus API key dari Keychain."
        }
    }

    private func loadElevenLabsAccountData() {
        guard !isLoadingElevenLabs else { return }
        let inlineKey = elevenLabsAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = inlineKey.isEmpty ? (ElevenLabsKeychain.load() ?? "") : inlineKey
        guard !apiKey.isEmpty else {
            elevenLabsErrorMessage = "Masukkan atau simpan ElevenLabs API key terlebih dahulu."
            return
        }

        isLoadingElevenLabs = true
        elevenLabsErrorMessage = nil
        elevenLabsKeyStatus = nil

        Task {
            do {
                async let subscriptionTask = TTSVoiceCatalog.fetchElevenLabsSubscription(apiKey: apiKey)
                async let voicesTask = TTSVoiceCatalog.fetchElevenLabsVoices(apiKey: apiKey)
                let (subscription, fetchedVoices) = try await (subscriptionTask, voicesTask)
                await MainActor.run {
                    elevenLabsSubscription = subscription
                    if !fetchedVoices.isEmpty {
                        elevenLabsVoices = fetchedVoices
                        if let matched = fetchedVoices.first(where: { $0.voiceId == settings.elevenLabsVoiceId }) {
                            settings.elevenLabsVoiceName = matched.name
                        }
                    }
                    isLoadingElevenLabs = false
                }
            } catch {
                await MainActor.run {
                    elevenLabsErrorMessage = friendlyElevenLabsErrorMessage(error)
                    isLoadingElevenLabs = false
                }
            }
        }
    }

    private func friendlyElevenLabsErrorMessage(_ error: Error) -> String {
        if let apiError = error as? ElevenLabsAPIError, let description = apiError.errorDescription {
            return description
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Tidak ada koneksi internet. Cek jaringan kamu lalu coba lagi."
            case .timedOut:
                return "Koneksi ke ElevenLabs habis waktu (timeout). Coba lagi sebentar."
            default:
                return "Gagal terhubung ke ElevenLabs (\(urlError.localizedDescription))."
            }
        }
        return "Gagal memuat data ElevenLabs: \(error.localizedDescription)"
    }

    @ViewBuilder
    private func deepseekConfigView(palette: NailPalette) -> some View {
        NeuWell(padding: 14, cornerRadius: 16) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title3)
                    .foregroundStyle(palette.textSecondary)
                Text("DeepSeek menggunakan suara bawaan pipeline lokal (stella).")
                    .font(.callout)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func speakingStyleCard(palette: NailPalette) -> some View {
        TalmoCard {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Gaya Bicara & Pengungkapan",
                    subtitle: "Atur nada bicara dan kepribadian Nail saat menjawab",
                    icon: "text.bubble.fill"
                )

                VStack(spacing: 10) {
                    ForEach(SpeakingStyle.allCases) { style in
                        let selected = settings.speakingStyle == style
                        Button {
                            if reduceMotion {
                                settings.speakingStyle = style
                            } else {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                    settings.speakingStyle = style
                                }
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                selectionCheckCircle(selected: selected, palette: palette)
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(style.label)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    Text(style.description)
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 8)
                            }
                            .padding(14)
                            .background {
                                neuSelectableSurface(selected: selected, cornerRadius: 16, palette: palette)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .nailHoverLift(cornerRadius: 16)
                    }
                }
                .disabled(isSessionActive)
                .opacity(isSessionActive ? 0.6 : 1.0)

                Divider()
                    .overlay(palette.hairline)

                NeuWell(padding: 14, cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Baca presentasi Google Meet", isOn: $settings.presentationReadingEnabled)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(palette.textPrimary)
                        Text("Nail membaca presentasi saat diminta. Gambar dapat dikirim ke Codex untuk pertanyaan visual.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Tab 2: Tampilan & HUD

    @ViewBuilder
    private func appearanceHUDSection(palette: NailPalette, isTwoColumn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            hudLivePreviewInkCard(palette: palette)

            if isTwoColumn {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        appThemeCard(palette: palette)
                        hudLayoutShapeCard(palette: palette)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 16) {
                        hudBehaviorAndMetricsCard(palette: palette)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    appThemeCard(palette: palette)
                    hudLayoutShapeCard(palette: palette)
                    hudBehaviorAndMetricsCard(palette: palette)
                }
            }
        }
    }

    private func hudLivePreviewInkCard(palette: NailPalette) -> some View {
        TalmoInkCard(padding: 20, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        NailSectionTitle(
                            title: "Pratinjau Langsung HUD",
                            subtitle: "Simulasikan tampilan HUD, ekspresi karakter 3D, dan transparansi secara langsung",
                            icon: "sparkles.rectangle.stack",
                            onInk: true
                        )

                        Spacer(minLength: 12)

                        hudPreviewActionControls(palette: palette)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        NailSectionTitle(
                            title: "Pratinjau Langsung HUD",
                            subtitle: "Simulasikan tampilan HUD, ekspresi karakter 3D, dan transparansi secara langsung",
                            icon: "sparkles.rectangle.stack",
                            onInk: true
                        )

                        hudPreviewActionControls(palette: palette)
                    }
                }

                miniHUDLivePreview(palette: palette)
            }
        }
    }

    private func hudPreviewActionControls(palette: NailPalette) -> some View {
        HStack(spacing: 8) {
            inkStageTogglePill(palette: palette)

            Button("Tampilkan / Sembunyikan HUD") {
                HUDPanel.shared.toggle()
            }
            .buttonStyle(NailPillButtonStyle(variant: .inkSecondary, compact: true))

            Button("Uji di Layar") {
                HUDPanel.shared.triggerSpeakingPreview()
            }
            .buttonStyle(NailPillButtonStyle(variant: .inkPrimary, compact: true))
        }
    }

    private func inkStageTogglePill(palette: NailPalette) -> some View {
        HStack(spacing: 3) {
            ForEach(SettingsHUDPreviewStage.allCases) { stage in
                let isSelected = previewStage == stage
                Button {
                    if reduceMotion {
                        previewStage = stage
                        previewSpeaking = (stage == .speaking)
                    } else {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            previewStage = stage
                            previewSpeaking = (stage == .speaking)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(stageDotColor(stage: stage, isSelected: isSelected, palette: palette))
                            .frame(width: 5.5, height: 5.5)

                        Text(stage.label)
                            .font(.caption.weight(isSelected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? Color(hex: 0x0A0A0A) : palette.inkCardMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(palette.inkCardFill)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(palette.inkCardSurface)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(palette.inkCardLine, lineWidth: 1)
                }
        }
    }

    private func stageDotColor(stage: SettingsHUDPreviewStage, isSelected: Bool, palette: NailPalette) -> Color {
        if isSelected {
            return stage == .standby ? Color(hex: 0x0A0A0A).opacity(0.55) : palette.goldBright
        }
        switch stage {
        case .standby:
            return Color(hex: 0x7A7A7A)
        case .listening:
            return Color(hex: 0xBDBDBD)
        case .processing:
            return palette.goldBright.opacity(0.85)
        case .speaking:
            return Color(hex: 0xF5F5F5)
        case .interrupted:
            return Color(hex: 0x9E9E9E)
        }
    }

    private func miniHUDLivePreview(palette: NailPalette) -> some View {
        let accent = previewAccentColor(palette: palette)
        let isNotch = settings.hudLayoutStyle == .notch

        return ZStack(alignment: .top) {
            // Studio Obsidian Stage (#111111) with subtle monochrome architectural grid
            Color(hex: 0x111111)
                .overlay {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height

                        ZStack {
                            Path { path in
                                let rows = 3
                                for row in 1...rows {
                                    let y = h * CGFloat(row) / CGFloat(rows + 1)
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: w, y: y))
                                }
                                let cols = 5
                                for col in 1...cols {
                                    let x = w * CGFloat(col) / CGFloat(cols + 1)
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: h))
                                }
                            }
                            .stroke(Color.white.opacity(0.032), lineWidth: 1)

                            if isNotch {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 1)
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }
                        }
                    }
                }

            VStack(spacing: 0) {
                if !isNotch {
                    Spacer(minLength: 8)
                }

                miniHUDChip(accent: accent, isNotch: isNotch)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.80),
                        value: settings.hudLayoutStyle
                    )
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.80),
                        value: settings.hudSize
                    )

                Spacer(minLength: 36)
            }

            // Bottom studio telemetry bar
            HStack(spacing: 8) {
                hudTelemetryTag(text: settings.hudLayoutStyle.label)
                hudTelemetryTag(text: "Ukuran \(settings.hudSize.label)")
                hudTelemetryTag(text: "Opasitas \(Int((settings.hudOpacity * 100).rounded()))%")
                if settings.hudHideFromScreenShare {
                    hudTelemetryTag(text: "Stealth Share")
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        }
    }

    private func hudTelemetryTag(text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(Color(hex: 0xA4A4A4))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.05), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            }
    }

    private func miniHUDChip(accent: Color, isNotch: Bool) -> some View {
        let isAnimated = previewStage.isAnimated && !reduceMotion
        let previewOwlSize: CGFloat = switch settings.hudSize {
        case .compact: 56
        case .standard: 66
        case .large: 74
        case .extraLarge: 82
        }

        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !previewStage.isAnimated || reduceMotion)) { context in
            let t = isAnimated ? context.date.timeIntervalSinceReferenceDate : 0.0
            let speakingEnergy: Double = switch previewStage {
            case .speaking:
                isAnimated ? (0.72 + 0.24 * sin(t * 3.1) * cos(t * 1.8)) : 0.68
            case .standby, .listening, .processing, .interrupted:
                0.0
            }
            let listeningEnergy: Double = switch previewStage {
            case .speaking:
                isAnimated ? (0.20 + 0.08 * sin(t * 2.2)) : 0.16
            case .listening:
                isAnimated ? (0.50 + 0.22 * sin(t * 2.4) * cos(t * 1.35)) : 0.45
            case .standby, .processing, .interrupted:
                0.0
            }

            Group {
                if previewStage == .standby {
                    miniHUDStandbyWings(
                        accent: accent,
                        isNotch: isNotch,
                        phase: t
                    )
                } else {
                    VStack(spacing: 6) {
                        if isNotch {
                            simulatedHardwareNotchBar(width: 112, height: 20)
                        }

                        NokoFloatingCompanionStage(
                            mood: previewStage.mood,
                            phase: t,
                            speakingEnergy: speakingEnergy,
                            listeningEnergy: listeningEnergy,
                            accentColor: accent,
                            owlSize: previewOwlSize,
                            isPaused: reduceMotion
                        )
                        .opacity(settings.hudOpacity)
                    }
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82),
                value: previewStage
            )
        }
    }

    private func simulatedNotchCameraDot(size: CGFloat) -> some View {
        let glintSize = size * 0.42
        let glintOffset = -size * 0.08
        return ZStack {
            Circle()
                .fill(Color(hex: 0x16181D))
                .frame(width: size, height: size)
            Circle()
                .fill(Color(hex: 0x2B3648))
                .frame(width: glintSize, height: glintSize)
                .offset(x: glintOffset, y: glintOffset)
        }
    }

    private func simulatedHardwareNotchBar(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color(hex: 0x000000))
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            }

            simulatedNotchCameraDot(size: 6)
        }
        .frame(width: width, height: height)
    }

    private func miniHUDStandbyWings(
        accent: Color,
        isNotch: Bool,
        phase: Double
    ) -> some View {
        Group {
            if isNotch {
                // Keep the centered MacBook notch optically centered with an empty left offset (no left filler box)
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 46, height: 34)

                    HStack(spacing: 0) {
                        simulatedNotchCameraDot(size: 7)
                            .frame(width: 112, height: 34)

                        NailBotFaceView(
                            mood: .standby,
                            form: .miniEyes,
                            phase: phase,
                            speakingEnergy: 0,
                            listeningEnergy: 0,
                            accentColor: accent,
                            size: CGSize(width: 26, height: 14),
                            isPaused: reduceMotion
                        )
                        .opacity(settings.hudOpacity)
                        .frame(width: 46, height: 34)
                    }
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 14,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                        .fill(Color(hex: 0x000000))
                        .overlay {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 12,
                                bottomTrailingRadius: 14,
                                topTrailingRadius: 0,
                                style: .continuous
                            )
                            .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.60), radius: 10, y: 4)
                    }
                }
            } else {
                NailBotFaceView(
                    mood: .standby,
                    form: .miniEyes,
                    phase: phase,
                    speakingEnergy: 0,
                    listeningEnergy: 0,
                    accentColor: accent,
                    size: CGSize(width: 26, height: 14),
                    isPaused: reduceMotion
                )
                .frame(width: 46, height: 36)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(hex: 0x080808))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.55), radius: 12, y: 5)
                }
                .opacity(settings.hudOpacity)
            }
        }
    }

    private func previewAccentColor(palette: NailPalette) -> Color {
        switch settings.hudAccentTheme {
        case .status:
            return palette.goldBright
        case .ocean:
            return palette.gold
        case .violet:
            return Color(hex: 0x9F8FE0)
        case .emerald:
            return Color(hex: 0x6BBF8E)
        }
    }

    private func appThemeCard(palette: NailPalette) -> some View {
        TalmoCard {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Tema Aplikasi",
                    subtitle: "Pilih tampilan jendela utama Meet Nail",
                    icon: "circle.lefthalf.filled"
                )

                HStack(spacing: 12) {
                    ForEach(AppAppearance.allCases) { appearance in
                        let selected = settings.appAppearance == appearance
                        Button {
                            if reduceMotion {
                                settings.appAppearance = appearance
                            } else {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                    settings.appAppearance = appearance
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                appearanceMiniSwatch(appearance: appearance, palette: palette)

                                HStack(spacing: 7) {
                                    Image(systemName: appearance.systemImage)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)

                                    Text(appearance.label)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1)

                                    Spacer(minLength: 4)

                                    selectionCheckCircle(selected: selected, palette: palette, size: 17)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                neuSelectableSurface(selected: selected, cornerRadius: 16, palette: palette)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .nailHoverLift(cornerRadius: 16)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func appearanceMiniSwatch(appearance: AppAppearance, palette: NailPalette) -> some View {
        switch appearance {
        case .dark:
            miniThemeSurfacePreview(
                canvas: Color(hex: 0x161920),
                sidebar: Color(hex: 0x14171D),
                card: Color(hex: 0x1E222B),
                ink: Color(hex: 0xF2F2F2),
                goldDot: palette.goldBright
            )
        case .light:
            miniThemeSurfacePreview(
                canvas: Color(hex: 0xE7ECF2),
                sidebar: Color(hex: 0xE3E9F0),
                card: Color(hex: 0xF1F5F9),
                ink: Color(hex: 0x141922),
                goldDot: palette.goldBright
            )
        case .system:
            GeometryReader { geo in
                HStack(spacing: 0) {
                    miniThemeSurfacePreview(
                        canvas: Color(hex: 0x161920),
                        sidebar: Color(hex: 0x14171D),
                        card: Color(hex: 0x1E222B),
                        ink: Color(hex: 0xF2F2F2),
                        goldDot: palette.goldBright
                    )
                    .frame(width: geo.size.width / 2)
                    .clipped()

                    miniThemeSurfacePreview(
                        canvas: Color(hex: 0xE7ECF2),
                        sidebar: Color(hex: 0xE3E9F0),
                        card: Color(hex: 0xF1F5F9),
                        ink: Color(hex: 0x141922),
                        goldDot: palette.goldBright
                    )
                    .frame(width: geo.size.width / 2)
                    .clipped()
                }
            }
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.hairlineStrong, lineWidth: 1)
            }
        }
    }

    private func miniThemeSurfacePreview(
        canvas: Color,
        sidebar: Color,
        card: Color,
        ink: Color,
        goldDot: Color
    ) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(sidebar)
                .frame(width: 18)
                .overlay(alignment: .top) {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(ink.opacity(0.85))
                            .frame(width: 5, height: 5)
                        Circle()
                            .fill(goldDot)
                            .frame(width: 3.5, height: 3.5)
                    }
                    .padding(.top, 5)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Capsule(style: .continuous)
                        .fill(ink.opacity(0.82))
                        .frame(width: 22, height: 4)
                    Capsule(style: .continuous)
                        .fill(goldDot)
                        .frame(width: 5, height: 4)
                }

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(card)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(card)
                }
            }
            .padding(.vertical, 3)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(canvas)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ink.opacity(0.14), lineWidth: 1)
        }
    }

    private func hudLayoutShapeCard(palette: NailPalette) -> some View {
        TalmoCard {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Bentuk HUD",
                    subtitle: "Pilih geometri HUD mengambang di layar Anda",
                    icon: "macwindow.on.rectangle"
                )

                VStack(spacing: 10) {
                    ForEach(HUDLayoutStyle.allCases) { style in
                        let selected = settings.hudLayoutStyle == style
                        Button {
                            if reduceMotion {
                                settings.hudLayoutStyle = style
                            } else {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                    settings.hudLayoutStyle = style
                                }
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                hudShapeDiagram(style: style, selected: selected, palette: palette)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(style.label)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    Text(style.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 8)

                                selectionCheckCircle(selected: selected, palette: palette)
                            }
                            .padding(14)
                            .background {
                                neuSelectableSurface(selected: selected, cornerRadius: 16, palette: palette)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .nailHoverLift(cornerRadius: 16)
                    }
                }
            }
        }
    }

    private func hudShapeDiagram(style: HUDLayoutStyle, selected: Bool, palette: NailPalette) -> some View {
        ZStack(alignment: style == .notch ? .top : .center) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: 0x111111))
                .frame(width: 56, height: 38)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

            if style == .notch {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color(hex: 0xF5F5F5))
                .frame(width: 28, height: 11)
            } else {
                Capsule(style: .continuous)
                    .fill(Color(hex: 0xF5F5F5))
                    .frame(width: 32, height: 11)
            }
        }
    }

    private func hudBehaviorAndMetricsCard(palette: NailPalette) -> some View {
        let opacityPercent = Int((settings.hudOpacity * 100).rounded())

        return TalmoCard {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Ukuran, Tema & Perilaku HUD",
                    subtitle: "Sesuaikan dimensi, tema aksen, dan respons HUD saat rapat",
                    icon: "sparkles"
                )

                NeuWell(padding: 14, cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Ukuran HUD", selection: $settings.hudSize) {
                            ForEach(HUDSizePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }

                        Divider()
                            .overlay(palette.hairline)

                        Picker("Tema Warna", selection: $settings.hudAccentTheme) {
                            ForEach(HUDAccentTheme.allCases) { theme in
                                Text(theme.label).tag(theme)
                            }
                        }
                    }
                }

                NeuWell(padding: 14, cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Lama tampil jawaban")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text("\(settings.hudReplyHoldSeconds) dtk")
                                    .font(.callout.weight(.semibold))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .foregroundStyle(palette.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(palette.neuSurfaceGradient, in: Capsule(style: .continuous))
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(palette.hairlineStrong, lineWidth: 0.8)
                                    }
                                    .animation(
                                        reduceMotion ? nil : .snappy(duration: 0.18),
                                        value: settings.hudReplyHoldSeconds
                                    )
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(settings.hudReplyHoldSeconds) },
                                    set: { settings.hudReplyHoldSeconds = Int($0.rounded()) }
                                ),
                                in: 2...15,
                                step: 1
                            )

                            HStack {
                                Text("2 dtk")
                                Spacer()
                                Text("15 dtk")
                            }
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(palette.textTertiary)
                        }

                        Divider()
                            .overlay(palette.hairline)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Opasitas HUD")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text("\(opacityPercent)%")
                                    .font(.callout.weight(.semibold))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .foregroundStyle(palette.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(palette.neuSurfaceGradient, in: Capsule(style: .continuous))
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(palette.hairlineStrong, lineWidth: 0.8)
                                    }
                                    .animation(
                                        reduceMotion ? nil : .snappy(duration: 0.18),
                                        value: opacityPercent
                                    )
                            }

                            Slider(
                                value: $settings.hudOpacity,
                                in: 0.75...1.0,
                                step: 0.05
                            )

                            HStack {
                                Text("75%")
                                Spacer()
                                Text("100%")
                            }
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(palette.textTertiary)
                        }
                    }
                }

                NeuWell(padding: 14, cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Buka saat kursor diarahkan (Hover)", isOn: $settings.hudExpandOnHover)
                            .font(.callout.weight(.medium))
                        Divider()
                            .overlay(palette.hairline)
                        Toggle("Buka otomatis saat Nail aktif / bicara", isOn: $settings.hudAutoExpandOnVoice)
                            .font(.callout.weight(.medium))
                        Divider()
                            .overlay(palette.hairline)
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Sembunyikan HUD saat Share Screen (Stealth)", isOn: $settings.hudHideFromScreenShare)
                                .font(.callout.weight(.medium))
                            Text("HUD tidak terlihat oleh peserta rapat saat Anda melakukan share screen.")
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                            .overlay(palette.hairline)
                        Text("HUD hanya menampilkan karakter Noko-Owl & animasi — detail percakapan ada di jendela Desktop.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Tab 3: Sistem

    @ViewBuilder
    private func systemSection(palette: NailPalette, isTwoColumn: Bool) -> some View {
        let readyCount = [
            prerequisites.electronBundled,
            prerequisites.agyInstalled,
            prerequisites.uvInstalled,
            prerequisites.ffmpegInstalled,
            prerequisites.whisperModelCached,
            prerequisites.meetProfileExists,
        ].filter { $0 }.count

        VStack(alignment: .leading, spacing: 16) {
            systemReadinessHeroCard(readyCount: readyCount, palette: palette)

            let columns = isTwoColumn
                ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
                : [GridItem(.flexible(), spacing: 14)]

            LazyVGrid(columns: columns, spacing: 14) {
                prerequisiteCard(
                    title: "Electron",
                    subtitle: "Runtime Electron tertanam",
                    icon: "macwindow.badge.plus",
                    ok: prerequisites.electronBundled,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.00)

                prerequisiteCard(
                    title: "Antigravity CLI (agy)",
                    subtitle: "Mesin AI cadangan lokal",
                    icon: "terminal.fill",
                    ok: prerequisites.agyInstalled,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.04)

                prerequisiteCard(
                    title: "uv",
                    subtitle: "Python offline runner",
                    icon: "bolt.horizontal.circle.fill",
                    ok: prerequisites.uvInstalled,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.08)

                prerequisiteCard(
                    title: "ffmpeg",
                    subtitle: "Pemrosesan audio rapat",
                    icon: "waveform.path.ecg",
                    ok: prerequisites.ffmpegInstalled,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.12)

                prerequisiteCard(
                    title: "Bobot Whisper",
                    subtitle: "Model lokal (\(settings.whisperModel))",
                    icon: "ear.and.waveform",
                    ok: prerequisites.whisperModelCached,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.16)

                prerequisiteCard(
                    title: "Profil Login Google Meet",
                    subtitle: "Sesi browser terautentikasi",
                    icon: "person.crop.circle.badge.checkmark",
                    ok: prerequisites.meetProfileExists,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.20)
            }
        }
    }

    private func systemReadinessHeroCard(readyCount: Int, palette: NailPalette) -> some View {
        let progress = min(max(Double(readyCount) / 6.0, 0.0), 1.0)

        return TalmoInkCard(padding: 22, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        readinessMetricBlock(readyCount: readyCount, palette: palette)
                        Spacer(minLength: 16)
                        readinessActionButtons
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        readinessMetricBlock(readyCount: readyCount, palette: palette)
                        readinessActionButtons
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        let fillWidth = max(0, geo.size.width * progress)
                        let tipWidth = min(16.0, fillWidth)

                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(palette.inkCardTrack)
                                .frame(height: 8)

                            Capsule(style: .continuous)
                                .fill(palette.inkCardFill)
                                .frame(width: fillWidth, height: 8)

                            if fillWidth > 0 {
                                Capsule(style: .continuous)
                                    .fill(palette.goldBright)
                                    .frame(width: tipWidth, height: 8)
                                    .shadow(color: palette.goldBright.opacity(0.65), radius: 5, x: 0, y: 0)
                                    .offset(x: max(0, fillWidth - tipWidth))
                            }
                        }
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82),
                            value: readyCount
                        )
                    }
                    .frame(height: 8)

                    Text(
                        readyCount == 6
                            ? "Semua prasyarat sistem siap digunakan"
                            : "Lengkapi komponen yang belum siap agar rapat berjalan lancar"
                    )
                    .font(.caption)
                    .foregroundStyle(palette.inkCardMuted)
                }
            }
        }
    }

    private func readinessMetricBlock(readyCount: Int, palette: NailPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(readyCount)/6")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
                .tracking(-0.8)
                .foregroundStyle(palette.inkCardFill)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82),
                    value: readyCount
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Komponen Siap")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(palette.inkCardText)

                    NailStatusBadge(
                        text: readyCount == 6 ? "Optimal" : "Perlu Perhatian",
                        color: readyCount == 6 ? palette.inkCardFill : palette.goldBright,
                        onInk: true
                    )
                }

                Text("Pemeriksaan kesiapan lingkungan lokal Meet Nail")
                    .font(.caption)
                    .foregroundStyle(palette.inkCardMuted)
            }
        }
    }

    private var readinessActionButtons: some View {
        HStack(spacing: 10) {
            Button {
                refreshPulse += 1
                refreshChecks()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .symbolEffect(.bounce, value: refreshPulse)
                    Text("Periksa Ulang")
                }
            }
            .buttonStyle(NailPillButtonStyle(variant: .inkSecondary, compact: false))

            Button("Login Google untuk Nail") {
                MeetSession.shared.signIn()
            }
            .buttonStyle(NailPillButtonStyle(variant: .inkPrimary, compact: false))
            .disabled(isSessionActive)
        }
    }

    private func prerequisiteCard(
        title: String,
        subtitle: String,
        icon: String,
        ok: Bool,
        palette: NailPalette
    ) -> some View {
        let dotColor = ok ? palette.good : palette.bad

        return TalmoCard(padding: 16, cornerRadius: 20) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.neuWellGradient)
                        .frame(width: 38, height: 38)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(palette.hairlineStrong, lineWidth: 1)
                        }
                        .overlay {
                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                        }

                    Circle()
                        .fill(dotColor)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle()
                                .strokeBorder(palette.card, lineWidth: 1.5)
                        }
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)

                    Text(ok ? "Siap" : "Belum")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ok ? palette.textPrimary : palette.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8.5)
                .padding(.vertical, 3.5)
                .background(palette.neuWellGradient, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(palette.hairlineStrong, lineWidth: 0.8)
                }
            }
        }
    }

    // MARK: - Shared Selection Indicator & Helpers

    @ViewBuilder
    private func neuSelectableSurface(
        selected: Bool,
        cornerRadius: CGFloat = 16,
        palette: NailPalette
    ) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.neuSurfaceGradient)
                .shadow(
                    color: palette.neuShadowLight,
                    radius: palette.isDark ? 4 : 5,
                    x: -2.5,
                    y: -2.5
                )
                .shadow(
                    color: palette.neuShadowDark.opacity(palette.isDark ? 0.85 : 0.88),
                    radius: palette.isDark ? 5 : 6,
                    x: 3,
                    y: 3
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(palette.accent, lineWidth: 1.5)
                }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.neuWellGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(palette.hairline, lineWidth: 1.0)
                }
        }
    }

    private func selectionCheckCircle(
        selected: Bool,
        palette: NailPalette,
        size: CGFloat = 20
    ) -> some View {
        ZStack {
            Circle()
                .fill(selected ? palette.accent : palette.well)
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .strokeBorder(
                            selected ? palette.accent : palette.hairlineStrong,
                            lineWidth: selected ? 1.5 : 1.25
                        )
                }

            if selected {
                Circle()
                    .strokeBorder(palette.goldBright.opacity(0.60), lineWidth: 1.0)
                    .frame(width: max(4, size - 5), height: max(4, size - 5))

                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(palette.accentInk)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.80), value: selected)
    }

    private func refreshChecks() {
        let model = settings.whisperModel
        Task.detached(priority: .userInitiated) {
            let loadedVoices = TTSVoiceCatalog.listIndonesianVoices()
            let checked = PrerequisiteChecker.check(whisperModel: model)
            let keyExists = ElevenLabsKeychain.hasKey()
            await MainActor.run {
                let applyUpdates = {
                    voices = loadedVoices
                    if !loadedVoices.contains(settings.ttsVoice) {
                        settings.ttsVoice = loadedVoices.first ?? TTSVoiceCatalog.defaultVoice
                    }
                    prerequisites = checked
                    hasElevenLabsKey = keyExists
                }
                if reduceMotion {
                    applyUpdates()
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        applyUpdates()
                    }
                }
            }
        }
    }
}
