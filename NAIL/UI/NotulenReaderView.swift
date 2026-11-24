import AppKit
import SwiftUI

enum NailSpeakerPalette {
    // Cool-neutral & monochrome architectural shades (silver / ash / pearl greys in Dark Mode)
    private static let darkColors: [Color] = [
        Color(hex: 0xECECEC), // pearl grey
        Color(hex: 0xD8DCE2), // cool silver
        Color(hex: 0xC8CCD2), // architectural ash
        Color(hex: 0xB8C0C8), // brushed steel
        Color(hex: 0xE0DED8), // warm platinum
        Color(hex: 0xC2C6CC), // titanium grey
        Color(hex: 0xD0D4D8), // mist silver
    ]

    // Cool-neutral & monochrome architectural shades (charcoal / graphite / slate greys in Light Mode)
    private static let lightColors: [Color] = [
        Color(hex: 0x1A1A1A), // deep charcoal
        Color(hex: 0x2C3036), // cool graphite
        Color(hex: 0x3A3F47), // architectural slate
        Color(hex: 0x4A5058), // brushed iron
        Color(hex: 0x262624), // deep basalt
        Color(hex: 0x34383E), // carbon steel
        Color(hex: 0x43484F), // muted pewter
    ]

    static func color(for speaker: String, scheme: ColorScheme) -> Color {
        var hash: UInt64 = 5381
        for byte in speaker.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let palette = scheme == .dark ? darkColors : lightColors
        return palette[Int(hash % UInt64(palette.count))]
    }
}

private enum TranscriptFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Semua"
    case meeting = "Rapat"
    case qa = "Tanya Jawab"

    var id: String { rawValue }
}

