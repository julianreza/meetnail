import AppKit
import Foundation
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

struct NailPalette: Sendable {
    let scheme: ColorScheme

    var isDark: Bool { scheme == .dark }

    // MARK: - Option A Spotlight Surfaces (Luminous Porcelain Light & Matte Obsidian Dark)

    var canvas: Color { isDark ? Color(hex: 0x0F1117) : Color(hex: 0xFBFBFD) }
    var canvasBottom: Color { isDark ? Color(hex: 0x0B0D12) : Color(hex: 0xF7F9FC) }
    var sidebar: Color { isDark ? Color(hex: 0x12151C) : Color(hex: 0xF8FAFC) }
    var card: Color { isDark ? Color(hex: 0x161922) : Color(hex: 0xFFFFFF) }
    var cardSecondary: Color { isDark ? Color(hex: 0x12151D) : Color(hex: 0xF8FAFC) }
    var row: Color { isDark ? Color(hex: 0x191D27) : Color(hex: 0xF4F6F9) }
    var raised: Color { isDark ? Color(hex: 0x1D212D) : Color(hex: 0xFFFFFF) }
    var cardElevated: Color { raised }
    var well: Color { isDark ? Color(hex: 0x11141B) : Color(hex: 0xF4F6F9) }
    var inputBg: Color { isDark ? Color(hex: 0x12151D) : Color(hex: 0xF8FAFC) }
    var hairline: Color { isDark ? Color.white.opacity(0.08) : Color(hex: 0x0F172A, alpha: 0.075) }
    var hairlineStrong: Color { isDark ? Color.white.opacity(0.14) : Color(hex: 0x0F172A, alpha: 0.12) }
    var specularTop: Color { isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.92) }
    var cardShadow: Color { isDark ? Color(hex: 0x000000, alpha: 0.45) : Color(hex: 0x0F172A, alpha: 0.06) }

    // MARK: - Surface Elevation & Subtle Shadow Tokens

    var neuShadowLight: Color { isDark ? Color(hex: 0x262C38).opacity(0.75) : Color.white.opacity(0.95) }
    var neuShadowDark: Color { isDark ? Color(hex: 0x07090D) : Color(hex: 0x94A3B8, alpha: 0.22) }
    var neuSurfaceTop: Color { isDark ? Color(hex: 0x191D28) : Color(hex: 0xFFFFFF) }
    var neuSurfaceBottom: Color { isDark ? Color(hex: 0x141720) : Color(hex: 0xFCFDFF) }
    var neuWellTop: Color { isDark ? Color(hex: 0x10131A) : Color(hex: 0xF4F6F9) }
    var neuWellBottom: Color { isDark ? Color(hex: 0x141821) : Color(hex: 0xF8FAFC) }

    var canvasGradient: LinearGradient {
        LinearGradient(colors: [canvas, canvasBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var neuSurfaceGradient: LinearGradient {
        LinearGradient(colors: [neuSurfaceTop, neuSurfaceBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var neuWellGradient: LinearGradient {
        LinearGradient(colors: [neuWellTop, neuWellBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Ink Card Tokens (Obsidian Featured Surface)

    var inkCard: Color { isDark ? Color(hex: 0x090B0E) : Color(hex: 0x0A0A0A) }
    var inkCardSurface: Color { isDark ? Color(hex: 0x12151B) : Color(hex: 0x141414) }
    var inkCardText: Color { Color(hex: 0xF0F0F0) }
    var inkCardMuted: Color { Color(hex: 0x9A9A9A) }
    var inkCardLine: Color { Color.white.opacity(0.10) }
    var inkCardTrack: Color { Color(hex: 0x2E2E2E) }
    var inkCardFill: Color { Color(hex: 0xF5F5F5) }

    // MARK: - Obsidian Ink Accent & High-Contrast Text

    var accent: Color { isDark ? Color(hex: 0xF8FAFC) : Color(hex: 0x111113) }
    var accentInk: Color { isDark ? Color(hex: 0x111113) : Color(hex: 0xFFFFFF) }
    var accentSoft: Color { isDark ? Color(hex: 0x232836) : Color(hex: 0xF1F5F9) }
    var textPrimary: Color { isDark ? Color(hex: 0xF5F6F8) : Color(hex: 0x111113) }
    var textSecondary: Color { isDark ? Color(hex: 0x9CA3AF) : Color(hex: 0x475569) }
    var textTertiary: Color { isDark ? Color(hex: 0x6B7280) : Color(hex: 0x64748B) }

    // MARK: - Backwards-Compatible Obsidian Accent Aliases (Remapped from Cobalt)

    var cobalt: Color { accent }
    var cobaltGlow: Color { accent.opacity(isDark ? 0.35 : 0.18) }
    var cobaltSoft: Color { accent.opacity(isDark ? 0.14 : 0.08) }

    // MARK: - Restrained Touch of Yellow / Amber Tokens

    var gold: Color { isDark ? Color(hex: 0xFBBF24) : Color(hex: 0xB45309) }
    var goldBright: Color { isDark ? Color(hex: 0xF59E0B) : Color(hex: 0xD97706) }
    var goldSoft: Color { isDark ? Color(hex: 0xF59E0B, alpha: 0.14) : Color(hex: 0xFFFBEB) }
    var goldBorder: Color { isDark ? Color(hex: 0xF59E0B, alpha: 0.35) : Color(hex: 0xD97706, alpha: 0.26) }

    // MARK: - Restrained Semantic Status

    var good: Color { isDark ? Color(hex: 0x34D399) : Color(hex: 0x059669) }
    var bad: Color { isDark ? Color(hex: 0xF87171) : Color(hex: 0xDC2626) }
    var warn: Color { isDark ? Color(hex: 0xFBBF24) : Color(hex: 0xD97706) }
    var info: Color { isDark ? Color(hex: 0xB8C0CC) : Color(hex: 0x475569) }

    var goodSoft: Color { isDark ? Color(hex: 0x10B981, alpha: 0.14) : Color(hex: 0xECFDF5) }
    var badSoft: Color { bad.opacity(isDark ? 0.16 : 0.10) }
    var warnSoft: Color { warn.opacity(isDark ? 0.15 : 0.10) }
    var infoSoft: Color { info.opacity(isDark ? 0.15 : 0.10) }

    // MARK: - Compatibility Aliases

    var indigo: Color { accent }
    var cyan: Color { textSecondary }
    var violet: Color { textSecondary }
    var meetGreen: Color { textPrimary }
    var teamsPurple: Color { textPrimary }
    var danger: Color { bad }
    var amber: Color { warn }
    var emerald: Color { good }

    var brandGradient: LinearGradient {
        LinearGradient(colors: [accent, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var subtleBrandTint: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
}

// MARK: - macOS Native Vibrancy Wrapper

struct MacVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .followsWindowActiveState
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material {
            nsView.material = material
        }
        if nsView.blendingMode != blendingMode {
            nsView.blendingMode = blendingMode
        }
        if nsView.state != state {
            nsView.state = state
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSVisualEffectView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }
}

// MARK: - 60fps Fluid Acoustic Canvas

enum FluidAcousticStyle: Sendable {
    case wave
    case aurora
    case minimal
}

struct FluidAcousticCanvas: View {
    var style: FluidAcousticStyle = .wave
    var phase: Double
    var speakingEnergy: Double
    var listeningEnergy: Double
    var accentColor: Color = Color(hex: 0x0A0A0A)
    var monochromePrimary: Color = Color(hex: 0xF5F5F5)
    var monochromeSecondary: Color = Color(hex: 0x8E8E8E)
    var height: CGFloat = 44

    init(
        style: FluidAcousticStyle = .wave,
        phase: Double,
        speakingEnergy: Double,
        listeningEnergy: Double,
        accentColor: Color = Color(hex: 0x0A0A0A),
        monochromePrimary: Color = Color(hex: 0xF5F5F5),
        monochromeSecondary: Color = Color(hex: 0x8E8E8E),
        height: CGFloat = 44
    ) {
        self.style = style
        self.phase = phase
        self.speakingEnergy = speakingEnergy
        self.listeningEnergy = listeningEnergy
        self.accentColor = accentColor
        self.monochromePrimary = monochromePrimary
        self.monochromeSecondary = monochromeSecondary
        self.height = height
    }

    var body: some View {
        let currentStyle = style
        let currentPhase = phase
        let speaking = min(max(speakingEnergy, 0), 1)
        let listening = min(max(listeningEnergy, 0), 1)
        let combined = max(speaking, listening)
        let primaryColor = monochromePrimary
        let secondaryColor = monochromeSecondary
        let surgicalAccent = accentColor

        Canvas(rendersAsynchronously: true) { context, size in
            let width = max(size.width, 1)
            let midY = size.height * 0.5
            let maxAmp = size.height * 0.40

            switch currentStyle {
            case .wave:
                // Calm baseline hairline
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: midY))
                baseline.addLine(to: CGPoint(x: width, y: midY))
                context.stroke(
                    baseline,
                    with: .color(secondaryColor.opacity(0.18)),
                    lineWidth: 0.75
                )

                // Soft monochrome secondary wave (1.2pt)
                let secondaryAmp = maxAmp * (0.14 + listening * 0.55 + speaking * 0.25)
                let secondaryPath = Self.makeWavePath(
                    width: width,
                    midY: midY,
                    amplitude: secondaryAmp,
                    frequency: 2.2,
                    phase: -currentPhase * 1.15 + 0.9,
                    secondaryFreq: 4.1,
                    secondaryWeight: 0.22
                )
                context.stroke(
                    secondaryPath,
                    with: .color(secondaryColor.opacity(0.42 + combined * 0.26)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )

                // Harmonic accent wave (1.4pt) scaling smoothly with active energy
                let cobaltAmp = maxAmp * (0.10 + combined * 0.74)
                let cobaltOpacity = 0.08 + combined * 0.78
                let cobaltPath = Self.makeWavePath(
                    width: width,
                    midY: midY,
                    amplitude: cobaltAmp,
                    frequency: 3.1,
                    phase: currentPhase * 1.55 + 1.85,
                    secondaryFreq: 5.4,
                    secondaryWeight: 0.28
                )
                context.stroke(
                    cobaltPath,
                    with: .color(surgicalAccent.opacity(cobaltOpacity)),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                )

                // Crisp monochrome primary wave (1.8pt)
                let primaryAmp = maxAmp * (0.18 + speaking * 0.78 + listening * 0.42)
                let primaryPath = Self.makeWavePath(
                    width: width,
                    midY: midY,
                    amplitude: primaryAmp,
                    frequency: 2.6,
                    phase: currentPhase * 1.35,
                    secondaryFreq: 4.8,
                    secondaryWeight: 0.18
                )
                context.stroke(
                    primaryPath,
                    with: .color(primaryColor.opacity(0.90)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )

            case .aurora:
                // Soft monochrome studio light ribbon
                let ribbonAmp = maxAmp * (0.20 + combined * 0.68)
                let ribbonPath = Self.makeRibbonPath(
                    width: width,
                    midY: midY,
                    amplitude: ribbonAmp,
                    phase: currentPhase
                )
                context.fill(
                    ribbonPath,
                    with: .color(primaryColor.opacity(0.10 + combined * 0.15))
                )

                // Secondary subtle contour
                let contourPath = Self.makeWavePath(
                    width: width,
                    midY: midY,
                    amplitude: ribbonAmp * 0.65,
                    frequency: 1.9,
                    phase: -currentPhase * 0.9,
                    secondaryFreq: 3.3,
                    secondaryWeight: 0.20
                )
                context.stroke(
                    contourPath,
                    with: .color(secondaryColor.opacity(0.35 + combined * 0.25)),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                )

                // Whisper-thin center horizon shimmer proportional to active energy
                let shimmerPath = Self.makeWavePath(
                    width: width,
                    midY: midY,
                    amplitude: ribbonAmp * 0.42,
                    frequency: 2.4,
                    phase: currentPhase * 1.25 + 0.6,
                    secondaryFreq: 4.2,
                    secondaryWeight: 0.15
                )
                context.stroke(
                    shimmerPath,
                    with: .color(surgicalAccent.opacity(0.10 + combined * 0.75)),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                )

                // Crisp monochrome center horizon
                let centerCrest = Self.makeWavePath(
                    width: width,
                    midY: midY,
                    amplitude: ribbonAmp * 0.82,
                    frequency: 2.1,
                    phase: currentPhase * 1.1,
                    secondaryFreq: 3.8,
                    secondaryWeight: 0.16
                )
                context.stroke(
                    centerCrest,
                    with: .color(primaryColor.opacity(0.78)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )

            case .minimal:
                // Ultra-crisp monochrome baseline (1.5pt)
                var baseLine = Path()
                baseLine.move(to: CGPoint(x: 0, y: midY))
                baseLine.addLine(to: CGPoint(x: width, y: midY))
                context.stroke(
                    baseLine,
                    with: .color(secondaryColor.opacity(0.28)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )

                // Faint harmonic core glint
                let glintAmp = maxAmp * (0.06 + combined * 0.42)
                let glintPath = Self.makeWavePath(
                    width: width,
                    midY: midY,
                    amplitude: glintAmp,
                    frequency: 2.0,
                    phase: currentPhase * 1.4 + 1.1,
                    secondaryFreq: 3.6,
                    secondaryWeight: 0.15,
                    gaussianSharpness: 6.5
                )
                context.stroke(
                    glintPath,
                    with: .color(surgicalAccent.opacity(0.12 + combined * 0.72)),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                )

                // Refined center breathing pulse in monochromePrimary
                let pulseAmp = maxAmp * (0.10 + combined * 0.56)
                let pulsePath = Self.makeWavePath(
                    width: width,
                    midY: midY,
                    amplitude: pulseAmp,
                    frequency: 1.8,
                    phase: currentPhase * 1.1,
                    secondaryFreq: 3.2,
                    secondaryWeight: 0.12,
                    gaussianSharpness: 5.2
                )
                context.stroke(
                    pulsePath,
                    with: .color(primaryColor.opacity(0.88)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private static func makeWavePath(
        width: CGFloat,
        midY: CGFloat,
        amplitude: CGFloat,
        frequency: Double,
        phase: Double,
        secondaryFreq: Double,
        secondaryWeight: Double,
        gaussianSharpness: Double = 3.4
    ) -> Path {
        var path = Path()
        let steps = max(Int(width / 2.5), 48)
        for i in 0...steps {
            let progress = Double(i) / Double(steps)
            let x = CGFloat(progress) * width
            let norm = progress * 2.0 - 1.0
            let envelope = exp(-gaussianSharpness * norm * norm)
            let primarySine = sin(progress * .pi * 2.0 * frequency + phase)
            let harmonicSine = sin(progress * .pi * 2.0 * secondaryFreq - phase * 0.75)
            let combinedWave = (primarySine * (1.0 - secondaryWeight) + harmonicSine * secondaryWeight) * envelope
            let y = midY + CGFloat(combinedWave) * amplitude
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private static func makeRibbonPath(
        width: CGFloat,
        midY: CGFloat,
        amplitude: CGFloat,
        phase: Double
    ) -> Path {
        var path = Path()
        let steps = max(Int(width / 3.0), 40)
        for i in 0...steps {
            let progress = Double(i) / Double(steps)
            let x = CGFloat(progress) * width
            let norm = progress * 2.0 - 1.0
            let envelope = exp(-3.2 * norm * norm)
            let topOffset = (sin(progress * .pi * 4.0 + phase) * 0.7 + cos(progress * .pi * 2.5 - phase * 0.8) * 0.3) * envelope
            let y = midY - abs(CGFloat(topOffset) * amplitude) - 1.5
            if i == 0 {
                path.move(to: CGPoint(x: x, y: midY))
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let progress = Double(i) / Double(steps)
            let x = CGFloat(progress) * width
            let norm = progress * 2.0 - 1.0
            let envelope = exp(-3.2 * norm * norm)
            let bottomOffset = (sin(progress * .pi * 3.6 - phase * 0.9) * 0.7 + cos(progress * .pi * 2.2 + phase) * 0.3) * envelope
            let y = midY + abs(CGFloat(bottomOffset) * amplitude) + 1.5
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Motion Modifiers

private struct NailHoverLiftModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let cornerRadius: CGFloat
    let highlightCobalt: Bool

    func body(content: Content) -> some View {
        let palette = NailPalette(scheme: colorScheme)
        let borderColor: Color = {
            guard isHovered else { return .clear }
            return highlightCobalt ? palette.cobalt.opacity(0.45) : palette.hairlineStrong
        }()

        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .scaleEffect(isHovered && !reduceMotion ? 1.006 : 1.0)
            .shadow(
                color: isHovered
                    ? (highlightCobalt ? palette.cobaltGlow.opacity(0.22) : palette.cardShadow.opacity(palette.isDark ? 0.55 : 0.85))
                    : Color.clear,
                radius: isHovered ? 12 : 0,
                x: 0,
                y: isHovered ? 4 : 0
            )
            .onHover { hovering in
                if reduceMotion {
                    isHovered = hovering
                } else {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        isHovered = hovering
                    }
                }
            }
    }
}

private struct NailStaggeredEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1.0 : 0.0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else if !appeared {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84).delay(delay)) {
                        appeared = true
                    }
                }
            }
    }
}

extension View {
    func nailHoverLift(cornerRadius: CGFloat = 20, highlightCobalt: Bool = false) -> some View {
        modifier(NailHoverLiftModifier(cornerRadius: cornerRadius, highlightCobalt: highlightCobalt))
    }

    func nailStaggeredEntrance(delay: Double = 0) -> some View {
        modifier(NailStaggeredEntranceModifier(delay: delay))
    }
}

// MARK: - Elevated macOS Surfaces & Inset Wells

enum TalmoCardSurface: Sendable {
    case card
    case secondary
    case raised
}

struct TalmoCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 20
    var surface: TalmoCardSurface = .card
    @ViewBuilder var content: () -> Content

    init(
        padding: CGFloat = 20,
        cornerRadius: CGFloat = 20,
        surface: TalmoCardSurface = .card,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.surface = surface
        self.content = content
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)
        let fillGradient: LinearGradient = switch surface {
        case .card:
            LinearGradient(
                colors: [palette.card, palette.neuSurfaceBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        case .secondary:
            LinearGradient(
                colors: [
                    palette.cardSecondary,
                    palette.isDark ? Color(hex: 0x10131A) : palette.row
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .raised:
            LinearGradient(
                colors: [
                    palette.raised,
                    palette.isDark ? Color(hex: 0x191D28) : palette.neuSurfaceBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillGradient)
                    .shadow(
                        color: palette.isDark
                            ? Color.black.opacity(0.24)
                            : Color(hex: 0x0F172A, alpha: 0.035),
                        radius: 3,
                        x: 0,
                        y: 1
                    )
                    .shadow(
                        color: palette.cardShadow,
                        radius: 14,
                        x: 0,
                        y: 6
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.hairline, lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: max(cornerRadius - 1, 0), style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(palette.isDark ? 0.07 : 0.85),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: UnitPoint(x: 0.5, y: 0.28)
                                ),
                                lineWidth: 1
                            )
                            .padding(1)
                    }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
                value: colorScheme
            )
    }
}

struct NeuWell<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: () -> Content

    init(
        padding: CGFloat = 14,
        cornerRadius: CGFloat = 18,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)

        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.neuWellTop, palette.neuWellBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        palette.isDark
                                            ? Color.black.opacity(0.22)
                                            : Color(hex: 0x0F172A, alpha: 0.03),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: UnitPoint(x: 0.5, y: 0.35)
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                palette.isDark ? palette.hairline : palette.hairlineStrong,
                                lineWidth: 1
                            )
                    }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
                value: colorScheme
            )
    }
}

struct NeuAcousticDial<CenterContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 148
    var isActive: Bool = false
    var showYellowSpark: Bool = true
    @ViewBuilder var center: () -> CenterContent

    init(
        size: CGFloat = 148,
        isActive: Bool = false,
        showYellowSpark: Bool = true,
        @ViewBuilder center: @escaping () -> CenterContent
    ) {
        self.size = size
        self.isActive = isActive
        self.showYellowSpark = showYellowSpark
        self.center = center
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)
        let ringSize = max(size - 12, 24)
        let wellSize = size * 0.76
        let tickRadius = (ringSize + wellSize) * 0.25
        let arcLineWidth = max(2.2, min(3.0, size * 0.017))

        ZStack {
            // 1. Sculpted luminous porcelain outer bezel
            Circle()
                .fill(
                    LinearGradient(
                        colors: palette.isDark
                            ? [Color(hex: 0x1D222E), Color(hex: 0x151922)]
                            : [Color.white, Color(hex: 0xF8FAFC)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .shadow(
                    color: Color.black.opacity(palette.isDark ? 0.34 : 0.06),
                    radius: 14,
                    x: 0,
                    y: 5
                )
                .overlay {
                    Circle()
                        .strokeBorder(palette.hairline, lineWidth: 1)
                }

            // 2. Crisp dial hairline track, cardinal ticks, and emerald-to-gold studio aura spark arc
            Circle()
                .strokeBorder(palette.hairline, lineWidth: 1)
                .frame(width: ringSize, height: ringSize)

            ForEach(0..<4, id: \.self) { idx in
                Capsule(style: .continuous)
                    .fill(palette.hairlineStrong.opacity(0.60))
                    .frame(width: 1, height: max(3.0, size * 0.026))
                    .offset(y: -tickRadius)
                    .rotationEffect(.degrees(Double(idx) * 90))
            }

            if showYellowSpark {
                Circle()
                    .trim(from: 0.0, to: 0.30)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: palette.good.opacity(isActive ? 0.98 : 0.88),
                                    location: 0.0
                                ),
                                .init(
                                    color: palette.good.opacity(isActive ? 0.96 : 0.84),
                                    location: 0.68
                                ),
                                .init(
                                    color: palette.goldBright.opacity(isActive ? 0.96 : 0.84),
                                    location: 0.90
                                ),
                                .init(
                                    color: palette.goldBright.opacity(isActive ? 0.96 : 0.84),
                                    location: 1.0
                                ),
                            ],
                            startPoint: .trailing,
                            endPoint: UnitPoint(x: 0.35, y: 0.98)
                        ),
                        style: StrokeStyle(lineWidth: arcLineWidth, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)
                    .shadow(
                        color: palette.good.opacity(isActive ? 0.34 : 0.08),
                        radius: isActive ? 5 : 1.5
                    )
                    .rotationEffect(.degrees(-88))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.25),
                        value: isActive
                    )
            }

            // 3. Soft recessed inner porcelain well
            Circle()
                .fill(
                    LinearGradient(
                        colors: palette.isDark
                            ? [Color(hex: 0x12161E), Color(hex: 0x171C26)]
                            : [Color(hex: 0xF4F7FB), Color.white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: wellSize, height: wellSize)
                .overlay {
                    Circle()
                        .strokeBorder(palette.hairline, lineWidth: 1)
                }

            // 4. Subtle ambient ground shadow ellipse + floating center() inside the well
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                palette.isDark
                                    ? Color.black.opacity(0.45)
                                    : Color(hex: 0x0F172A, alpha: 0.10),
                                palette.isDark
                                    ? Color.black.opacity(0.16)
                                    : Color(hex: 0x0F172A, alpha: 0.035),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: wellSize * 0.24
                        )
                    )
                    .frame(width: wellSize * 0.46, height: wellSize * 0.11)
                    .blur(radius: max(1.6, size * 0.016))
                    .offset(y: wellSize * 0.34)

                center()
            }
            .frame(width: wellSize, height: wellSize)
        }
        .frame(width: size, height: size)
        .animation(
            reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
            value: colorScheme
        )
    }
}

struct TalmoInkCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: () -> Content

    init(
        padding: CGFloat = 20,
        cornerRadius: CGFloat = 20,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)

        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.inkCard)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.045), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(palette.isDark ? 0.55 : 0.22),
                        radius: 18,
                        x: 0,
                        y: 8
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.inkCardLine, lineWidth: 1)
                    }
            }
    }
}

