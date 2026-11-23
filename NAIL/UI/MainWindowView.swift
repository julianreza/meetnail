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
    @FocusState private var titleFieldFocused: Bool

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
                palette.canvas

                RadialGradient(
                    colors: [
                        palette.good.opacity(palette.isDark ? 0.055 : 0.032),
                        palette.good.opacity(0.0)
                    ],
                    center: UnitPoint(x: 0.5, y: 0.14),
                    startRadius: 0,
                    endRadius: 420
                )

                RadialGradient(
                    colors: [
                        (palette.isDark ? Color.white : Color(hex: 0x0F172A))
                            .opacity(palette.isDark ? 0.018 : 0.014),
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
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(palette.canvas.opacity(0.90))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.hairline)
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
                .fill(palette.hairline)
                .frame(width: 1, height: 16)

            HStack(spacing: 8) {
                NailOrbMark(size: 22, isActive: meet.active)

                Text("Meet Nail")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 76)
    }

    private func topBarNavTabs(palette: NailPalette) -> some View {
        HStack(spacing: 2) {
            ForEach(DesktopSection.allCases) { section in
                topBarNavTab(section: section, palette: palette)
            }
        }
        .padding(3)
        .background(
            palette.textPrimary.opacity(palette.isDark ? 0.07 : 0.045),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    palette.textPrimary.opacity(palette.isDark ? 0.06 : 0.04),
                    lineWidth: 1
                )
        }
    }

    private func topBarNavTab(section: DesktopSection, palette: NailPalette) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section
        let inactiveColor = palette.isDark ? palette.textSecondary : palette.textTertiary

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
                            ? palette.textPrimary
                            : (isHovered ? palette.textPrimary.opacity(0.85) : inactiveColor)
                    )
                    .lineLimit(1)

                topBarSectionBadge(for: section, isSelected: isSelected, palette: palette)
            }
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(palette.isDark ? Color(hex: 0x222736) : Color.white)
                        .shadow(
                            color: Color.black.opacity(palette.isDark ? 0.32 : 0.06),
                            radius: 2,
                            x: 0,
                            y: 1
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                .strokeBorder(
                                    palette.isDark
                                        ? Color.white.opacity(0.08)
                                        : Color(hex: 0x0F172A, alpha: 0.06),
                                    lineWidth: 0.5
                                )
                        }
                        .matchedGeometryEffect(id: "TopBarActiveSegment", in: sidebarNavNS)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(palette.textPrimary.opacity(palette.isDark ? 0.05 : 0.03))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 20)
                    .frame(height: 17)
                    .background(
                        palette.textPrimary.opacity(palette.isDark ? 0.12 : 0.065),
                        in: Capsule(style: .continuous)
                    )
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
                    .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
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
        .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
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
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 135, alignment: .leading)

            Text("·")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textTertiary)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(NailFormatting.formatElapsed(since: meet.sessionStartedAt, now: context.date))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(palette.card, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(palette.hairlineStrong, lineWidth: 1)
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
                .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true))
            } else if prerequisites.allReady {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(palette.good.opacity(0.18))
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
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(palette.goodSoft, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(palette.good.opacity(0.22), lineWidth: 1)
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
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(-0.12)
                            .foregroundStyle(palette.warn)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(palette.warnSoft, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(palette.warn.opacity(0.24), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
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
                        onDelete: deleteNotulen
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

    // MARK: - Centered Spotlight Idle Workspace (Option A)

    private func idleSpotlightStage(palette: NailPalette) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !prerequisites.allReady {
                            OnboardingBanner(
                                status: prerequisites,
                                onOpenSettings: { selectSection(.settings) },
                                onSignIn: { meet.signIn() },
                                onRefresh: { refreshPrerequisites() }
                            )
                            .padding(.bottom, 14)
                        }

                        if !sidebarCollapsed {
                            spotlightHeroHeader(palette: palette)
                                .padding(.bottom, 16)
                                .transition(.opacity)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            spotlightComposerCard(palette: palette)
                                .nailStaggeredEntrance(delay: 0.0)

                            spotlightConsentSection(palette: palette)
                                .padding(.top, 12)

                            spotlightRecentNotesStrip(palette: palette)
                                .padding(.top, 24)
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
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
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
        palette: NailPalette
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            NeuAcousticDial(
                size: dialSize,
                isActive: isAcousticActive,
                showYellowSpark: true
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

            if showStatusDot {
                Circle()
                    .fill(palette.good)
                    .frame(width: 13, height: 13)
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
        .frame(width: dialSize, height: dialSize)
        .matchedGeometryEffect(id: "NailHeroCharacter", in: meetingMorphNS)
    }

    private func spotlightHeroHeader(palette: NailPalette) -> some View {
        VStack(spacing: 0) {
            nailHeroAvatar(
                dialSize: 118,
                faceSize: 76,
                mood: .standby,
                isAcousticActive: false,
                phase: 0,
                speakingEnergy: 0,
                listeningEnergy: 0,
                showStatusDot: true,
                palette: palette
            )
            .padding(.bottom, 12)
            .accessibilityHidden(true)

            Text("Siap mendampingi rapatmu")
                .font(.system(size: 27, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 5)

            Text("\(NailFormatting.indonesianDateHeader()) · \(settings.provider.label) · \(activeVoiceDisplayLabel)")
                .font(.system(size: 13.5))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func spotlightComposerCard(palette: NailPalette) -> some View {
        let trimmedLink = meetLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedPlatform = MeetSession.detectPlatform(trimmedLink)
        let canJoin = !meet.active && !trimmedLink.isEmpty && attendeesInformed

        let leadingTileIcon = detectedPlatform != nil ? "video.fill" : "link"
        let leadingIconColor: Color = {
            switch detectedPlatform {
            case .googleMeet:
                return palette.good
            case .microsoftTeams:
                return palette.accent
            case nil:
                return linkFieldFocused ? palette.textPrimary : palette.textSecondary
            }
        }()
        let leadingTileFill: Color = {
            switch detectedPlatform {
            case .googleMeet:
                return palette.goodSoft
            case .microsoftTeams:
                return palette.accentSoft
            case nil:
                return palette.isDark ? palette.cardSecondary : Color(hex: 0xF4F6F9)
            }
        }()

        let containerBorderColor: Color = {
            if linkFieldFocused {
                if detectedPlatform == .googleMeet {
                    return palette.good.opacity(0.45)
                }
                if detectedPlatform == .microsoftTeams {
                    return palette.accent.opacity(0.42)
                }
                return palette.hairlineStrong
            }
            return palette.hairline
        }()

        let toolbarFill = palette.cardSecondary

        return VStack(spacing: 0) {
            // Top Zone: URL Input + Optional Title + Inline Errors
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(leadingTileFill)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(palette.hairline, lineWidth: 1)
                            }

                        Image(systemName: leadingTileIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(leadingIconColor)
                    }
                    .frame(width: 28, height: 28)

                    TextField("Tempel link Google Meet atau Microsoft Teams", text: $meetLink)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                        .focused($linkFieldFocused)
                        .disabled(meet.active)
                        .onSubmit { joinMeet() }

                    HStack(spacing: 8) {
                        if let detectedPlatform {
                            let isMeet = detectedPlatform == .googleMeet
                            HStack(spacing: 5.5) {
                                Image(systemName: "video")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(isMeet ? "Google Meet" : "MS Teams")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .tracking(-0.12)
                            }
                            .foregroundStyle(
                                isMeet
                                    ? (palette.isDark ? palette.good : Color(hex: 0x047857))
                                    : palette.textPrimary
                            )
                            .padding(.horizontal, 9.5)
                            .frame(height: 26)
                            .background(
                                isMeet ? palette.goodSoft : palette.cardSecondary,
                                in: Capsule(style: .continuous)
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        isMeet ? palette.good.opacity(0.24) : palette.hairlineStrong,
                                        lineWidth: 1
                                    )
                            }
                            .transition(.scale.combined(with: .opacity))
                        }

                        if !meetLink.isEmpty {
                            Button {
                                meetLink = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(palette.textTertiary)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        palette.textPrimary.opacity(palette.isDark ? 0.08 : 0.045),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Bersihkan link")
                            .accessibilityLabel("Bersihkan link rapat")
                        }

                        Button {
                            if let pasted = NSPasteboard.general.string(forType: .string) {
                                meetLink = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Tempel")
                                    .font(.system(size: 12, weight: .medium))
                                    .tracking(-0.12)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(pasteHovered ? palette.textPrimary : palette.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(pasteHovered ? palette.cardSecondary : palette.card)
                                    .shadow(
                                        color: Color.black.opacity(palette.isDark ? 0.22 : 0.03),
                                        radius: 1.5,
                                        x: 0,
                                        y: 1
                                    )
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(palette.hairlineStrong, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                        .onHover { pasteHovered = $0 }
                        .help("Tempel link rapat dari papan klip")
                    }
                }
                .frame(minHeight: 36)

                // Optional Title Line
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(palette.hairline.opacity(0.6))
                        .frame(height: 1)
                        .padding(.bottom, 9)

                    HStack(spacing: 8) {
                        Image(systemName: meetingTitle.isEmpty ? "plus" : "tag")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(titleFieldFocused ? palette.textPrimary : palette.textTertiary)
                            .frame(width: 14)

                        TextField("Tambah judul rapat (opsional)", text: $meetingTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.textPrimary)
                            .focused($titleFieldFocused)

                        if !meetingTitle.isEmpty {
                            Button {
                                meetingTitle = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(palette.textTertiary)
                                    .frame(width: 20, height: 20)
                                    .background(
                                        palette.textPrimary.opacity(palette.isDark ? 0.08 : 0.045),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Bersihkan judul")
                        }
                    }
                }
                .padding(.leading, 40)

                if !meet.status.isEmpty && meet.visualState == .error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.caption)
                            .foregroundStyle(palette.bad)
                        Text(meet.status)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8.5)
                    .background(palette.badSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.bad.opacity(0.32), lineWidth: 1)
                    }
                }

                if !meet.notulenError.isEmpty {
                    notulenErrorBanner(palette: palette, onInk: false)
                }
            }
            .padding(.init(top: 18, leading: 20, bottom: 14, trailing: 20))
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82),
                value: detectedPlatform != nil
            )

            // Integrated Bottom Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    listeningModeMenuPill(palette: palette)
                    speakingStyleMenuPill(palette: palette)

                    Button {
                        HUDPanel.shared.triggerSpeakingPreview()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.good)

                            Text("Uji HUD")
                                .font(.system(size: 12.5, weight: .medium))
                                .tracking(-0.12)
                                .lineLimit(1)
                                .foregroundStyle(hudPreviewHovered ? palette.textPrimary : palette.textSecondary)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(
                            palette.textPrimary.opacity(
                                hudPreviewHovered
                                    ? (palette.isDark ? 0.09 : 0.065)
                                    : (palette.isDark ? 0.055 : 0.04)
                            ),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    palette.textPrimary.opacity(palette.isDark ? 0.08 : 0.05),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .onHover { hudPreviewHovered = $0 }
                    .help("Putar pratinjau HUD mengambang")
                }

                Spacer(minLength: 8)

                Button {
                    joinMeet()
                } label: {
                    HStack(spacing: 7) {
                        Text("Gabung Rapat")
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.15)
                    .foregroundStyle(
                        canJoin
                            ? (palette.isDark ? Color(hex: 0x111113) : Color.white)
                            : palette.textTertiary
                    )
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background {
                        if canJoin {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    palette.isDark
                                        ? (joinHovered ? Color.white : Color(hex: 0xF8FAFC))
                                        : (joinHovered ? Color(hex: 0x1F2024) : Color(hex: 0x111113))
                                )
                                .shadow(
                                    color: Color.black.opacity(palette.isDark ? 0.36 : 0.18),
                                    radius: 6,
                                    x: 0,
                                    y: 3
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            Color.white.opacity(palette.isDark ? 0.35 : 0.12),
                                            lineWidth: 1
                                        )
                                }
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.isDark ? Color(hex: 0x222736) : Color(hex: 0xE2E8F0))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(palette.hairline, lineWidth: 1)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!canJoin)
                .onHover { joinHovered = $0 }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(toolbarFill)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.card)
                .shadow(
                    color: Color.black.opacity(palette.isDark ? 0.36 : 0.05),
                    radius: 12,
                    x: 0,
                    y: 5
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(containerBorderColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func listeningModeMenuPill(palette: NailPalette, fillWidth: Bool = false) -> some View {
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
                    .foregroundStyle(palette.textSecondary)

                Text(settings.listeningMode.shortLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                if fillWidth {
                    Spacer(minLength: 4)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, fillWidth ? 12 : 11)
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
            .frame(height: fillWidth ? 36 : 32)
            .background {
                RoundedRectangle(cornerRadius: fillWidth ? 10 : 9, style: .continuous)
                    .fill(palette.card)
                    .shadow(
                        color: Color.black.opacity(palette.isDark ? 0.22 : 0.03),
                        radius: 2,
                        x: 0,
                        y: 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: fillWidth ? 10 : 9, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: fillWidth ? 10 : 9, style: .continuous))
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

    private func speakingStyleMenuPill(palette: NailPalette, fillWidth: Bool = false) -> some View {
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
                    .foregroundStyle(palette.textSecondary)

                Text("Gaya:")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.textSecondary)

                Text(settings.speakingStyle.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                if fillWidth {
                    Spacer(minLength: 4)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, fillWidth ? 12 : 11)
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
            .frame(height: fillWidth ? 36 : 32)
            .background {
                RoundedRectangle(cornerRadius: fillWidth ? 10 : 9, style: .continuous)
                    .fill(palette.card)
                    .shadow(
                        color: Color.black.opacity(palette.isDark ? 0.22 : 0.03),
                        radius: 2,
                        x: 0,
                        y: 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: fillWidth ? 10 : 9, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: fillWidth ? 10 : 9, style: .continuous))
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

    private func spotlightConsentSection(palette: NailPalette) -> some View {
        let trimmedLink = meetLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedPlatform = MeetSession.detectPlatform(trimmedLink)
        let needsAttention = !trimmedLink.isEmpty && !attendeesInformed

        let barFill: Color = palette.card.opacity(palette.isDark ? 0.78 : 0.78)
        let barBorder: Color = {
            if attendeesInformed {
                return palette.hairline
            }
            return needsAttention ? palette.goldBorder : palette.hairline
        }()

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if reduceMotion {
                    attendeesInformed.toggle()
                } else {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                        attendeesInformed.toggle()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(attendeesInformed ? palette.good : palette.card)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(
                                        attendeesInformed
                                            ? palette.good
                                            : (needsAttention ? palette.goldBright : palette.hairlineStrong),
                                        lineWidth: 1.5
                                    )
                            }

                        if attendeesInformed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Color.white)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 17, height: 17)
                    .shadow(
                        color: attendeesInformed ? palette.good.opacity(0.24) : Color.clear,
                        radius: 2,
                        x: 0,
                        y: 1
                    )

                    Text("Peserta sudah diberi tahu audio dikirim ke \(settings.provider.recipient)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text(attendeesInformed ? "Disetujui" : (needsAttention ? "Wajib dicentang" : "Wajib"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            attendeesInformed
                                ? (palette.isDark ? palette.good : Color(hex: 0x047857))
                                : palette.warn
                        )
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(
                            attendeesInformed ? palette.goodSoft : palette.warnSoft,
                            in: Capsule(style: .continuous)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    attendeesInformed
                                        ? palette.good.opacity(0.22)
                                        : palette.warn.opacity(0.24),
                                    lineWidth: 1
                                )
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(barFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(barBorder, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(attendeesInformed ? "Dicentang" : "Belum dicentang")

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
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(palette.cardSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.hairline, lineWidth: 1)
                }
            }
        }
    }

    private func spotlightRecentNotesStrip(palette: NailPalette) -> some View {
        let recentFiles = Array(notulenFiles.prefix(3))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("NOTULEN TERAKHIR")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)

                Spacer()

                Button {
                    selectSection(.notulen)
                } label: {
                    HStack(spacing: 4) {
                        Text("Lihat Semua")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            if recentFiles.isEmpty {
                LazyVGrid(columns: columns, spacing: 12) {
                    SpotlightQuickGuideCard(
                        number: "01",
                        title: "Tempel link",
                        subtitle: "Google Meet / Teams",
                        palette: palette
                    )
                    SpotlightQuickGuideCard(
                        number: "02",
                        title: "Centang izin",
                        subtitle: "Konfirmasi peserta",
                        palette: palette
                    )
                    SpotlightQuickGuideCard(
                        number: "03",
                        title: "Panggil \"Nail\"",
                        subtitle: "Atau Dengar & Jawab",
                        palette: palette
                    )
                }
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(recentFiles) { file in
                        let parsed = parseNotulenFilename(file.name)
                        SpotlightRecentNoteCard(
                            title: parsed.title,
                            dateTime: parsed.dateTime,
                            palette: palette
                        ) {
                            selectedNotulen = file
                            selectSection(.notulen)
                        }
                    }
                }
            }
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
                        .foregroundStyle(palette.textSecondary)
                }

                Text("·")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.textTertiary)

                HStack(spacing: 6) {
                    Text("\"Nail\"")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.gold)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(palette.goldSoft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(palette.goldBorder, lineWidth: 1)
                        }

                    Text("Kata Panggil")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                }

                Text("·")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.textTertiary)

                HStack(spacing: 6) {
                    HStack(spacing: 2.5) {
                        footerKeycap("⌘", palette: palette)
                        footerKeycap("\\", palette: palette)
                    }
                    Text("Mode Ringkas")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
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
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 265, alignment: .leading)
                        }

                        Button {
                            copyMeetingLink()
                        } label: {
                            Text(linkCopied ? "Tersalin" : "Salin")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(
                                    linkCopied
                                        ? (palette.isDark ? palette.good : Color(hex: 0x047857))
                                        : palette.textSecondary
                                )
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(palette.card, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                        .strokeBorder(
                                            linkCopied ? palette.good.opacity(0.35) : palette.hairlineStrong,
                                            lineWidth: 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)

                        Text("·")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                    } else {
                        Circle()
                            .fill(palette.good.opacity(0.85))
                            .frame(width: 6, height: 6)

                        Text(footerProviderLabel)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.textSecondary)

                        Text("·")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(palette.textTertiary)

                        Text(footerModelSummary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)

                        Text("·")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                    }

                    Button {
                        openArchiveOrNotulen()
                    } label: {
                        HStack(spacing: 3) {
                            Text("Buka Arsip")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                HStack(spacing: 7) {
                    Circle()
                        .fill(palette.good.opacity(0.85))
                        .frame(width: 6, height: 6)

                    Text(footerProviderLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.textSecondary)

                    Text("·")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(palette.textTertiary)

                    Text(footerModelSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(palette.textTertiary)

                    Button {
                        selectSection(.settings)
                    } label: {
                        HStack(spacing: 3) {
                            Text("Ubah")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(palette.canvas.opacity(0.94))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
        }
    }

    private func footerKeycap(_ label: String, palette: NailPalette) -> some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 19)
            .frame(height: 19)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(palette.card)
                    .shadow(
                        color: Color.black.opacity(palette.isDark ? 0.25 : 0.05),
                        radius: 0.5,
                        x: 0,
                        y: 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(palette.hairlineStrong, lineWidth: 1)
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
                            .foregroundStyle(stateTone.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(stateTone.bg, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(stateTone.border, lineWidth: 1)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)

                        Text(activeVoiceDisplayLabel)
                            .font(.system(size: 12, weight: .medium))
                            .tracking(-0.12)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(palette.cardSecondary, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(palette.hairline, lineWidth: 1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 10)

                // 2. Hero Nail Stage + 9-Bar Reactive Waveform + Clean Sans Headline
                VStack(spacing: 0) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isAcousticActive)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let phaseSpeed = 1.6 + speakingEnergy * 1.4 + listeningEnergy * 0.6
                        let currentPhase = (reduceMotion || !isAcousticActive) ? 0.0 : (t * phaseSpeed)

                        VStack(spacing: 12) {
                            nailHeroAvatar(
                                dialSize: 174,
                                faceSize: 104,
                                mood: activeBotMood,
                                isAcousticActive: isAcousticActive,
                                phase: currentPhase,
                                speakingEnergy: speakingEnergy,
                                listeningEnergy: listeningEnergy,
                                showStatusDot: false,
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
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .padding(.top, 12)

                    Text(!meet.status.isEmpty ? meet.status : "Panggil \"Nail\" kapan saja di \(platformName)")
                        .font(.system(size: 13))
                        .foregroundStyle(meet.visualState == .error ? palette.bad : palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.top, 4)
                }

                Spacer(minLength: 12)

                // 3. Clean Action Cluster
                VStack(spacing: 10) {
                    Button {
                        meet.answerMeeting()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(canListen ? palette.good : palette.textTertiary)
                                .symbolEffect(
                                    .variableColor.iterative.reversing,
                                    isActive: meet.voiceBusy || meet.isSpeaking
                                )

                            Text("Dengar & Jawab")
                                .font(.system(size: 13.5, weight: .semibold))
                                .tracking(-0.15)
                                .lineLimit(1)
                        }
                        .foregroundStyle(
                            canListen
                                ? (palette.isDark ? Color(hex: 0x111113) : Color.white)
                                : palette.textTertiary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if canListen {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        palette.isDark
                                            ? (listenHovered ? Color.white : Color(hex: 0xF8FAFC))
                                            : (listenHovered ? Color(hex: 0x1F2024) : Color(hex: 0x111113))
                                    )
                                    .shadow(
                                        color: Color.black.opacity(palette.isDark ? 0.34 : 0.16),
                                        radius: 8,
                                        x: 0,
                                        y: 4
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(
                                                Color.white.opacity(palette.isDark ? 0.35 : 0.12),
                                                lineWidth: 1
                                            )
                                    }
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(palette.isDark ? Color(hex: 0x222736) : Color(hex: 0xE2E8F0))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(palette.hairline, lineWidth: 1)
                                    }
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canListen)
                    .onHover { listenHovered = $0 }

                    HStack(spacing: 10) {
                        listeningModeMenuPill(palette: palette, fillWidth: true)
                        speakingStyleMenuPill(palette: palette, fillWidth: true)
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
                    Button {
                        HUDPanel.shared.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Text("HUD Melayang")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)

                            sculptedNeuSwitch(isOn: hudVisible, palette: palette)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(hudVisible ? "Sembunyikan HUD" : "Tampilkan HUD")

                    Button {
                        HUDPanel.shared.triggerSpeakingPreview()
                    } label: {
                        Text("Uji")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 9.5)
                            .frame(height: 25)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(palette.hairlineStrong, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
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
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(-0.12)
                            .lineLimit(1)

                        Text("⌘⇧M")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .frame(height: 18)
                            .background(
                                palette.bad.opacity(palette.isDark ? 0.18 : 0.09),
                                in: RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            )
                    }
                    .foregroundStyle(palette.bad)
                    .padding(.horizontal, 10.5)
                    .frame(height: 30)
                    .background(palette.badSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(palette.bad.opacity(0.22), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Potong suara Nail segera (⌘⇧M)")
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(palette.cardSecondary)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
            }
        }
        .background(alignment: .top) {
            RadialGradient(
                colors: [
                    palette.good.opacity(palette.isDark ? 0.09 : 0.065),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.06),
                startRadius: 0,
                endRadius: 290
            )
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.card)
                .shadow(
                    color: palette.cardShadow,
                    radius: 14,
                    x: 0,
                    y: 6
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
                .allowsHitTesting(false)
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

    private func sculptedNeuSwitch(isOn: Bool, palette: NailPalette) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(
                    isOn
                        ? palette.good
                        : palette.textPrimary.opacity(palette.isDark ? 0.16 : 0.12)
                )
                .frame(width: 36, height: 20)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isOn ? palette.good.opacity(0.25) : palette.hairlineStrong,
                            lineWidth: 1
                        )
                }

            Circle()
                .fill(Color.white)
                .frame(width: 15, height: 15)
                .shadow(
                    color: Color.black.opacity(palette.isDark ? 0.35 : 0.20),
                    radius: 2,
                    x: 0,
                    y: 1
                )
                .padding(.horizontal, 2.5)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78),
            value: isOn
        )
    }

    private func notulenErrorBanner(palette: NailPalette, onInk: Bool) -> some View {
        let warnColor = onInk ? Color(hex: 0xE0B05C) : palette.warn
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(warnColor)
            Text(meet.notulenError)
                .font(.caption.weight(.medium))
                .foregroundStyle(onInk ? palette.inkCardText : palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            warnColor.opacity(onInk ? 0.16 : 0.12),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(warnColor.opacity(0.34), lineWidth: 1)
        }
    }

    // MARK: - Right Column (54%): Airy Live Conversation Feed Card

    private func liveTranscriptCard(fillHeight: Bool, palette: NailPalette) -> some View {
        let entries = meet.transcriptStore.entries
        let filteredEntries = entries.filter { feedFilter.matches($0) }
        let hasFallback = entries.isEmpty && (!meet.voiceTranscript.isEmpty || !meet.voiceReply.isEmpty)
        let totalCount = totalTranscriptCount
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
                        .padding(.horizontal, 7.5)
                        .frame(height: 21)
                        .background(
                            palette.textPrimary.opacity(palette.isDark ? 0.08 : 0.05),
                            in: Capsule(style: .continuous)
                        )
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
                    .padding(.horizontal, 7.5)
                    .frame(height: 21)
                    .background(
                        isGoogleMeet ? palette.goodSoft : palette.cardSecondary,
                        in: Capsule(style: .continuous)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isGoogleMeet ? palette.good.opacity(0.22) : palette.hairlineStrong,
                                lineWidth: 1
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
                    notulenErrorBanner(palette: palette, onInk: false)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }

                if entries.isEmpty && !hasFallback {
                    VStack(spacing: 12) {
                        NailOrbMark(size: 46, isActive: meet.active)
                            .opacity(0.90)

                        Text("Menunggu Percakapan Rapat")
                            .font(.system(size: 15.5, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(palette.textPrimary)

                        Text(
                            settings.listeningMode == .notulen
                                ? "Transkrip peserta dan tanya jawab Nail akan muncul secara real-time di sini."
                                : "Mode Siaga aktif. Panggil \"Nail\" atau tekan Dengar & Jawab untuk memulai tanya jawab."
                        )
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    }
                    .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil)
                    .padding(.horizontal, 24)
                    .padding(.vertical, fillHeight ? 24 : 56)
                } else if hasFallback {
                    if feedFilter == .meeting {
                        emptyFilterView(palette: palette, fillHeight: fillHeight)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 11) {
                                if !meet.voiceTranscript.isEmpty {
                                    commandBubble(
                                        time: meet.lastHeardAt.map { TranscriptEntry.formatTime($0) } ?? "",
                                        text: meet.voiceTranscript,
                                        palette: palette
                                    )
                                }
                                if !meet.voiceReply.isEmpty {
                                    replyBubble(
                                        key: "fallback-reply",
                                        time: meet.lastReplyAt.map { TranscriptEntry.formatTime($0) } ?? "",
                                        text: meet.voiceReply,
                                        latency: meet.lastLatencySeconds,
                                        platformName: platformName,
                                        palette: palette
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : 460)
                        .frame(minHeight: fillHeight ? nil : 260)
                    }
                } else if filteredEntries.isEmpty {
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

                                Color.clear
                                    .frame(height: 1)
                                    .id("transcript-bottom-anchor")
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : 460)
                        .frame(minHeight: fillHeight ? nil : 280)
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
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundStyle(
                                linkCopied
                                    ? (palette.isDark ? palette.good : Color(hex: 0x047857))
                                    : palette.textSecondary
                            )
                            .padding(.horizontal, 8.5)
                            .frame(height: 24)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .strokeBorder(
                                        linkCopied ? palette.good.opacity(0.35) : palette.hairline,
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
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
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(palette.cardSecondary)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.card)
                .shadow(
                    color: palette.cardShadow,
                    radius: 14,
                    x: 0,
                    y: 6
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
                .allowsHitTesting(false)
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
                        .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8.5)
                        .frame(height: 24)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .fill(palette.isDark ? Color(hex: 0x222736) : Color.white)
                                    .shadow(
                                        color: Color.black.opacity(palette.isDark ? 0.28 : 0.055),
                                        radius: 2,
                                        x: 0,
                                        y: 1
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                            .strokeBorder(
                                                palette.isDark
                                                    ? Color.white.opacity(0.08)
                                                    : Color(hex: 0x0F172A, alpha: 0.05),
                                                lineWidth: 0.5
                                            )
                                    }
                                    .matchedGeometryEffect(id: "TranscriptFilterSegment", in: transcriptFilterNS)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background(
            palette.textPrimary.opacity(palette.isDark ? 0.07 : 0.045),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    palette.textPrimary.opacity(palette.isDark ? 0.06 : 0.04),
                    lineWidth: 1
                )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func emptyFilterView(palette: NailPalette, fillHeight: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
                .foregroundStyle(palette.textTertiary)
            Text("Belum ada baris untuk filter \"\(feedFilter.label)\"")
                .font(.callout.weight(.medium))
                .foregroundStyle(palette.textSecondary)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.isDark ? Color(hex: 0x1B1F2B) : palette.card)
                .shadow(
                    color: Color.black.opacity(palette.isDark ? 0.20 : 0.02),
                    radius: 2,
                    x: 0,
                    y: 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
        }
    }

    private func commandBubble(time: String, text: String, palette: NailPalette) -> some View {
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
                    .background(palette.goldSoft, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(palette.goldBorder, lineWidth: 1)
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

            Text(text)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.goldSoft.opacity(0.55))
                }
                .shadow(
                    color: Color.black.opacity(palette.isDark ? 0.18 : 0.02),
                    radius: 2,
                    x: 0,
                    y: 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.goldBorder.opacity(0.6), lineWidth: 1)
        }
    }

    private func replyBubble(
        key: String,
        time: String,
        text: String,
        latency: Double?,
        platformName: String,
        palette: NailPalette
    ) -> some View {
        let isCopied = copiedReplyKey == key
        let emeraldText = palette.isDark ? palette.good : Color(hex: 0x047857)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                NailOrbMark(size: 20, isActive: false)

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
                        .background(palette.goodSoft, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(palette.good.opacity(0.22), lineWidth: 1)
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
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? emeraldText : palette.textSecondary)
                    .padding(.horizontal, 8.5)
                    .frame(height: 24)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isCopied ? palette.good.opacity(0.35) : palette.hairlineStrong,
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
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
                    Text("Disuarakan ke \(platformName) · \(activeVoiceDisplayLabel)")
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.goodSoft.opacity(palette.isDark ? 0.45 : 0.65),
                                    palette.goodSoft.opacity(palette.isDark ? 0.14 : 0.18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .shadow(
                    color: palette.good.opacity(palette.isDark ? 0.14 : 0.09),
                    radius: 10,
                    x: 0,
                    y: 4
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.good.opacity(0.28), lineWidth: 1.2)
        }
    }

    // MARK: - Helpers

    private var totalTranscriptCount: Int {
        let entries = meet.transcriptStore.entries
        if entries.isEmpty {
            return (meet.voiceTranscript.isEmpty ? 0 : 1) + (meet.voiceReply.isEmpty ? 0 : 1)
        }
        return entries.count
    }

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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovered ? palette.textPrimary : palette.textSecondary)
                .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                .symbolEffect(.bounce, value: bounceTrigger)
                .rotationEffect(.degrees(symbolRotationDegrees))
                .frame(width: 28, height: 28)
                .background(
                    isHovered
                        ? palette.textPrimary.opacity(palette.isDark ? 0.08 : 0.04)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isHovered ? palette.hairline : Color.clear,
                            lineWidth: 1
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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

// MARK: - Spotlight Recent Note & Quick Guide Cards

private struct SpotlightRecentNoteCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let title: String
    let dateTime: String
    let palette: NailPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.isDark ? palette.cardSecondary : Color(hex: 0xF8FAFC))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(palette.hairline, lineWidth: 1)
                        }

                    Image(systemName: "doc.text")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2.5) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    Text(dateTime)
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isHovered
                            ? palette.textSecondary
                            : palette.textTertiary.opacity(0.70)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.card)
                    .shadow(
                        color: Color.black.opacity(isHovered ? (palette.isDark ? 0.34 : 0.055) : (palette.isDark ? 0.20 : 0.025)),
                        radius: isHovered ? 8 : 2,
                        x: 0,
                        y: isHovered ? 3 : 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isHovered ? palette.hairlineStrong : palette.hairline,
                        lineWidth: 1
                    )
            }
            .scaleEffect(isHovered && !reduceMotion ? 1.008 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                    isHovered = hovering
                }
            }
        }
    }
}

private struct SpotlightQuickGuideCard: View {
    let number: String
    let title: String
    let subtitle: String
    let palette: NailPalette

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.isDark ? palette.cardSecondary : Color(hex: 0xF8FAFC))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(palette.hairline, lineWidth: 1)
                    }

                Text(number)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.card)
                .shadow(
                    color: Color.black.opacity(palette.isDark ? 0.20 : 0.025),
                    radius: 2,
                    x: 0,
                    y: 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
        }
    }
}
