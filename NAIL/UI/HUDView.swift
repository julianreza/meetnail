import AppKit
import SwiftUI

private struct HUDMorphShape: Shape {
    var topFlare: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(topFlare, AnimatablePair(topRadius, bottomRadius))
        }
        set {
            topFlare = newValue.first
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width > 1, rect.height > 1 else {
            return Path(rect)
        }
        if topRadius > 0.5 && topFlare < 0.5 {
            let corner = min(bottomRadius, rect.width * 0.5, rect.height * 0.5)
            return RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: rect)
        }
        let t = min(max(0, topFlare), rect.width * 0.25, rect.height * 0.35)
        let b = min(max(4, bottomRadius), max(4, (rect.width - 2 * t) * 0.5), max(4, rect.height - t))
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
        path.addLine(to: CGPoint(x: t, y: rect.height - b))
        path.addQuadCurve(to: CGPoint(x: t + b, y: rect.height), control: CGPoint(x: t, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width - t - b, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: rect.width - t, y: rect.height - b), control: CGPoint(x: rect.width - t, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width - t, y: t))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.width - t, y: 0))
        path.closeSubpath()
        return path
    }
}

struct HUDView: View {
    private let meet = MeetSession.shared
    private let settings = VoiceSettings.shared
    var metrics: NotchMetrics
    var onDisplayModeChange: (HUDDisplayMode) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false
    @State private var hoverIntent = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var isPinned = false
    @State private var recentReplyVisible = false
    @State private var replyHideTask: Task<Void, Never>?

    // MARK: - Design #27 Obsidian Monochrome + Subtle Touch of Yellow Tokens

    private let obsidianSurface = Color(hex: 0x0A0A0A)
    private let recessedSurface = Color(hex: 0x13161C)
    private let alabasterInk = Color(hex: 0xF5F5F5)
    private let mutedInk = Color(hex: 0x9CA3AF)
    private let dangerInk = Color(hex: 0xF08A80)
    private let goldBright = Color(hex: 0xEAB308)
    private let goldWarm = Color(hex: 0xF2C94C)

    var body: some View {
        let mode = metrics.displayMode
        let isFloating = settings.hudLayoutStyle == .floatingPill
        let isExpanded = (mode != .collapsed)
        let shellWidth = cardWidth(for: mode)
        let shellHeight = cardHeight(for: mode)
        let morphShape = hudMorphShape(isFloating: isFloating, mode: mode)
        let shellSpring: Animation? = reduceMotion
            ? nil
            : (isExpanded
                ? .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.12)
                : .spring(response: 0.32, dampingFraction: 0.88, blendDuration: 0.08))

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                collapsedStealthWings(isFloating: isFloating)
                    .frame(width: cardWidth(for: .collapsed), height: cardHeight(for: .collapsed))
                    .opacity(mode == .collapsed ? 1 : 0)
                    .blur(radius: (!reduceMotion && mode != .collapsed) ? 3.5 : 0)
                    .scaleEffect((!reduceMotion && mode != .collapsed) ? 0.94 : 1.0, anchor: .top)
                    .allowsHitTesting(mode == .collapsed)
                    .animation(reduceMotion ? nil : .easeOut(duration: mode == .collapsed ? 0.22 : 0.12), value: mode)