struct NailGlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 20
    var elevated: Bool = false
    @ViewBuilder var content: () -> Content

    init(
        padding: CGFloat = 20,
        cornerRadius: CGFloat = 20,
        elevated: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.content = content
    }

    var body: some View {
        TalmoCard(
            padding: padding,
            cornerRadius: cornerRadius,
            surface: elevated ? .raised : .card,
            content: content
        )
    }
}

// MARK: - Page Header

struct TalmoPageHeader<Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)

        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Capsule(style: .continuous)
                            .fill(palette.accent)
                            .frame(width: 20, height: 2.5)

                        Capsule(style: .continuous)
                            .fill(palette.goldBright)
                            .frame(width: 6, height: 2.5)
                    }
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
    }
}

extension TalmoPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

// MARK: - Segmented Pill

struct TalmoSegmentedPill<Option: Identifiable & Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace

    let options: [Option]
    @Binding var selection: Option
    var compact: Bool = false
    var icon: ((Option) -> String?)? = nil
    var badge: ((Option) -> String?)? = nil
    var dotColor: ((Option) -> Color?)? = nil
    var label: (Option) -> String

    init(
        options: [Option],
        selection: Binding<Option>,
        compact: Bool = false,
        icon: ((Option) -> String?)? = nil,
        badge: ((Option) -> String?)? = nil,
        dotColor: ((Option) -> Color?)? = nil,
        label: @escaping (Option) -> String
    ) {
        self.options = options
        self._selection = selection
        self.compact = compact
        self.icon = icon
        self.badge = badge
        self.dotColor = dotColor
        self.label = label
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)
        let trackRadius: CGFloat = compact ? 12 : 15
        let pillRadius: CGFloat = compact ? 9.5 : 11.5

        HStack(spacing: compact ? 3 : 5) {
            ForEach(options) { option in
                let isSelected = selection == option
                let optionIcon = icon?(option)
                let optionBadge = badge?(option)
                let optionDot = dotColor?(option)

                Button {
                    if reduceMotion {
                        selection = option
                    } else {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                            selection = option
                        }
                    }
                } label: {
                    HStack(spacing: compact ? 5 : 7) {
                        if let optionDot {
                            Circle()
                                .fill(optionDot)
                                .frame(width: compact ? 6 : 6.5, height: compact ? 6 : 6.5)
                        } else if isSelected && !compact && optionIcon == nil {
                            Circle()
                                .fill(palette.goldBright)
                                .frame(width: 6, height: 6)
                        }

                        if let optionIcon {
                            Image(systemName: optionIcon)
                                .font(.system(size: compact ? 11 : 12.5, weight: .semibold))
                        }

                        Text(label(option))
                            .font(.system(size: compact ? 12 : 13, weight: isSelected ? .bold : .semibold))
                            .lineLimit(1)

                        if let optionBadge, !optionBadge.isEmpty {
                            Text(optionBadge)
                                .font(.system(size: compact ? 10 : 10.5, weight: .bold, design: .rounded))
                                .padding(.horizontal, compact ? 5 : 6)
                                .padding(.vertical, 1.5)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(badgeBackground(isSelected: isSelected, palette: palette))
                                }
                                .foregroundStyle(badgeForeground(isSelected: isSelected, palette: palette))
                        }
                    }
                    .foregroundStyle(segmentForeground(isSelected: isSelected, palette: palette))
                    .padding(.horizontal, compact ? 11 : 15)
                    .padding(.vertical, compact ? 6 : 8)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                                .fill(palette.isDark ? palette.accentSoft : Color.white)
                                .shadow(
                                    color: palette.isDark
                                        ? Color.black.opacity(0.32)
                                        : Color(hex: 0x0F172A, alpha: 0.07),
                                    radius: compact ? 3 : 4,
                                    x: 0,
                                    y: 1.5
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                                        .strokeBorder(
                                            palette.isDark
                                                ? Color.white.opacity(0.12)
                                                : palette.hairlineStrong,
                                            lineWidth: 1
                                        )
                                }
                                .matchedGeometryEffect(id: "TalmoActiveSegment", in: pillNamespace)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: pillRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(compact ? 3.5 : 4.5)
        .background {
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .fill(palette.well)
                .overlay {
                    RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                        .strokeBorder(
                            palette.isDark ? palette.hairline : palette.hairlineStrong,
                            lineWidth: 1
                        )
                }
        }
    }

    private func segmentForeground(isSelected: Bool, palette: NailPalette) -> Color {
        if isSelected {
            return palette.textPrimary
        }
        return palette.textSecondary
    }

    private func badgeBackground(isSelected: Bool, palette: NailPalette) -> Color {
        if isSelected {
            return palette.accent.opacity(palette.isDark ? 0.18 : 0.10)
        }
        return palette.well.opacity(0.85)
    }

    private func badgeForeground(isSelected: Bool, palette: NailPalette) -> Color {
        if isSelected {
            return palette.textPrimary
        }
        return palette.textSecondary
    }
}

