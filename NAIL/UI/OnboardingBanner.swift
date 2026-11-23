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
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)

                        Text("\(readyCount)/6")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(palette.textSecondary)
                            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82), value: readyCount)

                        Spacer(minLength: 4)

                        Circle()
                            .fill(status.allReady ? palette.good : palette.goldBright)
                            .frame(width: 6.5, height: 6.5)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: (isHovered || showingPopover)
                                        ? [palette.neuWellTop, palette.neuWellBottom]
                                        : [palette.neuSurfaceTop, palette.neuSurfaceBottom],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(
                                color: (isHovered || showingPopover) ? .clear : palette.neuShadowLight,
                                radius: 3,
                                x: -2,
                                y: -2
                            )
                            .shadow(
                                color: (isHovered || showingPopover) ? .clear : palette.neuShadowDark.opacity(0.75),
                                radius: 4,
                                x: 2.5,
                                y: 2.5
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        status.allReady ? palette.hairline : palette.goldBorder,
                                        lineWidth: 1
                                    )
                            }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [palette.neuSurfaceTop, palette.neuSurfaceBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .shadow(color: palette.neuShadowLight, radius: 2.5, x: -1.5, y: -1.5)
                        .shadow(color: palette.neuShadowDark.opacity(0.85), radius: 3, x: 2, y: 2)
                        .overlay {
                            Circle()
                                .strokeBorder(status.allReady ? palette.hairline : palette.goldBorder, lineWidth: 1)
                        }
                    Image(systemName: status.allReady ? "checkmark.shield" : "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(status.allReady ? palette.good : palette.goldBright)
                }

                Text(status.allReady ? "Semua Prasyarat Siap" : "Prasyarat Sistem")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
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
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 8.5)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(
                        colors: [palette.neuWellTop, palette.neuWellBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(status.allReady ? palette.hairline : palette.goldBorder, lineWidth: 0.9)
                }
            }

            NeuWell(padding: 8, cornerRadius: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.title) { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.ready ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(item.ready ? palette.good : palette.goldBright)

                            Text(item.title)
                                .font(.caption.weight(item.ready ? .medium : .regular))
                                .foregroundStyle(item.ready ? palette.textPrimary : palette.textSecondary)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(item.ready ? "Siap" : "Belum")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(item.ready ? palette.textTertiary : palette.gold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(item.ready ? palette.card.opacity(0.82) : palette.goldSoft.opacity(0.55))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(item.ready ? palette.hairline : palette.goldBorder, lineWidth: 1)
                                }
                        }
                    }
                }
            }

            Rectangle()
                .fill(palette.hairline)
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

            TalmoCard(padding: 15, cornerRadius: 18, surface: .card) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(palette.goldSoft)
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle()
                                    .strokeBorder(palette.goldBorder, lineWidth: 1)
                            }
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(palette.goldBright)
                    }

                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(palette.goldBright)
                                .frame(width: 6, height: 6)

                            Text("\(missing.count) prasyarat sistem perlu dilengkapi")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                        }

                        if let first = missing.first {
                            let extra = missing.count - 1
                            Text(extra > 0 ? "\(first) +\(extra) lainnya" : first)
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer(minLength: 12)

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
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(palette.goldBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