                if mode == .liveActivity {
                    liveActivityBody(isFloating: isFloating)
                        .frame(width: cardWidth(for: .liveActivity), height: cardHeight(for: .liveActivity), alignment: .top)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(scale: 0.95, anchor: .top))
                                    .combined(with: .offset(y: -4)),
                                removal: .opacity
                                    .combined(with: .scale(scale: 0.97, anchor: .top))
                            )
                        )
                }

                if mode == .commandTray {
                    commandTrayBody(isFloating: isFloating)
                        .frame(width: cardWidth(for: .commandTray), height: cardHeight(for: .commandTray), alignment: .top)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(scale: 0.95, anchor: .top))
                                    .combined(with: .offset(y: -4)),
                                removal: .opacity
                                    .combined(with: .scale(scale: 0.97, anchor: .top))
                            )
                        )
                }
            }
            .frame(width: shellWidth, height: shellHeight, alignment: .top)
            .background {
                hudBackdrop(shape: morphShape, isFloating: isFloating, mode: mode)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                handleHover(hovering)
            }
            .padding(.top, isFloating ? 1 : 0)
            .animation(shellSpring, value: mode)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84), value: shellWidth)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84), value: shellHeight)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84), value: isFloating)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: botMood)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, settings.appAppearance.colorScheme ?? colorScheme)
        .onAppear {
            syncVoiceTargets()
            if desiredDisplayMode != metrics.displayMode {
                onDisplayModeChange(desiredDisplayMode)
            }
        }
        .onChange(of: effectiveSpeaking) { _, _ in
            syncVoiceTargets()
        }
        .onChange(of: effectiveListening) { _, _ in
            syncVoiceTargets()
        }
        .onChange(of: botMood) { _, _ in
            syncVoiceTargets()
        }
        .onChange(of: metrics.previewStage) { _, _ in
            syncVoiceTargets()
        }
        .onChange(of: metrics.isVisible) { _, visible in
            if visible && !reduceMotion {
                syncVoiceTargets()
            } else {
                metrics.stopAnimations()
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                metrics.stopAnimations()
            } else if metrics.isVisible {
                syncVoiceTargets()
            }
        }
        .onChange(of: desiredDisplayMode) { _, newMode in
            onDisplayModeChange(newMode)
        }
        .onChange(of: settings.hudExpandOnHover) { _, enabled in
            if !enabled {
                hoverTask?.cancel()
                hoverIntent = false
            }
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
        .onChange(of: meet.active) { _, _ in
            HUDPanel.shared.scheduleRefreshLayout()
        }
        .onChange(of: meet.voiceReply) { _, reply in
            replyHideTask?.cancel()
            guard !reply.isEmpty else {
                recentReplyVisible = false
                return
            }
            recentReplyVisible = true
            let holdSeconds = settings.hudReplyHoldSeconds
            replyHideTask = Task {
                try? await Task.sleep(for: .seconds(holdSeconds))
                guard !Task.isCancelled else { return }
                recentReplyVisible = false
            }
        }
    }

    private func syncVoiceTargets() {
        metrics.updateVoiceTargets(
            speaking: metrics.isVisible && !reduceMotion && effectiveSpeaking,
            listening: metrics.isVisible && !reduceMotion && (effectiveListening || botMood == .processing)
        )
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        hoverTask?.cancel()
        if hovering {
            guard settings.hudExpandOnHover else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                hoverIntent = true
            }
        } else {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                while HUDPanel.shared.isMouseInsideVisibleHUD() {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                }
                guard !Task.isCancelled else { return }
                isHovering = false
                hoverIntent = false
            }
        }
    }

    // MARK: - Shape & Backdrop (H4 Boxless Active Modes)

    private func hudMorphShape(isFloating: Bool, mode: HUDDisplayMode) -> HUDMorphShape {
        if isFloating {
            let radius: CGFloat = mode == .collapsed ? 18 : 22
            return HUDMorphShape(topFlare: 0, topRadius: radius, bottomRadius: radius)
        }
        let topFlare: CGFloat = mode == .collapsed ? 8 : 14
        let bottomRadius: CGFloat = mode == .collapsed ? 12 : 20
        return HUDMorphShape(topFlare: topFlare, topRadius: 0, bottomRadius: bottomRadius)
    }

    @ViewBuilder
    private func hudBackdrop(shape: HUDMorphShape, isFloating: Bool, mode: HUDDisplayMode) -> some View {
        if mode == .collapsed && (isFloating || !metrics.hasHardwareNotch) {
            ZStack {
                shape
                    .fill(obsidianSurface.opacity(settings.hudOpacity))
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.015),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                shape
                    .stroke(
                        Color.white.opacity(0.12),
                        lineWidth: 1.0
                    )
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Layout 1: Collapsed — Ultra-Minimal Eyes-Only Stealth Peek

    @ViewBuilder
    private func collapsedStealthWings(isFloating: Bool) -> some View {
        let rowHeight: CGFloat = isFloating ? 36 : metrics.notchHeight
        let miniSize = CGSize(width: 28, height: 15)

        Group {
            if !isFloating && metrics.hasHardwareNotch {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 46, height: rowHeight)

                    HStack(spacing: 0) {
                        Spacer()
                            .frame(width: metrics.hardwareNotchWidth)

                        NailBotFaceView(
                            mood: botMood,
                            form: .miniEyes,
                            phase: metrics.phase,
                            speakingEnergy: metrics.speakingEnergy,
                            listeningEnergy: metrics.listeningEnergy,
                            accentColor: themeAccentColor,
                            size: miniSize,
                            isPaused: !metrics.isVisible
                        )
                        .frame(width: 46, height: rowHeight, alignment: .center)
                    }
                    .frame(width: metrics.hardwareNotchWidth + 46, height: rowHeight)
                    .background(
                        Color.black,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 12,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
                }
            } else {
                NailBotFaceView(
                    mood: botMood,
                    form: .miniEyes,
                    phase: metrics.phase,
                    speakingEnergy: metrics.speakingEnergy,
                    listeningEnergy: metrics.listeningEnergy,
                    accentColor: themeAccentColor,
                    size: miniSize,
                    isPaused: !metrics.isVisible
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .clipShape(hudMorphShape(isFloating: isFloating, mode: .collapsed))
            }
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            isPinned.toggle()
        }
        .accessibilityLabel("Buka pendamping Noko-Owl Meet Nail")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isPinned.toggle() }
    }

    // MARK: - Layout 2: Expanded Mode A — H4 Boxless Floating Noko Stage

    @ViewBuilder
    private func liveActivityBody(isFloating: Bool) -> some View {
        let topPad: CGFloat = (!isFloating && metrics.hasHardwareNotch) ? (metrics.notchHeight + 6) : 6
        let side = HUDPanel.stageSide(for: settings.hudSize)
        let owlSize = HUDPanel.owlSize(for: settings.hudSize)

        NokoFloatingCompanionStage(
            mood: botMood,
            phase: metrics.phase,
            speakingEnergy: metrics.speakingEnergy,
            listeningEnergy: metrics.listeningEnergy,
            accentColor: themeAccentColor,
            owlSize: owlSize,
            isPaused: !metrics.isVisible
        )
        .frame(width: side, height: side)
        .opacity(settings.hudOpacity)
        .padding(.top, topPad)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            AppNavigator.shared.showMainWindow()
        }
        .onTapGesture(count: 1) {
            isPinned.toggle()
        }
        .accessibilityLabel("Noko-Owl pendamping suara Meet Nail")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isPinned.toggle() }
    }

    // MARK: - Layout 3: Expanded Mode B — H4 Boxless Stage + Circular Icon Micro-Dock

    @ViewBuilder
    private func commandTrayBody(isFloating: Bool) -> some View {
        let topPad: CGFloat = (!isFloating && metrics.hasHardwareNotch) ? (metrics.notchHeight + 6) : 6
        let side = HUDPanel.stageSide(for: settings.hudSize)
        let owlSize = HUDPanel.owlSize(for: settings.hudSize)

        VStack(alignment: .center, spacing: 0) {
            NokoFloatingCompanionStage(
                mood: botMood,
                phase: metrics.phase,
                speakingEnergy: metrics.speakingEnergy,
                listeningEnergy: metrics.listeningEnergy,
                accentColor: themeAccentColor,
                owlSize: owlSize,
                isPaused: !metrics.isVisible
            )
            .frame(width: side, height: side)
            .opacity(settings.hudOpacity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                AppNavigator.shared.showMainWindow()
            }
            .onTapGesture(count: 1) {
                isPinned.toggle()
            }

            HStack(spacing: 8) {
                if meet.active {
                    if effectiveSpeaking || meet.voiceBusy || botMood == .processing {
                        hudUtilityCircleButton(
                            systemImage: "speaker.slash.fill",
                            isActive: false,
                            isDanger: true,
                            helpText: "Hentikan suara Nail"
                        ) {
                            meet.interrupt()
                        }
                    } else {
                        hudUtilityCircleButton(
                            systemImage: "waveform",
                            isActive: meet.voiceReady,
                            accentTint: meet.voiceReady ? themeAccentColor : nil,
                            isDisabled: !meet.voiceReady,
                            helpText: "Dengar & Jawab"
                        ) {
                            meet.answerMeeting()
                        }
                    }
                }

                hudUtilityCircleButton(
                    systemImage: isPinned ? "pin.fill" : "pin",
                    isActive: isPinned,
                    showPinDot: isPinned,
                    bounceValue: isPinned,
                    helpText: isPinned ? "Lepas pin HUD" : "Pin HUD tetap terbuka"
                ) {
                    isPinned.toggle()
                }

                hudUtilityCircleButton(
                    systemImage: "macwindow",
                    isActive: false,
                    helpText: "Buka jendela utama Meet Nail"
                ) {
                    AppNavigator.shared.showMainWindow()
                }

                hudUtilityCircleButton(
                    systemImage: "xmark",
                    isActive: false,
                    helpText: "Sembunyikan HUD"
                ) {
                    isPinned = false
                    hoverIntent = false
                    isHovering = false
                    HUDPanel.shared.hide()
                }
            }
            .frame(height: 34, alignment: .center)
        }
        .padding(.top, topPad)
    }

    @ViewBuilder
    private func hudUtilityCircleButton(
        systemImage: String,
        isActive: Bool,
        isDanger: Bool = false,
        accentTint: Color? = nil,
        isDisabled: Bool = false,
        showPinDot: Bool = false,
        bounceValue: Bool? = nil,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        let fillColor: Color = if isDanger {
            dangerInk.opacity(0.18)
        } else if let accentTint {
            accentTint.opacity(0.20)
        } else if isActive {
            alabasterInk.opacity(0.18)
        } else {
            recessedSurface.opacity(0.94)
        }
        let strokeColor: Color = if isDanger {
            dangerInk.opacity(0.38)
        } else if let accentTint {
            accentTint.opacity(0.42)
        } else if isActive {
            alabasterInk.opacity(0.32)
        } else {
            Color.white.opacity(0.12)
        }
        let iconColor: Color = if isDanger {
            dangerInk
        } else if let accentTint {
            accentTint
        } else if isActive {
            alabasterInk
        } else {
            mutedInk
        }

        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .overlay {
                        Circle()
                            .strokeBorder(strokeColor, lineWidth: 1)
                    }

                if let bounceValue {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: bounceValue)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 24, height: 24)
            .opacity(isDisabled ? 0.45 : 1.0)
            .shadow(color: Color.black.opacity(0.36), radius: 5, x: 0, y: 2)
            .overlay(alignment: .topTrailing) {
                if showPinDot {
                    Circle()
                        .fill(goldBright)
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle()
                                .strokeBorder(obsidianSurface, lineWidth: 1)
                        }
                        .offset(x: 1, y: -1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText)
    }

    // MARK: - Layout, Bot Mood & State Resolution

    private func cardWidth(for mode: HUDDisplayMode) -> CGFloat {
        HUDPanel.cardSize(for: mode, metrics: metrics, settings: settings, meet: meet).width
    }

    private func cardHeight(for mode: HUDDisplayMode) -> CGFloat {
        HUDPanel.cardSize(for: mode, metrics: metrics, settings: settings, meet: meet).height
    }

    private var desiredDisplayMode: HUDDisplayMode {
        if isPinned || (settings.hudExpandOnHover && hoverIntent) {
            return .commandTray
        } else if metrics.previewStage != .none
            || (settings.hudAutoExpandOnVoice && (
                effectiveSpeaking
                || effectiveListening
                || botMood == .processing
                || metrics.visualEnergy > 0.02
                || meet.visualState == .error
                || meet.visualState == .interrupted
                || recentReplyVisible
            )) {
            return .liveActivity
        } else {
            return .collapsed
        }
    }

    private var botMood: NailBotMood {
        switch metrics.previewStage {
        case .listening:
            return .listening
        case .processing:
            return .processing
        case .speaking:
            return .speaking
        case .finishing:
            return .standby
        case .none:
            break
        }
        return NailBotMood.forSession(
            meet.presentation,
            visualState: meet.visualState,
            isSpeaking: meet.isSpeaking,
            isActivelyListening: meet.isActivelyListening,
            hasNotesError: !meet.notulenError.isEmpty
        )
    }

    private var effectiveSpeaking: Bool {
        meet.isSpeaking || metrics.previewStage == .speaking
    }

    private var effectiveListening: Bool {
        !effectiveSpeaking && (meet.isActivelyListening || metrics.previewStage == .listening)
    }

    // MARK: - Theme Accent Mapping

    private var themeAccentColor: Color {
        switch settings.hudAccentTheme {
        case .status:
            switch botMood {
            case .error:
                return dangerInk
            case .listening, .processing, .speaking:
                return goldWarm
            case .standby, .interrupted:
                return goldBright
            }
        case .ocean:
            return botMood == .error ? dangerInk : Color(hex: 0x5B9BD5)
        case .violet:
            return botMood == .error ? dangerInk : Color(hex: 0x9F8FE0)
        case .emerald:
            return botMood == .error ? dangerInk : Color(hex: 0x6BBF8E)
        }
    }
}