struct NotulenReaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var archiveNS

    let files: [NotulenFile]
    @Binding var selectedFile: NotulenFile?
    var activeFileURL: URL?
    let onRefresh: () -> Void
    let onDelete: (NotulenFile) -> Void
    var onOpenBackendSettings: (() -> Void)? = nil

    @State private var searchQuery = ""
    @State private var inDocQuery = ""
    @State private var transcriptFilter: TranscriptFilter = .all
    @State private var rawContent = ""
    @State private var parsedDocument: ParsedNotulenDocument?
    @State private var loadTask: Task<Void, Never>?
    @State private var copiedFeedback = false
    @State private var filePendingDelete: NotulenFile?
    @State private var narrowShowingDetail = false
    @State private var refreshPulse = 0
    @State private var hoveredFileURL: URL?

    // Summary & Backend Submission State
    @State private var summary: NotulenSummary?
    @State private var submissionRecord: NotulenSubmissionRecord?
    @State private var isSummarizing = false
    @State private var summaryError: String?
    @State private var summaryTask: Task<Void, Never>?
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var submitErrorNeedsSettings = false
    @State private var submitTask: Task<Void, Never>?
    @State private var backendUnconfiguredCallout = false
    @State private var showingJSONPreview = false
    @State private var copiedSummaryFeedback = false
    @State private var copiedJSONFeedback = false
    @State private var savedMarkdownFeedback = false
    @State private var isSavingMarkdown = false

    private var filteredFiles: [NotulenFile] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return files }
        return files.filter { file in
            let parsed = ParsedFilename.parse(file.name)
            return file.name.lowercased().contains(query)
                || parsed.title.lowercased().contains(query)
                || parsed.dateTimeLabel.lowercased().contains(query)
        }
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)

        GeometryReader { geometry in
            let isWide = geometry.size.width >= 760

            VStack(alignment: .leading, spacing: 18) {
                TalmoPageHeader(
                    title: "Notulen",
                    subtitle: "\(files.count) catatan tersimpan · ~/NAIL/Notulen"
                ) {
                    HStack(spacing: 8) {
                        Button {
                            refreshPulse &+= 1
                            onRefresh()
                        } label: {
                            Label("Muat Ulang", systemImage: "arrow.clockwise")
                                .symbolEffect(.bounce, value: refreshPulse)
                        }
                        .buttonStyle(NailPillButtonStyle(variant: .primary))
                        .help("Muat ulang daftar notulen")

                        Button {
                            NotulenExporter.openFolder()
                        } label: {
                            Label("Buka Folder", systemImage: "folder")
                        }
                        .buttonStyle(NailPillButtonStyle(variant: .porcelain))
                        .help("Buka folder ~/NAIL/Notulen di Finder")
                    }
                }

                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        leftRail(palette: palette)
                            .frame(width: 260)
                            .frame(maxHeight: .infinity, alignment: .top)

                        detailPanel(palette: palette)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    if narrowShowingDetail, selectedFile != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Button {
                                    if reduceMotion {
                                        narrowShowingDetail = false
                                    } else {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            narrowShowingDetail = false
                                        }
                                    }
                                } label: {
                                    Label("Kembali ke Daftar", systemImage: "chevron.left")
                                }
                                .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))

                                Spacer()
                            }

                            detailPanel(palette: palette)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    } else {
                        leftRail(palette: palette)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .padding(22)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(palette.canvasGradient)
        }
        .onAppear {
            loadSelectedContent()
        }
        .onChange(of: selectedFile) { _, _ in
            summaryTask?.cancel()
            submitTask?.cancel()
            parsedDocument = nil
            rawContent = ""
            inDocQuery = ""
            transcriptFilter = .all
            summary = nil
            submissionRecord = nil
            isSummarizing = false
            summaryError = nil
            isSubmitting = false
            submitError = nil
            submitErrorNeedsSettings = false
            backendUnconfiguredCallout = false
            showingJSONPreview = false
            copiedSummaryFeedback = false
            copiedJSONFeedback = false
            savedMarkdownFeedback = false
            isSavingMarkdown = false
            loadSelectedContent()
        }
        .onDisappear {
            loadTask?.cancel()
            summaryTask?.cancel()
            submitTask?.cancel()
        }
        .onChange(of: files) { _, _ in
            loadSelectedContent()
        }
        .alert(
            "Hapus Notulen?",
            isPresented: Binding(
                get: { filePendingDelete != nil },
                set: { if !$0 { filePendingDelete = nil } }
            ),
            presenting: filePendingDelete
        ) { file in
            Button("Batal", role: .cancel) {
                filePendingDelete = nil
            }
            Button("Hapus", role: .destructive) {
                let target = file
                filePendingDelete = nil
                onDelete(target)
            }
        } message: { file in
            Text("Berkas \"\(ParsedFilename.parse(file.name).title)\" akan dihapus permanen dari ~/NAIL/Notulen/.")
        }
    }

    // MARK: - Left Archive Rail (260pt, Sculpted Porcelain)

    private func leftRail(palette: NailPalette) -> some View {
        TalmoCard(padding: 14, cornerRadius: 20, surface: .raised, tone: .porcelain) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Arsip Rapat")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(palette.primaryText(for: .porcelain))

                    Spacer(minLength: 4)

                    Text("\(filteredFiles.count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: filteredFiles.count)
                        .foregroundStyle(palette.secondaryText(for: .porcelain))
                        .padding(.horizontal, 8.5)
                        .padding(.vertical, 3)
                        .background {
                            NeuInsetBackground(isCapsule: true, depth: 0.72, tone: .porcelain)
                        }
                }
                .padding(.horizontal, 2)

                NeuWell(padding: 9, cornerRadius: 12, tone: .porcelain) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.tertiaryText(for: .porcelain))

                        TextField("Cari notulen…", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(palette.primaryText(for: .porcelain))

                        if !searchQuery.isEmpty {
                            TalmoCircleIconButton(
                                systemImage: "xmark",
                                tone: .porcelain,
                                size: 22,
                                helpText: "Bersihkan pencarian"
                            ) {
                                searchQuery = ""
                            }
                        }
                    }
                }

                NeuWell(padding: 8, cornerRadius: 16, tone: .porcelain) {
                    if filteredFiles.isEmpty {
                        VStack(spacing: 10) {
                            Spacer(minLength: 16)
                            ZStack {
                                NeuRaisedBackground(isCapsule: true, elevation: 0.55, tone: .porcelain)
                                    .frame(width: 44, height: 44)
                                Image(systemName: files.isEmpty ? "doc.text" : "magnifyingglass")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(palette.secondaryText(for: .porcelain))
                            }
                            Text(files.isEmpty ? "Belum Ada Notulen" : "Tidak Ada Hasil")
                                .font(.system(size: 14, weight: .semibold, design: .serif))
                                .foregroundStyle(palette.primaryText(for: .porcelain))
                            Text(
                                files.isEmpty
                                    ? "Aktifkan Mode Notulen saat rapat untuk menyimpan catatan ke ~/NAIL/Notulen/."
                                    : "Coba kata kunci lain untuk menemukan arsip rapat."
                            )
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: .porcelain))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            Spacer(minLength: 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredFiles) { file in
                                    fileRow(file: file, palette: palette)
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func fileRow(file: NotulenFile, palette: NailPalette) -> some View {
        let isSelected = selectedFile?.url == file.url
        let isActive = activeFileURL == file.url
        let isHovered = hoveredFileURL == file.url
        let parsed = ParsedFilename.parse(file.name)
        let rowTone: NeuTone = isSelected ? palette.activeContrastTone(for: .porcelain) : .porcelain

        return Button {
            if reduceMotion {
                selectedFile = file
                narrowShowingDetail = true
            } else {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                    selectedFile = file
                    narrowShowingDetail = true
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(parsed.title)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium, design: isSelected ? .serif : .default))
                        .foregroundStyle(palette.primaryText(for: rowTone))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 4)

                    if isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(palette.goldBright)
                                .frame(width: 5, height: 5)
                            Text("Aktif")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(palette.primaryText(for: rowTone))
                        .padding(.horizontal, 7.5)
                        .padding(.vertical, 3)
                        .background {
                            NeuRaisedBackground(
                                isCapsule: true,
                                elevation: 0.45,
                                tint: palette.goldBright,
                                tone: rowTone
                            )
                        }
                    }
                }

                Text(parsed.dateTimeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.secondaryText(for: rowTone))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(
            NeuArchiveRowButtonStyle(
                isSelected: isSelected,
                isHovered: isHovered,
                namespace: archiveNS
            )
        )
        .onHover { hovering in
            if reduceMotion {
                hoveredFileURL = hovering ? file.url : (hoveredFileURL == file.url ? nil : hoveredFileURL)
            } else {
                withAnimation(.easeOut(duration: 0.15)) {
                    hoveredFileURL = hovering ? file.url : (hoveredFileURL == file.url ? nil : hoveredFileURL)
                }
            }
        }
    }

    // MARK: - Right Detail Panel

    private func detailPanel(palette: NailPalette) -> some View {
        ZStack(alignment: .topLeading) {
            if let file = selectedFile, let doc = parsedDocument {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            metadataHeaderCard(file: file, doc: doc, palette: palette, scrollProxy: scrollProxy)
                            notulenSummaryCard(file: file, palette: palette)
                                .id("notulenSummaryCard")
                            inDocumentFilterBar(doc: doc, palette: palette)
                            transcriptStream(doc: doc, palette: palette)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .id(file.url)
                .transition(.opacity)
            } else if let file = selectedFile {
                TalmoCard(padding: 32, cornerRadius: 20, tone: .porcelain) {
                    NeuWell(padding: 24, cornerRadius: 16, tone: .porcelain) {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(palette.goldBright)
                            Text("Memuat notulen…")
                                .font(.callout)
                                .foregroundStyle(palette.secondaryText(for: .porcelain))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .id(file.url)
                .transition(.opacity)
            } else {
                TalmoCard(padding: 28, cornerRadius: 20, tone: .porcelain) {
                    NeuWell(padding: 28, cornerRadius: 18, tone: .porcelain) {
                        VStack(spacing: 14) {
                            NailOrbMark(size: 52, isActive: false)
                                .opacity(0.92)

                            Text(files.isEmpty ? "Belum Ada Berkas Notulen" : "Pilih Notulen")
                                .font(.system(size: 18, weight: .semibold, design: .serif))
                                .foregroundStyle(palette.primaryText(for: .porcelain))

                            Text(
                                files.isEmpty
                                    ? "Transkrip Mode Notulen akan otomatis tersimpan di sini."
                                    : "Pilih salah satu catatan rapat di daftar sebelah kiri untuk membaca detailnya."
                            )
                            .font(.callout)
                            .foregroundStyle(palette.secondaryText(for: .porcelain))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedFile?.url)
    }

    private func metadataHeaderCard(
        file: NotulenFile,
        doc: ParsedNotulenDocument,
        palette: NailPalette,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        TalmoCard(padding: 20, cornerRadius: 20, surface: .raised, tone: .porcelain) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        headerTitleBlock(doc: doc, palette: palette)
                        Spacer(minLength: 8)
                        HStack(spacing: 8) {
                            headerActionButtons(file: file, palette: palette, scrollProxy: scrollProxy)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        headerTitleBlock(doc: doc, palette: palette)
                        NotulenFlowLayout(spacing: 8) {
                            headerActionButtons(file: file, palette: palette, scrollProxy: scrollProxy)
                        }
                    }
                }

                NeuWell(padding: 8, cornerRadius: 14, tone: .porcelain) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let date = doc.date, !date.isEmpty {
                                metadataChip(icon: "calendar", text: date, palette: palette)
                            }
                            if let startTime = doc.startTime, !startTime.isEmpty {
                                metadataChip(icon: "clock", text: startTime, monospaced: true, palette: palette)
                            }
                            if let link = doc.meetingLink, let url = URL(string: link) {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(palette.goldBright)
                                            .frame(width: 5, height: 5)
                                        Image(systemName: "link")
                                            .font(.caption2.weight(.semibold))
                                        Text(doc.linkPlatformLabel)
                                            .font(.caption.weight(.semibold))
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                }
                                .buttonStyle(NailPillButtonStyle(variant: .tinted(palette.goldBright), compact: true, tone: .porcelain))
                                .help(link)
                            }

                            metadataChip(
                                icon: "text.alignleft",
                                text: "\(doc.meetingLineCount) baris",
                                monospaced: true,
                                numericTransition: true,
                                palette: palette
                            )
                            metadataChip(
                                icon: "person.2",
                                text: "\(doc.speakerCount) pembicara",
                                monospaced: true,
                                numericTransition: true,
                                palette: palette
                            )
                            metadataChip(
                                icon: "bubble.left.and.bubble.right",
                                text: "\(doc.qaCount) tanya jawab",
                                monospaced: true,
                                numericTransition: true,
                                palette: palette
                            )
                        }
                    }
                }
            }
        }
    }

    private func metadataChip(
        icon: String,
        text: String,
        monospaced: Bool = false,
        numericTransition: Bool = false,
        palette: NailPalette
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.tertiaryText(for: .porcelain))
            if numericTransition {
                Text(text)
                    .font(monospaced ? .caption.monospacedDigit() : .caption)
                    .contentTransition(.numericText())
                    .foregroundStyle(palette.primaryText(for: .porcelain))
                    .lineLimit(1)
            } else {
                Text(text)
                    .font(monospaced ? .caption.monospacedDigit() : .caption)
                    .foregroundStyle(palette.primaryText(for: .porcelain))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            NeuRaisedBackground(isCapsule: true, elevation: 0.48, tone: .porcelain)
        }
    }

    private func headerTitleBlock(doc: ParsedNotulenDocument, palette: NailPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(doc.title)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .tracking(-0.3)
                    .foregroundStyle(palette.primaryText(for: .porcelain))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let statusBadge = doc.statusBadge(palette: palette) {
                    NailStatusBadge(
                        text: statusBadge.label,
                        color: statusBadge.color,
                        pulse: statusBadge.isLive,
                        tone: .porcelain
                    )
                }
            }

            HStack(spacing: 4) {
                Capsule(style: .continuous)
                    .fill(palette.accent)
                    .frame(width: 16, height: 2.5)
                Capsule(style: .continuous)
                    .fill(palette.goldBright)
                    .frame(width: 6, height: 2.5)
                Capsule(style: .continuous)
                    .fill(palette.hairlineStrong(for: .porcelain))
                    .frame(width: 12, height: 2.5)
            }
        }
    }

    @ViewBuilder
    private func headerActionButtons(
        file: NotulenFile,
        palette: NailPalette,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        Button {
            scrollToSummaryCard(proxy: scrollProxy)
            if summary == nil && !isSummarizing {
                generateSummary(for: file)
            }
        } label: {
            Label(
                isSummarizing ? "Meringkas…" : "Ringkas",
                systemImage: "sparkles"
            )
        }
        .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
        .disabled(isSummarizing)
        .help("Buat atau lihat ringkasan notulen")

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rawContent, forType: .string)
            flashFeedback(.copiedRaw)
        } label: {
            Label(
                copiedFeedback ? "Tersalin" : "Salin",
                systemImage: copiedFeedback ? "checkmark" : "doc.on.doc"
            )
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true))

        Button {
            NSWorkspace.shared.open(file.url)
        } label: {
            Label("Buka File", systemImage: "arrow.up.right.square")
        }
        .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))

        Button {
            filePendingDelete = file
        } label: {
            Label("Hapus", systemImage: "trash")
        }
        .buttonStyle(NailPillButtonStyle(variant: .danger, compact: true))
    }

    // MARK: - Ringkasan Notulen Card

    private func notulenSummaryCard(file: NotulenFile, palette: NailPalette) -> some View {
        TalmoCard(padding: 18, cornerRadius: 20, surface: .card, tone: .porcelain) {
            VStack(alignment: .leading, spacing: 14) {
                summaryCardHeader(palette: palette)

                if isSummarizing {
                    NeuWell(padding: 16, cornerRadius: 14, tone: .porcelain) {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(palette.goldBright)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Menyusun ringkasan notulen…")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(palette.primaryText(for: .porcelain))
                                Text("Menganalisis transkrip, keputusan, dan tindak lanjut rapat.")
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText(for: .porcelain))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                } else if let summary {
                    if let summaryError {
                        summaryErrorBanner(message: summaryError, file: file, palette: palette)
                    }

                    summaryBodyContent(summary: summary, palette: palette)

                    if backendUnconfiguredCallout {
                        backendUnconfiguredBanner(palette: palette)
                    } else if let submitError {
                        submitErrorBanner(
                            message: submitError,
                            file: file,
                            summary: summary,
                            palette: palette
                        )
                    } else if let record = submissionRecord {
                        submissionSuccessBanner(record: record, palette: palette)
                    }

                    summaryActionBar(file: file, summary: summary, palette: palette)

                    if showingJSONPreview {
                        jsonPreviewPanel(summary: summary, palette: palette)
                    }
                } else if let summaryError {
                    summaryErrorBanner(message: summaryError, file: file, palette: palette)
                } else {
                    NeuWell(padding: 16, cornerRadius: 14, tone: .porcelain) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Buat ringkasan otomatis dari transkrip rapat ini, lalu kirim ke API backend.")
                                .font(.callout)
                                .foregroundStyle(palette.secondaryText(for: .porcelain))
                                .fixedSize(horizontal: false, vertical: true)

                            NotulenFlowLayout(spacing: 8) {
                                Button {
                                    generateSummary(for: file)
                                } label: {
                                    Label("Buat Ringkasan", systemImage: "sparkles")
                                }
                                .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true))

                                summaryModelPickerMenu(palette: palette, tone: .porcelain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryCardHeader(palette: NailPalette) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                summaryCardTitle(palette: palette)
                Spacer(minLength: 8)
                summaryHeaderBadges(palette: palette)
            }

            VStack(alignment: .leading, spacing: 8) {
                summaryCardTitle(palette: palette)
                NotulenFlowLayout(spacing: 8) {
                    summaryHeaderBadges(palette: palette)
                }
            }
        }
    }

    private func summaryCardTitle(palette: NailPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.goldBright)
            Text("Ringkasan Notulen")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(palette.textPrimary)
        }
    }

    private func summaryModelPickerMenu(palette: NailPalette, tone: NeuTone = .porcelain) -> some View {
        let currentModel = VoiceSettings.shared.summaryModel
        let currentLabel = VoiceSettings.summaryModelDisplayName(for: currentModel)

        return Menu {
            ForEach(VoiceSettings.summaryModelGroups, id: \.self) { group in
                Section(group) {
                    ForEach(VoiceSettings.summaryModelOptions.filter { $0.group == group }) { option in
                        Button {
                            VoiceSettings.shared.summaryModel = option.id
                        } label: {
                            if option.id == currentModel {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                }
            }
        } label: {
            NeuMenuLabel(currentLabel, systemImage: "cpu", tone: tone, compact: true)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(NeuTactileScaleButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isSummarizing)
        .help("Pilih model AI untuk membuat ringkasan notulen (\(currentModel))")
    }

    @ViewBuilder
    private func summaryHeaderBadges(palette: NailPalette) -> some View {
        HStack(spacing: 8) {
            summaryModelPickerMenu(palette: palette)

            if let summary {
                if summary.modelUsed != VoiceSettings.shared.summaryModel {
                    Text("Hasil: \(VoiceSettings.summaryModelDisplayName(for: summary.modelUsed))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8.5)
                        .padding(.vertical, 3.5)
                        .background {
                            NeuInsetBackground(isCapsule: true, depth: 0.60)
                        }
                        .lineLimit(1)
                        .help("Ringkasan ini dibuat menggunakan model \(summary.modelUsed)")
                }

                Text(Self.formatSummaryTimestamp(summary.generatedAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)

                if let record = submissionRecord {
                    let badgeLabel: String = {
                        if let remoteId = record.remoteId, !remoteId.isEmpty {
                            return "Terkirim · \(remoteId)"
                        }
                        return "Terkirim"
                    }()
                    NailStatusBadge(
                        text: badgeLabel,
                        color: palette.emerald,
                        icon: "checkmark.circle.fill",
                        onInk: false
                    )
                    .help("Dikirim pada \(Self.formatSummaryTimestamp(record.submittedAt))")
                }
            }
        }
    }

    private func summaryBodyContent(summary: NotulenSummary, palette: NailPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Ringkasan Utama (Sculpted Porcelain Focal Well)
            NeuWell(padding: 14, cornerRadius: 14, tone: .porcelain) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ringkasan Utama")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText(for: .porcelain))
                    Text(summary.executiveSummary)
                        .font(.callout)
                        .foregroundStyle(palette.primaryText(for: .porcelain))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Poin Pembahasan
            if !summary.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    summarySectionHeader("Poin Pembahasan", icon: "list.bullet", palette: palette)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(palette.goldBright)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                Text(point)
                                    .font(.callout)
                                    .foregroundStyle(palette.textPrimary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            // Keputusan Rapat
            if !summary.decisions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    summarySectionHeader("Keputusan Rapat", icon: "checkmark.seal", palette: palette)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(summary.decisions.enumerated()), id: \.offset) { _, decision in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.emerald)
                                    .padding(.top, 2)
                                Text(decision)
                                    .font(.callout)
                                    .foregroundStyle(palette.textPrimary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            // Tindak Lanjut
            if !summary.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    summarySectionHeader("Tindak Lanjut", icon: "checklist", palette: palette)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.actionItems) { item in
                            NeuWell(padding: 11, cornerRadius: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.task)
                                        .font(.callout)
                                        .foregroundStyle(palette.textPrimary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    let hasOwner = !(item.owner?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                                    let hasDue = !(item.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                                    if hasOwner || hasDue {
                                        NotulenFlowLayout(spacing: 6) {
                                            if let owner = item.owner?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty {
                                                actionMetaCapsule(icon: "person", text: owner, palette: palette)
                                            }
                                            if let dueDate = item.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines), !dueDate.isEmpty {
                                                actionMetaCapsule(icon: "calendar", text: dueDate, palette: palette)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Peserta
            if !summary.participants.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    summarySectionHeader("Peserta", icon: "person.2", palette: palette)
                    NotulenFlowLayout(spacing: 6) {
                        ForEach(summary.participants, id: \.self) { participant in
                            let participantColor = NailSpeakerPalette.color(for: participant, scheme: colorScheme)
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(participantColor)
                                    .frame(width: 5, height: 5)
                                Text(participant)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background {
                                NeuRaisedBackground(isCapsule: true, elevation: 0.38)
                            }
                        }
                    }
                }
            }
        }
    }

    private func summarySectionHeader(_ title: String, icon: String, palette: NailPalette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textTertiary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func actionMetaCapsule(icon: String, text: String, palette: NailPalette) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.textTertiary)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            NeuRaisedBackground(isCapsule: true, elevation: 0.38)
        }
    }

    private func summaryErrorBanner(
        message: String,
        file: NotulenFile,
        palette: NailPalette
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(palette.bad)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                generateSummary(for: file)
            } label: {
                Label("Coba Lagi", systemImage: "arrow.clockwise")
            }
            .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
        }
        .padding(12)
        .background {
            NeuRaisedBackground(
                cornerRadius: 12,
                elevation: 0.42,
                tint: palette.bad
            )
        }
    }

    private func backendUnconfiguredBanner(palette: NailPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(palette.goldBright)
                    .padding(.top, 1)

                Text("Endpoint API backend belum diatur — masih menunggu konfigurasi backend.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let onOpenBackendSettings {
                Button {
                    onOpenBackendSettings()
                } label: {
                    Label("Atur Endpoint & Kredensial", systemImage: "gearshape")
                }
                .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
            }
        }
        .padding(12)
        .background {
            NeuRaisedBackground(
                cornerRadius: 12,
                elevation: 0.42,
                tint: palette.goldBright
            )
        }
    }

    private func submitErrorBanner(
        message: String,
        file: NotulenFile,
        summary: NotulenSummary,
        palette: NailPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(palette.bad)
                    .padding(.top, 1)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            NotulenFlowLayout(spacing: 8) {
                Button {
                    submitSummaryToBackend(file: file, summary: summary)
                } label: {
                    Label("Coba Lagi", systemImage: "arrow.clockwise")
                }
                .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))

                if submitErrorNeedsSettings, let onOpenBackendSettings {
                    Button {
                        onOpenBackendSettings()
                    } label: {
                        Label("Atur Endpoint & Kredensial", systemImage: "gearshape")
                    }
                    .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
                }
            }
        }
        .padding(12)
        .background {
            NeuRaisedBackground(
                cornerRadius: 12,
                elevation: 0.42,
                tint: palette.bad
            )
        }
    }

    private func submissionSuccessBanner(
        record: NotulenSubmissionRecord,
        palette: NailPalette
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(palette.emerald)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                let idText = record.remoteId.map { " · ID: \($0)" } ?? ""
                Text("Terkirim ke backend · \(Self.formatSummaryTimestamp(record.submittedAt))\(idText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let msg = record.message, !msg.isEmpty {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .background {
            NeuRaisedBackground(
                cornerRadius: 12,
                elevation: 0.42,
                tint: palette.emerald
            )
        }
    }

    private func summaryActionBar(
        file: NotulenFile,
        summary: NotulenSummary,
        palette: NailPalette
    ) -> some View {
        NotulenFlowLayout(spacing: 8) {
            Button {
                generateSummary(for: file)
            } label: {
                Label("Ringkas Ulang", systemImage: "arrow.clockwise")
            }
            .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
            .disabled(isSummarizing)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(summary.renderedMarkdown(), forType: .string)
                flashFeedback(.copiedSummary)
            } label: {
                Label(
                    copiedSummaryFeedback ? "Tersalin" : "Salin Ringkasan",
                    systemImage: copiedSummaryFeedback ? "checkmark" : "doc.on.doc"
                )
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))

            Button {
                saveSummaryToMarkdown(file: file, summary: summary)
            } label: {
                Label(
                    savedMarkdownFeedback ? "Tersimpan" : "Simpan ke .md",
                    systemImage: savedMarkdownFeedback ? "checkmark" : "square.and.arrow.down"
                )
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
            .disabled(isSavingMarkdown)

            Button {
                if reduceMotion {
                    showingJSONPreview.toggle()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        showingJSONPreview.toggle()
                    }
                }
            } label: {
                Label(
                    showingJSONPreview ? "Tutup JSON" : "Lihat JSON",
                    systemImage: "curlybraces"
                )
            }
            .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))

            Button {
                submitSummaryToBackend(file: file, summary: summary)
            } label: {
                if isSubmitting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Mengirim…")
                    }
                } else {
                    Label("Kirim ke Backend", systemImage: "paperplane.fill")
                }
            }
            .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true))
            .disabled(isSubmitting)
        }
    }

    private func jsonPreviewPanel(summary: NotulenSummary, palette: NailPalette) -> some View {
        let payloadJSON = NotulenSummarySubmissionPayload(summary: summary, rawMarkdown: rawContent)
            .prettyPrintedJSON()

        return NeuWell(padding: 12, cornerRadius: 14, tone: .porcelain) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Payload JSON · POST application/json")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText(for: .porcelain))

                    Spacer(minLength: 4)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payloadJSON, forType: .string)
                        flashFeedback(.copiedJSON)
                    } label: {
                        Label(
                            copiedJSONFeedback ? "Tersalin" : "Salin JSON",
                            systemImage: copiedJSONFeedback ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(NailPillButtonStyle(variant: .porcelain, compact: true))
                }

                ScrollView(.vertical) {
                    Text(payloadJSON)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.primaryText(for: .porcelain))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }
        }
    }

    // MARK: - In-Document Filter & Search Bar

    private func inDocumentFilterBar(doc: ParsedNotulenDocument, palette: NailPalette) -> some View {
        TalmoCard(padding: 12, cornerRadius: 16, tone: .porcelain) {
            HStack(spacing: 12) {
                NeuWell(padding: 8, cornerRadius: 11, tone: .porcelain) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.tertiaryText(for: .porcelain))

                        TextField("Cari di transkrip…", text: $inDocQuery)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(palette.primaryText(for: .porcelain))

                        if !inDocQuery.isEmpty {
                            TalmoCircleIconButton(
                                systemImage: "xmark",
                                tone: .porcelain,
                                size: 20,
                                helpText: "Bersihkan pencarian transkrip"
                            ) {
                                inDocQuery = ""
                            }
                        }
                    }
                }

                TalmoSegmentedPill(
                    options: TranscriptFilter.allCases,
                    selection: $transcriptFilter,
                    compact: true,
                    tone: .porcelain,
                    badge: { option in
                        switch option {
                        case .all:
                            return nil
                        case .meeting:
                            return doc.meetingLineCount > 0 ? "\(doc.meetingLineCount)" : nil
                        case .qa:
                            return doc.qaCount > 0 ? "\(doc.qaCount)" : nil
                        }
                    },
                    label: { $0.rawValue }
                )
            }
        }
    }

    // MARK: - Transcript Stream

    @ViewBuilder
    private func transcriptStream(doc: ParsedNotulenDocument, palette: NailPalette) -> some View {
        if doc.items.isEmpty {
            TalmoCard(padding: 20, cornerRadius: 20, tone: .porcelain) {
                NeuWell(padding: 18, cornerRadius: 14, tone: .porcelain) {
                    Text("Belum ada isi transkrip pada berkas ini.")
                        .font(.callout)
                        .foregroundStyle(palette.secondaryText(for: .porcelain))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            let visibleItems = filteredItems(for: doc)
            if visibleItems.isEmpty {
                TalmoCard(padding: 22, cornerRadius: 20, tone: .porcelain) {
                    NeuWell(padding: 22, cornerRadius: 16, tone: .porcelain) {
                        VStack(spacing: 10) {
                            ZStack {
                                NeuRaisedBackground(isCapsule: true, elevation: 0.50, tone: .porcelain)
                                    .frame(width: 42, height: 42)
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(palette.secondaryText(for: .porcelain))
                            }

                            Text("Tidak ada baris yang cocok")
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundStyle(palette.primaryText(for: .porcelain))

                            Text("Coba ubah filter kategori atau kata kunci pencarian di atas.")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText(for: .porcelain))
                                .multilineTextAlignment(.center)

                            if !inDocQuery.isEmpty || transcriptFilter != .all {
                                Button {
                                    inDocQuery = ""
                                    transcriptFilter = .all
                                } label: {
                                    Label("Reset Filter", systemImage: "arrow.counterclockwise")
                                }
                                .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
                                .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                TalmoCard(padding: 18, cornerRadius: 20, tone: .porcelain) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleItems) { item in
                            switch item.kind {
                            case .subheading(let heading):
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(palette.goldBright)
                                        .frame(width: 5, height: 5)
                                    Text(heading)
                                        .font(.system(size: 15, weight: .semibold, design: .serif))
                                        .foregroundStyle(palette.textPrimary)
                                    Rectangle()
                                        .fill(palette.hairlineStrong)
                                        .frame(height: 1)
                                }
                                .padding(.top, 6)
                                .padding(.bottom, 2)

                            case .meetingLine(let time, let speaker, let text):
                                HStack(alignment: .top, spacing: 10) {
                                    if let time {
                                        Text(time)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(palette.textTertiary)
                                            .frame(width: 60, alignment: .leading)
                                            .padding(.top, 2)
                                    }
                                    if let speaker, !speaker.isEmpty {
                                        let speakerColor = NailSpeakerPalette.color(for: speaker, scheme: colorScheme)
                                        Text(speaker)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(speakerColor)
                                            .padding(.horizontal, 8.5)
                                            .padding(.vertical, 3)
                                            .background {
                                                NeuRaisedBackground(
                                                    isCapsule: true,
                                                    elevation: 0.40,
                                                    tint: speakerColor,
                                                    tone: .porcelain
                                                )
                                            }
                                    }
                                    Text(text)
                                        .font(.callout)
                                        .foregroundStyle(palette.textPrimary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background {
                                    NeuRaisedBackground(cornerRadius: 12, elevation: 0.25, tone: .porcelain)
                                }

                            case .dengar(let time, let text):
                                NeuWell(padding: 12, cornerRadius: 14, tone: .porcelain) {
                                    HStack(alignment: .top, spacing: 11) {
                                        ZStack {
                                            NeuRaisedBackground(isCapsule: true, elevation: 0.50, tone: .porcelain)
                                                .frame(width: 26, height: 26)
                                            Image(systemName: "ear.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(palette.primaryText(for: .porcelain))
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                Text("Dengar")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(palette.textPrimary)
                                                if let time {
                                                    Text(time)
                                                        .font(.caption2.monospacedDigit())
                                                        .foregroundStyle(palette.textTertiary)
                                                }
                                            }
                                            Text(text)
                                                .font(.callout)
                                                .foregroundStyle(palette.textPrimary)
                                                .textSelection(.enabled)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }

                            case .nail(let time, let latency, let text):
                                TalmoCard(padding: 12, cornerRadius: 14, surface: .raised, tone: .porcelain) {
                                    HStack(alignment: .top, spacing: 11) {
                                        NailOrbMark(size: 22, isActive: false)
                                            .padding(.top, 1)

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                Text("Nail")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(palette.primaryText(for: .porcelain))
                                                if let time {
                                                    Text(time)
                                                        .font(.caption2.monospacedDigit())
                                                        .foregroundStyle(palette.tertiaryText(for: .porcelain))
                                                }
                                                if let latency {
                                                    Text(latency)
                                                        .font(.caption2.weight(.medium).monospacedDigit())
                                                        .foregroundStyle(palette.secondaryText(for: .porcelain))
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 2)
                                                        .background {
                                                            NeuInsetBackground(isCapsule: true, depth: 0.65, tone: .porcelain)
                                                        }
                                                }
                                            }
                                            Text(text)
                                                .font(.callout)
                                                .foregroundStyle(palette.primaryText(for: .porcelain))
                                                .textSelection(.enabled)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.leading, 4)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(palette.accent.opacity(0.20), lineWidth: 1)
                                }
                                .overlay(alignment: .leading) {
                                    VStack(spacing: 3) {
                                        Circle()
                                            .fill(palette.goldBright)
                                            .frame(width: 4.5, height: 4.5)
                                        Capsule(style: .continuous)
                                            .fill(palette.accent)
                                            .frame(width: 2.5)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.leading, 5)
                                }

                            case .plain(let text):
                                Text(text)
                                    .font(.callout)
                                    .foregroundStyle(palette.textSecondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    private func filteredItems(for doc: ParsedNotulenDocument) -> [ParsedNotulenItem] {
        let query = inDocQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [ParsedNotulenItem] = []
        var pendingSubheading: ParsedNotulenItem?

        for item in doc.items {
            switch item.kind {
            case .subheading:
                pendingSubheading = item
            default:
                if itemMatches(item.kind, filter: transcriptFilter, query: query) {
                    if let subheading = pendingSubheading {
                        result.append(subheading)
                        pendingSubheading = nil
                    }
                    result.append(item)
                }
            }
        }

        return result
    }

    private func itemMatches(
        _ kind: ParsedNotulenItem.Kind,
        filter: TranscriptFilter,
        query: String
    ) -> Bool {
        switch kind {
        case .subheading:
            return false

        case .meetingLine(let time, let speaker, let text):
            guard filter == .all || filter == .meeting else { return false }
            guard !query.isEmpty else { return true }
            return text.lowercased().contains(query)
                || (speaker?.lowercased().contains(query) ?? false)
                || (time?.lowercased().contains(query) ?? false)

        case .dengar(let time, let text):
            guard filter == .all || filter == .qa else { return false }
            guard !query.isEmpty else { return true }
            return text.lowercased().contains(query)
                || (time?.lowercased().contains(query) ?? false)
                || "dengar".contains(query)

        case .nail(let time, let latency, let text):
            guard filter == .all || filter == .qa else { return false }
            guard !query.isEmpty else { return true }
            return text.lowercased().contains(query)
                || (time?.lowercased().contains(query) ?? false)
                || (latency?.lowercased().contains(query) ?? false)
                || "nail".contains(query)

        case .plain(let text):
            guard filter == .all || filter == .meeting else { return false }
            guard !query.isEmpty else { return true }
            return text.lowercased().contains(query)
        }
    }

    private enum TransientFeedbackKind {
        case copiedRaw
        case copiedSummary
        case copiedJSON
        case savedMarkdown
    }

    private func setFeedbackFlag(_ kind: TransientFeedbackKind, value: Bool) {
        switch kind {
        case .copiedRaw: copiedFeedback = value
        case .copiedSummary: copiedSummaryFeedback = value
        case .copiedJSON: copiedJSONFeedback = value
        case .savedMarkdown: savedMarkdownFeedback = value
        }
    }

    private func flashFeedback(_ kind: TransientFeedbackKind) {
        if reduceMotion {
            setFeedbackFlag(kind, value: true)
        } else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                setFeedbackFlag(kind, value: true)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if reduceMotion {
                setFeedbackFlag(kind, value: false)
            } else {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                    setFeedbackFlag(kind, value: false)
                }
            }
        }
    }

    private func scrollToSummaryCard(proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("notulenSummaryCard", anchor: .top)
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                proxy.scrollTo("notulenSummaryCard", anchor: .top)
            }
        }
    }

    private func generateSummary(for file: NotulenFile) {
        summaryTask?.cancel()
        let targetURL = file.url
        let titleFallback = ParsedFilename.parse(file.name).title
        let currentMarkdown = rawContent
        let model = VoiceSettings.shared.summaryModel

        summaryError = nil
        backendUnconfiguredCallout = false
        if reduceMotion {
            isSummarizing = true
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSummarizing = true
            }
        }

        summaryTask = Task {
            do {
                let markdownToSummarize: String
                if currentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    markdownToSummarize = await Task.detached(priority: .userInitiated) {
                        NotulenExporter.readContent(of: targetURL)
                    }.value
                } else {
                    markdownToSummarize = currentMarkdown
                }

                let generated = try await NotulenSummaryService.summarize(
                    file: file,
                    markdown: markdownToSummarize,
                    model: model
                )
                try Task.checkCancellation()

                try await Task.detached(priority: .utility) {
                    try NotulenSummaryService.saveCachedSummary(generated, for: targetURL)
                }.value

                guard !Task.isCancelled, selectedFile?.url == targetURL else { return }
                if rawContent.isEmpty && !markdownToSummarize.isEmpty {
                    rawContent = markdownToSummarize
                    parsedDocument = ParsedNotulenDocument.parse(
                        markdown: markdownToSummarize,
                        fallbackTitle: titleFallback
                    )
                }
                if reduceMotion {
                    summary = generated
                    isSummarizing = false
                } else {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        summary = generated
                        isSummarizing = false
                    }
                }
            } catch is CancellationError {
                if selectedFile?.url == targetURL {
                    isSummarizing = false
                }
            } catch {
                guard !Task.isCancelled, selectedFile?.url == targetURL else { return }
                summaryError = error.localizedDescription
                isSummarizing = false
            }
        }
    }

    private func saveSummaryToMarkdown(file: NotulenFile, summary: NotulenSummary) {
        guard !isSavingMarkdown else { return }
        let targetURL = file.url
        let fallbackTitle = ParsedFilename.parse(file.name).title
        isSavingMarkdown = true
        summaryError = nil

        Task {
            do {
                let reloaded: (String, ParsedNotulenDocument) = try await Task.detached(priority: .userInitiated) {
                    try NotulenSummaryService.upsertSummarySection(in: targetURL, summary: summary)
                    let updatedContent = NotulenExporter.readContent(of: targetURL)
                    let parsed = ParsedNotulenDocument.parse(markdown: updatedContent, fallbackTitle: fallbackTitle)
                    return (updatedContent, parsed)
                }.value

                guard selectedFile?.url == targetURL else { return }
                rawContent = reloaded.0
                parsedDocument = reloaded.1
                isSavingMarkdown = false
                flashFeedback(.savedMarkdown)
            } catch {
                guard selectedFile?.url == targetURL else { return }
                isSavingMarkdown = false
                summaryError = "Gagal menyimpan ringkasan ke berkas .md: \(error.localizedDescription)"
            }
        }
    }

    private func submitSummaryToBackend(file: NotulenFile, summary: NotulenSummary) {
        let config = VoiceSettings.shared.notulenBackendConfig()
        guard config.isConfigured else {
            submitError = nil
            submitErrorNeedsSettings = false
            if reduceMotion {
                backendUnconfiguredCallout = true
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    backendUnconfiguredCallout = true
                }
            }
            return
        }

        submitTask?.cancel()
        let targetURL = file.url
        let markdownSnapshot = rawContent
        backendUnconfiguredCallout = false
        submitError = nil
        submitErrorNeedsSettings = false
        isSubmitting = true

        submitTask = Task {
            do {
                let credential = NotulenBackendKeychain.load()
                let record = try await NotulenBackendClient.submit(
                    summary: summary,
                    rawMarkdown: markdownSnapshot,
                    config: config,
                    credential: credential
                )
                try Task.checkCancellation()

                try await Task.detached(priority: .utility) {
                    try NotulenSummaryService.saveSubmissionRecord(record, for: targetURL)
                }.value

                guard !Task.isCancelled, selectedFile?.url == targetURL else { return }
                if reduceMotion {
                    submissionRecord = record
                    isSubmitting = false
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        submissionRecord = record
                        isSubmitting = false
                    }
                }
            } catch is CancellationError {
                if selectedFile?.url == targetURL {
                    isSubmitting = false
                }
            } catch let backendError as NotulenBackendError {
                guard !Task.isCancelled, selectedFile?.url == targetURL else { return }
                isSubmitting = false
                switch backendError {
                case .endpointNotConfigured, .invalidEndpointURL, .missingCredential:
                    submitErrorNeedsSettings = true
                case .httpError, .networkError:
                    submitErrorNeedsSettings = false
                }
                submitError = backendError.localizedDescription
            } catch {
                guard !Task.isCancelled, selectedFile?.url == targetURL else { return }
                isSubmitting = false
                submitErrorNeedsSettings = false
                submitError = error.localizedDescription
            }
        }
    }

    private static let summaryTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }()

    private static func formatSummaryTimestamp(_ date: Date) -> String {
        summaryTimestampFormatter.string(from: date)
    }

    private func loadSelectedContent() {
        loadTask?.cancel()
        guard let file = selectedFile else {
            rawContent = ""
            parsedDocument = nil
            summary = nil
            submissionRecord = nil
            return
        }
        loadTask = Task {
            let result = await Task.detached(priority: .utility) {
                let content = NotulenExporter.readContent(of: file.url)
                let title = ParsedFilename.parse(file.name).title
                let parsed = ParsedNotulenDocument.parse(markdown: content, fallbackTitle: title)
                let cachedSummary = NotulenSummaryService.loadCachedSummary(for: file.url)
                let cachedRecord = NotulenSummaryService.loadSubmissionRecord(for: file.url)
                return (content, parsed, cachedSummary, cachedRecord)
            }.value
            guard !Task.isCancelled, selectedFile?.url == file.url else { return }
            rawContent = result.0
            parsedDocument = result.1
            if !isSummarizing {
                summary = result.2
            }
            if !isSubmitting {
                submissionRecord = result.3
            }
        }
    }
}