// MARK: - Circle Icon Button

struct TalmoCircleIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var systemImage: String
    var isActive: Bool = false
    var badgeText: String? = nil
    var dotColor: Color? = nil
    var onInk: Bool = false
    var size: CGFloat = 34
    var helpText: String = ""
    var action: () -> Void

    init(
        systemImage: String,
        isActive: Bool = false,
        badgeText: String? = nil,
        dotColor: Color? = nil,
        onInk: Bool = false,
        size: CGFloat = 34,
        helpText: String = "",
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.isActive = isActive
        self.badgeText = badgeText
        self.dotColor = dotColor
        self.onInk = onInk
        self.size = size
        self.helpText = helpText
        self.action = action
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)

        Button(action: action) {
            ZStack {
                Circle()
                    .fill(circleFill(palette: palette))
                    .shadow(
                        color: onInk
                            ? .clear
                            : (palette.isDark ? Color.black.opacity(0.28) : Color(hex: 0x0F172A, alpha: 0.06)),
                        radius: 4,
                        x: 0,
                        y: 1.5
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(circleBorder(palette: palette), lineWidth: 1)
                    }

                Image(systemName: systemImage)
                    .font(.system(size: size * 0.41, weight: .semibold))
                    .foregroundStyle(iconForeground(palette: palette))
            }
            .frame(width: size, height: size)
            .scaleEffect(isHovered && !reduceMotion ? 1.03 : 1.0)
            .overlay(alignment: .topTrailing) {
                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(onInk ? Color(hex: 0x0A0A0A) : palette.accentInk)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(onInk ? palette.inkCardFill : palette.accent)
                        }
                        .offset(x: 4, y: -3)
                } else if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .strokeBorder(onInk ? palette.inkCard : palette.card, lineWidth: 1.5)
                        }
                        .offset(x: 1, y: -1)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
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

    private func circleFill(palette: NailPalette) -> AnyShapeStyle {
        if onInk {
            if isActive {
                return AnyShapeStyle(palette.inkCardFill)
            }
            return AnyShapeStyle(isHovered ? Color.white.opacity(0.14) : palette.inkCardSurface)
        }
        if isActive {
            return AnyShapeStyle(palette.accent)
        }
        return AnyShapeStyle(
            palette.isDark
                ? (isHovered ? palette.accentSoft : palette.raised)
                : (isHovered ? palette.accentSoft : Color.white)
        )
    }

    private func circleBorder(palette: NailPalette) -> Color {
        if onInk {
            return isActive ? Color.clear : (isHovered ? Color.white.opacity(0.22) : palette.inkCardLine)
        }
        return isActive
            ? Color.clear
            : (isHovered ? palette.hairlineStrong : (palette.isDark ? palette.hairline : palette.hairlineStrong))
    }

    private func iconForeground(palette: NailPalette) -> Color {
        if onInk {
            return isActive ? Color(hex: 0x0A0A0A) : palette.inkCardText
        }
        return isActive ? palette.accentInk : palette.textPrimary
    }
}

// MARK: - Pill Button Style

enum NailPillVariant {
    case primary
    case secondary
    case inkPrimary
    case inkSecondary
    case inkDanger
    case danger
    case ghost
    case tinted(Color)
}

