import AppKit
import SwiftUI

enum DesktopSection: String, CaseIterable, Identifiable {
    case meeting
    case notulen
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meeting: "Rapat"
        case .notulen: "Notulen"
        case .settings: "Pengaturan"
        }
    }

    var systemImage: String {
        switch self {
        case .meeting: "video.bubble.left"
        case .notulen: "doc.text"
        case .settings: "gearshape"
        }
    }
}

private enum TranscriptFeedFilter: String, CaseIterable, Identifiable {
    case all
    case qa
    case meeting

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "Semua"
        case .qa: "Tanya Jawab"
        case .meeting: "Rapat"
        }
    }

    func matches(_ entry: TranscriptEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .qa:
            return entry.kind == .command || entry.kind == .reply
        case .meeting:
            return entry.kind == .meeting
        }
    }
}

struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var sidebarNavNS
    @Namespace private var meetingMorphNS
    @Namespace private var transcriptFilterNS
    @FocusState private var linkFieldFocused: Bool

    @State private var selection: DesktopSection = .meeting
    @State private var sectionSlideDirection: CGFloat = 1
    @State private var sidebarCollapsed = false
    @State private var hoveredSection: DesktopSection?
    @State private var hudPreviewHovered = false
    @State private var pasteHovered = false
    @State private var joinHovered = false
    @State private var listenHovered = false
    @State private var meetingTitle = ""
    @State private var meetLink = ""
    @State private var attendeesInformed = false
    @State private var prerequisites = PrerequisiteChecker.check()
    @State private var notulenFiles: [NotulenFile] = []
    @State private var selectedNotulen: NotulenFile?
    @State private var copiedReplyKey: String?
    @State private var copyReplyGeneration = 0
    @State private var linkCopied = false
    @State private var copyLinkGeneration = 0
    @State private var feedFilter: TranscriptFeedFilter = .all
    @State private var themeSwitchTick = 0
    @State private var themeWaveProgress: CGFloat = 1.0
    @State private var themeWaveOpacity: Double = 0.0
    @State private var meetingMorphPulse = false
    @State private var meetingMorphHaloVisible = false
    @State private var meetingMorphGeneration = 0

    private let meet = MeetSession.shared
    private let settings = VoiceSettings.shared

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)

        VStack(spacing: 0) {
            topFlushNavigationBar(palette: palette)

            mainContentStage(palette: palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 920, minHeight: 620)
        .background {
            ZStack {
                palette.canvasGradient

                RadialGradient(
                    colors: [
                        palette.good.opacity(palette.isDark ? 0.045 : 0.025),
                        palette.good.opacity(0.0)
                    ],
                    center: UnitPoint(x: 0.5, y: 0.14),
                    startRadius: 0,
                    endRadius: 420
                )

                RadialGradient(
                    colors: [
                        (palette.isDark ? Color.white : Color(hex: 0x0F172A))
                            .opacity(palette.isDark ? 0.015 : 0.010),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: 0,
                    endRadius: 340
                )
            }
            .ignoresSafeArea()
        }
        .overlay {
            themeTransitionOverlay(palette: palette)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
            value: colorScheme
        )
        .onAppear {
            AppNavigator.shared.openMainAction = { openWindow(id: "main") }
            refreshPrerequisites()
            refreshNotulen()
        }
        .onChange(of: colorScheme) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
                themeSwitchTick += 1
            }
            themeWaveProgress = 0.02
            themeWaveOpacity = 1.0
            withAnimation(.easeOut(duration: 0.48)) {
                themeWaveProgress = 1.0
                themeWaveOpacity = 0.0
            }
        }
        .onChange(of: meet.active) { _, active in
            if !active {
                attendeesInformed = false
                refreshNotulen()
            }
            if !reduceMotion {
                triggerMeetingMorphPulse()
            }
        }
        .onChange(of: meet.transcriptStore.entries.count) { _, _ in
            if selection == .notulen {
                refreshNotulen()
            }
        }
        .onChange(of: selection) { _, newSection in
            if newSection == .notulen {
                refreshNotulen()
            } else if newSection == .meeting {
                refreshPrerequisites()
            }
        }
    }

    private func selectSection(_ newSection: DesktopSection) {
        guard selection != newSection else { return }
        let sections = DesktopSection.allCases
        let oldIndex = sections.firstIndex(of: selection) ?? 0
        let newIndex = sections.firstIndex(of: newSection) ?? 0
        sectionSlideDirection = newIndex >= oldIndex ? 1 : -1

        if reduceMotion {
            selection = newSection
        } else {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                selection = newSection
            }
        }
    }

    private func triggerMeetingMorphPulse() {
        meetingMorphGeneration += 1
        let generation = meetingMorphGeneration

        var startTransaction = Transaction()
        startTransaction.disablesAnimations = true
        withTransaction(startTransaction) {
            meetingMorphHaloVisible = true
            meetingMorphPulse = false
        }

        Task { @MainActor in
            await Task.yield()
            guard meetingMorphGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                meetingMorphPulse = true
            }
            try? await Task.sleep(for: .milliseconds(600))
            guard meetingMorphGeneration == generation else { return }
            var endTransaction = Transaction()
            endTransaction.disablesAnimations = true
            withTransaction(endTransaction) {
                meetingMorphHaloVisible = false
                meetingMorphPulse = false
            }
        }
    }

    // MARK: - Slim Flush Top Bar (Option A)

    @ViewBuilder
    private func topFlushNavigationBar(palette: NailPalette) -> some View {
        Group {
            if meet.active {
                HStack(spacing: 12) {
                    topBarLeft(palette: palette)
                    Spacer(minLength: 8)
                    topBarNavTabs(palette: palette)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    topBarRight(palette: palette)
                }
            } else {
                ZStack {
                    HStack(spacing: 12) {
                        topBarLeft(palette: palette)
                        Spacer(minLength: 16)
                        topBarRight(palette: palette)
                    }

                    topBarNavTabs(palette: palette)
                }
            }
        }
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(palette.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.hairline(for: .porcelain))
                .frame(height: 1)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.82),
            value: meet.active
        )
    }

    private func topBarLeft(palette: NailPalette) -> some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(palette.hairline(for: .porcelain))
                .frame(width: 1, height: 16)

            HStack(spacing: 8) {
                NailOrbMark(size: 22, isActive: meet.active)

                Text("Meet Nail")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(palette.primaryText(for: .porcelain))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 76)
    }

    private func topBarNavTabs(palette: NailPalette) -> some View {
        HStack(spacing: 3) {
            ForEach(DesktopSection.allCases) { section in
                topBarNavTab(section: section, palette: palette)
            }
        }
        .padding(3.5)
        .background {
            NeuInsetBackground(isCapsule: true, depth: 0.85, tone: .porcelain)
        }
    }

    private func topBarNavTab(section: DesktopSection, palette: NailPalette) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section

        return Button {
            selectSection(section)
        } label: {
            HStack(spacing: 6) {
                if section == .meeting && meet.active {
                    SidebarLivePulseDot(
                        color: meet.visualState == .error ? palette.bad : palette.good
                    )
                }

                Text(section.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .tracking(-0.12)
                    .foregroundStyle(
                        isSelected
                            ? palette.primaryText(for: .obsidian)
                            : (isHovered ? palette.primaryText(for: .porcelain) : palette.secondaryText(for: .porcelain))
                    )
                    .lineLimit(1)

                topBarSectionBadge(for: section, isSelected: isSelected, palette: palette)
            }
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background {
                if isSelected {
                    NeuRaisedBackground(isCapsule: true, elevation: 0.65, tone: .obsidian)
                        .matchedGeometryEffect(id: "TopBarActiveSegment", in: sidebarNavNS)
                } else if isHovered {
                    Capsule(style: .continuous)
                        .fill(palette.hairline(for: .porcelain))
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(NeuTactileSegmentButtonStyle())
        .onHover { hovering in
            if reduceMotion {
                hoveredSection = hovering ? section : (hoveredSection == section ? nil : hoveredSection)
            } else {
                withAnimation(.easeOut(duration: 0.14)) {
                    hoveredSection = hovering ? section : (hoveredSection == section ? nil : hoveredSection)
                }
            }
        }
        .help(section.title)
    }

    @ViewBuilder
    private func topBarSectionBadge(
        for section: DesktopSection,
        isSelected: Bool,
        palette: NailPalette
    ) -> some View {
        switch section {
        case .meeting:
            EmptyView()
        case .notulen:
            if !notulenFiles.isEmpty {
                Text("\(notulenFiles.count)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(palette.primaryText(for: isSelected ? .obsidian : .porcelain))
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20)
                    .frame(height: 17)
                    .background {
                        if isSelected {
                            NeuInsetBackground(
                                isCapsule: true,
                                depth: 0.45,
                                tone: .obsidian
                            )
                        } else {
                            NeuRaisedBackground(
                                isCapsule: true,
                                elevation: 0.35,
                                tone: .porcelain
                            )
                        }
                    }
            }
        case .settings:
            if !prerequisites.allReady {
                Circle()
                    .fill(palette.warn)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func topBarRight(palette: NailPalette) -> some View {
        HStack(spacing: 8) {
            if meet.active {
                topBarActiveMeetingChip(palette: palette)

                if meet.meetingAvatarAvailable {
                    meetingAvatarButton
                }

                if meet.joiningMeeting {
                    Button {
                        meet.toggleBrowserWindow()
                    } label: {
                        Label(meet.browserWindowVisible ? "Tutup Web" : "Web", systemImage: "globe")
                    }
                    .buttonStyle(NailPillButtonStyle(variant: .porcelain, compact: true))
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Tampilkan atau sembunyikan jendela browser rapat")
                }

                Button {
                    meet.leave()
                } label: {
                    Label("Keluar Rapat", systemImage: "phone.down.fill")
                }
                .buttonStyle(NailPillButtonStyle(variant: .danger, compact: true))
                .fixedSize(horizontal: true, vertical: false)
            } else {
                topBarIdleStatusPill(palette: palette)
            }

            HStack(spacing: 5) {
                PrerequisiteStatusPill(
                    status: prerequisites,
                    onOpenSettings: { selectSection(.settings) },
                    onSignIn: { meet.signIn() },
                    onRefresh: { refreshPrerequisites() },
                    compact: true
                )

                TopBarIconButton(
                    systemImage: colorScheme == .dark ? "sun.max" : "moon.stars",
                    palette: palette,
                    helpText: colorScheme == .dark ? "Beralih ke Tema Terang" : "Beralih ke Tema Gelap",
                    symbolRotationDegrees: reduceMotion ? 0 : Double(themeSwitchTick) * 180,
                    bounceTrigger: themeSwitchTick
                ) {
                    toggleAppearance()
                }

                TopBarIconButton(
                    systemImage: sidebarCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                    palette: palette,
                    helpText: sidebarCollapsed ? "Tampilan Standar (⌘\\)" : "Tampilan Ringkas (⌘\\)"
                ) {
                    toggleSidebar()
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
        }
        .padding(.trailing, 20)
    }

    private var meetingAvatarButton: some View {
        let state = meet.meetingAvatarState
        let status: String = switch state {
        case .off: "Mati"
        case .starting: "Menyalakan"
        case .on: "Aktif"
        case .stopping: "Mematikan"
        case .unavailable: "Tidak tersedia"
        }
        return Button {
            meet.setMeetingAvatarEnabled(!meet.meetingAvatarRequested)
        } label: {
            Label(state == .unavailable ? "Avatar tidak tersedia" : "Avatar di rapat",
                  systemImage: meet.meetingAvatarRequested ? "video.fill" : "video.slash")
        }
        .buttonStyle(NailPillButtonStyle(variant: .porcelain, compact: true))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityValue(status)
        .help(state == .unavailable ? "Avatar tidak tersedia. Klik untuk mencoba lagi." : "Avatar di rapat · \(status)")
    }

    private func topBarActiveMeetingChip(palette: NailPalette) -> some View {
        let title = !meet.currentMeetingTitle.isEmpty
            ? meet.currentMeetingTitle
            : (meet.activePlatform?.label ?? "Sesi Rapat")

        return HStack(spacing: 7) {
            SidebarLivePulseDot(
                color: meet.visualState == .error ? palette.bad : palette.good
            )

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.primaryText(for: .porcelain))
                .lineLimit(1)
                .frame(maxWidth: 135, alignment: .leading)

            Text("·")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.tertiaryText(for: .porcelain))

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(NailFormatting.formatElapsed(since: meet.sessionStartedAt, now: context.date))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(palette.primaryText(for: .porcelain))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background {
            NeuRaisedBackground(isCapsule: true, elevation: 0.55, tone: .porcelain)
        }
        .matchedGeometryEffect(id: "TopBarStatusChip", in: meetingMorphNS)
    }

    private func topBarIdleStatusPill(palette: NailPalette) -> some View {
        Group {
            if !prerequisites.meetProfileExists {
                Button {
                    meet.signIn()
                } label: {
                    Label("Login Google", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(NailPillButtonStyle(variant: .porcelain, compact: true))
            } else if prerequisites.allReady {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(palette.good.opacity(0.20))
                            .frame(width: 11.5, height: 11.5)
                        Circle()
                            .fill(palette.good)
                            .frame(width: 6.5, height: 6.5)
                    }

                    Text("Siap")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.12)
                        .foregroundStyle(palette.isDark ? palette.good : Color(hex: 0x047857))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background {
                    NeuRaisedBackground(isCapsule: true, elevation: 0.50, tone: .porcelain)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status konsol: Siap")
            } else {
                Button {
                    selectSection(.settings)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(palette.warn)
                            .frame(width: 6.5, height: 6.5)

                        Text("Perlu Setup")
                    }
                }
                .buttonStyle(NailPillButtonStyle(variant: .tinted(palette.warn), compact: true, tone: .porcelain))
                .help("Buka Pengaturan untuk menyelesaikan penyiapan")
            }
        }
        .matchedGeometryEffect(id: "TopBarStatusChip", in: meetingMorphNS)
    }

    private func toggleSidebar() {
        if reduceMotion {
            sidebarCollapsed.toggle()
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                sidebarCollapsed.toggle()
            }
        }
    }

    private func toggleAppearance() {
        if reduceMotion {
            settings.appAppearance = (colorScheme == .dark) ? .light : .dark
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                settings.appAppearance = (colorScheme == .dark) ? .light : .dark
            }
        }
    }

    @ViewBuilder
    private func themeTransitionOverlay(palette: NailPalette) -> some View {
        if !reduceMotion && themeWaveOpacity > 0.001 {
            GeometryReader { proxy in
                let maxDimension = hypot(proxy.size.width, proxy.size.height) * 1.15
                let currentRadius = max(24, maxDimension * themeWaveProgress)
                let waveTint = palette.isDark
                    ? Color(hex: 0x34D399, alpha: 0.16)
                    : Color(hex: 0xFFFFFF, alpha: 0.55)
                let innerCore = palette.isDark
                    ? Color(hex: 0x0F1117, alpha: 0.28)
                    : Color(hex: 0xFBFBFD, alpha: 0.36)

                RadialGradient(
                    colors: [
                        waveTint,
                        innerCore,
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.93, y: 0.04),
                    startRadius: max(0, currentRadius * 0.12),
                    endRadius: currentRadius
                )
                .opacity(themeWaveOpacity)
                .blendMode(palette.isDark ? .plusLighter : .normal)
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Main Content Stage

    private func mainContentStage(palette: NailPalette) -> some View {
        ZStack {
            Group {
                switch selection {
                case .meeting:
                    meetingPane(palette: palette)
                case .notulen:
                    NotulenReaderView(
                        files: notulenFiles,
                        selectedFile: $selectedNotulen,
                        activeFileURL: meet.currentNotulenURL,
                        onRefresh: refreshNotulen,
                        onDelete: deleteNotulen,
                        onOpenBackendSettings: { selectSection(.settings) }
                    )
                case .settings:
                    SettingsView(settings: settings, isSessionActive: meet.active)
                }
            }
            .id(selection)
            .transition(
                .asymmetric(
                    insertion: .opacity
                        .combined(with: .offset(x: 28 * sectionSlideDirection))
                        .combined(with: .scale(scale: 0.992)),
                    removal: .opacity
                        .combined(with: .offset(x: -18 * sectionSlideDirection))
                )
            )
        }
        .background(Color.clear)
        .animation(
            reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86),
            value: selection
        )
    }

    // MARK: - Halaman Rapat (Spotlight Idle Command Center + Option N2 Portrait)

    private func meetingPane(palette: NailPalette) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if meet.active {
                    activeMeetingStage(palette: palette)
                } else {
                    idleSpotlightStage(palette: palette)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.82),
                value: meet.active
            )

            spotlightFooterBar(palette: palette)
        }
    }

    private func activeMeetingStage(palette: NailPalette) -> some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let availableHeight = proxy.size.height
            let showOnboarding = !prerequisites.allReady
            let stackVertically = availableWidth < 820
            let needsOuterScroll = stackVertically || availableHeight < (showOnboarding ? 570 : 495)

            if needsOuterScroll {
                ScrollView {
                    VStack(spacing: 12) {
                        if showOnboarding {
                            OnboardingBanner(
                                status: prerequisites,
                                onOpenSettings: { selectSection(.settings) },
                                onSignIn: { meet.signIn() },
                                onRefresh: { refreshPrerequisites() }
                            )
                        }

                        activeWorkspace(
                            width: availableWidth,
                            stackVertically: stackVertically,
                            fillHeight: false,
                            palette: palette
                        )
                    }
                    .frame(maxWidth: 1120)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    if showOnboarding {
                        OnboardingBanner(
                            status: prerequisites,
                            onOpenSettings: { selectSection(.settings) },
                            onSignIn: { meet.signIn() },
                            onRefresh: { refreshPrerequisites() }
                        )
                    }

                    activeWorkspace(
                        width: availableWidth,
                        stackVertically: false,
                        fillHeight: true,
                        palette: palette
                    )
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: 1120, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Centered Spotlight Idle Workspace (Minimalist Neumorphic)

    private func idleSpotlightStage(palette: NailPalette) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)

                    VStack(alignment: .center, spacing: 0) {
                        if !prerequisites.allReady {
                            OnboardingBanner(
                                status: prerequisites,
                                onOpenSettings: { selectSection(.settings) },
                                onSignIn: { meet.signIn() },
                                onRefresh: { refreshPrerequisites() }
                            )
                            .frame(maxWidth: 660)
                            .padding(.bottom, 18)
                        }

                        if !sidebarCollapsed {
                            spotlightHeroHeader(palette: palette)
                                .padding(.bottom, 26)
                                .transition(.opacity)
                        }

                        VStack(alignment: .center, spacing: 0) {
                            spotlightComposerCard(palette: palette)
                                .nailStaggeredEntrance(delay: 0.0)

                            idleTactileControlsRow(palette: palette)
                                .padding(.top, 16)

                            spotlightContextualNotices(palette: palette)

                            spotlightRecentNotesStrip(palette: palette)
                                .padding(.top, 30)
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: 18))
                                    .combined(with: .scale(scale: 0.97)),
                                removal: .opacity
                                    .combined(with: .offset(y: 12))
                                    .combined(with: .scale(scale: 0.96))
                            )
                        )
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeVoiceDisplayLabel: String {
        switch settings.provider {
        case .codex:
            return "Suara \(settings.codexVoice.capitalized)"
        case .antigravity:
            if settings.ttsEngine == .elevenlabs {
                let voiceName = settings.elevenLabsVoiceName.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayVoice = voiceName.isEmpty ? settings.elevenLabsVoiceId : voiceName
                let cleanVoice = displayVoice
                    .components(separatedBy: " - ")
                    .first?
                    .components(separatedBy: " — ")
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? displayVoice
                return "Suara \(cleanVoice)"
            }
            return "Suara \(TTSVoiceCatalog.shortDisplayName(for: settings.ttsVoice))"
        case .deepseek:
            return "Suara Stella"
        }
    }

    private var footerProviderLabel: String {
        settings.provider == .antigravity ? "Antigravity" : settings.provider.shortBadge
    }

    private var footerModelSummary: String {
        switch settings.provider {
        case .antigravity:
            return settings.agyModel
        case .codex:
            let hf = settings.codexHandsFree ? "Hands-Free" : "Manual"
            return "Suara \(settings.codexVoice.capitalized) · \(hf)"
        case .deepseek:
            return "deepseek-chat"
        }
    }

    @ViewBuilder
    private func nailHeroAvatar(
        dialSize: CGFloat,
        faceSize: CGFloat,
        mood: NailBotMood,
        isAcousticActive: Bool,
        phase: Double,
        speakingEnergy: Double,
        listeningEnergy: Double,
        showStatusDot: Bool,
        tone: NeuTone = .porcelain,
        palette: NailPalette
    ) -> some View {
        ZStack(alignment: .center) {
            NeuAcousticDial(
                size: dialSize,
                isActive: isAcousticActive,
                showYellowSpark: true,
                tone: tone
            ) {
                NailBotFaceView(
                    mood: mood,
                    form: .fullFace,
                    phase: phase,
                    speakingEnergy: speakingEnergy,
                    listeningEnergy: listeningEnergy,
                    accentColor: palette.goldBright,
                    size: CGSize(width: faceSize, height: faceSize),
                    isPaused: reduceMotion
                )
            }

            if !reduceMotion {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                palette.good.opacity(0.95),
                                palette.goldBright.opacity(0.58),
                                palette.good.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: dialSize, height: dialSize)
                    .shadow(color: palette.good.opacity(0.45), radius: 10)
                    .scaleEffect(meetingMorphHaloVisible ? (meetingMorphPulse ? 1.30 : 0.88) : 0.88)
                    .opacity(meetingMorphHaloVisible ? (meetingMorphPulse ? 0.0 : 0.55) : 0.0)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showStatusDot {
                Circle()
                    .fill(palette.good)
                    .frame(width: 14, height: 14)
                    .shadow(
                        color: Color.black.opacity(palette.isDark ? 0.28 : 0.14),
                        radius: 2,
                        x: 0,
                        y: 1
                    )
                    .overlay {
                        Circle()
                            .stroke(palette.card, lineWidth: 2.5)
                    }
                    .offset(x: -dialSize * 0.085, y: -dialSize * 0.085)
            }
        }
        .frame(width: dialSize, height: dialSize, alignment: .center)
        .matchedGeometryEffect(id: "NailHeroCharacter", in: meetingMorphNS)
    }

    private func spotlightHeroHeader(palette: NailPalette) -> some View {
        VStack(alignment: .center, spacing: 0) {
            nailHeroAvatar(
                dialSize: 204,
                faceSize: 168,
                mood: .standby,
                isAcousticActive: false,
                phase: 0,
                speakingEnergy: 0,
                listeningEnergy: 0,
                showStatusDot: true,
                tone: .porcelain,
                palette: palette
            )
            .padding(.bottom, 18)
            .accessibilityHidden(true)

            Text("Siap mendampingi rapatmu")
                .font(.system(size: 27, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.primaryText(for: .porcelain))
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            Text("\(NailFormatting.indonesianDateHeader()) · \(activeVoiceDisplayLabel)")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(palette.secondaryText(for: .porcelain))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .help("Penyedia AI aktif: \(settings.provider.label)")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 660)
    }

    private func spotlightComposerCard(palette: NailPalette) -> some View {
        let trimmedLink = meetLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedPlatform = MeetSession.detectPlatform(trimmedLink)
        let canJoin = !meet.active && !trimmedLink.isEmpty && attendeesInformed

        let joinHelpText: String = {
            if trimmedLink.isEmpty {
                return "Tempel link Google Meet atau Teams terlebih dahulu"
            }
            if !attendeesInformed {
                return "Aktifkan Info audio terlebih dahulu sebelum bergabung"
            }
            return "Bergabung ke rapat dengan Nail"
        }()

        let focusRingColor: Color = {
            guard linkFieldFocused else { return Color.clear }
            switch detectedPlatform {
            case .googleMeet:
                return palette.good.opacity(0.38)
            case .microsoftTeams:
                return palette.accent.opacity(0.32)
            case nil:
                return palette.hairlineStrong.opacity(0.65)
            }
        }()

        return HStack(spacing: 10) {
            if let detectedPlatform {
                Circle()
                    .fill(detectedPlatform == .googleMeet ? palette.good : palette.accent)
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: (detectedPlatform == .googleMeet ? palette.good : palette.accent).opacity(0.35),
                        radius: 3
                    )
                    .padding(.leading, 22)
                    .help(detectedPlatform == .googleMeet ? "Link Google Meet terdeteksi" : "Link Microsoft Teams terdeteksi")
                    .transition(.scale.combined(with: .opacity))
            }

            TextField("Tempel link Google Meet atau Teams...", text: $meetLink)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundStyle(palette.primaryText(for: .porcelain))
                .focused($linkFieldFocused)
                .disabled(meet.active)
                .padding(.leading, detectedPlatform == nil ? 22 : 0)
                .onSubmit {
                    if canJoin {
                        joinMeet()
                    }
                }

            if meetLink.isEmpty {
                TalmoCircleIconButton(
                    systemImage: "doc.on.clipboard",
                    tone: .porcelain,
                    size: 32,
                    helpText: "Tempel link rapat dari papan klip"
                ) {
                    if let pasted = NSPasteboard.general.string(forType: .string) {
                        meetLink = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .accessibilityLabel("Tempel link rapat")
            } else {
                TalmoCircleIconButton(
                    systemImage: "xmark",
                    tone: .porcelain,
                    size: 28,
                    helpText: "Bersihkan link"
                ) {
                    meetLink = ""
                }
                .accessibilityLabel("Bersihkan link rapat")
            }

            Button {
                joinMeet()
            } label: {
                Text("Gabung Rapat")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.15)
                    .lineLimit(1)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
            }
            .buttonStyle(
                NeuTactilePillActionStyle(
                    isCapsule: true,
                    tone: .obsidian,
                    isHovered: joinHovered
                )
            )
            .fixedSize(horizontal: true, vertical: false)
            .disabled(!canJoin)
            .onHover { joinHovered = $0 }
            .padding(.trailing, 7)
            .help(joinHelpText)
        }
        .frame(maxWidth: 660)
        .frame(height: 58)
        .background {
            NeuInsetBackground(isCapsule: true, depth: 1.05, tone: .porcelain)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(focusRingColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82),
            value: detectedPlatform != nil
        )
    }

    private func idleTactileControlsRow(palette: NailPalette) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(ListeningMode.allCases) { mode in
                        Button {
                            if reduceMotion {
                                settings.listeningMode = mode
                            } else {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                    settings.listeningMode = mode
                                }
                            }
                            meet.setListeningMode(mode)
                        } label: {
                            if settings.listeningMode == mode {
                                Label(mode.shortLabel, systemImage: "checkmark")
                            } else {
                                Text(mode.shortLabel)
                            }
                            Text(mode.description)
                        }
                    }
                } label: {
                    NeuMenuLabel(
                        settings.listeningMode.shortLabel,
                        systemImage: settings.listeningMode == .standby ? "bolt.fill" : "doc.text.fill",
                        tone: .porcelain,
                        compact: true
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(settings.listeningMode.description)

                Menu {
                    ForEach(SpeakingStyle.allCases) { style in
                        Button {
                            if reduceMotion {
                                settings.speakingStyle = style
                            } else {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                    settings.speakingStyle = style
                                }
                            }
                        } label: {
                            if settings.speakingStyle == style {
                                Label(style.label, systemImage: "checkmark")
                            } else {
                                Text(style.label)
                            }
                            Text(style.description)
                        }
                    }
                } label: {
                    NeuMenuLabel(
                        settings.speakingStyle.label,
                        systemImage: "bubble.left",
                        tone: .porcelain,
                        compact: true
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(settings.speakingStyle.description)

                Button {
                    HUDPanel.shared.triggerSpeakingPreview()
                } label: {
                    Label("Uji HUD", systemImage: "waveform")
                }
                .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true, tone: .porcelain))
                .fixedSize()
                .onHover { hudPreviewHovered = $0 }
                .help("Putar pratinjau HUD mengambang")
            }

            Spacer(minLength: 12)

            HStack(spacing: 9) {
                NeuSwitchToggle(isOn: $attendeesInformed, tone: .porcelain)

                Text("Info audio")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.primaryText(for: .porcelain))
                    .lineLimit(1)
                    .onTapGesture {
                        if reduceMotion {
                            attendeesInformed.toggle()
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                attendeesInformed.toggle()
                            }
                        }
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                NeuRaisedBackground(isCapsule: true, elevation: 0.45, tone: .porcelain)
            }
            .help("Peserta sudah diberi tahu audio dikirim ke \(settings.provider.recipient)")
        }
        .frame(maxWidth: 660)
    }

    @ViewBuilder
    private func spotlightContextualNotices(palette: NailPalette) -> some View {
        let trimmedLink = meetLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedPlatform = MeetSession.detectPlatform(trimmedLink)
        let hasError = !meet.status.isEmpty && meet.visualState == .error
        let hasNotulenError = !meet.notulenError.isEmpty

        if detectedPlatform == .microsoftTeams || hasError || hasNotulenError {
            VStack(spacing: 8) {
                if detectedPlatform == .microsoftTeams {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.caption)
                            .foregroundStyle(palette.textPrimary)
                        Text("Mode tamu Microsoft Teams (tanpa akun) — Nail masuk sebagai 'Nail'.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background {
                        NeuRaisedBackground(cornerRadius: 12, elevation: 0.45)
                    }
                }

                if hasError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.caption)
                            .foregroundStyle(palette.bad)
                        Text(meet.status)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background {
                        NeuRaisedBackground(cornerRadius: 12, elevation: 0.45, tint: palette.bad)
                    }
                }

                if hasNotulenError {
                    notulenErrorBanner(palette: palette)
                }
            }
            .frame(maxWidth: 660)
            .padding(.top, 14)
        }
    }

    private func listeningModeMenuPill(
        palette: NailPalette,
        fillWidth: Bool = false,
        tone: NeuTone = .porcelain
    ) -> some View {
        let menu = Menu {
            ForEach(ListeningMode.allCases) { mode in
                Button {
                    if reduceMotion {
                        settings.listeningMode = mode
                    } else {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            settings.listeningMode = mode
                        }
                    }
                    meet.setListeningMode(mode)
                } label: {
                    if settings.listeningMode == mode {
                        Label(mode.shortLabel, systemImage: "checkmark")
                    } else {
                        Text(mode.shortLabel)
                    }
                    Text(mode.description)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: settings.listeningMode == .standby ? "bolt.fill" : "doc.text.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(
                        settings.listeningMode == .standby ? palette.goldBright : palette.good
                    )

                Text("Mode:")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryText(for: tone))

                Text(settings.listeningMode.shortLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.primaryText(for: tone))
                    .lineLimit(1)

                if fillWidth {
                    Spacer(minLength: 4)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.tertiaryText(for: tone))
            }
            .padding(.horizontal, fillWidth ? 12 : 11)
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
            .frame(height: fillWidth ? 36 : 32)
            .background {
                NeuRaisedBackground(
                    cornerRadius: fillWidth ? 12 : 10,
                    elevation: 0.65,
                    tone: tone
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: fillWidth ? 12 : 10, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(settings.listeningMode.description)

        return Group {
            if fillWidth {
                menu.frame(maxWidth: .infinity)
            } else {
                menu.fixedSize()
            }
        }
    }

    private func speakingStyleMenuPill(
        palette: NailPalette,
        fillWidth: Bool = false,
        tone: NeuTone = .porcelain
    ) -> some View {
        let menu = Menu {
            ForEach(SpeakingStyle.allCases) { style in
                Button {
                    if reduceMotion {
                        settings.speakingStyle = style
                    } else {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            settings.speakingStyle = style
                        }
                    }
                } label: {
                    if settings.speakingStyle == style {
                        Label(style.label, systemImage: "checkmark")
                    } else {
                        Text(style.label)
                    }
                    Text(style.description)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.secondaryText(for: tone))

                Text("Gaya:")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryText(for: tone))

                Text(settings.speakingStyle.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.primaryText(for: tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                if fillWidth {
                    Spacer(minLength: 4)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.tertiaryText(for: tone))
            }
            .padding(.horizontal, fillWidth ? 12 : 11)
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
            .frame(height: fillWidth ? 36 : 32)
            .background {
                NeuRaisedBackground(
                    cornerRadius: fillWidth ? 12 : 10,
                    elevation: 0.65,
                    tone: tone
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: fillWidth ? 12 : 10, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(settings.speakingStyle.description)

        return Group {
            if fillWidth {
                menu.frame(maxWidth: .infinity)
            } else {
                menu.fixedSize()
            }
        }
    }

    @ViewBuilder
    private func spotlightRecentNotesStrip(palette: NailPalette) -> some View {
        if let latestFile = notulenFiles.first {
            let parsed = parseNotulenFilename(latestFile.name)

            Button {
                selectedNotulen = latestFile
                selectSection(.notulen)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Notulen terakhir:")
                        .foregroundStyle(palette.secondaryText(for: .porcelain))
                    Text("\(parsed.title) · \(parsed.dateTime)")
                        .foregroundStyle(palette.primaryText(for: .porcelain))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .buttonStyle(NailPillButtonStyle(variant: .porcelain, compact: true))
            .help("Buka notulen terakhir di tab Notulen")
        }
    }

    private func spotlightFooterBar(palette: NailPalette) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    HStack(spacing: 2.5) {
                        footerKeycap("⌘", palette: palette)
                        footerKeycap("⇧", palette: palette)
                        footerKeycap("M", palette: palette)
                    }
                    Text("Panic Mute")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText(for: .porcelain))
                }

                Text("·")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.tertiaryText(for: .porcelain))

                HStack(spacing: 6) {
                    Text("\"Nail\"")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText(for: .porcelain))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background {
                            NeuRaisedBackground(cornerRadius: 6, elevation: 0.35, tint: palette.goldBright, tone: .porcelain)
                        }

                    Text("Kata Panggil")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText(for: .porcelain))
                }

                Text("·")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.tertiaryText(for: .porcelain))

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        footerKeycap("⌘", palette: palette)
                        footerKeycap("\\", palette: palette)
                    }
                    Text("Mode Ringkas")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText(for: .porcelain))
                }
            }

            Spacer(minLength: 12)

            if meet.active {
                HStack(spacing: 8) {
                    if !meet.currentMeetingLink.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "link")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(palette.good)

                            Text(meet.currentMeetingLink)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondaryText(for: .porcelain))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 265, alignment: .leading)
                        }

                        Button {
                            copyMeetingLink()
                        } label: {
                            Text(linkCopied ? "Tersalin" : "Salin")
                        }
                        .buttonStyle(NailPillButtonStyle(variant: linkCopied ? .tinted(palette.good) : .porcelain, compact: true))
                        .fixedSize(horizontal: true, vertical: false)

                        Text("·")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(palette.tertiaryText(for: .porcelain))
                    } else {
                        Circle()
                            .fill(palette.good.opacity(0.85))
                            .frame(width: 6, height: 6)

                        Text(footerProviderLabel)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.secondaryText(for: .porcelain))

                        Text("·")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(palette.tertiaryText(for: .porcelain))

                        Text(footerModelSummary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.tertiaryText(for: .porcelain))
                            .lineLimit(1)

                        Text("·")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(palette.tertiaryText(for: .porcelain))
                    }

                    Button {
                        openArchiveOrNotulen()
                    } label: {
                        HStack(spacing: 3) {
                            Text("Buka Arsip")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(NailPillButtonStyle(variant: .porcelain, compact: true))
                    .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                HStack(spacing: 7) {
                    Circle()
                        .fill(palette.good.opacity(0.85))
                        .frame(width: 6, height: 6)

                    Text(footerProviderLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.secondaryText(for: .porcelain))

                    Text("·")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(palette.tertiaryText(for: .porcelain))

                    Text(footerModelSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.tertiaryText(for: .porcelain))
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(palette.tertiaryText(for: .porcelain))

                    Button {
                        selectSection(.settings)
                    } label: {
                        HStack(spacing: 3) {
                            Text("Ubah")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(NailPillButtonStyle(variant: .porcelain, compact: true))
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .background(palette.canvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.hairline(for: .porcelain))
                .frame(height: 1)
        }
    }

    private func footerKeycap(_ label: String, palette: NailPalette) -> some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.secondaryText(for: .porcelain))
            .padding(.horizontal, 5.5)
            .frame(minWidth: 20)
            .frame(height: 20)
            .background {
                NeuRaisedBackground(cornerRadius: 5.5, elevation: 0.35, tone: .porcelain)
            }
    }

    // MARK: - Option N2 Active Workspace ("Nail Companion Portrait" — 46% Portrait / 54% Live Feed)

    @ViewBuilder
    private func activeWorkspace(
        width: CGFloat,
        stackVertically: Bool,
        fillHeight: Bool,
        palette: NailPalette
    ) -> some View {
        let rightFeedTransition = AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .offset(x: 28)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .offset(x: 18))
        )

        if stackVertically {
            VStack(spacing: 16) {
                portraitCompanionCard(fillHeight: false, palette: palette)
                    .frame(maxWidth: .infinity)

                liveTranscriptCard(fillHeight: false, palette: palette)
                    .frame(maxWidth: .infinity)
                    .transition(rightFeedTransition)
            }
        } else {
            let contentWidth = min(max(width - 48, 0), 1120)
            let columnsWidth = max(contentWidth - 18, 0)
            let leftWidth = floor(columnsWidth * 0.46)

            HStack(alignment: .top, spacing: 18) {
                portraitCompanionCard(fillHeight: fillHeight, palette: palette)
                    .frame(width: leftWidth)
                    .frame(maxHeight: fillHeight ? .infinity : nil)

                liveTranscriptCard(fillHeight: fillHeight, palette: palette)
                    .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil)
                    .transition(rightFeedTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil)
        }
    }

    // MARK: - Left Column (46%): Dedicated Nail Portrait Card

    private var activeBotMood: NailBotMood {
        if meet.visualState == .error { return .error }
        if meet.visualState == .interrupted { return .interrupted }
        if meet.isSpeaking || meet.presentation == .speaking { return .speaking }
        if meet.presentation == .processing { return .processing }
        if meet.isActivelyListening { return .listening }
        return .standby
    }

    private var activeDialHeadline: String {
        SessionPresentation.dialHeadline(
            presentation: meet.presentation,
            visualState: meet.visualState,
            voiceBusy: meet.voiceBusy
        )
    }

    private var activePlatformShortLabel: String {
        switch meet.activePlatform {
        case .googleMeet:
            return "Google Meet"
        case .microsoftTeams:
            return "MS Teams"
        case nil:
            return meet.joiningMeeting ? "Sesi Rapat" : "Login Google"
        }
    }

    private func portraitCompanionCard(fillHeight: Bool, palette: NailPalette) -> some View {
        let speakingEnergy: Double = meet.isSpeaking ? 1.0 : 0.0
        let listeningEnergy: Double = meet.isActivelyListening ? 0.85 : 0.0
        let isAcousticActive = meet.isSpeaking || meet.isActivelyListening || meet.presentation == .processing
        let hudVisible = HUDPanel.shared.metrics.isVisible
        let platformName = activePlatformShortLabel
        let canListen = meet.voiceReady && !meet.voiceBusy

        let stateTone: (dot: Color, text: Color, bg: Color, border: Color, pulse: Bool) = {
            if meet.visualState == .error || meet.presentation == .error {
                return (palette.bad, palette.bad, palette.badSoft, palette.bad.opacity(0.24), false)
            }
            if meet.visualState == .interrupted || meet.presentation == .interrupted {
                return (palette.warn, palette.warn, palette.warnSoft, palette.warn.opacity(0.24), false)
            }
            if meet.presentation == .processing {
                return (palette.goldBright, palette.gold, palette.goldSoft, palette.goldBorder, true)
            }
            return (
                palette.good,
                palette.isDark ? palette.good : Color(hex: 0x047857),
                palette.goodSoft,
                palette.good.opacity(0.22),
                true
            )
        }()

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                // 1. Top Pill Row inside Portrait Card
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        if stateTone.pulse {
                            SidebarLivePulseDot(color: stateTone.dot)
                        } else {
                            Circle()
                                .fill(stateTone.dot)
                                .frame(width: 6.5, height: 6.5)
                        }

                        Text(meet.presentation.label)
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(-0.12)
                            .foregroundStyle(stateTone.dot)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background {
                        NeuRaisedBackground(
                            isCapsule: true,
                            elevation: 0.55,
                            tint: stateTone.dot,
                            tone: .porcelain
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondaryText(for: .porcelain))

                        Text(activeVoiceDisplayLabel)
                            .font(.system(size: 12, weight: .medium))
                            .tracking(-0.12)
                            .foregroundStyle(palette.secondaryText(for: .porcelain))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background {
                        NeuInsetBackground(isCapsule: true, depth: 0.70, tone: .porcelain)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 10)

                // 2. Hero Nail Stage + 9-Bar Reactive Waveform + Clean Sans Headline
                VStack(alignment: .center, spacing: 0) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isAcousticActive)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let phaseSpeed = 1.6 + speakingEnergy * 1.4 + listeningEnergy * 0.6
                        let currentPhase = (reduceMotion || !isAcousticActive) ? 0.0 : (t * phaseSpeed)

                        VStack(alignment: .center, spacing: 12) {
                            nailHeroAvatar(
                                dialSize: 210,
                                faceSize: 172,
                                mood: activeBotMood,
                                isAcousticActive: isAcousticActive,
                                phase: currentPhase,
                                speakingEnergy: speakingEnergy,
                                listeningEnergy: listeningEnergy,
                                showStatusDot: false,
                                tone: .porcelain,
                                palette: palette
                            )

                            portraitWaveformBars(
                                phase: currentPhase,
                                speakingEnergy: speakingEnergy,
                                listeningEnergy: listeningEnergy,
                                isActive: isAcousticActive,
                                palette: palette
                            )
                        }
                    }

                    Text(activeDialHeadline)
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(palette.primaryText(for: .porcelain))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .padding(.top, 12)

                    Text(!meet.status.isEmpty ? meet.status : "Panggil \"Nail\" kapan saja di \(platformName)")
                        .font(.system(size: 13))
                        .foregroundStyle(meet.visualState == .error ? palette.bad : palette.secondaryText(for: .porcelain))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 12)

                // 3. Clean Action Cluster
                VStack(spacing: 10) {
                    Button {
                        meet.answerMeeting()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(canListen ? palette.good : palette.tertiaryText(for: .porcelain))
                                .symbolEffect(
                                    .variableColor.iterative.reversing,
                                    isActive: meet.voiceBusy || meet.isSpeaking
                                )

                            Text("Dengar & Jawab")
                                .font(.system(size: 13.5, weight: .semibold))
                                .tracking(-0.15)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                    }
                    .buttonStyle(
                        NeuTactilePillActionStyle(
                            cornerRadius: 12,
                            isCapsule: false,
                            tone: .obsidian,
                            disabledTone: .porcelain,
                            isHovered: listenHovered
                        )
                    )
                    .disabled(!canListen)
                    .onHover { listenHovered = $0 }

                    HStack(spacing: 10) {
                        listeningModeMenuPill(palette: palette, fillWidth: true, tone: .porcelain)
                        speakingStyleMenuPill(palette: palette, fillWidth: true, tone: .porcelain)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 14)))
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil)

            // 4. Bottom Row inside Portrait Card: HUD Melayang + Uji | Panic Mute ⌘⇧M
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("HUD Melayang")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(palette.secondaryText(for: .porcelain))
                            .lineLimit(1)
                            .onTapGesture {
                                HUDPanel.shared.toggle()
                            }

                        NeuSwitchToggle(
                            isOn: Binding(
                                get: { hudVisible },
                                set: { _ in HUDPanel.shared.toggle() }
                            ),
                            tone: .porcelain
                        )
                    }
                    .help(hudVisible ? "Sembunyikan HUD" : "Tampilkan HUD")

                    Button {
                        HUDPanel.shared.triggerSpeakingPreview()
                    } label: {
                        Text("Uji")
                    }
                    .buttonStyle(NailPillButtonStyle(variant: .porcelain, compact: true))
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Putar pratinjau gelombang suara HUD")
                }

                Spacer(minLength: 8)

                Button {
                    meet.interrupt()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 11, weight: .semibold))

                        Text("Panic Mute")
                            .lineLimit(1)

                        Text("⌘⇧M")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .frame(height: 17)
                            .background(
                                palette.bad.opacity(0.22),
                                in: RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            )
                    }
                }
                .buttonStyle(NailPillButtonStyle(variant: .danger, compact: true))
                .fixedSize(horizontal: true, vertical: false)
                .help("Potong suara Nail segera (⌘⇧M)")
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(palette.well.opacity(0.65))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.hairline(for: .porcelain))
                    .frame(height: 1)
            }
        }
        .background(alignment: .top) {
            RadialGradient(
                colors: [
                    palette.good.opacity(0.10),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.06),
                startRadius: 0,
                endRadius: 290
            )
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background {
            NeuRaisedBackground(cornerRadius: 22, elevation: 1.0, tone: .porcelain)
        }
    }

    private func portraitWaveformBars(
        phase: Double,
        speakingEnergy: Double,
        listeningEnergy: Double,
        isActive: Bool,
        palette: NailPalette
    ) -> some View {
        let baseHeights: [CGFloat] = [6, 10, 15, 11, 19, 13, 16, 9, 6]
        let baseOpacities: [Double] = [0.35, 0.55, 0.78, 0.65, 1.0, 0.75, 0.85, 0.52, 0.35]
        let energy = isActive ? max(speakingEnergy, max(listeningEnergy * 0.80, 0.35)) : 0.0
        let barColor: Color = {
            if meet.visualState == .error { return palette.bad }
            if meet.visualState == .interrupted { return palette.warn }
            return palette.good
        }()

        return HStack(spacing: 4.5) {
            ForEach(0..<baseHeights.count, id: \.self) { index in
                let base = baseHeights[index]
                let wave = (!isActive || reduceMotion)
                    ? 1.0
                    : (0.64 + 0.50 * abs(sin(phase * 2.4 + Double(index) * 0.68)))
                let barHeight: CGFloat = isActive
                    ? max(5, min(22, base * (0.72 + CGFloat(energy) * 0.38) * CGFloat(wave)))
                    : base
                let barOpacity: Double = isActive
                    ? min(1.0, baseOpacities[index] + 0.14)
                    : (baseOpacities[index] * 0.85)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                barColor.opacity(min(1.0, barOpacity + 0.10)),
                                barColor.opacity(barOpacity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.5, height: barHeight)
            }
        }
        .frame(height: 22)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isActive)
        .accessibilityHidden(true)
    }

    private func notulenErrorBanner(palette: NailPalette) -> some View {
        let warnColor = palette.warn
        let tone: NeuTone = .porcelain
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(warnColor)
            Text(meet.notulenError)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.primaryText(for: tone))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            NeuRaisedBackground(cornerRadius: 11, elevation: 0.45, tint: warnColor, tone: tone)
        }
    }

    // MARK: - Right Column (54%): Airy Live Conversation Feed Card

    private func liveTranscriptCard(fillHeight: Bool, palette: NailPalette) -> some View {
        let entries = meet.transcriptStore.entries
        let filteredEntries = entries.filter { feedFilter.matches($0) }
        let liveHeard = meet.liveVoice.heard ?? ""
        let liveReply = meet.liveVoice.reply ?? ""
        let hasLiveText = !liveHeard.isEmpty || !liveReply.isEmpty
        let showLive = feedFilter != .meeting && hasLiveText
        let totalCount = entries.count + (liveHeard.isEmpty ? 0 : 1) + (liveReply.isEmpty ? 0 : 1)
        let headingTitle = !meet.currentMeetingTitle.isEmpty ? meet.currentMeetingTitle : "Rapat Berlangsung"
        let platformName = activePlatformShortLabel
        let isGoogleMeet = meet.activePlatform == .googleMeet

        return VStack(spacing: 0) {
            // 1. Header Row
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    Text(headingTitle)
                        .font(.system(size: 17.5, weight: .semibold))
                        .tracking(-0.35)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("\(totalCount) baris")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background {
                            NeuInsetBackground(isCapsule: true, depth: 0.65)
                        }
                        .fixedSize(horizontal: true, vertical: false)

                    HStack(spacing: 4.5) {
                        Image(systemName: "video")
                            .font(.system(size: 10, weight: .semibold))
                        Text(platformName)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(-0.12)
                    }
                    .foregroundStyle(
                        isGoogleMeet
                            ? (palette.isDark ? palette.good : Color(hex: 0x047857))
                            : palette.textSecondary
                    )
                    .padding(.horizontal, 8.5)
                    .frame(height: 22)
                    .background {
                        NeuRaisedBackground(
                            isCapsule: true,
                            elevation: 0.40,
                            tint: isGoogleMeet ? palette.good : nil
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 8)

                transcriptSegmentedFilter(palette: palette)
            }
            .padding(.init(top: 17, leading: 18, bottom: 13, trailing: 18))

            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)

            // 2. Clean Scrollable Conversation Feed
            VStack(spacing: 0) {
                if !meet.notulenError.isEmpty {
                    notulenErrorBanner(palette: palette)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }

                if entries.isEmpty && !hasLiveText {
                    VStack {
                        NeuWell(padding: 28, cornerRadius: 18, tone: .porcelain) {
                            VStack(spacing: 12) {
                                NailOrbMark(size: 46, isActive: meet.active)
                                    .opacity(0.90)

                                Text("Menunggu Percakapan Rapat")
                                    .font(.system(size: 15.5, weight: .semibold))
                                    .tracking(-0.2)
                                    .foregroundStyle(palette.primaryText(for: .porcelain))

                                Text(
                                    settings.listeningMode == .notulen
                                        ? "Transkrip peserta dan tanya jawab Nail akan muncul secara real-time di sini."
                                        : "Mode Siaga aktif. Panggil \"Nail\" atau tekan Dengar & Jawab untuk memulai tanya jawab."
                                )
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.secondaryText(for: .porcelain))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 340)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil)
                    .padding(.horizontal, 24)
                    .padding(.vertical, fillHeight ? 24 : 56)
                } else if filteredEntries.isEmpty && !showLive {
                    emptyFilterView(palette: palette, fillHeight: fillHeight)
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 11) {
                                ForEach(filteredEntries) { entry in
                                    switch entry.kind {
                                    case .meeting:
                                        meetingTimelineRow(entry: entry, palette: palette)
                                    case .command:
                                        commandBubble(time: entry.formattedTime, text: entry.text, palette: palette)
                                    case .reply:
                                        replyBubble(
                                            key: entry.id.uuidString,
                                            time: entry.formattedTime,
                                            text: entry.text,
                                            latency: entry.latencySeconds,
                                            platformName: platformName,
                                            palette: palette
                                        )
                                    }
                                }

                                if showLive && !liveHeard.isEmpty {
                                    commandBubble(time: "", text: liveHeard, palette: palette, isStreaming: true)
                                }
                                if showLive && !liveReply.isEmpty {
                                    replyBubble(
                                        key: "live-reply",
                                        time: "",
                                        text: liveReply,
                                        latency: nil,
                                        platformName: platformName,
                                        palette: palette,
                                        isStreaming: true
                                    )
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("transcript-bottom-anchor")
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : 460)
                        .frame(minHeight: fillHeight ? nil : 280)
                        .onChange(of: meet.liveVoice, initial: true) { _, _ in
                            if showLive {
                                scrollProxy.scrollTo("transcript-bottom-anchor", anchor: .bottom)
                            }
                        }
                        .onChange(of: entries.count) { _, _ in
                            if reduceMotion {
                                scrollProxy.scrollTo("transcript-bottom-anchor", anchor: .bottom)
                            } else {
                                withAnimation(.easeOut(duration: 0.22)) {
                                    scrollProxy.scrollTo("transcript-bottom-anchor", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil)

            // 3. Subtle Bottom Bar inside Right Card
            HStack(spacing: 10) {
                if !meet.currentMeetingLink.isEmpty {
                    HStack(spacing: 7) {
                        Image(systemName: "link")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)

                        Text(meet.currentMeetingLink)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text("·")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textTertiary)

                        Button {
                            copyMeetingLink()
                        } label: {
                            HStack(spacing: 4) {
                                if linkCopied {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                Text(linkCopied ? "Tersalin" : "Salin")
                            }
                        }
                        .buttonStyle(
                            NailPillButtonStyle(
                                variant: linkCopied ? .tinted(palette.good) : .secondary,
                                compact: true,
                                tone: .porcelain
                            )
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                } else {
                    Text("Sesi aktif")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: 8)

                Button {
                    openArchiveOrNotulen()
                } label: {
                    HStack(spacing: 4) {
                        Text(meet.currentNotulenURL != nil ? "Lihat Notulen" : "Buka Arsip")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true))
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(palette.cardSecondary.opacity(0.65))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background {
            NeuRaisedBackground(cornerRadius: 22, elevation: 1.0)
        }
    }

    private func transcriptSegmentedFilter(palette: NailPalette) -> some View {
        HStack(spacing: 2) {
            ForEach(TranscriptFeedFilter.allCases) { option in
                let isSelected = feedFilter == option

                Button {
                    if reduceMotion {
                        feedFilter = option
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            feedFilter = option
                        }
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .tracking(-0.12)
                        .foregroundStyle(
                            isSelected
                                ? palette.primaryText(for: .obsidian)
                                : palette.secondaryText(for: .porcelain)
                        )
                        .lineLimit(1)
                        .padding(.horizontal, 9.5)
                        .frame(height: 24)
                        .background {
                            if isSelected {
                                NeuRaisedBackground(isCapsule: true, elevation: 0.55, tone: .obsidian)
                                    .matchedGeometryEffect(id: "TranscriptFilterSegment", in: transcriptFilterNS)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(NeuTactileSegmentButtonStyle())
            }
        }
        .padding(3)
        .background {
            NeuInsetBackground(isCapsule: true, depth: 0.70, tone: .porcelain)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func emptyFilterView(palette: NailPalette, fillHeight: Bool) -> some View {
        VStack {
            NeuWell(padding: 22, cornerRadius: 16, tone: .porcelain) {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(palette.tertiaryText(for: .porcelain))
                    Text("Belum ada baris untuk filter \"\(feedFilter.label)\"")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(palette.secondaryText(for: .porcelain))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil)
        .padding(.vertical, fillHeight ? 24 : 54)
    }

    private func meetingTimelineRow(entry: TranscriptEntry, palette: NailPalette) -> some View {
        let speakerLabel = (entry.speaker?.isEmpty == false) ? entry.speaker! : "Peserta Rapat"

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 7) {
                Circle()
                    .fill(palette.textTertiary.opacity(0.65))
                    .frame(width: 6, height: 6)

                Text(speakerLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(palette.textPrimary)

                Spacer(minLength: 8)

                Text(entry.formattedTime)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }

            Text(entry.text)
                .font(.system(size: 13.5))
                .lineSpacing(1.5)
                .foregroundStyle(palette.isDark ? Color(hex: 0xD1D5DB) : Color(hex: 0x334155))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            NeuRaisedBackground(cornerRadius: 14, elevation: 0.55)
        }
    }

    private func commandBubble(time: String, text: String, palette: NailPalette, isStreaming: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 7) {
                Text("Kamu")
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(palette.textPrimary)

                Text("Perintah")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.gold)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background {
                        NeuRaisedBackground(
                            isCapsule: true,
                            elevation: 0.30,
                            tint: palette.goldBright,
                            tone: .porcelain
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                if !time.isEmpty {
                    Text(time)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                }
            }

            Group {
                if isStreaming {
                    LiveCommandText(text: text)
                } else {
                    Text(text)
                }
            }
                .font(.system(size: 13.5, weight: .semibold))
                .lineSpacing(1.5)
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            NeuRaisedBackground(cornerRadius: 14, elevation: 0.60, tint: palette.goldBright)
        }
    }

    private func replyBubble(
        key: String,
        time: String,
        text: String,
        latency: Double?,
        platformName: String,
        palette: NailPalette,
        isStreaming: Bool = false
    ) -> some View {
        let isCopied = copiedReplyKey == key
        let emeraldText = palette.isDark ? palette.good : Color(hex: 0x047857)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                NailOrbMark(size: 20, isActive: isStreaming)

                Text("Nail · Jawaban Suara")
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(emeraldText)
                    .lineLimit(1)

                if let latency {
                    Text(TranscriptEntry.formatLatency(latency))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(emeraldText)
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background {
                            NeuRaisedBackground(
                                isCapsule: true,
                                elevation: 0.30,
                                tint: palette.good,
                                tone: .porcelain
                            )
                        }
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 6)

                if !time.isEmpty {
                    Text(time)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                }

                Button {
                    copyReplyText(text, key: key)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(isCopied ? "Tersalin" : "Salin")
                    }
                }
                .buttonStyle(
                    NailPillButtonStyle(
                        variant: isCopied ? .tinted(palette.good) : .secondary,
                        compact: true,
                        tone: .porcelain
                    )
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(palette.good.opacity(0.14))
                .frame(height: 1)

            HStack(spacing: 8) {
                HStack(spacing: 5.5) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 10.5, weight: .medium))
                    Text(isStreaming
                        ? "Sedang disuarakan ke \(platformName)"
                        : "Disuarakan ke \(platformName) · \(activeVoiceDisplayLabel)")
                        .lineLimit(1)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(emeraldText)

                Spacer(minLength: 8)

                Text("Gaya: \(settings.speakingStyle.label)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            NeuRaisedBackground(cornerRadius: 16, elevation: 0.70, tint: palette.good)
        }
    }

    // MARK: - Helpers

    private func copyReplyText(_ text: String, key: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyReplyGeneration += 1
        let gen = copyReplyGeneration
        if reduceMotion {
            copiedReplyKey = key
        } else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                copiedReplyKey = key
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard copyReplyGeneration == gen else { return }
            if reduceMotion {
                copiedReplyKey = nil
            } else {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                    copiedReplyKey = nil
                }
            }
        }
    }

    private func copyMeetingLink() {
        guard !meet.currentMeetingLink.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(meet.currentMeetingLink, forType: .string)
        copyLinkGeneration += 1
        let gen = copyLinkGeneration
        if reduceMotion {
            linkCopied = true
        } else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                linkCopied = true
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard copyLinkGeneration == gen else { return }
            if reduceMotion {
                linkCopied = false
            } else {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                    linkCopied = false
                }
            }
        }
    }

    private func openArchiveOrNotulen() {
        if let activeNotulenURL = meet.currentNotulenURL {
            refreshNotulen()
            if let file = notulenFiles.first(where: { $0.url == activeNotulenURL }) {
                selectedNotulen = file
            }
        }
        selectSection(.notulen)
    }

    private func parseNotulenFilename(_ filename: String) -> (title: String, dateTime: String) {
        if let match = filename.wholeMatch(of: #/^(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})_(.+)$/#) {
            let datePart = String(match.1)
            let hour = String(match.2)
            let minute = String(match.3)
            let slug = String(match.4).replacingOccurrences(of: "-", with: " ")
            let cleanTitle = slug.isEmpty ? "Rapat" : slug
            let displayDate = (datePart == Self.todayDatePrefix()) ? "Hari ini" : datePart
            return (cleanTitle, "\(displayDate) · \(hour):\(minute)")
        }
        if let match = filename.wholeMatch(of: #/^(\d{4}-\d{2}-\d{2})$/#) {
            let datePart = String(match.1)
            return ("Notulen \(datePart)", datePart == Self.todayDatePrefix() ? "Hari ini" : datePart)
        }
        return (filename.replacingOccurrences(of: "-", with: " "), "Catatan Rapat")
    }

    private static let notulenDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func todayDatePrefix() -> String {
        notulenDateFormatter.string(from: Date())
    }

    private func joinMeet() {
        guard attendeesInformed else { return }
        meet.join(meetLink, title: meetingTitle, settings: settings)
    }

    private func refreshPrerequisites() {
        let model = settings.whisperModel
        Task.detached(priority: .utility) {
            let checked = PrerequisiteChecker.check(whisperModel: model)
            await MainActor.run { prerequisites = checked }
        }
    }

    private func refreshNotulen() {
        let activeURL = meet.currentNotulenURL
        Task.detached(priority: .utility) {
            let files = NotulenExporter.listFiles()
            await MainActor.run {
                notulenFiles = files
                if let current = selectedNotulen,
                   let updated = files.first(where: { $0.url == current.url }) {
                    selectedNotulen = updated
                } else if let activeURL,
                          let activeFile = files.first(where: { $0.url == activeURL }) {
                    selectedNotulen = activeFile
                } else {
                    selectedNotulen = files.first
                }
            }
        }
    }

    private func deleteNotulen(_ file: NotulenFile) {
        try? NotulenExporter.deleteFile(at: file.url)
        if selectedNotulen?.url == file.url {
            selectedNotulen = nil
        }
        refreshNotulen()
    }
}

// MARK: - Sidebar Live Pulse Dot

private struct LiveCommandText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleText = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .hidden()
                .accessibilityHidden(true)
            Text(reduceMotion ? text : visibleText)
                .accessibilityLabel(Text(text))
        }
        .task(id: reduceMotion ? nil : text) {
            guard !Task.isCancelled else { return }
            if reduceMotion {
                visibleText = text
                return
            }

            let sharedCount = zip(visibleText, text).prefix(while: { $0.0 == $0.1 }).count
            visibleText = String(text.prefix(sharedCount))
            let remaining = text.dropFirst(sharedCount)
            guard !remaining.isEmpty else { return }
            let interval = Duration.milliseconds(min(14, max(1, 480 / remaining.count)))

            for character in remaining {
                guard !Task.isCancelled else { return }
                visibleText.append(character)
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }
}

private struct SidebarLivePulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 11, height: 11)
                .scaleEffect(pulsing ? 1.35 : 0.85)
                .opacity(pulsing ? 0.15 : 0.65)

            Circle()
                .fill(color)
                .frame(width: 6.5, height: 6.5)
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
    }
}

// MARK: - Top Bar Minimal Icon Button

private struct TopBarIconButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let systemImage: String
    let palette: NailPalette
    let helpText: String
    var symbolRotationDegrees: Double = 0
    var bounceTrigger: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(
                    isHovered
                        ? palette.primaryText(for: .porcelain)
                        : palette.secondaryText(for: .porcelain)
                )
                .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                .symbolEffect(.bounce, value: bounceTrigger)
                .rotationEffect(.degrees(symbolRotationDegrees))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(NeuTactileCircleIconButtonStyle(tone: .porcelain, isHovered: isHovered))
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
        }
        .help(helpText)
    }
}

