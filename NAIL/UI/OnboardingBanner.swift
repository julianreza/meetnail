import SwiftUI

struct PrerequisiteStatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let status: PrerequisiteStatus
    let onOpenSettings: () -> Void
    let onSignIn: () -> Void
    var onRefresh: () -> Void = {}
    var compact: Bool = false

    @State private var showingPopover = false
    @State private var isHovered = false
    @State private var refreshPulse = 0

    private var readyCount: Int {
        [
            status.electronBundled,
            status.agyInstalled,
            status.uvInstalled,
            status.ffmpegInstalled,
            status.whisperModelCached,
            status.meetProfileExists,
        ].filter { $0 }.count
    }

    private var helpText: String {
        let missingCount = status.missingItems.count
        return status.allReady
            ? "Semua sistem siap"
            : "\(missingCount) prasyarat perlu dilengkapi"
    }

    var body: some View {
        let palette = NailPalette(scheme: colorScheme)
        let missingCount = status.missingItems.count

        Group {
            if compact {
                TalmoCircleIconButton(
                    systemImage: status.allReady ? "checkmark.shield" : "exclamationmark.triangle",
                    isActive: showingPopover,
                    badgeText: status.allReady ? nil : "\(missingCount)",
                    dotColor: status.allReady ? palette.good : nil,
                    tone: .porcelain,
                    size: 34,
                    helpText: helpText
                ) {
                    showingPopover.toggle()
                }
            } else {
                Button {
                    showingPopover.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: status.allReady ? "checkmark.shield" : "exclamationmark.triangle")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(status.allReady ? palette.accent : palette.gold)

                        Text("Sistem")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.primaryText(for: .porcelain))
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(status.allReady ? palette.good : palette.goldBright)
                                .frame(width: 6, height: 6)

                            Text("\(readyCount)/6")
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(palette.primaryText(for: .porcelain))
                                .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82), value: readyCount)
                        }
                        .padding(.horizontal, 7.5)
                        .padding(.vertical, 3.5)
                        .background {
                            NeuRaisedBackground(
                                isCapsule: true,
                                elevation: 0.55,
                                tint: status.allReady ? nil : palette.goldBright,
                                tone: .porcelain
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(
                    PrerequisitePillButtonStyle(
                        isHovered: isHovered,
                        isPopoverOpen: showingPopover,
                        tint: status.allReady ? nil : palette.goldBright
                    )
                )
                .onHover { hovering in
                    if reduceMotion {
                        isHovered = hovering
                    } else {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                            isHovered = hovering
                        }
                    }
                }
                .help(helpText)
            }
        }
        .popover(isPresented: $showingPopover, arrowEdge: compact ? .trailing : .top) {
            popoverContent(palette: palette)
        }
    }

    @ViewBuilder
    private func popoverContent(palette: NailPalette) -> some View {
        let items: [(title: String, ready: Bool)] = [
            ("Runtime Electron", status.electronBundled),
            ("Antigravity CLI (agy)", status.agyInstalled),
            ("uv", status.uvInstalled),
            ("ffmpeg", status.ffmpegInstalled),
            ("Model Whisper lokal", status.whisperModelCached),
            ("Profil Google Meet", status.meetProfileExists),
        ]

        VStack(alignment: .leading, spacing: 14) {
            TalmoCard(padding: 12, cornerRadius: 14, tone: .porcelain) {
                HStack(spacing: 10) {
                    ZStack {
                        NeuInsetBackground(
                            isCapsule: true,
                            depth: 0.72,
                            tone: .porcelain
                        )
                        .frame(width: 30, height: 30)
                        Image(systemName: status.allReady ? "checkmark.shield" : "exclamationmark.triangle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(status.allReady ? palette.good : palette.gold)
                    }

                    Text(status.allReady ? "Semua Prasyarat Siap" : "Prasyarat Sistem")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(palette.primaryText(for: .porcelain))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(status.allReady ? palette.good : palette.goldBright)
                            .frame(width: 6, height: 6)

                        Text("\(readyCount)/6")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(palette.primaryText(for: .porcelain))
                    }
                    .padding(.horizontal, 8.5)
                    .padding(.vertical, 4)
                    .background {
                        NeuRaisedBackground(isCapsule: true, elevation: 0.55, tone: .porcelain)
                    }
                }
            }

            NeuWell(padding: 8, cornerRadius: 14, tone: .porcelain) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.title) { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.ready ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(item.ready ? palette.good : palette.goldBright)

                            Text(item.title)
                                .font(.caption.weight(item.ready ? .medium : .regular))
                                .foregroundStyle(
                                    item.ready
                                        ? palette.primaryText(for: .porcelain)
                                        : palette.secondaryText(for: .porcelain)
                                )
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(item.ready ? "Siap" : "Belum")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(
                                    item.ready
                                        ? palette.tertiaryText(for: .porcelain)
                                        : palette.gold
                                )
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background {
                            NeuRaisedBackground(
                                cornerRadius: 10,
                                elevation: 0.42,
                                tint: item.ready ? nil : palette.goldBright,
                                tone: .porcelain
                            )
                        }
                    }
                }
            }

            Rectangle()
                .fill(palette.hairline(for: .porcelain))
                .frame(height: 1)

            HStack(spacing: 8) {
                if !status.meetProfileExists {
                    Button("Login Google") {
                        showingPopover = false
                        onSignIn()
                    }
                    .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true))
                }

                Button {
                    refreshPulse += 1
                    onRefresh()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.bounce, value: refreshPulse)
                        Text("Periksa Ulang")
                    }
                }
                .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))

                Spacer(minLength: 4)

                Button("Pengaturan") {
                    showingPopover = false
                    onOpenSettings()
                }
                .buttonStyle(NailPillButtonStyle(variant: .ghost, compact: true))
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct PrerequisitePillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isHovered: Bool
    let isPopoverOpen: Bool
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let pressed = (configuration.isPressed && isEnabled) || isPopoverOpen

        configuration.label
            .background {
                if pressed {
                    NeuInsetBackground(cornerRadius: 12, depth: 0.72, tone: .porcelain)
                } else {
                    NeuRaisedBackground(
                        cornerRadius: 12,
                        elevation: isHovered ? 0.74 : 0.60,
                        tint: tint,
                        tone: .porcelain
                    )
                }
            }
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.48)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78),
                value: pressed
            )
    }
}

