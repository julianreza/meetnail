import AppKit
import Observation
import SwiftUI

enum HUDPreviewStage: Equatable, Sendable {
    case none
    case listening
    case processing
    case speaking
    case finishing
}

enum HUDDisplayMode: Equatable, Sendable {
    case collapsed
    case liveActivity
    case commandTray
}

@MainActor @Observable
final class NotchMetrics {
    var hasHardwareNotch: Bool = false
    var notchHeight: CGFloat = 34
    var hardwareNotchWidth: CGFloat = 0
    var displayMode: HUDDisplayMode = .collapsed {
        didSet {
            let expanded = (displayMode != .collapsed)
            if isExpanded != expanded {
                isExpanded = expanded
            }
        }
    }
    var isExpanded: Bool = false
    var isVisible: Bool = false
    var previewStage: HUDPreviewStage = .none

    var phase: Double = 0
    var speakingEnergy: Double = 0
    var listeningEnergy: Double = 0

    var previewSpeaking: Bool { previewStage == .speaking }
    var visualEnergy: Double { max(speakingEnergy, listeningEnergy) }

    @ObservationIgnored private var targetSpeaking = false
    @ObservationIgnored private var targetListening = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick: TimeInterval = 0

    func updateVoiceTargets(speaking: Bool, listening: Bool) {
        targetSpeaking = speaking
        targetListening = listening
        if speaking || listening || speakingEnergy > 0 || listeningEnergy > 0 {
            startTimerIfNeeded()
        }
    }

    func step(dt rawDt: Double) {
        let dt = min(max(rawDt, 0.001), 0.05)
        phase += dt * (1.0 + speakingEnergy * 1.6 + listeningEnergy * 0.6)

        let sTarget = targetSpeaking ? 1.0 : 0.0
        let sRate = sTarget > speakingEnergy ? 8.5 : 3.8
        speakingEnergy += (sTarget - speakingEnergy) * min(1.0, dt * sRate)

        let lTarget = (!targetSpeaking && targetListening) ? 1.0 : 0.0
        let lRate = lTarget > listeningEnergy ? 7.0 : 4.2
        listeningEnergy += (lTarget - listeningEnergy) * min(1.0, dt * lRate)

        if !targetSpeaking && !targetListening && speakingEnergy < 0.008 && listeningEnergy < 0.008 {
            speakingEnergy = 0
            listeningEnergy = 0
            stopTimer()
        }
    }

    func stopAnimations() {
        targetSpeaking = false
        targetListening = false
        speakingEnergy = 0
        listeningEnergy = 0
        stopTimer()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastTick > 0 ? (now - lastTick) : (1.0 / 60.0)
        lastTick = now
        step(dt: dt)
    }
}

private final class HUDHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private final class HUDRootContainerView: NSView {
    let hostingView: HUDHostingView<HUDView>

    init(rootView: HUDView, frame: NSRect) {
        let hosting = HUDHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.sceneBridgingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        self.hostingView = hosting
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        if hostingView.frame != bounds {
            hostingView.frame = bounds
        }
    }
}

final class HUDPanel: NSPanel {
    static let shared = HUDPanel()

    let metrics = NotchMetrics()
    private var containerView: HUDRootContainerView!
    var hostingView: NSHostingView<HUDView> { containerView.hostingView }

    private var desiredMode: HUDDisplayMode = .collapsed
    private var isApplyingProgrammaticFrame = false
    private var transitionGeneration: UInt64 = 0
    private var expandWorkItem: DispatchWorkItem?
    private var shrinkWorkItem: DispatchWorkItem?
    private var previewTask: Task<Void, Never>?
    private var layoutRefreshWorkItem: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?

    private enum FloatingKeys {
        static let anchorMidX = "nail.hud.floatingAnchorMidX"
        static let anchorMaxY = "nail.hud.floatingAnchorMaxY"
    }