// MARK: - Tactile Neumorphic Button Styles

private struct NeuTactileSegmentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.74),
                value: configuration.isPressed
            )
    }
}

private struct NeuTactileCircleIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tone: NeuTone = .porcelain
    var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                NeuRaisedBackground(
                    isCapsule: true,
                    elevation: isHovered && !configuration.isPressed ? 0.60 : 0.42,
                    isPressed: configuration.isPressed,
                    tone: tone
                )
            }
            .scaleEffect(
                configuration.isPressed && !reduceMotion
                    ? 0.94
                    : (isHovered && !reduceMotion ? 1.04 : 1.0)
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.74),
                value: configuration.isPressed
            )
    }
}

private struct NeuTactilePillActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var cornerRadius: CGFloat = 12
    var isCapsule: Bool = false
    var tone: NeuTone = .porcelain
    var disabledTone: NeuTone? = nil
    var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let palette = NailPalette(scheme: colorScheme)
        let effectiveDisabledTone = disabledTone ?? tone
        let pressed = configuration.isPressed && isEnabled

        configuration.label
            .foregroundStyle(
                isEnabled
                    ? palette.primaryText(for: tone)
                    : palette.tertiaryText(for: effectiveDisabledTone)
            )
            .background {
                if isEnabled {
                    NeuRaisedBackground(
                        cornerRadius: cornerRadius,
                        isCapsule: isCapsule,
                        elevation: isHovered && !pressed ? 0.95 : 0.78,
                        isPressed: pressed,
                        tone: tone
                    )
                } else {
                    NeuInsetBackground(
                        cornerRadius: cornerRadius,
                        isCapsule: isCapsule,
                        depth: 0.75,
                        tone: effectiveDisabledTone
                    )
                }
            }
            .opacity(isEnabled ? (pressed ? 0.94 : 1.0) : 0.72)
            .scaleEffect(pressed && !reduceMotion ? 0.975 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.74),
                value: configuration.isPressed
            )
    }
}
