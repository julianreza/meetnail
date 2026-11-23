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
        Color(hex: 0x1A1A1A), // obsidian charcoal
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
                        .buttonStyle(NailPillButtonStyle(variant: .secondary))
                        .help("Muat ulang daftar notulen")

                        Button {
                            NotulenExporter.openFolder()
                        } label: {
                            Label("Buka Folder", systemImage: "folder")
                        }
                        .buttonStyle(NailPillButtonStyle(variant: .secondary))
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
            parsedDocument = nil
            rawContent = ""
            inDocQuery = ""
            transcriptFilter = .all
            loadSelectedContent()
        }
        .onDisappear { loadTask?.cancel() }
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

    // MARK: - Left Archive Rail (260pt)

    private func leftRail(palette: NailPalette) -> some View {
        TalmoCard(padding: 14, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Arsip Rapat")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(palette.textPrimary)

                    Spacer(minLength: 4)

                    Text("\(filteredFiles.count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: filteredFiles.count)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(palette.well, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(palette.hairlineStrong, lineWidth: 1)
                        }
                }
                .padding(.horizontal, 2)

                NeuWell(padding: 9, cornerRadius: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.textTertiary)

                        TextField("Cari notulen…", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(palette.textPrimary)

                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Bersihkan pencarian")
                        }
                    }
                }

                NeuWell(padding: 8, cornerRadius: 16) {
                    if filteredFiles.isEmpty {
                        VStack(spacing: 10) {
                            Spacer(minLength: 16)
                            Image(systemName: files.isEmpty ? "doc.text" : "magnifyingglass")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(palette.textTertiary)
                            Text(files.isEmpty ? "Belum Ada Notulen" : "Tidak Ada Hasil")
                                .font(.system(size: 14, weight: .semibold, design: .serif))
                                .foregroundStyle(palette.textPrimary)
                            Text(
                                files.isEmpty
                                    ? "Aktifkan Mode Notulen saat rapat untuk menyimpan catatan ke ~/NAIL/Notulen/."
                                    : "Coba kata kunci lain untuk menemukan arsip rapat."
                            )
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
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
                        .foregroundStyle(palette.textPrimary)
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
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            palette.goldSoft,
                            in: Capsule(style: .continuous)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    palette.goldBorder,
                                    lineWidth: 0.8
                                )
                        }
                    }
                }

                Text(parsed.dateTimeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 15)
            .padding(.trailing, 11)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    if isSelected {
                        TalmoCard(padding: 0, cornerRadius: 14, surface: .raised) {
                            Color.clear
                        }
                        .matchedGeometryEffect(id: "SelectedNotulenBg", in: archiveNS)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isHovered ? palette.card : palette.row.opacity(0.65))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        isHovered ? palette.hairlineStrong : palette.hairline,
                                        lineWidth: 1
                                    )
                            }
                    }
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    VStack(spacing: 3) {
                        Circle()
                            .fill(palette.goldBright)
                            .frame(width: 5, height: 5)
                        Capsule(style: .continuous)
                            .fill(palette.accent)
                            .frame(width: 3, height: 14)
                    }
                    .padding(.leading, 5.5)
                    .matchedGeometryEffect(id: "SelectedNotulenAccent", in: archiveNS)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        metadataHeaderCard(file: file, doc: doc, palette: palette)
                        inDocumentFilterBar(doc: doc, palette: palette)
                        transcriptStream(doc: doc, palette: palette)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(file.url)
                .transition(.opacity)
            } else if let file = selectedFile {
                TalmoCard(padding: 32, cornerRadius: 20) {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Memuat notulen…")
                            .font(.callout)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .id(file.url)
                .transition(.opacity)
            } else {
                TalmoCard(padding: 32, cornerRadius: 20) {
                    NeuWell(padding: 28, cornerRadius: 18) {
                        VStack(spacing: 14) {
                            NailOrbMark(size: 52, isActive: false)
                                .opacity(0.88)

                            Text(files.isEmpty ? "Belum Ada Berkas Notulen" : "Pilih Notulen")
                                .font(.system(size: 18, weight: .semibold, design: .serif))
                                .foregroundStyle(palette.textPrimary)

                            Text(
                                files.isEmpty
                                    ? "Transkrip Mode Notulen akan otomatis tersimpan di sini."
                                    : "Pilih salah satu catatan rapat di daftar sebelah kiri untuk membaca detailnya."
                            )
                            .font(.callout)
                            .foregroundStyle(palette.textSecondary)
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

    private func metadataHeaderCard(file: NotulenFile, doc: ParsedNotulenDocument, palette: NailPalette) -> some View {
        TalmoCard(padding: 20, cornerRadius: 20, surface: .raised) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 10) {
                            Text(doc.title)
                                .font(.system(size: 22, weight: .semibold, design: .serif))
                                .tracking(-0.3)
                                .foregroundStyle(palette.textPrimary)
                                .textSelection(.enabled)

                            if let statusBadge = doc.statusBadge(palette: palette) {
                                NailStatusBadge(
                                    text: statusBadge.label,
                                    color: statusBadge.color,
                                    pulse: statusBadge.isLive,
                                    onInk: false
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
                                .fill(palette.hairlineStrong)
                                .frame(width: 12, height: 2.5)
                        }
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(rawContent, forType: .string)
                            if reduceMotion {
                                copiedFeedback = true
                            } else {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                    copiedFeedback = true
                                }
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.5))
                                if reduceMotion {
                                    copiedFeedback = false
                                } else {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                        copiedFeedback = false
                                    }
                                }
                            }
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
                }

                NeuWell(padding: 8, cornerRadius: 14) {
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
                                    .foregroundStyle(palette.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        palette.card,
                                        in: Capsule(style: .continuous)
                                    )
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(palette.goldBorder, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
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
                .foregroundStyle(palette.textTertiary)
            if numericTransition {
                Text(text)
                    .font(monospaced ? .caption.monospacedDigit() : .caption)
                    .contentTransition(.numericText())
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            } else {
                Text(text)
                    .font(monospaced ? .caption.monospacedDigit() : .caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(palette.card, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(palette.hairlineStrong, lineWidth: 1)
        }
    }

    // MARK: - In-Document Filter & Search Bar

    private func inDocumentFilterBar(doc: ParsedNotulenDocument, palette: NailPalette) -> some View {
        TalmoCard(padding: 12, cornerRadius: 16) {
            HStack(spacing: 12) {
                NeuWell(padding: 8, cornerRadius: 11) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.textTertiary)

                        TextField("Cari di transkrip…", text: $inDocQuery)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(palette.textPrimary)

                        if !inDocQuery.isEmpty {
                            Button {
                                inDocQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Bersihkan pencarian transkrip")
                        }
                    }
                }

                TalmoSegmentedPill(
                    options: TranscriptFilter.allCases,
                    selection: $transcriptFilter,
                    compact: true,
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
            TalmoCard(padding: 20, cornerRadius: 20) {
                NeuWell(padding: 18, cornerRadius: 14) {
                    Text("Belum ada isi transkrip pada berkas ini.")
                        .font(.callout)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            let visibleItems = filteredItems(for: doc)
            if visibleItems.isEmpty {
                TalmoCard(padding: 22, cornerRadius: 20) {
                    NeuWell(padding: 22, cornerRadius: 16) {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(palette.textTertiary)

                            Text("Tidak ada baris yang cocok")
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundStyle(palette.textPrimary)

                            Text("Coba ubah filter kategori atau kata kunci pencarian di atas.")
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
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
                TalmoCard(padding: 18, cornerRadius: 20) {
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
                                            .background(
                                                speakerColor.opacity(palette.isDark ? 0.14 : 0.09),
                                                in: Capsule(style: .continuous)
                                            )
                                            .overlay {
                                                Capsule(style: .continuous)
                                                    .strokeBorder(
                                                        speakerColor.opacity(palette.isDark ? 0.28 : 0.22),
                                                        lineWidth: 0.8
                                                    )
                                            }
                                    }
                                    Text(text)
                                        .font(.callout)
                                        .foregroundStyle(palette.textPrimary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 3)

                            case .dengar(let time, let text):
                                NeuWell(padding: 12, cornerRadius: 14) {
                                    HStack(alignment: .top, spacing: 11) {
                                        ZStack {
                                            Circle()
                                                .fill(palette.card)
                                                .frame(width: 26, height: 26)
                                                .overlay {
                                                    Circle()
                                                        .strokeBorder(palette.hairlineStrong, lineWidth: 0.8)
                                                }
                                            Image(systemName: "ear.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(palette.textPrimary)
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
                                TalmoCard(padding: 12, cornerRadius: 14, surface: .raised) {
                                    HStack(alignment: .top, spacing: 11) {
                                        NailOrbMark(size: 22, isActive: false)
                                            .padding(.top, 1)

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                Text("Nail")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(palette.textPrimary)
                                                if let time {
                                                    Text(time)
                                                        .font(.caption2.monospacedDigit())
                                                        .foregroundStyle(palette.textTertiary)
                                                }
                                                if let latency {
                                                    Text(latency)
                                                        .font(.caption2.weight(.medium).monospacedDigit())
                                                        .foregroundStyle(palette.textSecondary)
                                                        .padding(.horizontal, 6.5)
                                                        .padding(.vertical, 1.5)
                                                        .background(palette.well, in: Capsule(style: .continuous))
                                                        .overlay {
                                                            Capsule(style: .continuous)
                                                                .strokeBorder(palette.hairline, lineWidth: 0.8)
                                                        }
                                                }
                                            }
                                            Text(text)
                                                .font(.callout)
                                                .foregroundStyle(palette.textPrimary)
                                                .textSelection(.enabled)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.leading, 4)
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

    private func loadSelectedContent() {
        loadTask?.cancel()
        guard let file = selectedFile else {
            rawContent = ""
            parsedDocument = nil
            return
        }
        loadTask = Task {
            let result = await Task.detached(priority: .utility) {
                let content = NotulenExporter.readContent(of: file.url)
                let title = ParsedFilename.parse(file.name).title
                return (content, ParsedNotulenDocument.parse(markdown: content, fallbackTitle: title))
            }.value
            guard !Task.isCancelled, selectedFile?.url == file.url else { return }
            rawContent = result.0
            parsedDocument = result.1
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
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
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