struct NailPillButtonStyle: ButtonStyle {
    var variant: NailPillVariant = .secondary
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, variant: variant, compact: compact)
    }

    private struct PillBody: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        let configuration: Configuration
        let variant: NailPillVariant
        let compact: Bool

        private var isPrimaryVariant: Bool {
            if case .primary = variant { return true }
            return false
        }

        var body: some View {
            let palette = NailPalette(scheme: colorScheme)
            configuration.label
                .font(compact ? .caption.weight(.bold) : .callout.weight(.bold))
                .lineLimit(1)
                .foregroundStyle(foregroundColor(palette: palette))
                .padding(.horizontal, compact ? 12 : 16)
                .padding(.vertical, compact ? 6 : 9)
                .background {
                    backgroundShape(palette: palette)
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1.0) : (isPrimaryVariant ? 1.0 : 0.42))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72),
                    value: configuration.isPressed
                )
                .onHover { hovering in
                    if reduceMotion {
                        isHovered = hovering
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHovered = hovering
                        }
                    }
                }
        }

        private func foregroundColor(palette: NailPalette) -> Color {
            switch variant {
            case .primary:
                return isEnabled ? palette.accentInk : palette.textTertiary
            case .secondary, .ghost:
                return palette.textPrimary
            case .inkPrimary:
                return Color(hex: 0x0A0A0A)
            case .inkSecondary:
                return palette.inkCardText
            case .inkDanger:
                return Color(hex: 0xF08A80)
            case .danger:
                return palette.bad
            case .tinted(let color):
                return color
            }
        }

        @ViewBuilder
        private func backgroundShape(palette: NailPalette) -> some View {
            let cornerRadius: CGFloat = compact ? 11 : 14

            switch variant {
            case .primary:
                if isEnabled {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            palette.isDark
                                ? (isHovered ? Color.white : Color(hex: 0xF8FAFC))
                                : (isHovered ? Color(hex: 0x1E1F23) : Color(hex: 0x111113))
                        )
                        .shadow(
                            color: palette.isDark
                                ? Color.black.opacity(0.32)
                                : Color(hex: 0x0F172A, alpha: 0.16),
                            radius: compact ? 4 : 7,
                            x: 0,
                            y: compact ? 2 : 3
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    Color.white.opacity(palette.isDark ? 0.35 : 0.12),
                                    lineWidth: 1
                                )
                        }
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.isDark ? Color(hex: 0x252A36) : Color(hex: 0xE5E7EB))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    palette.isDark ? palette.hairline : palette.hairlineStrong,
                                    lineWidth: 1
                                )
                        }
                }

            case .secondary:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        palette.isDark
                            ? (isHovered && isEnabled ? palette.accentSoft : palette.raised)
                            : (isHovered && isEnabled ? palette.cardSecondary : Color.white)
                    )
                    .shadow(
                        color: Color(hex: 0x0F172A, alpha: palette.isDark ? 0.28 : 0.045),
                        radius: compact ? 3 : 5,
                        x: 0,
                        y: 1.5
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.hairlineStrong, lineWidth: 1)
                    }

            case .inkPrimary:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.inkCardFill)

            case .inkSecondary:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.14 : 0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.inkCardLine, lineWidth: 1)
                    }

            case .inkDanger:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(hex: 0xF08A80).opacity(isHovered ? 0.24 : 0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color(hex: 0xF08A80).opacity(0.38), lineWidth: 1)
                    }

            case .danger:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isHovered && isEnabled
                            ? palette.bad.opacity(palette.isDark ? 0.22 : 0.16)
                            : palette.badSoft
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                palette.bad.opacity(isHovered && isEnabled ? 0.48 : 0.32),
                                lineWidth: 1
                            )
                    }

            case .ghost:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? palette.hairline : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.hairlineStrong, lineWidth: 1)
                    }

            case .tinted(let color):
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color.opacity(palette.isDark ? 0.16 : 0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(color.opacity(isHovered ? 0.45 : 0.32), lineWidth: 1)
                    }
            }
        }
    }
}

// MARK: - Marks, Badges & Section Titles

enum NailBrandLogo {
    @MainActor
    static func menuBarTemplateImage(isActive: Bool = false) -> NSImage {
        let active = isActive
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let cgContext = NSGraphicsContext.current?.cgContext else {
                return false
            }

            cgContext.saveGState()
            defer { cgContext.restoreGState() }

            cgContext.setAllowsAntialiasing(true)
            cgContext.setShouldAntialias(true)

            // Isolate cutouts inside a transparency layer so .clear never erases behind the icon.
            cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { cgContext.endTransparencyLayer() }

            let owlWidth: CGFloat = 13.6
            let owlHeight: CGFloat = 14.0
            let owlOriginX = rect.midX - owlWidth * 0.5 - (active ? 0.45 : 0)
            let owlOriginY = rect.midY - owlHeight * 0.5
            let owlRect = CGRect(x: owlOriginX, y: owlOriginY, width: owlWidth, height: owlHeight)

            // 1. Solid Noko-Owl sculpted rounded ear-tuft silhouette
            let silhouette = NokoOwlSilhouetteShape.cgPath(in: owlRect, flipY: true)
            cgContext.setFillColor(NSColor.black.cgColor)
            cgContext.addPath(silhouette)
            cgContext.fillPath()

            // 2. Crisp cutout rounded-pill eye visor + sleek curved smile arc
            let visorWidth = owlWidth * 0.76
            let visorHeight = owlHeight * 0.31
            let visorCenterY = owlRect.minY + (1.0 - 0.45) * owlHeight
            let visorRect = CGRect(
                x: owlRect.midX - visorWidth * 0.5,
                y: visorCenterY - visorHeight * 0.5,
                width: visorWidth,
                height: visorHeight
            )
            let visorPath = CGPath(
                roundedRect: visorRect,
                cornerWidth: visorHeight * 0.5,
                cornerHeight: visorHeight * 0.5,
                transform: nil
            )

            cgContext.setBlendMode(.clear)
            cgContext.addPath(visorPath)
            cgContext.fillPath()

            // Cutout sleek curved acoustic smile arc centered beneath the visor
            let smileHalfW: CGFloat = 1.90
            let smileTopY = visorRect.minY - 1.45
            let smileControlY = smileTopY - 1.45
            let smilePath = CGMutablePath()
            smilePath.move(to: CGPoint(x: owlRect.midX - smileHalfW, y: smileTopY))
            smilePath.addQuadCurve(
                to: CGPoint(x: owlRect.midX + smileHalfW, y: smileTopY),
                control: CGPoint(x: owlRect.midX, y: smileControlY)
            )
            cgContext.setLineWidth(1.22)
            cgContext.setLineCap(.round)
            cgContext.addPath(smilePath)
            cgContext.strokePath()

            // 3. Solid crisp round geometric eyes inside the cutout visor
            cgContext.setBlendMode(.normal)
            cgContext.setFillColor(NSColor.black.cgColor)

            let eyeDiameter: CGFloat = 2.20
            let eyeSpacingHalf: CGFloat = 2.15
            let leftEyeRect = CGRect(
                x: owlRect.midX - eyeSpacingHalf - eyeDiameter * 0.5,
                y: visorCenterY - eyeDiameter * 0.5,
                width: eyeDiameter,
                height: eyeDiameter
            )
            let rightEyeRect = CGRect(
                x: owlRect.midX + eyeSpacingHalf - eyeDiameter * 0.5,
                y: visorCenterY - eyeDiameter * 0.5,
                width: eyeDiameter,
                height: eyeDiameter
            )
            cgContext.fillEllipse(in: leftEyeRect)
            cgContext.fillEllipse(in: rightEyeRect)

            // 4. Subtle active status indicator dot at top-right when live session is active
            if active {
                let dotDiameter: CGFloat = 2.8
                let dotRect = CGRect(
                    x: rect.maxX - dotDiameter - 0.65,
                    y: rect.maxY - dotDiameter - 0.85,
                    width: dotDiameter,
                    height: dotDiameter
                )
                cgContext.fillEllipse(in: dotRect)
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}

struct NailOrbMark: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringExpanded = false

    var size: CGFloat = 30
    var isActive: Bool = false
    var onInk: Bool = false

    init(size: CGFloat = 30, isActive: Bool = false, onInk: Bool = false) {
        self.size = size
        self.isActive = isActive
        self.onInk = onInk
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)
        let medallionTop = onInk
            ? Color(hex: 0xF3F6FA)
            : (palette.isDark ? Color(hex: 0x222733) : Color(hex: 0x1A1E26))
        let medallionBottom = onInk
            ? Color(hex: 0xDCE4EE)
            : (palette.isDark ? Color(hex: 0x0C0F15) : Color(hex: 0x0A0A0A))
        let ringColor = onInk ? palette.inkCardFill : palette.accent

        let owlH = size * 0.67
        let owlW = owlH * 0.97
        let visorW = owlW * 0.75
        let visorH = owlH * 0.32
        let eyeSize = max(1.6, owlH * 0.145)
        let eyeSpacing = owlW * 0.20
        let smileW = max(2.8, owlW * 0.21)
        let smileH = max(0.95, owlH * 0.068)

        ZStack {
            if isActive {
                Circle()
                    .strokeBorder(palette.goldBright.opacity(ringExpanded ? 0.18 : 0.52), lineWidth: 1.2)
                    .frame(width: size * 1.38, height: size * 1.38)
                    .scaleEffect(ringExpanded ? 1.10 : 0.94)

                Circle()
                    .strokeBorder(ringColor.opacity(ringExpanded ? 0.14 : 0.34), lineWidth: 1.4)
                    .frame(width: size * 1.24, height: size * 1.24)
                    .scaleEffect(ringExpanded ? 1.08 : 0.96)
            }

            // Medallion circle (obsidian on porcelain canvas; porcelain on dark ink cards)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [medallionTop, medallionBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    onInk
                                        ? Color.white.opacity(0.88)
                                        : Color.white.opacity(palette.isDark ? 0.22 : 0.18),
                                    onInk
                                        ? Color(hex: 0xB8C5D6, alpha: 0.55)
                                        : (isActive ? palette.goldBright.opacity(0.45) : palette.hairlineStrong),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(0.75, size * 0.028)
                        )
                }

            // Crisp miniature sculpted Noko-Owl emblem inside the medallion
            ZStack {
                NokoOwlSilhouetteShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xFAFBFD),
                                Color(hex: 0xECF0F5),
                                Color(hex: 0xD7E1EC),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        NokoOwlSilhouetteShape()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.95),
                                        Color(hex: 0xB6C4D5, alpha: 0.65),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: max(0.45, size * 0.022)
                            )
                    }
                    .shadow(
                        color: Color(hex: 0x0A0E16, alpha: onInk ? 0.28 : 0.38),
                        radius: max(0.8, size * 0.045),
                        x: 0,
                        y: max(0.4, size * 0.025)
                    )

                // Matte-obsidian pill eye visor
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x181C24), Color(hex: 0x090A0D)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: visorW, height: visorH)
                    .overlay {
                        HStack(spacing: eyeSpacing) {
                            ForEach(0..<2, id: \.self) { _ in
                                ZStack {
                                    if isActive {
                                        Circle()
                                            .stroke(
                                                palette.goldBright.opacity(0.85),
                                                lineWidth: max(0.55, size * 0.024)
                                            )
                                            .frame(width: eyeSize * 1.55, height: eyeSize * 1.55)
                                    }
                                    Circle()
                                        .fill(Color(hex: 0xF8FAFC))
                                        .frame(width: eyeSize, height: eyeSize)
                                }
                            }
                        }
                    }
                    .offset(y: -owlH * 0.055)

                // Sleek matte-obsidian curved acoustic smile with warm-yellow micro-core accent
                ZStack {
                    NokoSmileArcShape(inverted: false)
                        .stroke(
                            Color(hex: 0x141922),
                            style: StrokeStyle(
                                lineWidth: max(0.85, size * 0.036),
                                lineCap: .round
                            )
                        )
                        .frame(width: smileW, height: smileH)

                    Capsule(style: .continuous)
                        .fill(palette.goldBright)
                        .frame(width: max(1.1, smileW * 0.36), height: max(0.65, size * 0.025))
                        .offset(y: smileH * 0.45)
                }
                .offset(y: owlH * 0.205)
            }
            .frame(width: owlW, height: owlH)
        }
        .onAppear {
            if isActive && !reduceMotion {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    ringExpanded = true
                }
            }
        }
        .onChange(of: isActive) { _, active in
            if active && !reduceMotion {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    ringExpanded = true
                }
            } else {
                ringExpanded = false
            }
        }
    }
}

