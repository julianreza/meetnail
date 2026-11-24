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
    @State private var backendCredentialInput = ""
    @State private var hasBackendCredential = false
    @State private var backendCredentialStatus: String?
    @State private var backendCredentialError: String?

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
            hasBackendCredential = NotulenBackendKeychain.hasCredential()
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
                subtitle: "\(settings.provider.shortBadge) · \(settings.speakingStyle.label) · HUD \(settings.hudLayoutStyle.label)",
                tone: .porcelain
            ) {
                if isSessionActive {
                    NailStatusBadge(
                        text: "Terkunci saat rapat aktif",
                        color: palette.warn,
                        icon: "lock.fill",
                        onInk: false,
                        tone: .porcelain
                    )
                }
            }

            HStack(spacing: 12) {
                TalmoSegmentedPill(
                    options: Array(SettingsTab.allCases),
                    selection: $activeTab,
                    tone: .porcelain,
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
        let tone: NeuTone = .porcelain
        return TalmoCard(tone: tone) {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Penyedia AI & Suara",
                    subtitle: "Pilih mesin suara & kecerdasan yang digunakan Nail saat rapat",
                    icon: "cpu.fill",
                    onInk: false,
                    tone: tone
                )

                VStack(spacing: 10) {
                    providerCard(
                        provider: .codex,
                        tag: "Utama · Natural",
                        tagColor: palette.good,
                        subtitle: "Suara real-time ChatGPT yang ekspresif & responsif",
                        tone: tone,
                        palette: palette
                    )
                    providerCard(
                        provider: .antigravity,
                        tag: "Cadangan · Lokal",
                        tagColor: palette.info,
                        subtitle: "Antigravity CLI + Whisper lokal & Neural TTS Indonesia",
                        tone: tone,
                        palette: palette
                    )
                    providerCard(
                        provider: .deepseek,
                        tag: "Opsional",
                        tagColor: palette.secondaryText(for: tone),
                        subtitle: "Pipeline lokal dengan suara bawaan (stella)",
                        tone: tone,
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
        tone: NeuTone,
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
                selectionCheckCircle(selected: selected, palette: palette, tone: tone)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(provider.label)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(palette.primaryText(for: tone))
                        NailStatusBadge(text: tag, color: tagColor, onInk: tone == .obsidian, tone: tone)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText(for: tone))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
        }
        .buttonStyle(NeuSelectableCardButtonStyle(selected: selected, cornerRadius: 16, padding: 14, tone: tone))
        .nailHoverLift(cornerRadius: 16)
    }

    private func providerConfigurationCard(palette: NailPalette) -> some View {
        let tone: NeuTone = .porcelain
        return TalmoCard(tone: tone) {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Konfigurasi Penyedia",
                    subtitle: settings.provider.label,
                    icon: "slider.horizontal.3",
                    tone: tone
                )

                Group {
                    switch settings.provider {
                    case .codex:
                        codexConfigView(palette: palette, tone: tone)
                    case .antigravity:
                        antigravityConfigView(palette: palette, tone: tone)
                    case .deepseek:
                        deepseekConfigView(palette: palette, tone: tone)
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
    private func codexConfigView(palette: NailPalette, tone: NeuTone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NeuWell(padding: 14, cornerRadius: 16, tone: tone) {
                VStack(alignment: .leading, spacing: 10) {
                    neuMenuPickerRow(
                        "Suara ChatGPT",
                        valueLabel: settings.codexVoice == "cove" ? "Cove (Default)" : settings.codexVoice.capitalized,
                        systemImage: "waveform",
                        tone: tone,
                        palette: palette
                    ) {
                        ForEach(VoiceSettings.codexPrimaryVoiceOptions, id: \.self) { voice in
                            Button {
                                settings.codexVoice = voice
                            } label: {
                                let label = voice == "cove" ? "Cove (Default)" : voice.capitalized
                                if voice == settings.codexVoice {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        }
                        Divider()
                        ForEach(VoiceSettings.codexExtendedVoiceOptions, id: \.self) { voice in
                            Button {
                                settings.codexVoice = voice
                            } label: {
                                if voice == settings.codexVoice {
                                    Label(voice.capitalized, systemImage: "checkmark")
                                } else {
                                    Text(voice.capitalized)
                                }
                            }
                        }
                    }
                    .disabled(isSessionActive)

                    Divider()
                        .overlay(palette.hairline(for: tone))

                    neuToggleRow(
                        "Panggil otomatis dengan kata \"Nail\" (Hands-Free)",
                        isOn: $settings.codexHandsFree,
                        tone: tone,
                        palette: palette
                    )
                    .disabled(isSessionActive)

                    Divider()
                        .overlay(palette.hairline(for: tone))

                    neuMenuPickerRow(
                        "Model Whisper Lokal",
                        valueLabel: settings.whisperModel,
                        systemImage: "ear.and.waveform",
                        tone: tone,
                        palette: palette
                    ) {
                        ForEach(VoiceSettings.whisperModelOptions, id: \.self) { model in
                            Button {
                                settings.whisperModel = model
                            } label: {
                                if model == settings.whisperModel {
                                    Label(model, systemImage: "checkmark")
                                } else {
                                    Text(model)
                                }
                            }
                        }
                    }
                    .disabled(isSessionActive)
                }
            }

            NeuWell(padding: 12, cornerRadius: 14, tone: tone) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText(for: tone))
                        .padding(.top, 1)

                    Text("Hands-Free menyimak kata \"Nail\" secara lokal lewat Whisper tanpa memakai kuota Codex sebelum dipanggil. Tombol manual \"Tanya\" tetap tersedia sebagai cadangan. Perubahan suara, gaya bicara, dan Hands-Free berlaku di sesi rapat berikutnya.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText(for: tone))
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
    private func antigravityConfigView(palette: NailPalette, tone: NeuTone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NeuWell(padding: 14, cornerRadius: 16, tone: tone) {
                VStack(alignment: .leading, spacing: 10) {
                    neuMenuPickerRow(
                        "Model Antigravity",
                        valueLabel: settings.agyModel,
                        systemImage: "cpu",
                        tone: tone,
                        palette: palette
                    ) {
                        ForEach(VoiceSettings.agyModelOptions, id: \.self) { model in
                            Button {
                                settings.agyModel = model
                            } label: {
                                if model == settings.agyModel {
                                    Label(model, systemImage: "checkmark")
                                } else {
                                    Text(model)
                                }
                            }
                        }
                    }
                    .disabled(isSessionActive)

                    Divider()
                        .overlay(palette.hairline(for: tone))

                    neuMenuPickerRow(
                        "Model Whisper Lokal",
                        valueLabel: settings.whisperModel,
                        systemImage: "ear.and.waveform",
                        tone: tone,
                        palette: palette
                    ) {
                        ForEach(VoiceSettings.whisperModelOptions, id: \.self) { model in
                            Button {
                                settings.whisperModel = model
                            } label: {
                                if model == settings.whisperModel {
                                    Label(model, systemImage: "checkmark")
                                } else {
                                    Text(model)
                                }
                            }
                        }
                    }
                    .disabled(isSessionActive)

                    Divider()
                        .overlay(palette.hairline(for: tone))

                    neuMenuPickerRow(
                        "Mesin Suara (TTS)",
                        valueLabel: settings.ttsEngine.label,
                        systemImage: "waveform.and.mic",
                        tone: tone,
                        palette: palette
                    ) {
                        ForEach(TTSEngine.allCases) { engine in
                            Button {
                                settings.ttsEngine = engine
                            } label: {
                                if engine == settings.ttsEngine {
                                    Label(engine.label, systemImage: "checkmark")
                                } else {
                                    Text(engine.label)
                                }
                            }
                        }
                    }
                    .disabled(isSessionActive)

                    if settings.ttsEngine == .elevenlabs {
                        Divider()
                            .overlay(palette.hairline(for: tone))

                        elevenLabsConfigSection(palette: palette, tone: tone)

                        Divider()
                            .overlay(palette.hairline(for: tone))

                        neuMenuPickerRow(
                            "Suara Cadangan (Edge / macOS)",
                            valueLabel: TTSVoiceCatalog.displayName(for: settings.ttsVoice),
                            systemImage: "speaker.wave.2",
                            tone: tone,
                            palette: palette
                        ) {
                            ForEach(voices, id: \.self) { voice in
                                Button {
                                    settings.ttsVoice = voice
                                } label: {
                                    let name = TTSVoiceCatalog.displayName(for: voice)
                                    if voice == settings.ttsVoice {
                                        Label(name, systemImage: "checkmark")
                                    } else {
                                        Text(name)
                                    }
                                }
                            }
                        }
                        .disabled(isSessionActive)
                    } else {
                        Divider()
                            .overlay(palette.hairline(for: tone))

                        neuMenuPickerRow(
                            "Suara Indonesia (TTS)",
                            valueLabel: TTSVoiceCatalog.displayName(for: settings.ttsVoice),
                            systemImage: "speaker.wave.2",
                            tone: tone,
                            palette: palette
                        ) {
                            ForEach(voices, id: \.self) { voice in
                                Button {
                                    settings.ttsVoice = voice
                                } label: {
                                    let name = TTSVoiceCatalog.displayName(for: voice)
                                    if voice == settings.ttsVoice {
                                        Label(name, systemImage: "checkmark")
                                    } else {
                                        Text(name)
                                    }
                                }
                            }
                        }
                        .disabled(isSessionActive)
                    }

                    Divider()
                        .overlay(palette.hairline(for: tone))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("Kecepatan")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(palette.primaryText(for: tone))

                            Text("\(settings.ttsRate) wpm")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(palette.primaryText(for: tone))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background {
                                    NeuRaisedBackground(isCapsule: true, elevation: 0.42, tone: tone)
                                }
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
                            .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true, tone: tone))
                        }

                        NeuSlider(
                            value: Binding(
                                get: { Double(settings.ttsRate) },
                                set: { settings.ttsRate = Int($0.rounded()) }
                            ),
                            in: 140...230,
                            step: 5,
                            tone: tone
                        )
                    }
                }
            }

            if settings.ttsEngine == .elevenlabs {
                NeuWell(padding: 12, cornerRadius: 14, tone: tone) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText(for: tone))
                            .padding(.top, 1)

                        Text("ElevenLabs memakai kuota akun (10.000 kredit gratis/bulan di paket Free). Jika kredit habis, API gagal, atau offline, Nail otomatis beralih ke Edge Neural lalu Damayanti macOS.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: tone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if TTSVoiceCatalog.isNeuralVoice(settings.ttsVoice) {
                NeuWell(padding: 12, cornerRadius: 14, tone: tone) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "waveform.and.mic")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText(for: tone))
                            .padding(.top, 1)

                        Text("Suara Neural Bahasa Indonesia memakai pelafalan penutur asli (butuh internet; otomatis kembali ke Damayanti macOS jika offline).")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: tone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if !TTSVoiceCatalog.hasEnhancedVoice(in: voices) {
                NeuWell(padding: 12, cornerRadius: 14, tone: tone) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText(for: tone))
                            .padding(.top, 1)

                        Text("Tip: unduh suara Enhanced Bahasa Indonesia di Pengaturan Sistem → Aksesibilitas → Konten Ucapan untuk suara lebih natural.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: tone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func elevenLabsConfigSection(palette: NailPalette, tone: NeuTone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("ElevenLabs API Key")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(palette.primaryText(for: tone))

                Spacer()

                NailStatusBadge(
                    text: hasElevenLabsKey ? "Tersimpan di Keychain" : "Belum tersimpan",
                    color: hasElevenLabsKey ? palette.good : palette.warn,
                    icon: hasElevenLabsKey ? "key.fill" : "exclamationmark.triangle",
                    onInk: tone == .obsidian,
                    tone: tone
                )
            }

            HStack(spacing: 8) {
                SecureField(
                    hasElevenLabsKey
                        ? "API key tersimpan (isi untuk mengganti)"
                        : "Masukkan ElevenLabs API Key",
                    text: $elevenLabsAPIKeyInput
                )
                .textFieldStyle(NeuTextFieldStyle(tone: tone, cornerRadius: 12, horizontalPadding: 11, verticalPadding: 8))
                .font(.callout.monospaced())
                .disabled(isSessionActive)

                Button("Simpan") {
                    saveElevenLabsAPIKey()
                }
                .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true, tone: tone))
                .disabled(
                    isSessionActive
                        || elevenLabsAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button("Hapus") {
                    deleteElevenLabsAPIKey()
                }
                .buttonStyle(NailPillButtonStyle(variant: .danger, compact: true, tone: tone))
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
                .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true, tone: tone))
                .disabled(isLoadingElevenLabs)

                if let subscription = elevenLabsSubscription {
                    let remainingText = "\(subscription.remainingCharacters.formatted()) / \(subscription.characterLimit.formatted()) karakter tersisa"
                    let quotaColor: Color = subscription.remainingCharacters > 1000
                        ? palette.good
                        : (subscription.remainingCharacters > 0 ? palette.warn : palette.bad)
                    NailStatusBadge(
                        text: subscription.tier.map { "\($0.capitalized) · \(remainingText)" } ?? remainingText,
                        color: quotaColor,
                        icon: "gauge.medium",
                        onInk: tone == .obsidian,
                        tone: tone
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
                .overlay(palette.hairline(for: tone))

            neuMenuPickerRow(
                "Model ElevenLabs",
                valueLabel: TTSVoiceCatalog.elevenLabsModelDisplayName(for: settings.elevenLabsModel),
                systemImage: "sparkles",
                tone: tone,
                palette: palette
            ) {
                ForEach(VoiceSettings.elevenLabsModelOptions, id: \.self) { model in
                    Button {
                        settings.elevenLabsModel = model
                    } label: {
                        let name = TTSVoiceCatalog.elevenLabsModelDisplayName(for: model)
                        if model == settings.elevenLabsModel {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            }
            .disabled(isSessionActive)

            let selectedVoiceName = displayedElevenLabsVoices.first(where: { $0.voiceId == settings.elevenLabsVoiceId })?.name ?? settings.elevenLabsVoiceId
            neuMenuPickerRow(
                "Suara ElevenLabs",
                valueLabel: selectedVoiceName,
                systemImage: "person.wave.2",
                tone: tone,
                palette: palette
            ) {
                ForEach(displayedElevenLabsVoices) { voice in
                    Button {
                        settings.elevenLabsVoiceId = voice.voiceId
                    } label: {
                        if voice.voiceId == settings.elevenLabsVoiceId {
                            Label(voice.name, systemImage: "checkmark")
                        } else {
                            Text(voice.name)
                        }
                    }
                }
            }
            .disabled(isSessionActive)

            HStack(spacing: 8) {
                Text("Custom Voice ID")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(palette.primaryText(for: tone))

                TextField("Opsional (contoh: EXAVITQu4vr4xnSDxMaL)", text: $customElevenLabsVoiceId)
                    .textFieldStyle(NeuTextFieldStyle(tone: tone, cornerRadius: 12, horizontalPadding: 11, verticalPadding: 8))
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
    private func deepseekConfigView(palette: NailPalette, tone: NeuTone) -> some View {
        NeuWell(padding: 14, cornerRadius: 16, tone: tone) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title3)
                    .foregroundStyle(palette.secondaryText(for: tone))
                Text("DeepSeek menggunakan suara bawaan pipeline lokal (stella).")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText(for: tone))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func speakingStyleCard(palette: NailPalette) -> some View {
        let tone: NeuTone = .porcelain
        return TalmoCard(tone: tone) {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Gaya Bicara & Pengungkapan",
                    subtitle: "Atur nada bicara dan kepribadian Nail saat menjawab",
                    icon: "text.bubble.fill",
                    onInk: false,
                    tone: tone
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
                                selectionCheckCircle(selected: selected, palette: palette, tone: tone)
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(style.label)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(palette.primaryText(for: tone))
                                    Text(style.description)
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText(for: tone))
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 8)
                            }
                        }
                        .buttonStyle(NeuSelectableCardButtonStyle(selected: selected, cornerRadius: 16, padding: 14, tone: tone))
                        .nailHoverLift(cornerRadius: 16)
                    }
                }
                .disabled(isSessionActive)
                .opacity(isSessionActive ? 0.6 : 1.0)

                Divider()
                    .overlay(palette.hairline(for: tone))

                NeuWell(padding: 14, cornerRadius: 16, tone: tone) {
                    VStack(alignment: .leading, spacing: 6) {
                        neuToggleRow(
                            "Baca presentasi Google Meet",
                            isOn: $settings.presentationReadingEnabled,
                            tone: tone,
                            palette: palette
                        )
                        Text("Nail membaca presentasi saat diminta. Gambar dapat dikirim ke Codex untuk pertanyaan visual.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: tone))
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
                            onInk: true,
                            tone: .obsidian
                        )

                        Spacer(minLength: 12)

                        hudPreviewActionControls(palette: palette)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        NailSectionTitle(
                            title: "Pratinjau Langsung HUD",
                            subtitle: "Simulasikan tampilan HUD, ekspresi karakter 3D, dan transparansi secara langsung",
                            icon: "sparkles.rectangle.stack",
                            onInk: true,
                            tone: .obsidian
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
        TalmoSegmentedPill(
            options: Array(SettingsHUDPreviewStage.allCases),
            selection: $previewStage,
            compact: true,
            tone: .obsidian,
            dotColor: { stage in
                stageDotColor(stage: stage, isSelected: previewStage == stage, palette: palette)
            },
            label: { $0.label }
        )
    }

    private func stageDotColor(stage: SettingsHUDPreviewStage, isSelected: Bool, palette: NailPalette) -> Color {
        if isSelected {
            return stage == .standby ? palette.secondaryText(for: .porcelain) : palette.goldBright
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
        NeuChip(text, tone: .obsidian)
            .monospacedDigit()
            .contentTransition(.numericText())
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
        let tone: NeuTone = .porcelain
        return TalmoCard(tone: tone) {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Tema Aplikasi",
                    subtitle: "Pilih tampilan jendela utama Meet Nail",
                    icon: "circle.lefthalf.filled",
                    tone: tone
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
                                        .foregroundStyle(selected ? palette.primaryText(for: tone) : palette.secondaryText(for: tone))

                                    Text(appearance.label)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(palette.primaryText(for: tone))
                                        .lineLimit(1)

                                    Spacer(minLength: 4)

                                    selectionCheckCircle(selected: selected, palette: palette, size: 17, tone: tone)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(NeuSelectableCardButtonStyle(selected: selected, cornerRadius: 16, padding: 12, tone: tone))
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
        let tone: NeuTone = .porcelain
        return TalmoCard(tone: tone) {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Bentuk HUD",
                    subtitle: "Pilih geometri HUD mengambang di layar Anda",
                    icon: "macwindow.on.rectangle",
                    onInk: false,
                    tone: tone
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
                                        .foregroundStyle(palette.primaryText(for: tone))
                                    Text(style.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText(for: tone))
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 8)

                                selectionCheckCircle(selected: selected, palette: palette, tone: tone)
                            }
                        }
                        .buttonStyle(NeuSelectableCardButtonStyle(selected: selected, cornerRadius: 16, padding: 14, tone: tone))
                        .nailHoverLift(cornerRadius: 16)
                    }
                }
            }
        }
    }

    private func hudShapeDiagram(style: HUDLayoutStyle, selected: Bool, palette: NailPalette) -> some View {
        ZStack(alignment: style == .notch ? .top : .center) {
            NeuInsetBackground(cornerRadius: 8, depth: 0.85, tone: .obsidian)
                .frame(width: 56, height: 38)

            if style == .notch {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [palette.inkCardFill, Color(hex: 0xDDE3EC)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 11)
                .shadow(color: Color.black.opacity(0.45), radius: 2, x: 1, y: 1.5)
            } else {
                NeuRaisedBackground(isCapsule: true, elevation: 0.55, tone: .porcelain)
                    .frame(width: 32, height: 11)
            }
        }
    }

    private func hudBehaviorAndMetricsCard(palette: NailPalette) -> some View {
        let tone: NeuTone = .porcelain
        let opacityPercent = Int((settings.hudOpacity * 100).rounded())

        return TalmoCard(tone: tone) {
            VStack(alignment: .leading, spacing: 14) {
                NailSectionTitle(
                    title: "Ukuran, Tema & Perilaku HUD",
                    subtitle: "Sesuaikan dimensi, tema aksen, dan respons HUD saat rapat",
                    icon: "sparkles",
                    tone: tone
                )

                NeuWell(padding: 14, cornerRadius: 16, tone: tone) {
                    VStack(alignment: .leading, spacing: 10) {
                        neuMenuPickerRow(
                            "Ukuran HUD",
                            valueLabel: settings.hudSize.label,
                            systemImage: "arrow.up.left.and.arrow.down.right",
                            tone: tone,
                            palette: palette
                        ) {
                            ForEach(HUDSizePreset.allCases) { preset in
                                Button {
                                    settings.hudSize = preset
                                } label: {
                                    if preset == settings.hudSize {
                                        Label(preset.label, systemImage: "checkmark")
                                    } else {
                                        Text(preset.label)
                                    }
                                }
                            }
                        }

                        Divider()
                            .overlay(palette.hairline(for: tone))

                        neuMenuPickerRow(
                            "Tema Warna",
                            valueLabel: settings.hudAccentTheme.label,
                            systemImage: "paintpalette",
                            tone: tone,
                            palette: palette
                        ) {
                            ForEach(HUDAccentTheme.allCases) { theme in
                                Button {
                                    settings.hudAccentTheme = theme
                                } label: {
                                    if theme == settings.hudAccentTheme {
                                        Label(theme.label, systemImage: "checkmark")
                                    } else {
                                        Text(theme.label)
                                    }
                                }
                            }
                        }
                    }
                }

                NeuWell(padding: 14, cornerRadius: 16, tone: tone) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Lama tampil jawaban")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(palette.primaryText(for: tone))
                                Spacer()
                                Text("\(settings.hudReplyHoldSeconds) dtk")
                                    .font(.callout.weight(.semibold))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .foregroundStyle(palette.primaryText(for: tone))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 2.5)
                                    .background {
                                        NeuRaisedBackground(isCapsule: true, elevation: 0.42, tone: tone)
                                    }
                                    .animation(
                                        reduceMotion ? nil : .snappy(duration: 0.18),
                                        value: settings.hudReplyHoldSeconds
                                    )
                            }

                            NeuSlider(
                                value: Binding(
                                    get: { Double(settings.hudReplyHoldSeconds) },
                                    set: { settings.hudReplyHoldSeconds = Int($0.rounded()) }
                                ),
                                in: 2...15,
                                step: 1,
                                tone: tone
                            )

                            HStack {
                                Text("2 dtk")
                                Spacer()
                                Text("15 dtk")
                            }
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(palette.tertiaryText(for: tone))
                        }

                        Divider()
                            .overlay(palette.hairline(for: tone))

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Opasitas HUD")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(palette.primaryText(for: tone))
                                Spacer()
                                Text("\(opacityPercent)%")
                                    .font(.callout.weight(.semibold))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .foregroundStyle(palette.primaryText(for: tone))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 2.5)
                                    .background {
                                        NeuRaisedBackground(isCapsule: true, elevation: 0.42, tone: tone)
                                    }
                                    .animation(
                                        reduceMotion ? nil : .snappy(duration: 0.18),
                                        value: opacityPercent
                                    )
                            }

                            NeuSlider(
                                value: $settings.hudOpacity,
                                in: 0.75...1.0,
                                step: 0.05,
                                tone: tone
                            )

                            HStack {
                                Text("75%")
                                Spacer()
                                Text("100%")
                            }
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(palette.tertiaryText(for: tone))
                        }
                    }
                }

                NeuWell(padding: 14, cornerRadius: 16, tone: tone) {
                    VStack(alignment: .leading, spacing: 10) {
                        neuToggleRow(
                            "Buka saat kursor diarahkan (Hover)",
                            isOn: $settings.hudExpandOnHover,
                            tone: tone,
                            palette: palette
                        )
                        Divider()
                            .overlay(palette.hairline(for: tone))
                        neuToggleRow(
                            "Buka otomatis saat Nail aktif / bicara",
                            isOn: $settings.hudAutoExpandOnVoice,
                            tone: tone,
                            palette: palette
                        )
                        Divider()
                            .overlay(palette.hairline(for: tone))
                        VStack(alignment: .leading, spacing: 4) {
                            neuToggleRow(
                                "Sembunyikan HUD saat Share Screen (Stealth)",
                                isOn: $settings.hudHideFromScreenShare,
                                tone: tone,
                                palette: palette
                            )
                            Text("HUD tidak terlihat oleh peserta rapat saat Anda melakukan share screen.")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText(for: tone))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                            .overlay(palette.hairline(for: tone))
                        Text("HUD hanya menampilkan karakter Noko-Owl & animasi — detail percakapan ada di jendela Desktop.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: tone))
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
                    tone: .porcelain,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.00)

                prerequisiteCard(
                    title: "Antigravity CLI (agy)",
                    subtitle: "Mesin AI cadangan lokal",
                    icon: "terminal.fill",
                    ok: prerequisites.agyInstalled,
                    tone: .porcelain,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.04)

                prerequisiteCard(
                    title: "uv",
                    subtitle: "Python offline runner",
                    icon: "bolt.horizontal.circle.fill",
                    ok: prerequisites.uvInstalled,
                    tone: .porcelain,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.08)

                prerequisiteCard(
                    title: "ffmpeg",
                    subtitle: "Pemrosesan audio rapat",
                    icon: "waveform.path.ecg",
                    ok: prerequisites.ffmpegInstalled,
                    tone: .porcelain,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.12)

                prerequisiteCard(
                    title: "Bobot Whisper",
                    subtitle: "Model lokal (\(settings.whisperModel))",
                    icon: "ear.and.waveform",
                    ok: prerequisites.whisperModelCached,
                    tone: .porcelain,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.16)

                prerequisiteCard(
                    title: "Profil Login Google Meet",
                    subtitle: "Sesi browser terautentikasi",
                    icon: "person.crop.circle.badge.checkmark",
                    ok: prerequisites.meetProfileExists,
                    tone: .porcelain,
                    palette: palette
                )
                .nailHoverLift(cornerRadius: 20)
                .nailStaggeredEntrance(delay: 0.20)
            }

            backendIntegrationCard(palette: palette)
        }
    }

    private func backendIntegrationCard(palette: NailPalette) -> some View {
        let config = settings.notulenBackendConfig()
        let trimmedEndpoint = settings.backendSummaryEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInvalidEndpoint = !trimmedEndpoint.isEmpty && config.resolvedEndpointURL == nil

        let statusBadge: (text: String, color: Color, icon: String) = {
            if !config.isConfigured {
                return ("Menunggu Endpoint", palette.warn, "link.badge.plus")
            }
            if config.authScheme.requiresCredential && !hasBackendCredential {
                return ("Perlu Kredensial", palette.warn, "key.fill")
            }
            return ("Siap Kirim", palette.good, "checkmark.circle.fill")
        }()

        return TalmoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    NailSectionTitle(
                        title: "Integrasi API Backend Notulen",
                        subtitle: "Atur model AI ringkasan, endpoint, & autentikasi untuk mengirim ringkasan rapat",
                        icon: "paperplane.circle.fill"
                    )

                    Spacer(minLength: 8)

                    NailStatusBadge(
                        text: statusBadge.text,
                        color: statusBadge.color,
                        icon: statusBadge.icon
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Model AI Ringkasan Notulen")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(palette.textPrimary)

                    Menu {
                        ForEach(VoiceSettings.summaryModelGroups, id: \.self) { group in
                            Section(group) {
                                ForEach(VoiceSettings.summaryModelOptions.filter { $0.group == group }) { option in
                                    Button {
                                        settings.summaryModel = option.id
                                    } label: {
                                        if option.id == settings.summaryModel {
                                            Label("\(option.label) (\(option.id))", systemImage: "checkmark")
                                        } else {
                                            Text("\(option.label) (\(option.id))")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cpu")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(palette.goldBright)

                            Text(VoiceSettings.summaryModelDisplayName(for: settings.summaryModel))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)

                            Text(settings.summaryModel)
                                .font(.caption.monospaced())
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .neuPickerSurface(tone: .porcelain, cornerRadius: 12, elevation: 0.60)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Endpoint URL (POST)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(palette.textPrimary)

                    NeuWell(padding: 10, cornerRadius: 12, tone: .porcelain) {
                        HStack(spacing: 8) {
                            NeuChip("POST", tone: .porcelain)
                                .font(.caption2.monospaced().weight(.bold))

                            TextField(
                                VoiceSettings.defaultBackendSummaryEndpoint,
                                text: $settings.backendSummaryEndpoint
                            )
                            .textFieldStyle(.plain)
                            .font(.callout.monospaced())
                            .foregroundStyle(palette.textPrimary)
                        }
                    }

                    if hasInvalidEndpoint {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("URL endpoint tidak valid. Gunakan skema http:// atau https:// dengan host yang valid.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(palette.bad)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Skema Autentikasi")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(palette.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        TalmoSegmentedPill(
                            options: Array(BackendAuthScheme.allCases),
                            selection: $settings.backendAuthScheme,
                            compact: true,
                            tone: .porcelain,
                            label: { $0.label }
                        )
                    }
                }

                if settings.backendAuthScheme == .apiKeyHeader {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nama Header Kustom")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(palette.textPrimary)

                        TextField("X-API-Key", text: $settings.backendAuthHeaderName)
                            .textFieldStyle(NeuTextFieldStyle(tone: .porcelain, cornerRadius: 12, horizontalPadding: 12, verticalPadding: 10))
                            .font(.callout.monospaced())
                    }
                }

                if settings.backendAuthScheme.requiresCredential {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Kredensial / Token API")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(palette.textPrimary)

                            Spacer()

                            NailStatusBadge(
                                text: hasBackendCredential ? "Tersimpan aman di macOS Keychain" : "Belum tersimpan",
                                color: hasBackendCredential ? palette.good : palette.warn,
                                icon: hasBackendCredential ? "lock.shield.fill" : "exclamationmark.triangle"
                            )
                        }

                        HStack(spacing: 8) {
                            SecureField(
                                hasBackendCredential
                                    ? "Kredensial tersimpan (isi untuk mengganti)"
                                    : settings.backendAuthScheme.credentialPlaceholder,
                                text: $backendCredentialInput
                            )
                            .textFieldStyle(NeuTextFieldStyle(tone: .porcelain, cornerRadius: 12, horizontalPadding: 12, verticalPadding: 10))
                            .font(.callout.monospaced())

                            Button("Simpan ke Keychain") {
                                saveBackendCredential()
                            }
                            .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true))
                            .disabled(
                                backendCredentialInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )

                            Button("Hapus") {
                                deleteBackendCredential()
                            }
                            .buttonStyle(NailPillButtonStyle(variant: .danger, compact: true))
                            .disabled(!hasBackendCredential)
                        }

                        if let backendCredentialStatus, !backendCredentialStatus.isEmpty {
                            Text(backendCredentialStatus)
                                .font(.caption)
                                .foregroundStyle(palette.good)
                        }

                        if let backendCredentialError, !backendCredentialError.isEmpty {
                            Text(backendCredentialError)
                                .font(.caption)
                                .foregroundStyle(palette.bad)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                NeuWell(padding: 12, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Label("Ringkasan Kontrak API", systemImage: "doc.text.magnifyingglass")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)

                            Spacer(minLength: 8)

                            Text("POST · application/json")
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(palette.textSecondary)
                        }

                        Text("Payload JSON: text, title, source")
                            .font(.caption2.monospaced())
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Endpoint & kredensial dapat diisi kapan saja saat backend siap. Token disimpan terenkripsi di macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func saveBackendCredential() {
        let trimmed = backendCredentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if NotulenBackendKeychain.save(trimmed) {
            hasBackendCredential = true
            backendCredentialInput = ""
            backendCredentialError = nil
            backendCredentialStatus = "Tersimpan aman di macOS Keychain."
        } else {
            backendCredentialStatus = nil
            backendCredentialError = "Gagal menyimpan kredensial ke Keychain macOS."
        }
    }

    private func deleteBackendCredential() {
        if NotulenBackendKeychain.delete() {
            hasBackendCredential = false
            backendCredentialInput = ""
            backendCredentialError = nil
            backendCredentialStatus = "Kredensial dihapus dari macOS Keychain."
        } else {
            backendCredentialStatus = nil
            backendCredentialError = "Gagal menghapus kredensial dari Keychain macOS."
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
                    NeuProgressTrack(
                        progress: progress,
                        tone: .obsidian,
                        height: 8,
                        tint: readyCount == 6 ? palette.inkCardFill : palette.goldBright
                    )
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82),
                        value: readyCount
                    )

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
        tone: NeuTone = .porcelain,
        palette: NailPalette
    ) -> some View {
        let dotColor = ok ? palette.good : palette.bad
        let dotBorder = tone == .obsidian ? palette.obsidianSurfaceTop : palette.card

        return TalmoCard(padding: 16, cornerRadius: 20, tone: tone) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    NeuInsetBackground(cornerRadius: 12, depth: 0.72, tone: tone)
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.primaryText(for: tone))
                        }

                    Circle()
                        .fill(dotColor)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle()
                                .strokeBorder(dotBorder, lineWidth: 1.5)
                        }
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.primaryText(for: tone))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText(for: tone))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)

                    Text(ok ? "Siap" : "Belum")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ok ? palette.primaryText(for: tone) : palette.secondaryText(for: tone))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8.5)
                .padding(.vertical, 3.5)
                .background {
                    NeuInsetBackground(isCapsule: true, depth: 0.60, tone: tone)
                }
            }
        }
    }

    // MARK: - Shared Selection Indicator & Helpers

    private func neuMenuPickerRow<MenuContent: View>(
        _ title: String,
        valueLabel: String,
        systemImage: String? = nil,
        tone: NeuTone = .porcelain,
        palette: NailPalette,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(palette.primaryText(for: tone))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Menu {
                menuContent()
            } label: {
                NeuMenuLabel(valueLabel, systemImage: systemImage, tone: tone, compact: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    private func neuToggleRow(
        _ title: String,
        isOn: Binding<Bool>,
        tone: NeuTone = .porcelain,
        palette: NailPalette
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(palette.primaryText(for: tone))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            NeuSwitchToggle(isOn: isOn, tone: tone)
        }
    }

    private func selectionCheckCircle(
        selected: Bool,
        palette: NailPalette,
        size: CGFloat = 20,
        tone: NeuTone = .porcelain
    ) -> some View {
        let activeTone = palette.activeContrastTone(for: tone)
        return ZStack {
            if selected {
                NeuRaisedBackground(isCapsule: true, elevation: 0.68, tone: activeTone)
                    .frame(width: size, height: size)

                Circle()
                    .strokeBorder(palette.goldBright.opacity(0.75), lineWidth: 1.0)
                    .frame(width: max(4, size - 5), height: max(4, size - 5))

                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(palette.primaryText(for: activeTone))
            } else {
                NeuInsetBackground(isCapsule: true, depth: 0.70, tone: tone)
                    .frame(width: size, height: size)
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
            let backendCredentialExists = NotulenBackendKeychain.hasCredential()
            await MainActor.run {
                let applyUpdates = {
                    voices = loadedVoices
                    if !loadedVoices.contains(settings.ttsVoice) {
                        settings.ttsVoice = loadedVoices.first ?? TTSVoiceCatalog.defaultVoice
                    }
                    prerequisites = checked
                    hasElevenLabsKey = keyExists
                    hasBackendCredential = backendCredentialExists
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

private struct NeuSelectableCardButtonStyle: ButtonStyle {
    var selected: Bool
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 14
    var tone: NeuTone = .porcelain
    var selectedTone: NeuTone? = nil

    func makeBody(configuration: Configuration) -> some View {
        CardBody(
            configuration: configuration,
            selected: selected,
            cornerRadius: cornerRadius,
            padding: padding,
            tone: tone,
            selectedTone: selectedTone
        )
    }

    private struct CardBody: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        let configuration: Configuration
        let selected: Bool
        let cornerRadius: CGFloat
        let padding: CGFloat
        let tone: NeuTone
        let selectedTone: NeuTone?

        var body: some View {
            let palette = NailPalette(scheme: colorScheme)
            let activeTone = selected ? (selectedTone ?? tone) : tone
            let rimColor = activeTone == .obsidian
                ? palette.goldBright.opacity(0.65)
                : palette.accent.opacity(palette.isDark ? 0.75 : 0.85)

            configuration.label
                .padding(padding)
                .background {
                    if selected {
                        NeuRaisedBackground(
                            cornerRadius: cornerRadius,
                            elevation: 0.78,
                            isPressed: configuration.isPressed,
                            tone: activeTone
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(rimColor, lineWidth: 1.4)
                        }
                    } else {
                        NeuInsetBackground(
                            cornerRadius: cornerRadius,
                            depth: configuration.isPressed ? 0.92 : 0.72,
                            tone: tone
                        )
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.988 : 1.0)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.76),
                    value: configuration.isPressed
                )
        }
    }
}
