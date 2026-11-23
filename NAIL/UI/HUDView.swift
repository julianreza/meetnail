import AppKit
import SwiftUI

private struct HUDLiquidMorphStage: View, @MainActor Animatable {
    var morphProgress: CGFloat

    let stageWidth: CGFloat
    let stageHeight: CGFloat
    let rowHeight: CGFloat
    let topPad: CGFloat
    let side: CGFloat
    let owlSize: CGFloat
    let isFloating: Bool
    let isHardwareNotch: Bool
    let hardwareNotchWidth: CGFloat
    let collapsedSize: CGSize
    let mood: NailBotMood
    let phase: Double
    let speakingEnergy: Double
    let listeningEnergy: Double
    let accentColor: Color
    let hudOpacity: Double
    let isPaused: Bool
    let reduceMotion: Bool

    var animatableData: CGFloat {
        get { morphProgress }
        set { morphProgress = newValue }
    }

    var body: some View {
        let effectiveProgress = reduceMotion ? (morphProgress >= 0.5 ? 1.0 : 0.0) : morphProgress
        let t = HUDMorphMath.clamp01(effectiveProgress)
        let shapeT = HUDMorphMath.smoothstep(t, edge0: 0.08, edge1: 0.92)

        let collapsedOrigin = CGPoint(
            x: isHardwareNotch
                ? (stageWidth * 0.5 + hardwareNotchWidth * 0.5 + 23)
                : (stageWidth * 0.5),
            y: rowHeight * 0.5
        )
        let expandedOrigin = CGPoint(
            x: stageWidth * 0.5,
            y: topPad + side * 0.5
        )

        let controlPoint = CGPoint(
            x: isHardwareNotch
                ? (collapsedOrigin.x * 0.85 + expandedOrigin.x * 0.15)
                : expandedOrigin.x,
            y: HUDMorphMath.lerp(
                collapsedOrigin.y,
                expandedOrigin.y,
                t: isHardwareNotch ? 0.68 : 0.55
            )
        )

        let inv = 1.0 - t
        let bx = inv * inv * collapsedOrigin.x + 2.0 * inv * t * controlPoint.x + t * t * expandedOrigin.x
        let by = inv * inv * collapsedOrigin.y + 2.0 * inv * t * controlPoint.y + t * t * expandedOrigin.y
        let overshootY = reduceMotion ? 0 : max(0, effectiveProgress - 1.0) * (expandedOrigin.y - collapsedOrigin.y) * 0.36
        let center = CGPoint(x: bx, y: by + overshootY)

        let morphPillCollapsedSize = isHardwareNotch
            ? CGSize(width: 46, height: rowHeight)
            : collapsedSize
        let shellSize = HUDMorphMath.morphShellDimensions(
            progress: t,
            collapsedSize: morphPillCollapsedSize,
            expandedOwlSize: owlSize
        )
        let squash = reduceMotion ? CGSize(width: 1.0, height: 1.0) : HUDMorphMath.squashStretch(progress: t)

        let restChromeAlpha = 1.0 - HUDMorphMath.smoothstep(t, edge0: 0.0, edge1: 0.10)
        let notchEarAlpha = 1.0 - HUDMorphMath.smoothstep(t, edge0: 0.0, edge1: 0.35)
        let shellFadeIn: CGFloat = isHardwareNotch
            ? HUDMorphMath.smoothstep(t, edge0: 0.0, edge1: 0.08)
            : (t > 0.001 ? 1.0 : 0.0)
        let shellFadeOut = 1.0 - HUDMorphMath.smoothstep(t, edge0: 0.68, edge1: 0.96)
        let shellOpacity = shellFadeIn * shellFadeOut

        let porcelainMix = HUDMorphMath.smoothstep(t, edge0: 0.22, edge1: 0.72)
        let midPulse = sin(t * .pi)

        let bloomIn = HUDMorphMath.smoothstep(t, edge0: 0.25, edge1: 0.54)
        let bloomOut = 1.0 - HUDMorphMath.smoothstep(t, edge0: 0.56, edge1: 0.90)
        let bloomAlpha = bloomIn * bloomOut

        let eyeFadeOut = 1.0 - HUDMorphMath.smoothstep(t, edge0: 0.44, edge1: 0.64)
        let eyeGrow = HUDMorphMath.smoothstep(t, edge0: 0.0, edge1: 0.62)
        let owlScale = owlSize / 48.0
        let targetEyeScale = max(1.0, owlScale / (15.0 / 14.0))
        let currentEyeScale = HUDMorphMath.lerp(1.0, targetEyeScale, t: eyeGrow)
        let visorOffsetY = HUDMorphMath.lerp(0, -2.4 * owlScale, t: eyeGrow)
        let visorReveal = HUDMorphMath.smoothstep(t, edge0: 0.20, edge1: 0.58)
        let visorW = HUDMorphMath.lerp(28, 32.2 * owlScale, t: eyeGrow)
        let visorH = HUDMorphMath.lerp(15, 14.2 * owlScale, t: eyeGrow)

        let owlReveal = reduceMotion
            ? (t >= 0.5 ? 1.0 : 0.0)
            : HUDMorphMath.smoothstep(t, edge0: 0.48, edge1: 0.88)

        ZStack(alignment: .topLeading) {
            if isHardwareNotch {
                if notchEarAlpha > 0.001 {
                    Color.black
                        .frame(width: hardwareNotchWidth + 46, height: rowHeight)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 12,
                                bottomTrailingRadius: 12,
                                topTrailingRadius: 0,
                                style: .continuous
                            )
                        )
                        .opacity(notchEarAlpha)
                        .position(x: stageWidth * 0.5 + 23, y: rowHeight * 0.5)
                }
            } else if restChromeAlpha > 0.001 {
                let restShape = isFloating
                    ? HUDMorphShellShape(topFlare: 0, topRadius: 18, bottomRadius: 18)
                    : HUDMorphShellShape(topFlare: 8, topRadius: 0, bottomRadius: 12)
                ZStack {
                    restShape
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(hex: 0x181B22).opacity(hudOpacity), location: 0.0),
                                    .init(color: Color(hex: 0x0C0D11).opacity(hudOpacity), location: 0.55),
                                    .init(color: Color(hex: 0x060709).opacity(hudOpacity), location: 1.0),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    restShape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.06),
                                    Color.black.opacity(0.45),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                }
                .frame(width: collapsedSize.width, height: collapsedSize.height)
                .shadow(
                    color: isFloating ? Color.white.opacity(0.08 * hudOpacity) : .clear,
                    radius: isFloating ? 3 : 0,
                    x: -1.5,
                    y: -1.5
                )
                .shadow(
                    color: isFloating ? Color.black.opacity(0.55 * hudOpacity) : .clear,
                    radius: isFloating ? 7 : 0,
                    x: 2,
                    y: 4
                )
                .opacity(restChromeAlpha)
                .position(x: collapsedOrigin.x, y: collapsedOrigin.y)
            }

            if bloomAlpha > 0.001 && !reduceMotion {
                let bloomScale = HUDMorphMath.lerp(
                    0.88,
                    1.38,
                    t: HUDMorphMath.smoothstep(t, edge0: 0.25, edge1: 0.90)
                )
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    accentColor.opacity(0.24 * bloomAlpha),
                                    Color(hex: 0xF2C94C).opacity(0.08 * bloomAlpha),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: shellSize.width * 0.18,
                                endRadius: shellSize.width * 0.78
                            )
                        )
                        .frame(width: shellSize.width * 1.56, height: shellSize.height * 1.56)

                    PillToOwlMorphShape(progress: shapeT)
                        .stroke(accentColor.opacity(0.42 * bloomAlpha), lineWidth: 1.5)
                        .frame(width: shellSize.width, height: shellSize.height)
                        .scaleEffect(bloomScale)
                }
                .scaleEffect(x: squash.width, y: squash.height)
                .position(x: center.x, y: center.y)
            }

            if shellOpacity > 0.001 && t > 0.001 {
                let morphShape = PillToOwlMorphShape(progress: shapeT)
                ZStack {
                    // Sculpted obsidian capsule phase (#181B22 -> #060709 + specular rim)
                    ZStack {
                        morphShape
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(hex: 0x181B22), location: 0.0),
                                        .init(color: Color(hex: 0x0C0D11), location: 0.55),
                                        .init(color: Color(hex: 0x060709), location: 1.0),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        morphShape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.24),
                                        Color.white.opacity(0.07),
                                        Color.black.opacity(0.42),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    }
                    .opacity(1.0 - porcelainMix * 0.90)

                    // Sculpted porcelain Noko-Owl transition phase (#FAFBFD -> #DAE3EE)
                    ZStack {
                        morphShape
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(hex: 0xFAFBFD), location: 0.0),
                                        .init(color: Color(hex: 0xF3F6FA), location: 0.34),
                                        .init(color: Color(hex: 0xECF0F5), location: 0.66),
                                        .init(color: Color(hex: 0xDAE3EE), location: 1.0),
                                    ],
                                    startPoint: UnitPoint(x: 0.22, y: 0.10),
                                    endPoint: UnitPoint(x: 0.86, y: 0.95)
                                )
                            )
                        morphShape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.92),
                                        Color.white.opacity(0.40),
                                        Color(hex: 0xB8C5D6, alpha: 0.65),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    }
                    .opacity(porcelainMix)

                    // Luminous mid-morph accent rim pulse
                    morphShape
                        .stroke(accentColor.opacity(0.45 * midPulse), lineWidth: 1.25)
                        .shadow(color: accentColor.opacity(0.32 * midPulse), radius: 8.0 * midPulse)
                        .opacity(midPulse)
                }
                .frame(width: shellSize.width, height: shellSize.height)
                .scaleEffect(x: squash.width, y: squash.height)
                .opacity(shellOpacity * hudOpacity)
                .position(x: center.x, y: center.y)
            }

            if eyeFadeOut > 0.001 {
                ZStack {
                    if visorReveal > 0.001 && t > 0.001 {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(hex: 0x171A21), location: 0.0),
                                        .init(color: Color(hex: 0x0E1015), location: 0.50),
                                        .init(color: Color(hex: 0x0A0A0A), location: 1.0),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: visorW, height: visorH)
                            .opacity(visorReveal)
                    }

                    NailBotFaceView(
                        mood: mood,
                        form: .miniEyes,
                        phase: phase,
                        speakingEnergy: speakingEnergy,
                        listeningEnergy: listeningEnergy,
                        accentColor: accentColor,
                        size: CGSize(width: 28, height: 15),
                        isPaused: isPaused
                    )
                    .scaleEffect(currentEyeScale)
                }
                .offset(y: visorOffsetY)
                .frame(width: shellSize.width, height: shellSize.height)
                .clipShape(PillToOwlMorphShape(progress: shapeT))
                .scaleEffect(x: squash.width, y: squash.height)
                .opacity(eyeFadeOut * (t <= 0.001 ? 1.0 : hudOpacity))
                .position(x: center.x, y: center.y)
            }

            if t > 0.001 || owlReveal > 0.001 {
                NokoFloatingCompanionStage(
                    mood: mood,
                    phase: phase,
                    speakingEnergy: speakingEnergy,
                    listeningEnergy: listeningEnergy,
                    accentColor: accentColor,
                    owlSize: owlSize,
                    isPaused: isPaused || t < 0.45
                )
                .frame(width: side, height: side)
                .scaleEffect(x: squash.width, y: squash.height)
                .opacity(owlReveal * hudOpacity)
                .position(x: center.x, y: center.y)
            }
        }
        .frame(width: stageWidth, height: stageHeight, alignment: .topLeading)
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

    @State private var morphProgress: CGFloat = 0
    @State private var isStageExpanded = false
    @State private var stageCollapseTask: Task<Void, Never>?
    @State private var dockRevealed = false
    @State private var dockMounted = false
    @State private var dockUnmountTask: Task<Void, Never>?
    @State private var dockRevealTask: Task<Void, Never>?

    // MARK: - Design #27 Obsidian Monochrome + Subtle Touch of Yellow Tokens

    private let obsidianSurface = Color(hex: 0x0A0A0A)
    private let dangerInk = Color(hex: 0xF08A80)
    private let goldBright = Color(hex: 0xEAB308)
    private let goldWarm = Color(hex: 0xF2C94C)

    var body: some View {
        let mode = metrics.displayMode
        let isFloating = settings.hudLayoutStyle == .floatingPill
        let isHardwareNotch = !isFloating && metrics.hasHardwareNotch
        let isExpanded = (mode != .collapsed)
        let rowHeight: CGFloat = isFloating ? 36 : metrics.notchHeight
        let topPad: CGFloat = isHardwareNotch ? (metrics.notchHeight + 6) : 6
        let side = HUDPanel.stageSide(for: settings.hudSize)
        let owlSize = HUDPanel.owlSize(for: settings.hudSize)
        let collapsedSize = HUDPanel.cardSize(for: .collapsed, metrics: metrics, settings: settings, meet: meet)

        let activeStageExpanded = isExpanded || isStageExpanded
        let stageWidth: CGFloat = activeStageExpanded
            ? (isHardwareNotch ? max(side, collapsedSize.width) : side)
            : collapsedSize.width
        let stageHeight: CGFloat = activeStageExpanded
            ? (topPad + side)
            : collapsedSize.height
        let showDockRow = activeStageExpanded && (mode == .commandTray || dockMounted)

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                HUDLiquidMorphStage(
                    morphProgress: morphProgress,
                    stageWidth: stageWidth,
                    stageHeight: stageHeight,
                    rowHeight: rowHeight,
                    topPad: topPad,
                    side: side,
                    owlSize: owlSize,
                    isFloating: isFloating,
                    isHardwareNotch: isHardwareNotch,
                    hardwareNotchWidth: metrics.hardwareNotchWidth,
                    collapsedSize: collapsedSize,
                    mood: botMood,
                    phase: metrics.phase,
                    speakingEnergy: metrics.speakingEnergy,
                    listeningEnergy: metrics.listeningEnergy,
                    accentColor: themeAccentColor,
                    hudOpacity: settings.hudOpacity,
                    isPaused: !metrics.isVisible,
                    reduceMotion: reduceMotion
                )

                interactiveHitLayer(
                    mode: mode,
                    stageWidth: stageWidth,
                    rowHeight: rowHeight,
                    topPad: topPad,
                    side: side,
                    collapsedSize: collapsedSize,
                    isHardwareNotch: isHardwareNotch
                )

                if showDockRow {
                    microDockRow
                        .frame(height: 34, alignment: .center)
                        .padding(.top, topPad + side)
                        .allowsHitTesting(mode == .commandTray)
                }
            }
            .frame(width: stageWidth, height: stageHeight + (showDockRow ? 34 : 0), alignment: .top)
            .onHover { hovering in
                handleHover(hovering)
            }
            .padding(.top, isFloating ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: botMood)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, settings.appAppearance.colorScheme ?? colorScheme)
        .onAppear {
            syncVoiceTargets()
            let initiallyExpanded = (metrics.displayMode != .collapsed)
            isStageExpanded = initiallyExpanded
            morphProgress = initiallyExpanded ? 1.0 : 0.0
            let initialDock = (metrics.displayMode == .commandTray)
            dockMounted = initialDock
            dockRevealed = initialDock
            if desiredDisplayMode != metrics.displayMode {
                onDisplayModeChange(desiredDisplayMode)
            }
        }
        .onChange(of: metrics.displayMode) { oldMode, newMode in
            handleDisplayModeTransition(from: oldMode, to: newMode)
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
                let expanded = (metrics.displayMode != .collapsed)
                stageCollapseTask?.cancel()
                dockUnmountTask?.cancel()
                dockRevealTask?.cancel()
                isStageExpanded = expanded
                morphProgress = expanded ? 1.0 : 0.0
                dockMounted = (metrics.displayMode == .commandTray)
                dockRevealed = (metrics.displayMode == .commandTray)
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

    // MARK: - Morph & Dock Transition Coordination

    private func handleDisplayModeTransition(from oldMode: HUDDisplayMode, to newMode: HUDDisplayMode) {
        let wasExpanded = (oldMode != .collapsed)
        let nowExpanded = (newMode != .collapsed)

        let expandSpring: Animation? = reduceMotion
            ? nil
            : .spring(response: 0.50, dampingFraction: 0.72, blendDuration: 0.12)
        let collapseSpring: Animation? = reduceMotion
            ? nil
            : .spring(response: 0.36, dampingFraction: 0.84, blendDuration: 0.08)

        if nowExpanded {
            stageCollapseTask?.cancel()
            stageCollapseTask = nil
            isStageExpanded = true
            if !wasExpanded || morphProgress < 0.999 {
                withAnimation(expandSpring) {
                    morphProgress = 1.0
                }
            }
        } else {
            withAnimation(collapseSpring) {
                morphProgress = 0.0
            }
            stageCollapseTask?.cancel()
            if reduceMotion {
                isStageExpanded = false
            } else {
                stageCollapseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(460))
                    guard !Task.isCancelled, metrics.displayMode == .collapsed else { return }
                    isStageExpanded = false
                }
            }
        }

        if newMode == .commandTray {
            dockUnmountTask?.cancel()
            dockUnmountTask = nil
            dockRevealTask?.cancel()
            dockMounted = true
            if reduceMotion {
                dockRevealed = true
            } else {
                let extraDelayMs = wasExpanded ? 0 : 90
                dockRevealTask = Task { @MainActor in
                    if extraDelayMs > 0 {
                        try? await Task.sleep(for: .milliseconds(extraDelayMs))
                    } else {
                        await Task.yield()
                    }
                    guard !Task.isCancelled, metrics.displayMode == .commandTray else { return }
                    dockRevealed = true
                }
            }
        } else {
            dockRevealTask?.cancel()
            dockRevealTask = nil
            let tuckAnim: Animation? = reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.88)
            withAnimation(tuckAnim) {
                dockRevealed = false
            }
            dockUnmountTask?.cancel()
            if reduceMotion {
                dockMounted = false
            } else {
                dockUnmountTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(240))
                    guard !Task.isCancelled, metrics.displayMode != .commandTray else { return }
                    dockMounted = false
                }
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
                try? await Task.sleep(for: .milliseconds(85))
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

    // MARK: - Interactive Hit Layer (Zero-Clip Click & Accessibility Targets)

    @ViewBuilder
    private func interactiveHitLayer(
        mode: HUDDisplayMode,
        stageWidth: CGFloat,
        rowHeight: CGFloat,
        topPad: CGFloat,
        side: CGFloat,
        collapsedSize: CGSize,
        isHardwareNotch: Bool
    ) -> some View {
        if mode == .collapsed {
            Color.clear
                .frame(width: collapsedSize.width, height: rowHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    isPinned.toggle()
                }
                .accessibilityLabel("Buka pendamping Noko-Owl Meet Nail")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { isPinned.toggle() }
        } else {
            ZStack(alignment: .top) {
                if isHardwareNotch {
                    Color.clear
                        .frame(width: collapsedSize.width, height: rowHeight)
                        .contentShape(Rectangle())
                }

                Color.clear
                    .frame(width: side, height: side)
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
                    .padding(.top, topPad)
            }
        }
    }

    // MARK: - Staggered Circular Icon Micro-Dock (.commandTray)

    @ViewBuilder
    private var microDockRow: some View {
        let hasMeetAction = meet.active
        let pinIndex = hasMeetAction ? 1 : 0
        let windowIndex = hasMeetAction ? 2 : 1
        let closeIndex = hasMeetAction ? 3 : 2

        HStack(spacing: 8) {
            if hasMeetAction {
                if effectiveSpeaking || meet.voiceBusy || botMood == .processing {
                    staggeredDockButton(index: 0) {
                        hudUtilityCircleButton(
                            systemImage: "speaker.slash.fill",
                            isActive: false,
                            isDanger: true,
                            helpText: "Hentikan suara Nail"
                        ) {
                            meet.interrupt()
                        }
                    }
                } else {
                    staggeredDockButton(index: 0) {
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
            }

            staggeredDockButton(index: pinIndex) {
                hudUtilityCircleButton(
                    systemImage: isPinned ? "pin.fill" : "pin",
                    isActive: isPinned,
                    showPinDot: isPinned,
                    bounceValue: isPinned,
                    helpText: isPinned ? "Lepas pin HUD" : "Pin HUD tetap terbuka"
                ) {
                    isPinned.toggle()
                }
            }

            staggeredDockButton(index: windowIndex) {
                hudUtilityCircleButton(
                    systemImage: "macwindow",
                    isActive: false,
                    helpText: "Buka jendela utama Meet Nail"
                ) {
                    AppNavigator.shared.showMainWindow()
                }
            }

            staggeredDockButton(index: closeIndex) {
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
        }
    }

    @ViewBuilder
    private func staggeredDockButton<Content: View>(
        index: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let anim: Animation? = reduceMotion
            ? nil
            : (dockRevealed
                ? .spring(response: 0.36, dampingFraction: 0.76).delay(Double(index) * 0.035)
                : .spring(response: 0.22, dampingFraction: 0.88))

        content()
            .opacity(dockRevealed ? 1.0 : 0.0)
            .scaleEffect(dockRevealed ? 1.0 : 0.68)
            .offset(y: dockRevealed ? 0 : -10)
            .animation(anim, value: dockRevealed)
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
        // Sculpted obsidian tactile dock buttons matching the dark HUD shell.
        let buttonTone: NeuTone = .obsidian
        let tintColor: Color? = isDanger ? dangerInk : accentTint

        HUDDockCircleButton(
            systemImage: systemImage,
            tone: buttonTone,
            isActive: isActive,
            isDanger: isDanger,
            accentTint: tintColor,
            isDisabled: isDisabled,
            showPinDot: showPinDot,
            bounceValue: bounceValue,
            helpText: helpText,
            dangerInk: dangerInk,
            goldBright: goldBright,
            obsidianSurface: obsidianSurface,
            action: action
        )
    }

    // MARK: - Bot Mood & State Resolution

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

private struct HUDNeuCircleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tone: NeuTone
    let isHovered: Bool
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled

        configuration.label
            .background {
                if pressed {
                    NeuInsetBackground(isCapsule: true, depth: 0.72, tone: tone)
                } else {
                    NeuRaisedBackground(
                        isCapsule: true,
                        elevation: isHovered ? 0.72 : 0.56,
                        tint: tint,
                        tone: tone
                    )
                }
            }
            .scaleEffect(pressed && !reduceMotion ? 0.93 : (isHovered && !reduceMotion ? 1.04 : 1.0))
            .opacity(isEnabled ? 1.0 : 0.45)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.76),
                value: pressed
            )
    }
}

private struct HUDDockCircleButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let systemImage: String
    let tone: NeuTone
    let isActive: Bool
    let isDanger: Bool
    let accentTint: Color?
    let isDisabled: Bool
    let showPinDot: Bool
    let bounceValue: Bool?
    let helpText: String
    let dangerInk: Color
    let goldBright: Color
    let obsidianSurface: Color
    let action: () -> Void

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)
        let iconColor: Color = if isDanger {
            dangerInk
        } else if let accentTint {
            accentTint
        } else {
            palette.primaryText(for: tone)
        }

        Button(action: action) {
            ZStack {
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
            .frame(width: 26, height: 26)
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
        .buttonStyle(
            HUDNeuCircleButtonStyle(
                tone: tone,
                isHovered: isHovered,
                tint: accentTint
            )
        )
        .disabled(isDisabled)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                    isHovered = hovering
                }
            }
        }
        .help(helpText)
    }
}