struct NailStatusBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var text: String
    var color: Color
    var icon: String? = nil
    var pulse: Bool = false
    var onInk: Bool = false

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)
        let bgOpacity = (onInk || palette.isDark) ? 0.18 : 0.12
        let borderOpacity = (onInk || palette.isDark) ? 0.34 : 0.28

        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
            } else {
                ZStack {
                    if pulse {
                        Circle()
                            .fill(color.opacity(0.45))
                            .frame(width: 10, height: 10)
                            .scaleEffect(pulsing ? 1.45 : 0.85)
                            .opacity(pulsing ? 0.15 : 0.7)
                    }
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8.5)
        .padding(.vertical, 3.5)
        .background(color.opacity(bgOpacity), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(borderOpacity), lineWidth: 0.8)
        }
        .onAppear {
            if pulse && !reduceMotion {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
    }
}

struct NailSectionTitle: View {
    @Environment(\.colorScheme) private var colorScheme
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var onInk: Bool = false

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)
        let titleColor = onInk ? palette.inkCardText : palette.textPrimary
        let subtitleColor = onInk ? palette.inkCardMuted : palette.textSecondary
        let iconColor = onInk ? palette.inkCardMuted : palette.textSecondary

        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(titleColor)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                }
            }
        }
    }
}

// MARK: - Formatting

enum NailFormatting {
    nonisolated static func formatElapsed(since start: Date?, now: Date = Date()) -> String {
        guard let start else { return "00:00" }
        let totalSeconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    nonisolated static func indonesianDateHeader(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.dateFormat = "EEEE, d MMMM"
        let raw = formatter.string(from: date)
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + raw.dropFirst()
    }
}

// MARK: - 04 · NOKO-OWL (Sculpted Porcelain Acoustic Owl Character)

struct NokoOwlSilhouetteShape: Shape {
    nonisolated static func cgPath(in rect: CGRect, flipY: Bool = false) -> CGPath {
        func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + nx * rect.width,
                y: flipY
                    ? rect.minY + (1.0 - ny) * rect.height
                    : rect.minY + ny * rect.height
            )
        }

        let path = CGMutablePath()
        // Plump, rounded sculpted porcelain silhouette with subtle curved crown ear-tufts (G1 continuous)
        path.move(to: pt(0.50, 0.100))
        // Crown valley -> right ear crest
        path.addCurve(
            to: pt(0.795, 0.014),
            control1: pt(0.625, 0.100),
            control2: pt(0.715, 0.014)
        )
        // Right ear crest -> fuller, rounder right cheek
        path.addCurve(
            to: pt(0.996, 0.515),
            control1: pt(0.885, 0.014),
            control2: pt(0.996, 0.235)
        )
        // Right cheek -> circular sculpted ceramic chin/base center
        path.addCurve(
            to: pt(0.50, 0.992),
            control1: pt(0.996, 0.795),
            control2: pt(0.785, 0.992)
        )
        // Circular base center -> fuller, rounder left cheek
        path.addCurve(
            to: pt(0.004, 0.515),
            control1: pt(0.215, 0.992),
            control2: pt(0.004, 0.795)
        )
        // Left cheek -> left ear crest
        path.addCurve(
            to: pt(0.205, 0.014),
            control1: pt(0.004, 0.235),
            control2: pt(0.115, 0.014)
        )
        // Left ear crest -> crown valley
        path.addCurve(
            to: pt(0.50, 0.100),
            control1: pt(0.285, 0.014),
            control2: pt(0.375, 0.100)
        )
        path.closeSubpath()
        return path
    }

    func path(in rect: CGRect) -> Path {
        Path(Self.cgPath(in: rect, flipY: false))
    }
}

enum NailBotMood: Equatable, Sendable {
    case standby
    case listening
    case processing
    case speaking
    case interrupted
    case error
}

enum NailBotForm: Equatable, Sendable {
    case miniEyes
    case fullFace
}