/// Tactile neumorphic archive list row style: unselected rows sit in a subtle porcelain inset,
/// hovered rows lift slightly, selected rows pop into sculpted porcelain with an accent tint,
/// and presses compress with inner shadow.
private struct NeuArchiveRowButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSelected: Bool
    let isHovered: Bool
    let namespace: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        let palette = NailPalette(scheme: colorScheme)

        configuration.label
            .background {
                ZStack {
                    if isSelected {
                        NeuRaisedBackground(
                            cornerRadius: 14,
                            elevation: 0.72,
                            isPressed: configuration.isPressed,
                            tone: palette.activeContrastTone(for: .porcelain)
                        )
                        .matchedGeometryEffect(id: "SelectedNotulenBg", in: namespace)
                    } else if isHovered || configuration.isPressed {
                        NeuRaisedBackground(
                            cornerRadius: 14,
                            elevation: configuration.isPressed ? 0.25 : 0.48,
                            isPressed: configuration.isPressed,
                            tone: .porcelain
                        )
                    } else {
                        NeuInsetBackground(
                            cornerRadius: 14,
                            depth: 0.45,
                            tone: .porcelain
                        )
                    }
                }
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

/// Tactile press-scale style for neumorphic menu triggers so they depress smoothly without flat bezels.
private struct NeuTactileScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

private struct NotulenFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxMeasuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                maxMeasuredWidth = max(maxMeasuredWidth, currentX - spacing)
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        if currentX > 0 {
            maxMeasuredWidth = max(maxMeasuredWidth, currentX - spacing)
        }
        let finalWidth = proposal.width ?? maxMeasuredWidth
        return CGSize(width: finalWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Parsing Helpers

private struct ParsedFilename {
    let title: String
    let dateTimeLabel: String

    static func parse(_ filename: String) -> ParsedFilename {
        // Expected: YYYY-MM-DD_HH-mm_Slug or YYYY-MM-DD
        if let match = filename.wholeMatch(of: #/^(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})_(.+)$/#) {
            let datePart = String(match.1)
            let hour = String(match.2)
            let minute = String(match.3)
            let slug = String(match.4).replacingOccurrences(of: "-", with: " ")
            let cleanTitle = slug.isEmpty ? "Rapat" : slug
            return ParsedFilename(title: cleanTitle, dateTimeLabel: "\(datePart) · \(hour):\(minute)")
        }
        if let match = filename.wholeMatch(of: #/^(\d{4}-\d{2}-\d{2})$/#) {
            return ParsedFilename(title: "Notulen \(match.1)", dateTimeLabel: String(match.1))
        }
        return ParsedFilename(title: filename.replacingOccurrences(of: "-", with: " "), dateTimeLabel: "Catatan Rapat")
    }
}

private struct ParsedNotulenItem: Identifiable, Sendable {
    enum Kind: Sendable {
        case subheading(String)
        case meetingLine(time: String?, speaker: String?, text: String)
        case dengar(time: String?, text: String)
        case nail(time: String?, latency: String?, text: String)
        case plain(String)
    }

    let id = UUID()
    let kind: Kind
}

private struct ParsedNotulenDocument: Sendable {
    let title: String
    let date: String?
    let startTime: String?
    let meetingLink: String?
    let isTeams: Bool
    let statusRaw: String?
    let items: [ParsedNotulenItem]

    var linkPlatformLabel: String {
        isTeams ? "Link Microsoft Teams" : "Link Google Meet"
    }

    var meetingLineCount: Int {
        items.reduce(0) { count, item in
            if case .meetingLine = item.kind {
                return count + 1
            }
            return count
        }
    }

    var speakerCount: Int {
        var speakers = Set<String>()
        for item in items {
            if case .meetingLine(_, let speaker, _) = item.kind,
               let trimmed = speaker?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                speakers.insert(trimmed.lowercased())
            }
        }
        return speakers.count
    }

    var qaCount: Int {
        var dengarCount = 0
        var nailCount = 0
        for item in items {
            switch item.kind {
            case .dengar:
                dengarCount += 1
            case .nail:
                nailCount += 1
            default:
                break
            }
        }
        return max(dengarCount, nailCount)
    }

    func statusBadge(palette: NailPalette) -> (label: String, color: Color, isLive: Bool)? {
        guard let statusRaw, !statusRaw.isEmpty else { return nil }
        let lower = statusRaw.lowercased()
        if lower.contains("selesai") {
            return (statusRaw, palette.emerald, false)
        }
        if lower.contains("terputus") {
            return (statusRaw, palette.amber, false)
        }
        if lower.contains("berlangsung") {
            return (statusRaw, palette.gold, true)
        }
        return (statusRaw, palette.textSecondary, false)
    }

    static func parse(markdown: String, fallbackTitle: String) -> ParsedNotulenDocument {
        var title = fallbackTitle
        var date: String?
        var startTime: String?
        var meetingLink: String?
        var isTeams = false
        var statusRaw: String?
        var items: [ParsedNotulenItem] = []

        let lines = markdown.components(separatedBy: .newlines)
        var insideSummaryBlock = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "<!-- NAIL_SUMMARY_START -->" {
                insideSummaryBlock = true
                continue
            }
            if line == "<!-- NAIL_SUMMARY_END -->" {
                insideSummaryBlock = false
                continue
            }
            if insideSummaryBlock { continue }
            if line.isEmpty { continue }

            if line.hasPrefix("# ") && title == fallbackTitle {
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("- **Tanggal:**") {
                date = String(line.dropFirst("- **Tanggal:**".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("- **Mulai:**") {
                startTime = String(line.dropFirst("- **Mulai:**".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("- **Link Meet:**") {
                meetingLink = String(line.dropFirst("- **Link Meet:**".count)).trimmingCharacters(in: .whitespaces)
                isTeams = false
                continue
            }
            if line.hasPrefix("- **Link Teams:**") {
                meetingLink = String(line.dropFirst("- **Link Teams:**".count)).trimmingCharacters(in: .whitespaces)
                isTeams = true
                continue
            }
            if line.hasPrefix("- **Status:**") {
                statusRaw = String(line.dropFirst("- **Status:**".count)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("## ") {
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                items.append(ParsedNotulenItem(kind: .subheading(heading)))
                continue
            }

            // - [HH:mm:ss] **Speaker:** text
            if let match = line.wholeMatch(of: #/^- \[(\d{2}:\d{2}:\d{2})\] \*\*(.+?):\*\* (.+)$/#) {
                let ts = String(match.1)
                let rawSpeaker = String(match.2)
                let speaker = unescapeMarkdown(rawSpeaker)
                let text = String(match.3)
                items.append(ParsedNotulenItem(kind: .meetingLine(time: ts, speaker: speaker, text: text)))
                continue
            }

            // - [HH:mm:ss] text
            if let match = line.wholeMatch(of: #/^- \[(\d{2}:\d{2}:\d{2})\] (.+)$/#) {
                items.append(ParsedNotulenItem(kind: .meetingLine(time: String(match.1), speaker: nil, text: String(match.2))))
                continue
            }

            // **Dengar (HH:mm:ss):** text
            if let match = line.wholeMatch(of: #/^\*\*Dengar \(([^)]+)\):\*\* (.+)$/#) {
                items.append(ParsedNotulenItem(kind: .dengar(time: String(match.1), text: String(match.2))))
                continue
            }

            // **Nail (HH:mm:ss · X.X dtk):** text  OR  **Nail (HH:mm:ss):** text
            if let match = line.wholeMatch(of: #/^\*\*Nail \(([^)]+)\):\*\* (.+)$/#) {
                let meta = String(match.1)
                let text = String(match.2)
                let parts = meta.components(separatedBy: " · ")
                let time = parts.first
                let latency = parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : nil
                items.append(ParsedNotulenItem(kind: .nail(time: time, latency: latency, text: text)))
                continue
            }

            items.append(ParsedNotulenItem(kind: .plain(line)))
        }

        return ParsedNotulenDocument(
            title: title,
            date: date,
            startTime: startTime,
            meetingLink: meetingLink,
            isTeams: isTeams,
            statusRaw: statusRaw,
            items: items
        )
    }

    private static func unescapeMarkdown(_ raw: String) -> String {
        var result = ""
        var escaped = false
        for ch in raw {
            if escaped {
                result.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else {
                result.append(ch)
            }
        }
        return result
    }
}