struct OnboardingBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: PrerequisiteStatus
    let onOpenSettings: () -> Void
    let onSignIn: () -> Void
    var onRefresh: () -> Void = {}

    var body: some View {
        if !status.allReady {
            let palette = NailPalette(scheme: colorScheme)
            let missing = status.missingItems

            HStack(spacing: 12) {
                ZStack {
                    NeuInsetBackground(isCapsule: true, depth: 0.76, tone: .porcelain)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Circle()
                                .fill(palette.goldBright.opacity(0.16))
                        }
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.gold)
                }

                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(palette.goldBright)
                            .frame(width: 6, height: 6)

                        Text("\(missing.count) prasyarat sistem perlu dilengkapi")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.primaryText(for: .porcelain))
                            .lineLimit(1)
                    }

                    if let first = missing.first {
                        let extra = missing.count - 1
                        Text(extra > 0 ? "\(first) +\(extra) lainnya" : first)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: .porcelain))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    if !status.meetProfileExists {
                        Button("Login Google") {
                            onSignIn()
                        }
                        .buttonStyle(NailPillButtonStyle(variant: .primary, compact: true))
                    }

                    Button("Buka Sistem") {
                        onOpenSettings()
                    }
                    .buttonStyle(NailPillButtonStyle(variant: .secondary, compact: true))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                NeuRaisedBackground(
                    cornerRadius: 18,
                    elevation: 0.82,
                    tint: palette.goldBright,
                    tone: .porcelain
                )
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