struct NailBotFaceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBlinking: Bool = false
    @State private var glanceX: CGFloat = 0

    var mood: NailBotMood
    var form: NailBotForm = .fullFace
    var phase: Double = 0
    var speakingEnergy: Double = 0
    var listeningEnergy: Double = 0
    var accentColor: Color = Color(hex: 0xEAB308)
    var size: CGSize? = nil
    var isPaused: Bool = false
    var framePose: NailBotFacePose? = nil
    var speechLevel: Double? = nil

    init(
        mood: NailBotMood,
        form: NailBotForm = .fullFace,
        phase: Double = 0,
        speakingEnergy: Double = 0,
        listeningEnergy: Double = 0,
        accentColor: Color = Color(hex: 0xEAB308),
        size: CGSize? = nil,
        isPaused: Bool = false,
        framePose: NailBotFacePose? = nil,
        speechLevel: Double? = nil
    ) {
        self.mood = mood
        self.form = form
        self.phase = phase
        self.speakingEnergy = speakingEnergy
        self.listeningEnergy = listeningEnergy
        self.accentColor = accentColor
        self.size = size
        self.isPaused = isPaused
        self.framePose = framePose
        self.speechLevel = speechLevel
    }

    private var defaultSize: CGSize {
        switch form {
        case .miniEyes:
            return CGSize(width: 26, height: 14)
        case .fullFace:
            return CGSize(width: 48, height: 48)
        }
    }

    private var effectiveSize: CGSize {
        size ?? defaultSize
    }

    private var scaleFactor: CGFloat {
        let base = defaultSize
        guard base.width > 0, base.height > 0 else { return 1.0 }
        let target = effectiveSize
        return min(target.width / base.width, target.height / base.height)
    }

    private var clampedSpeaking: Double {
        min(max(speakingEnergy, 0), 1)
    }

    private var clampedListening: Double {
        min(max(listeningEnergy, 0), 1)
    }

    private var animationsEnabled: Bool {
        !reduceMotion && !isPaused
    }

    private var eyeScale: CGFloat {
        guard animationsEnabled else { return 1 }
        return framePose?.blinkScaleY ?? (isBlinking ? 0.14 : 1)
    }

    private var eyeGlance: CGFloat {
        animationsEnabled ? (framePose?.glanceX ?? glanceX) : 0
    }

    var body: some View {
        let targetSize = effectiveSize
        let s = max(scaleFactor, 0.35)

        Group {
            switch form {
            case .miniEyes:
                miniEyesOnlyBody(scale: s)
            case .fullFace:
                fullNokoBody(scale: s)
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .task(id: reduceMotion || isPaused || framePose != nil) {
            if reduceMotion || isPaused || framePose != nil {
                isBlinking = false
                glanceX = 0
                return
            }
            var cycle = 0
            while !Task.isCancelled {
                let sleepMs = Int.random(in: 2800...4800)
                try? await Task.sleep(for: .milliseconds(sleepMs))
                guard !Task.isCancelled else { break }

                withAnimation(.easeInOut(duration: 0.08)) {
                    isBlinking = true
                }
                try? await Task.sleep(for: .milliseconds(125))
                guard !Task.isCancelled else { break }

                withAnimation(.easeInOut(duration: 0.08)) {
                    isBlinking = false
                }

                cycle += 1
                if mood == .standby && cycle % 2 == 0 {
                    let nextGlance = CGFloat.random(in: -1.3...1.3)
                    withAnimation(.easeInOut(duration: 0.28)) {
                        glanceX = nextGlance
                    }
                    try? await Task.sleep(for: .milliseconds(850))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.32)) {
                        glanceX = 0
                    }
                } else if glanceX != 0 {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        glanceX = 0
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Shared Iconic Logo Eye Orb Helper

    @ViewBuilder
    private func nokoLogoEyeOrb(
        diameter: CGFloat,
        scale s: CGFloat,
        showGoldCrescent: Bool = true
    ) -> some View {
        ZStack {
            if showGoldCrescent {
                Circle()
                    .trim(from: 0.0, to: 0.28)
                    .stroke(
                        accentColor.opacity(0.78),
                        style: StrokeStyle(
                            lineWidth: max(0.85, 1.0 * s),
                            lineCap: .round
                        )
                    )
                    .frame(width: diameter + 2.4 * s, height: diameter + 2.4 * s)
                    .rotationEffect(.degrees(14))
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color(hex: 0xF3F6FA),
                            Color(hex: 0xDCE3EE),
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 0.2 * s,
                        endRadius: diameter * 0.65
                    )
                )
                .frame(width: diameter, height: diameter)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: max(1.1, diameter * 0.25), height: max(1.1, diameter * 0.25))
                        .offset(x: diameter * 0.16, y: diameter * 0.16)
                }
                .shadow(color: Color.white.opacity(0.22), radius: 1.2 * s)
        }
    }

    // MARK: - Form .miniEyes (Razor-Crisp Floating Eyes Only for Collapsed Notch HUD & Pill)

    @ViewBuilder
    private func miniEyesOnlyBody(scale s: CGFloat) -> some View {
        let speaking = clampedSpeaking
        let listening = clampedListening
        let animate = animationsEnabled

        let blinkScaleY = eyeScale
        let eyeWhite = Color(hex: 0xF8FAFC)
        let errorCoral = Color(hex: 0xF08A80)

        switch mood {
        case .standby:
            let glance = eyeGlance * 0.90 * s
            HStack(spacing: 5.6 * s) {
                ForEach(0..<2, id: \.self) { _ in
                    nokoLogoEyeOrb(diameter: 6.2 * s, scale: s, showGoldCrescent: true)
                }
            }
            .scaleEffect(x: 1.0, y: blinkScaleY)
            .offset(x: glance)

        case .listening:
            let pulse = animate ? (0.5 + 0.5 * sin(phase * 5.2)) : 0.5
            let eyeDia = (5.3 + CGFloat(listening) * 0.45) * s
            let haloDia = (8.2 + CGFloat(listening) * 0.80 + CGFloat(pulse) * 0.40) * s
            HStack(spacing: 4.6 * s) {
                ForEach(0..<2, id: \.self) { _ in
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.18 + listening * 0.18))
                            .frame(width: haloDia + 1.2 * s, height: haloDia + 1.2 * s)

                        Circle()
                            .stroke(
                                accentColor.opacity(0.85 + listening * 0.15),
                                lineWidth: max(0.95, 1.15 * s)
                            )
                            .frame(width: haloDia, height: haloDia)

                        nokoLogoEyeOrb(diameter: eyeDia, scale: s, showGoldCrescent: false)
                    }
                }
            }
            .scaleEffect(x: 1.0, y: blinkScaleY)

        case .processing:
            let sideShift = (1.15 + (animate ? CGFloat(sin(phase * 1.9)) * 0.30 : 0)) * s
            let orbitDeg = animate
                ? (phase * 155).truncatingRemainder(dividingBy: 360) - 68
                : -68
            let eyeDia = 5.0 * s
            let orbitDia = 8.4 * s

            HStack(spacing: 5.0 * s) {
                nokoLogoEyeOrb(diameter: eyeDia, scale: s, showGoldCrescent: false)

                ZStack {
                    Circle()
                        .trim(from: 0.0, to: 0.36)
                        .stroke(
                            accentColor,
                            style: StrokeStyle(lineWidth: max(1.0, 1.2 * s), lineCap: .round)
                        )
                        .frame(width: orbitDia, height: orbitDia)
                        .rotationEffect(.degrees(orbitDeg))
                        .shadow(color: accentColor.opacity(0.50), radius: 1.2 * s)

                    nokoLogoEyeOrb(diameter: eyeDia, scale: s, showGoldCrescent: false)
                }
            }
            .scaleEffect(x: 1.0, y: blinkScaleY)
            .offset(x: sideShift)

        case .speaking:
            let speakAmp = 0.35 + 0.65 * speaking
            let bounceY: CGFloat = animate
                ? CGFloat(-0.85 * sin(phase * 8.5) * speakAmp) * s
                : -CGFloat(speaking) * 0.35 * s
            HStack(spacing: 5.4 * s) {
                ForEach(0..<2, id: \.self) { _ in
                    NokoArcEyeShape()
                        .stroke(
                            eyeWhite,
                            style: StrokeStyle(
                                lineWidth: max(1.45, 1.85 * s),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(width: 6.2 * s, height: 3.4 * s)
                        .shadow(color: Color.white.opacity(0.28), radius: 1.1 * s)
                }
            }
            .offset(y: bounceY)

        case .interrupted:
            HStack(spacing: 5.6 * s) {
                NailChevronEyeShape(pointsRight: true)
                    .stroke(
                        eyeWhite.opacity(0.94),
                        style: StrokeStyle(lineWidth: max(1.3, 1.65 * s), lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 4.8 * s, height: 5.4 * s)

                NailChevronEyeShape(pointsRight: false)
                    .stroke(
                        eyeWhite.opacity(0.94),
                        style: StrokeStyle(lineWidth: max(1.3, 1.65 * s), lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 4.8 * s, height: 5.4 * s)
            }

        case .error:
            HStack(spacing: 5.6 * s) {
                Capsule(style: .continuous)
                    .fill(errorCoral)
                    .frame(width: 4.4 * s, height: 6.2 * s)
                    .rotationEffect(.degrees(-16))
                    .shadow(color: errorCoral.opacity(0.35), radius: 1.3 * s)

                Capsule(style: .continuous)
                    .fill(errorCoral)
                    .frame(width: 4.4 * s, height: 6.2 * s)
                    .rotationEffect(.degrees(16))
                    .shadow(color: errorCoral.opacity(0.35), radius: 1.3 * s)
            }
            .scaleEffect(x: 1.0, y: blinkScaleY)
        }
    }

    // MARK: - Form .fullFace (Sculpted 3D Porcelain 04 · NOKO-OWL)

    @ViewBuilder
    private func fullNokoBody(scale s: CGFloat) -> some View {
        let bodyW = 43.0 * s
        let bodyH = 43.6 * s
        let visorW = 32.2 * s
        let visorH = 14.2 * s

        let speaking = clampedSpeaking
        let listening = clampedListening
        let animate = animationsEnabled

        let speakAmplitude = 0.35 + 0.65 * speaking
        let bobWave = (mood == .speaking && animate) ? sin(phase * 8.5) * speakAmplitude : 0
        let squashX: CGFloat = (mood == .speaking && animate)
            ? CGFloat(1.0 + 0.022 * cos(phase * 8.5) * speakAmplitude)
            : 1.0
        let squashY: CGFloat = (mood == .speaking && animate)
            ? CGFloat(1.0 - 0.022 * cos(phase * 8.5) * speakAmplitude)
            : 1.0
        let listeningScale: CGFloat = (mood == .listening && animate)
            ? CGFloat(1.02 + 0.015 * listening)
            : 1.0
        let processingTilt: Double = (mood == .processing && animate)
            ? sin(phase * 2.2) * 1.4
            : 0
        let bodyBobY: CGFloat = CGFloat(-1.35 * bobWave) * s

        ZStack {
            // 1. Multi-stop 3D sculpted ceramic porcelain body (#F9FBFD -> #ECF0F5 -> #DAE3EE)
            NokoOwlSilhouetteShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0xFAFBFD), location: 0.0),
                            .init(color: Color(hex: 0xF3F6FA), location: 0.32),
                            .init(color: Color(hex: 0xECF0F5), location: 0.64),
                            .init(color: Color(hex: 0xDAE3EE), location: 1.0),
                        ],
                        startPoint: UnitPoint(x: 0.22, y: 0.10),
                        endPoint: UnitPoint(x: 0.86, y: 0.95)
                    )
                )
                .overlay {
                    // Upper-left 3D porcelain studio key light
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.80),
                            Color.white.opacity(0.22),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.27, y: 0.20),
                        startRadius: 0.5 * s,
                        endRadius: 23.0 * s
                    )
                    .clipShape(NokoOwlSilhouetteShape())
                }
                .overlay {
                    // Subtle lower-right ceramic curvature depth + delicate vertical specular cheek reflection
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.clear,
                                Color(hex: 0xBCC9D9, alpha: 0.36),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        Color.white.opacity(0.12),
                                        Color.clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 2.2 * s, height: 15.0 * s)
                            .blur(radius: 0.8 * s)
                            .offset(x: bodyW * 0.38, y: bodyH * 0.14)
                    }
                    .clipShape(NokoOwlSilhouetteShape())
                }
                .overlay {
                    // Soft upper-left porcelain brow specular highlight
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.68), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 11.5 * s, height: 5.5 * s)
                        .rotationEffect(.degrees(-14))
                        .offset(x: -7.0 * s, y: -13.5 * s)
                        .clipShape(NokoOwlSilhouetteShape())
                }
                .overlay {
                    // Crisp ceramic rim stroke (pops on BOTH light porcelain wells & dark obsidian HUD)
                    NokoOwlSilhouetteShape()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.white.opacity(0.42),
                                    Color(hex: 0xB8C5D6, alpha: 0.68),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(0.85, 1.05 * s)
                        )
                }

            // 2. Inset matte-obsidian horizontal rounded-pill eye visor with recessed porcelain bevel
            ZStack {
                // Recessed porcelain groove around the visor
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xB8C5D6, alpha: 0.85),
                                Color(hex: 0xD3DCE7, alpha: 0.30),
                                Color.white.opacity(0.92),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(0.9, 1.2 * s)
                    )
                    .frame(width: visorW + 1.2 * s, height: visorH + 1.2 * s)

                // Deep matte-obsidian visor glass
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: 0x171A21), location: 0.0),
                                .init(color: Color(hex: 0x0E1015), location: 0.45),
                                .init(color: Color(hex: 0x0A0A0A), location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: visorW, height: visorH)

                // Subtle curved top glass reflection sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.02),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: visorH * 0.42)
                    Spacer(minLength: 0)
                }
                .frame(width: visorW, height: visorH)
                .clipShape(Capsule(style: .continuous))

                // Expressive 60fps animated mood eyes inside the obsidian visor
                fullNokoEyes(scale: s, speaking: speaking, listening: listening, animate: animate)
                    .frame(width: visorW, height: visorH)
                    .clipShape(Capsule(style: .continuous))

                // Crisp inner visor bevel rim
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.75),
                                Color.clear,
                                Color.white.opacity(0.14),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: max(0.65, 0.8 * s)
                    )
                    .frame(width: visorW, height: visorH)
            }
            .offset(y: -2.4 * s)

            // 3. Sleek industrial acoustic mouth system below visor (Braun / Nothing / EVE aesthetic)
            fullNokoAcousticMouth(scale: s, speaking: speaking, listening: listening, animate: animate)
                .offset(y: 9.3 * s)

            // 4. Subtle 3 micro-dots acoustic chin detail (matching 04 · NOKO-OWL)
            HStack(spacing: 2.0 * s) {
                Circle()
                    .fill(Color(hex: 0x8C9AAA, alpha: mood == .speaking ? 0.30 : 0.52))
                    .frame(width: 1.05 * s, height: 1.05 * s)
                Circle()
                    .fill(Color(hex: 0x8C9AAA, alpha: mood == .speaking ? 0.36 : 0.62))
                    .frame(width: 1.25 * s, height: 1.25 * s)
                    .offset(y: 0.55 * s)
                Circle()
                    .fill(Color(hex: 0x8C9AAA, alpha: mood == .speaking ? 0.30 : 0.52))
                    .frame(width: 1.05 * s, height: 1.05 * s)
            }
            .offset(y: 16.5 * s)
        }
        .frame(width: bodyW, height: bodyH)
        .scaleEffect(x: squashX * listeningScale, y: squashY * listeningScale)
        .rotationEffect(.degrees(processingTilt))
        .offset(y: bodyBobY)
        .shadow(color: Color(hex: 0x0B1018, alpha: 0.24), radius: 3.0 * s, x: 0, y: 2.0 * s)
    }

    @ViewBuilder
    private func fullNokoEyes(
        scale s: CGFloat,
        speaking: Double,
        listening: Double,
        animate: Bool
    ) -> some View {
        let eyeWhite = Color(hex: 0xF8FAFC)
        let errorCoral = Color(hex: 0xF08A80)
        let blinkScaleY = eyeScale

        switch mood {
        case .standby:
            let glance = eyeGlance * s
            HStack(spacing: 7.4 * s) {
                ForEach(0..<2, id: \.self) { _ in
                    nokoLogoEyeOrb(diameter: 6.3 * s, scale: s, showGoldCrescent: true)
                }
            }
            .scaleEffect(x: 1.0, y: blinkScaleY)
            .offset(x: glance)

        case .listening:
            let breathe = animate ? (0.5 + 0.5 * sin(phase * 5.2)) : 0.5
            let eyeDia = (6.3 + CGFloat(listening) * 0.55) * s
            let haloDia = eyeDia + (3.1 + CGFloat(listening) * 0.7 + CGFloat(breathe) * 0.45) * s
            let haloOpacity = 0.76 + 0.24 * max(listening, breathe * 0.6)

            HStack(spacing: 6.4 * s) {
                ForEach(0..<2, id: \.self) { _ in
                    ZStack {
                        // Soft warm golden iris ambient glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        accentColor.opacity(0.32 + listening * 0.28),
                                        accentColor.opacity(0.08),
                                        Color.clear,
                                    ],
                                    center: .center,
                                    startRadius: eyeDia * 0.42,
                                    endRadius: haloDia * 0.62
                                )
                            )
                            .frame(width: haloDia + 1.8 * s, height: haloDia + 1.8 * s)

                        // Crisp concentric golden iris halo ring
                        Circle()
                            .stroke(
                                accentColor.opacity(haloOpacity),
                                lineWidth: max(0.85, 1.05 * s)
                            )
                            .frame(width: haloDia, height: haloDia)

                        // Wide alert iconic logo eye orb
                        nokoLogoEyeOrb(diameter: eyeDia, scale: s, showGoldCrescent: false)
                    }
                }
            }
            .scaleEffect(x: 1.0, y: blinkScaleY)

        case .processing:
            let sideShift = (2.15 + (animate ? CGFloat(sin(phase * 1.9)) * 0.35 : 0)) * s
            let orbitDeg = animate
                ? (phase * 155).truncatingRemainder(dividingBy: 360) - 68
                : -68
            let eyeDia = 5.4 * s
            let orbitDia = 8.8 * s

            HStack(spacing: 6.6 * s) {
                // Left side-glancing eye
                Circle()
                    .fill(eyeWhite)
                    .frame(width: eyeDia, height: eyeDia)

                // Right side-glancing eye with orbiting warm-yellow arc + trailing spark dot
                ZStack {
                    Circle()
                        .trim(from: 0.0, to: 0.34)
                        .stroke(
                            accentColor,
                            style: StrokeStyle(lineWidth: max(0.95, 1.15 * s), lineCap: .round)
                        )
                        .frame(width: orbitDia, height: orbitDia)
                        .rotationEffect(.degrees(orbitDeg))
                        .shadow(color: accentColor.opacity(0.55), radius: 1.6 * s)

                    // Tiny glowing spark dot trailing the orbiting arc
                    Circle()
                        .fill(accentColor)
                        .frame(width: 1.35 * s, height: 1.35 * s)
                        .offset(x: orbitDia * 0.5)
                        .rotationEffect(.degrees(orbitDeg + 132))

                    Circle()
                        .fill(eyeWhite)
                        .frame(width: eyeDia, height: eyeDia)
                }
            }
            .scaleEffect(x: 1.0, y: blinkScaleY)
            .offset(x: sideShift, y: -0.25 * s)

        case .speaking:
            let energyLift = CGFloat(speaking) * 0.45 * s
            HStack(spacing: 6.8 * s) {
                ForEach(0..<2, id: \.self) { _ in
                    NokoArcEyeShape()
                        .stroke(
                            eyeWhite,
                            style: StrokeStyle(
                                lineWidth: max(1.4, 1.95 * s),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(width: 6.8 * s, height: 3.6 * s)
                        .shadow(color: Color.white.opacity(0.32), radius: 1.2 * s)
                }
            }
            .offset(y: -energyLift)

        case .interrupted:
            HStack(spacing: 7.4 * s) {
                NailChevronEyeShape(pointsRight: true)
                    .stroke(
                        eyeWhite.opacity(0.92),
                        style: StrokeStyle(
                            lineWidth: max(1.3, 1.75 * s),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: 5.4 * s, height: 5.8 * s)

                NailChevronEyeShape(pointsRight: false)
                    .stroke(
                        eyeWhite.opacity(0.92),
                        style: StrokeStyle(
                            lineWidth: max(1.3, 1.75 * s),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: 5.4 * s, height: 5.8 * s)
            }

        case .error:
            HStack(spacing: 7.4 * s) {
                Capsule(style: .continuous)
                    .fill(errorCoral)
                    .frame(width: 5.0 * s, height: 6.8 * s)
                    .rotationEffect(.degrees(-16))
                    .shadow(color: errorCoral.opacity(0.38), radius: 1.5 * s)

                Capsule(style: .continuous)
                    .fill(errorCoral)
                    .frame(width: 5.0 * s, height: 6.8 * s)
                    .rotationEffect(.degrees(16))
                    .shadow(color: errorCoral.opacity(0.38), radius: 1.5 * s)
            }
            .scaleEffect(x: 1.0, y: blinkScaleY)
        }
    }

    @ViewBuilder
    private func fullNokoAcousticMouth(
        scale s: CGFloat,
        speaking: Double,
        listening: Double,
        animate: Bool
    ) -> some View {
        let errorCoral = Color(hex: 0xF08A80)
        let obsidianMouth = Color(hex: 0x141922)

        switch mood {
        case .standby:
            ZStack {
                // Subtle porcelain lower rim bevel under recessed smile arc
                NokoSmileArcShape(inverted: false)
                    .stroke(
                        Color.white.opacity(0.85),
                        style: StrokeStyle(
                            lineWidth: max(1.1, 1.55 * s),
                            lineCap: .round
                        )
                    )
                    .frame(width: 7.5 * s, height: 2.15 * s)
                    .offset(y: 0.45 * s)

                // Sleek matte-obsidian recessed curved smile arc
                NokoSmileArcShape(inverted: false)
                    .stroke(
                        obsidianMouth,
                        style: StrokeStyle(
                            lineWidth: max(1.2, 1.65 * s),
                            lineCap: .round
                        )
                    )
                    .frame(width: 7.4 * s, height: 2.1 * s)

                // Luminous warm golden-yellow micro-core pill accent at smile center
                Capsule(style: .continuous)
                    .fill(accentColor)
                    .frame(width: 2.5 * s, height: 1.15 * s)
                    .shadow(color: accentColor.opacity(0.55), radius: 1.2 * s)
                    .offset(y: 0.98 * s)
            }

        case .listening:
            ZStack {
                // Recessed porcelain lip around mini acoustic slit
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: max(0.55, 0.72 * s))
                    .frame(width: 9.8 * s, height: 3.55 * s)
                    .offset(y: 0.32 * s)

                // Matte-obsidian recessed acoustic slit
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x0E1218), Color(hex: 0x1A202B)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 9.4 * s, height: 3.35 * s)

                // 3 pulsing warm-golden precision sound pips reacting to listeningEnergy & phase
                HStack(spacing: 1.55 * s) {
                    ForEach(0..<3, id: \.self) { idx in
                        let wave = animate
                            ? (0.5 + 0.5 * sin(phase * 6.4 - Double(idx) * 0.95))
                            : (idx == 1 ? 0.9 : 0.55)
                        let pipScale = 0.82 + 0.34 * max(listening, wave * 0.75)
                        let pipOpacity = 0.72 + 0.28 * max(listening, wave)
                        Circle()
                            .fill(accentColor.opacity(pipOpacity))
                            .frame(width: 1.45 * s, height: 1.45 * s)
                            .scaleEffect(CGFloat(pipScale))
                            .shadow(color: accentColor.opacity(0.55), radius: 1.0 * s)
                    }
                }
            }

        case .processing:
            // Fluid kinetic 3-dot wave (matte-obsidian & warm-gold micro-beads rippling in sequence)
            HStack(spacing: 2.1 * s) {
                ForEach(0..<3, id: \.self) { idx in
                    let wave = animate
                        ? (0.5 + 0.5 * sin(phase * 5.8 - Double(idx) * 1.15))
                        : (idx == 1 ? 0.92 : 0.42)
                    let yOffset: CGFloat = animate
                        ? CGFloat(-0.95 * sin(phase * 5.8 - Double(idx) * 1.15)) * s
                        : 0
                    let dia = (1.75 + 0.40 * CGFloat(wave)) * s

                    ZStack {
                        Circle()
                            .fill(obsidianMouth)
                            .frame(width: dia, height: dia)

                        Circle()
                            .fill(accentColor.opacity(0.22 + 0.78 * wave))
                            .frame(width: dia, height: dia)
                            .shadow(color: accentColor.opacity(0.45 * wave), radius: 1.1 * s)
                    }
                    .offset(y: yOffset)
                }
            }

        case .speaking:
            // Dynamic 5-bar sculpted warm-golden voice equalizer over delicate obsidian acoustic base
            let energy = 0.35 + 0.65 * speaking
            let mouthLevel = speechLevel.map { min(1, max(0, $0)) }
            let weights: [Double] = [0.54, 0.82, 1.0, 0.82, 0.54]
            let phaseOffsets: [Double] = [1.45, 0.72, 0.0, 0.72, 1.45]

            ZStack {
                // Soft warm golden ambient halo
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.18 + 0.18 * speaking))
                    .frame(width: 12.6 * s, height: 5.2 * s)
                    .blur(radius: 1.1 * s)

                // Delicate matte-obsidian recessed acoustic base
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x10141B), Color(hex: 0x1B222E)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 11.2 * s, height: 4.3 * s)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.72), lineWidth: max(0.5, 0.65 * s))
                    }

                // 5 symmetrical dancing warm-golden equalizer bars
                HStack(alignment: .center, spacing: 1.0 * s) {
                    ForEach(0..<5, id: \.self) { idx in
                        let wave = animate
                            ? (0.5 + 0.5 * sin(phase * 11.2 - phaseOffsets[idx]))
                            : 0.75
                        let normH = min(1.0, max(0.28, weights[idx] * (0.35 + 0.65 * wave) * energy))
                        let barH = mouthLevel.map { (0.8 + 3.5 * CGFloat($0 * weights[idx] * (0.75 + 0.25 * wave))) * s }
                            ?? (1.35 + 3.25 * CGFloat(normH)) * s

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0xF2C94C), accentColor],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1.22 * s, height: barH)
                            .shadow(color: accentColor.opacity(0.50), radius: 0.85 * s)
                    }
                }
            }

        case .interrupted:
            // Crisp matte-obsidian muted horizontal bar with subtle angled mute slash
            ZStack {
                Capsule(style: .continuous)
                    .fill(obsidianMouth.opacity(0.88))
                    .frame(width: 8.2 * s, height: 1.75 * s)

                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.88))
                    .frame(width: 1.2 * s, height: 4.1 * s)
                    .rotationEffect(.degrees(28))
            }

        case .error:
            // Clean coral-red inverted subtle frown arc
            NokoSmileArcShape(inverted: true)
                .stroke(
                    errorCoral,
                    style: StrokeStyle(
                        lineWidth: max(1.2, 1.65 * s),
                        lineCap: .round
                    )
                )
                .frame(width: 6.8 * s, height: 2.0 * s)
                .shadow(color: errorCoral.opacity(0.35), radius: 1.2 * s)
        }
    }
}