    private init() {
        let initialScreen = Self.preferredScreen()
        let initialMetrics = Self.measureScreen(initialScreen)
        metrics.hasHardwareNotch = initialMetrics.hasNotch
        metrics.notchHeight = initialMetrics.height
        metrics.hardwareNotchWidth = initialMetrics.width

        let isFloating = VoiceSettings.shared.hudLayoutStyle == .floatingPill
        let width = Self.collapsedWidth(for: metrics)
        let height = Self.collapsedHeight(for: metrics)
        let rect: NSRect
        if isFloating {
            let visibleFrame = initialScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 875)
            let savedOrigin = Self.loadFloatingAnchor().map {
                NSPoint(x: round($0.x - width / 2), y: $0.y - height)
            }
            rect = Self.floatingFrame(
                visibleFrame: visibleFrame,
                width: width,
                height: height,
                savedOrigin: savedOrigin
            )
        } else {
            let screenFrame = initialScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            rect = Self.panelFrame(screenFrame: screenFrame, width: width, height: height)
        }

        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        title = "Meet Nail"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = isFloating
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .canJoinAllApplications]
        contentMinSize = NSSize(width: 1, height: 1)
        contentMaxSize = NSSize(width: 10_000, height: 10_000)
        applySharingType()

        let root = HUDView(metrics: metrics) { [weak self] mode in
            self?.setDisplayMode(mode)
        }
        let container = HUDRootContainerView(rootView: root, frame: NSRect(origin: .zero, size: rect.size))
        self.containerView = container
        contentView = container

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRefreshLayout()
            }
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleWindowDidMove()
                }
            }
        }

        applyFrame(rect, display: false)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    nonisolated static func panelFrame(screenFrame: NSRect, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(
            x: round(screenFrame.midX - width / 2),
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    nonisolated static func floatingFrame(
        visibleFrame: NSRect,
        width: CGFloat,
        height: CGFloat,
        savedOrigin: NSPoint? = nil
    ) -> NSRect {
        let defaultX = round(visibleFrame.midX - width / 2)
        let defaultY = round(visibleFrame.maxY - height - 2)
        let rawX = savedOrigin?.x ?? defaultX
        let rawY = savedOrigin?.y ?? defaultY
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - height)
        let clampedX = min(max(rawX, visibleFrame.minX), maxX)
        let clampedY = min(max(rawY, visibleFrame.minY), maxY)
        return NSRect(x: clampedX, y: clampedY, width: width, height: height)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func applySharingType() {
        sharingType = VoiceSettings.shared.hudHideFromScreenShare ? .none : .readOnly
    }

    func isMouseInsideVisibleHUD() -> Bool {
        guard isVisible else { return false }
        let activeMode = metrics.displayMode
        let isFloating = VoiceSettings.shared.hudLayoutStyle == .floatingPill
        let mouse = NSEvent.mouseLocation

        if activeMode == .collapsed {
            let insetX: CGFloat = isFloating ? 10 : 4
            let insetBottom: CGFloat = isFloating ? 10 : 2
            let hitRect = NSRect(
                x: frame.minX + insetX,
                y: frame.minY + insetBottom,
                width: max(1, frame.width - insetX * 2),
                height: max(1, frame.height - insetBottom)
            ).insetBy(dx: -6, dy: -6)
            return hitRect.contains(mouse)
        }

        let card = Self.cardSize(for: activeMode, metrics: metrics)
        let cardRect = NSRect(
            x: frame.midX - card.width * 0.5,
            y: frame.maxY - card.height - (isFloating ? 1 : 0),
            width: card.width,
            height: card.height
        ).insetBy(dx: -8, dy: -8)
        if cardRect.contains(mouse) {
            return true
        }

        if !isFloating && metrics.hasHardwareNotch {
            let notchWidth = Self.collapsedWidth(for: metrics)
            let notchRect = NSRect(
                x: frame.midX - notchWidth * 0.5,
                y: frame.maxY - metrics.notchHeight,
                width: notchWidth,
                height: metrics.notchHeight
            ).insetBy(dx: -6, dy: -6)
            return notchRect.contains(mouse)
        }

        return false
    }

    func show() {
        applySharingType()
        refreshLayout()
        orderFrontRegardless()
        if metrics.isVisible != isVisible {
            metrics.isVisible = isVisible
        }
    }

    func hide() {
        desiredMode = .collapsed
        transitionGeneration &+= 1
        expandWorkItem?.cancel()
        expandWorkItem = nil
        shrinkWorkItem?.cancel()
        shrinkWorkItem = nil
        previewTask?.cancel()
        previewTask = nil
        layoutRefreshWorkItem?.cancel()
        layoutRefreshWorkItem = nil
        if metrics.previewStage != .none {
            metrics.previewStage = .none
        }
        metrics.stopAnimations()
        if metrics.displayMode != .collapsed {
            metrics.displayMode = .collapsed
        }
        orderOut(nil)
        if metrics.isVisible != isVisible {
            metrics.isVisible = isVisible
        }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func triggerSpeakingPreview() {
        previewTask?.cancel()
        expandWorkItem?.cancel()
        expandWorkItem = nil
        shrinkWorkItem?.cancel()
        shrinkWorkItem = nil
        layoutRefreshWorkItem?.cancel()
        layoutRefreshWorkItem = nil
        if metrics.previewStage != .listening {
            metrics.previewStage = .listening
        }
        desiredMode = .liveActivity
        show()
        setDisplayMode(.liveActivity)
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            self.metrics.previewStage = .processing
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            self.metrics.previewStage = .speaking
            try? await Task.sleep(for: .milliseconds(2600))
            guard !Task.isCancelled else { return }
            self.metrics.previewStage = .finishing
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self.metrics.previewStage = .none
        }
    }

    func setExpanded(_ expanded: Bool) {
        setDisplayMode(expanded ? .commandTray : .collapsed)
    }

    func setDisplayMode(_ mode: HUDDisplayMode) {
        shrinkWorkItem?.cancel()
        shrinkWorkItem = nil
        expandWorkItem?.cancel()
        expandWorkItem = nil
        transitionGeneration &+= 1
        let generation = transitionGeneration
        desiredMode = mode

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let targetFrame = frameFor(mode: mode, preserveTopAnchor: isVisible)
        let isGrowing = targetFrame.width > frame.width || targetFrame.height > frame.height || (metrics.displayMode == .collapsed && mode != .collapsed)

        if isGrowing && mode != .collapsed {
            let expandWork = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.transitionGeneration == generation, self.desiredMode == mode else { return }
                    self.applyFrame(self.frameFor(mode: mode, preserveTopAnchor: self.isVisible), display: false)
                    let applyModeWork = DispatchWorkItem { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.transitionGeneration == generation, self.desiredMode == mode else { return }
                            if self.metrics.displayMode != mode {
                                self.metrics.displayMode = mode
                            }
                        }
                    }
                    self.expandWorkItem = applyModeWork
                    let delayMs = reduceMotion ? 0 : 16
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: applyModeWork)
                }
            }
            expandWorkItem = expandWork
            DispatchQueue.main.async(execute: expandWork)
        } else {
            let collapseWork = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.transitionGeneration == generation, self.desiredMode == mode else { return }
                    if self.metrics.displayMode != mode {
                        self.metrics.displayMode = mode
                    }
                    let shrinkFrameWork = DispatchWorkItem { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self,
                                  self.transitionGeneration == generation,
                                  self.desiredMode == mode,
                                  self.metrics.displayMode == mode else { return }
                            self.applyFrame(self.frameFor(mode: mode, preserveTopAnchor: self.isVisible), display: false)
                        }
                    }
                    self.shrinkWorkItem = shrinkFrameWork
                    let shrinkDelayMs = reduceMotion ? 0 : 480
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(shrinkDelayMs), execute: shrinkFrameWork)
                }
            }
            shrinkWorkItem = collapseWork
            DispatchQueue.main.async(execute: collapseWork)
        }
    }

    func scheduleRefreshLayout() {
        layoutRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshLayout()
            }
        }
        layoutRefreshWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    func refreshLayout() {
        applySharingType()
        let measured = Self.measureScreen(Self.preferredScreen())
        if metrics.hasHardwareNotch != measured.hasNotch {
            metrics.hasHardwareNotch = measured.hasNotch
        }
        if metrics.notchHeight != measured.height {
            metrics.notchHeight = measured.height
        }
        if metrics.hardwareNotchWidth != measured.width {
            metrics.hardwareNotchWidth = measured.width
        }
        let floating = (VoiceSettings.shared.hudLayoutStyle == .floatingPill)
        if isMovableByWindowBackground != floating {
            isMovableByWindowBackground = floating
        }
        let activeMode = desiredMode != .collapsed ? desiredMode : metrics.displayMode
        applyFrame(frameFor(mode: activeMode, preserveTopAnchor: false), display: false)
    }

    private func applyFrame(_ rect: NSRect, display: Bool) {
        let dx = abs(frame.origin.x - rect.origin.x)
        let dy = abs(frame.origin.y - rect.origin.y)
        let dw = abs(frame.size.width - rect.size.width)
        let dh = abs(frame.size.height - rect.size.height)
        guard dx > 0.5 || dy > 0.5 || dw > 0.5 || dh > 0.5 else { return }
        isApplyingProgrammaticFrame = true
        setFrame(rect, display: display, animate: false)
        invalidateShadow()
        isApplyingProgrammaticFrame = false
    }

    private func handleWindowDidMove() {
        guard isVisible,
              !isApplyingProgrammaticFrame,
              VoiceSettings.shared.hudLayoutStyle == .floatingPill,
              NSEvent.pressedMouseButtons != 0 else { return }
        Self.saveFloatingAnchor(NSPoint(x: frame.midX, y: frame.maxY))
    }

    private static func loadFloatingAnchor() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: FloatingKeys.anchorMidX) != nil,
              defaults.object(forKey: FloatingKeys.anchorMaxY) != nil else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: FloatingKeys.anchorMidX),
            y: defaults.double(forKey: FloatingKeys.anchorMaxY)
        )
    }

    private static func saveFloatingAnchor(_ anchor: NSPoint) {
        let defaults = UserDefaults.standard
        defaults.set(Double(anchor.x), forKey: FloatingKeys.anchorMidX)
        defaults.set(Double(anchor.y), forKey: FloatingKeys.anchorMaxY)
    }

    nonisolated static func stageSide(for size: HUDSizePreset) -> CGFloat {
        switch size {
        case .compact: 126
        case .standard: 148
        case .large: 170
        case .extraLarge: 192
        }
    }

    nonisolated static func owlSize(for size: HUDSizePreset) -> CGFloat {
        switch size {
        case .compact: 72
        case .standard: 88
        case .large: 104
        case .extraLarge: 120
        }
    }

    @MainActor
    static func cardSize(
        for mode: HUDDisplayMode,
        metrics: NotchMetrics,
        settings: VoiceSettings = .shared,
        meet: MeetSession = .shared
    ) -> CGSize {
        let isFloating = settings.hudLayoutStyle == .floatingPill
        let topPad: CGFloat = (!isFloating && metrics.hasHardwareNotch) ? (metrics.notchHeight + 6) : 6
        let side = stageSide(for: settings.hudSize)

        switch mode {
        case .collapsed:
            if !isFloating && metrics.hasHardwareNotch {
                return CGSize(
                    width: metrics.hardwareNotchWidth + 92,
                    height: metrics.notchHeight
                )
            }
            if isFloating {
                return CGSize(width: 46, height: 36)
            }
            return CGSize(width: 58, height: metrics.notchHeight)

        case .liveActivity:
            return CGSize(width: side, height: topPad + side)

        case .commandTray:
            return CGSize(width: side, height: topPad + side + 34)
        }
    }

    private func frameFor(mode: HUDDisplayMode, preserveTopAnchor: Bool = false) -> NSRect {
        let targetScreen = Self.preferredScreen(containing: self)
        let isFloating = VoiceSettings.shared.hudLayoutStyle == .floatingPill
        let card = Self.cardSize(for: mode, metrics: metrics)
        let width: CGFloat
        let height: CGFloat

        switch mode {
        case .collapsed:
            width = Self.collapsedWidth(for: metrics)
            height = Self.collapsedHeight(for: metrics)
        case .liveActivity, .commandTray:
            let minNotchWidth: CGFloat = (!isFloating && metrics.hasHardwareNotch)
                ? (Self.collapsedWidth(for: metrics) + 16)
                : 0
            width = max(card.width + 32, minNotchWidth)
            height = card.height + 28
        }

        if isFloating {
            let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 875)
            let origin: NSPoint?
            if preserveTopAnchor, frame.height > 0 {
                origin = NSPoint(
                    x: round(frame.midX - width / 2),
                    y: frame.maxY - height
                )
            } else if let anchor = Self.loadFloatingAnchor() {
                origin = NSPoint(
                    x: round(anchor.x - width / 2),
                    y: anchor.y - height
                )
            } else {
                origin = nil
            }
            return Self.floatingFrame(visibleFrame: visibleFrame, width: width, height: height, savedOrigin: origin)
        }

        let screenFrame = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return Self.panelFrame(screenFrame: screenFrame, width: width, height: height)
    }

    private static func collapsedWidth(for metrics: NotchMetrics) -> CGFloat {
        let card = cardSize(for: .collapsed, metrics: metrics)
        if VoiceSettings.shared.hudLayoutStyle == .floatingPill {
            return card.width + 24
        }
        return card.width
    }

    private static func collapsedHeight(for metrics: NotchMetrics) -> CGFloat {
        let card = cardSize(for: .collapsed, metrics: metrics)
        if VoiceSettings.shared.hudLayoutStyle == .floatingPill {
            return card.height + 16
        }
        return card.height
    }

    private static func preferredScreen(containing panel: NSPanel? = nil) -> NSScreen? {
        if VoiceSettings.shared.hudLayoutStyle == .floatingPill,
           let panelScreen = panel?.screen {
            return panelScreen
        }
        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func measureScreen(_ screen: NSScreen?) -> (hasNotch: Bool, height: CGFloat, width: CGFloat) {
        guard let screen else { return (false, 34, 0) }
        let topInset = screen.safeAreaInsets.top
        let hasNotch = topInset > 0
        let height = hasNotch ? max(32, topInset) : 34
        let width: CGFloat
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            width = min(max(right.minX - left.maxX, 170), 220)
        } else {
            width = hasNotch ? 190 : 0
        }
        return (hasNotch, height, width)
    }
}