struct NokoFloatingCompanionStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var mood: NailBotMood
    var phase: Double = 0
    var speakingEnergy: Double = 0
    var listeningEnergy: Double = 0
    var accentColor: Color = Color(hex: 0xEAB308)
    var owlSize: CGFloat = 88
    var isPaused: Bool = false
    var showFloorShadow: Bool = true

    init(
        mood: NailBotMood,
        phase: Double = 0,
        speakingEnergy: Double = 0,
        listeningEnergy: Double = 0,
        accentColor: Color = Color(hex: 0xEAB308),
        owlSize: CGFloat = 88,
        isPaused: Bool = false,
        showFloorShadow: Bool = true
    ) {
        self.mood = mood
        self.phase = phase
        self.speakingEnergy = speakingEnergy
        self.listeningEnergy = listeningEnergy
        self.accentColor = accentColor
        self.owlSize = owlSize
        self.isPaused = isPaused
        self.showFloorShadow = showFloorShadow
    }

    private var animationsEnabled: Bool {
        !reduceMotion && !isPaused
    }

    private var clampedSpeaking: Double {
        min(max(speakingEnergy, 0), 1)
    }

    private var clampedListening: Double {
        min(max(listeningEnergy, 0), 1)
    }

    private var scaleFactor: CGFloat {
        max(owlSize / 88.0, 0.35)
    }

    private var bodyOffsetX: CGFloat {
        let animate = animationsEnabled
        let s = scaleFactor
        switch mood {
        case .interrupted:
            return (animate ? CGFloat(sin(phase * 14.0) * 2.0) : 0) * s
        default:
            return 0
        }
    }

    private var bodyOffsetY: CGFloat {
        let animate = animationsEnabled
        let s = scaleFactor
        switch mood {
        case .standby:
            return (animate ? CGFloat(sin(phase * 1.6) * 2.0) : 0) * s
        case .listening:
            return (animate ? CGFloat(sin(phase * 2.6) * 3.0) : 0) * s
        case .processing:
            return 5.0 * s
        case .speaking:
            let hop = animate
                ? -abs(sin(phase * 4.4)) * (4.5 + 3.5 * clampedSpeaking)
                : -2.5 * clampedSpeaking
            return CGFloat(hop) * s
        case .interrupted, .error:
            return 0
        }
    }

    private var bodyTiltDegrees: Double {
        let animate = animationsEnabled
        switch mood {
        case .listening:
            return 3.0
        case .processing:
            return -6.5 + (animate ? sin(phase * 2.2) * 1.8 : 0)
        default:
            return 0
        }
    }

    var body: some View {
        let s = scaleFactor
        let animate = animationsEnabled
        let offsetX = bodyOffsetX
        let offsetY = bodyOffsetY
        let tilt = bodyTiltDegrees
        let liftNormalized = max(0, -offsetY) / max(1, 9.0 * s)
        let sinkNormalized = max(0, offsetY) / max(1, 9.0 * s)
        let shadowScaleX = max(0.68, min(1.08, 1.0 - liftNormalized * 0.26 + sinkNormalized * 0.06))
        let shadowScaleY = max(0.72, min(1.06, 1.0 - liftNormalized * 0.22 + sinkNormalized * 0.05))
        let shadowAlpha = Double(max(0.18, min(0.46, 0.40 - liftNormalized * 0.18 + sinkNormalized * 0.04)))

        ZStack {
            if showFloorShadow {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.black.opacity(shadowAlpha),
                                Color.black.opacity(shadowAlpha * 0.42),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 1.0 * s,
                            endRadius: owlSize * 0.32
                        )
                    )
                    .frame(width: owlSize * 0.62, height: max(8, owlSize * 0.11))
                    .scaleEffect(x: shadowScaleX, y: shadowScaleY)
                    .blur(radius: 1.8 * s)
                    .offset(x: offsetX * 0.35, y: owlSize * 0.56)
            }

            moodOpenAirAura(scale: s, animate: animate, bodyOffsetX: offsetX, bodyOffsetY: offsetY)

            NailBotFaceView(
                mood: mood,
                form: .fullFace,
                phase: phase,
                speakingEnergy: speakingEnergy,
                listeningEnergy: listeningEnergy,
                accentColor: accentColor,
                size: CGSize(width: owlSize, height: owlSize),
                isPaused: isPaused
            )
            .shadow(color: Color.black.opacity(0.28), radius: 10 * s, x: 0, y: 6 * s)
            .rotationEffect(.degrees(tilt))
            .offset(x: offsetX, y: offsetY)

            if mood == .processing {
                processingOverheadHalo(scale: s, animate: animate)
            }
        }
        .frame(width: owlSize * 1.68, height: owlSize * 1.62)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func moodOpenAirAura(
        scale s: CGFloat,
        animate: Bool,
        bodyOffsetX: CGFloat,
        bodyOffsetY: CGFloat
    ) -> some View {
        let goldHighlight = Color(hex: 0xF2C94C)
        let errorCoral = Color(hex: 0xF08A80)
        let mutedAlabaster = Color(hex: 0xF5F5F5)

        switch mood {
        case .standby, .processing:
            EmptyView()

        case .listening:
            let listen = clampedListening
            let pulseWave = animate ? (0.5 + 0.5 * sin(phase * 3.4)) : 0.45
            let innerDia = owlSize * (1.18 + 0.03 * CGFloat(listen))
            let outerDia = owlSize * (1.28 + 0.22 * CGFloat(pulseWave) + 0.08 * CGFloat(listen))
            let outerAlpha = (1.0 - 0.58 * pulseWave) * (0.48 + 0.28 * listen)
            let innerRot = animate ? (phase * 18.0).truncatingRemainder(dividingBy: 360) : 0

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentColor.opacity(0.14 + 0.12 * listen),
                                accentColor.opacity(0.04),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: owlSize * 0.36,
                            endRadius: outerDia * 0.55
                        )
                    )
                    .frame(width: outerDia, height: outerDia)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                goldHighlight.opacity(outerAlpha),
                                accentColor.opacity(outerAlpha * 0.75),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1.1, 1.35 * s)
                    )
                    .frame(width: outerDia, height: outerDia)
                    .shadow(color: accentColor.opacity(0.32), radius: 3.5 * s)

                Circle()
                    .stroke(
                        accentColor.opacity(0.76 + 0.20 * listen),
                        style: StrokeStyle(
                            lineWidth: max(1.25, 1.55 * s),
                            lineCap: .round,
                            dash: [4.8 * s, 5.4 * s]
                        )
                    )
                    .frame(width: innerDia, height: innerDia)
                    .rotationEffect(.degrees(innerRot))
                    .shadow(color: accentColor.opacity(0.38), radius: 2.5 * s)
            }
            .offset(x: bodyOffsetX, y: bodyOffsetY)

        case .speaking:
            let speak = clampedSpeaking
            let energy = 0.35 + 0.65 * speak

            ZStack {
                ForEach(0..<2, id: \.self) { idx in
                    let wave = animate
                        ? (0.5 + 0.5 * sin(phase * 6.8 - Double(idx) * 1.15))
                        : (idx == 0 ? 0.78 : 0.52)
                    let baseX = owlSize * (0.57 + CGFloat(idx) * 0.12)
                    let dynamicPush = owlSize * CGFloat(0.035 * wave * energy)
                    let arcW = owlSize * (0.075 + CGFloat(idx) * 0.015)
                    let arcH = owlSize * (0.28 + CGFloat(idx) * 0.13 + CGFloat(0.04 * speak))
                    let alpha = (idx == 0 ? 0.88 : 0.62) * (0.65 + 0.35 * max(speak, wave))
                    let strokeW = max(1.5, (idx == 0 ? 2.25 : 1.75) * s)

                    // Left acoustic soundwave arc ((
                    NokoCheekSoundArcShape(isLeft: true)
                        .stroke(
                            LinearGradient(
                                colors: [goldHighlight.opacity(alpha), accentColor.opacity(alpha)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: strokeW, lineCap: .round)
                        )
                        .frame(width: arcW, height: arcH)
                        .shadow(color: accentColor.opacity(0.42 * alpha), radius: 2.6 * s)
                        .offset(x: -(baseX + dynamicPush), y: bodyOffsetY - 1.5 * s)

                    // Right acoustic soundwave arc ))
                    NokoCheekSoundArcShape(isLeft: false)
                        .stroke(
                            LinearGradient(
                                colors: [goldHighlight.opacity(alpha), accentColor.opacity(alpha)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: strokeW, lineCap: .round)
                        )
                        .frame(width: arcW, height: arcH)
                        .shadow(color: accentColor.opacity(0.42 * alpha), radius: 2.6 * s)
                        .offset(x: baseX + dynamicPush, y: bodyOffsetY - 1.5 * s)
                }
            }

        case .interrupted:
            let ringDia = owlSize * 1.16
            Circle()
                .stroke(
                    mutedAlabaster.opacity(0.45),
                    style: StrokeStyle(lineWidth: max(1.25, 1.55 * s), lineCap: .round)
                )
                .frame(width: ringDia, height: ringDia)
                .shadow(color: Color.black.opacity(0.18), radius: 2.5 * s)
                .offset(x: bodyOffsetX, y: bodyOffsetY)

        case .error:
            let pulse = animate ? (0.5 + 0.5 * sin(phase * 3.8)) : 0.5
            let ringDia = owlSize * (1.16 + 0.05 * CGFloat(pulse))
            let ringAlpha = 0.62 + 0.28 * pulse

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                errorCoral.opacity(0.18 + 0.08 * pulse),
                                errorCoral.opacity(0.04),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: owlSize * 0.38,
                            endRadius: ringDia * 0.55
                        )
                    )
                    .frame(width: ringDia, height: ringDia)

                Circle()
                    .stroke(
                        errorCoral.opacity(ringAlpha),
                        style: StrokeStyle(lineWidth: max(1.4, 1.75 * s), lineCap: .round)
                    )
                    .frame(width: ringDia, height: ringDia)
                    .shadow(color: errorCoral.opacity(0.42), radius: 3.5 * s)
            }
            .offset(x: bodyOffsetX, y: bodyOffsetY)
        }
    }

    @ViewBuilder
    private func processingOverheadHalo(
        scale s: CGFloat,
        animate: Bool
    ) -> some View {
        let haloW = owlSize * 0.54
        let haloH = owlSize * 0.16
        let goldBase = Color(hex: 0xEAB308)
        let pearlGold = Color(hex: 0xF2C94C)
        let orbitAngle = animate ? phase * 3.2 : -0.6
        let pearlX = CGFloat(cos(orbitAngle)) * (haloW * 0.5)
        let pearlY = CGFloat(sin(orbitAngle)) * (haloH * 0.5)
        let pearlScale: CGFloat = animate ? CGFloat(0.92 + 0.18 * sin(orbitAngle)) : 1.0
        let pearlDotSize = max(4.2, 5.4 * s)

        ZStack {
            Ellipse()
                .stroke(
                    goldBase.opacity(0.30),
                    lineWidth: max(2.2, 2.8 * s)
                )
                .frame(width: haloW, height: haloH)
                .blur(radius: 1.6 * s)

            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [pearlGold.opacity(0.95), goldBase.opacity(0.82)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: max(1.4, 1.8 * s),
                        lineCap: .round,
                        dash: [4.2 * s, 3.8 * s]
                    )
                )
                .frame(width: haloW, height: haloH)
                .shadow(color: goldBase.opacity(0.45), radius: 2.4 * s)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white, pearlGold, goldBase],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0.2 * s,
                        endRadius: pearlDotSize * 0.65
                    )
                )
                .frame(width: pearlDotSize, height: pearlDotSize)
                .scaleEffect(pearlScale)
                .shadow(color: pearlGold.opacity(0.75), radius: 2.8 * s)
                .offset(x: pearlX, y: pearlY)
        }
        .rotationEffect(.degrees(-4.0))
        .offset(x: -1.5 * s, y: -owlSize * 0.56)
    }
}

private struct NokoCheekSoundArcShape: Shape {
    let isLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isLeft {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.minX - rect.width * 0.35, y: rect.midY)
            )
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: rect.maxX + rect.width * 0.35, y: rect.midY)
            )
        }
        return path
    }
}

private struct NokoSmileArcShape: Shape {
    var inverted: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if inverted {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 1.95)
            )
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 1.95)
            )
        }
        return path
    }
}

private struct NokoArcEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.35)
        )
        return path
    }
}

private struct NailChevronEyeShape: Shape {
    let pointsRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsRight {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        return path
    }
}
