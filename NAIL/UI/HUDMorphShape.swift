import CoreGraphics
import SwiftUI

/// Notch/pill container shell shape used by the HUD backdrop and clipping chrome.
struct HUDMorphShellShape: Shape, Sendable {
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

/// Animatable 6-segment cubic Bezier shape that continuously morphs from a smooth
/// rounded HUD capsule (`progress == 0`) to the exact `NokoOwlSilhouetteShape`
/// contour (`progress == 1`).
struct PillToOwlMorphShape: Shape, Sendable {
    var progress: CGFloat

    init(progress: CGFloat = 0) {
        self.progress = progress
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    nonisolated static func cgPath(in rect: CGRect, progress: CGFloat) -> CGPath {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return CGMutablePath()
        }

        let t = HUDMorphMath.clamp01(progress)

        func pt(_ nx0: CGFloat, _ ny0: CGFloat, _ nx1: CGFloat, _ ny1: CGFloat) -> CGPoint {
            let nx = HUDMorphMath.lerp(nx0, nx1, t: t)
            let ny = HUDMorphMath.lerp(ny0, ny1, t: t)
            return CGPoint(
                x: rect.minX + nx * rect.width,
                y: rect.minY + ny * rect.height
            )
        }

        let path = CGMutablePath()

        // Start: top-center (0.50, 0.00) -> crown valley (0.50, 0.100)
        path.move(to: pt(0.50, 0.00, 0.50, 0.100))

        // Curve 1: top-right arc -> right ear crest
        path.addCurve(
            to: pt(0.82, 0.04, 0.795, 0.014),
            control1: pt(0.64, 0.00, 0.625, 0.100),
            control2: pt(0.74, 0.00, 0.715, 0.014)
        )

        // Curve 2: right upper side -> right cheek
        path.addCurve(
            to: pt(1.00, 0.50, 0.996, 0.515),
            control1: pt(0.94, 0.10, 0.885, 0.014),
            control2: pt(1.00, 0.28, 0.996, 0.235)
        )

        // Curve 3: bottom-right -> bottom center / ceramic chin
        path.addCurve(
            to: pt(0.50, 1.00, 0.50, 0.992),
            control1: pt(1.00, 0.80, 0.996, 0.795),
            control2: pt(0.80, 1.00, 0.785, 0.992)
        )

        // Curve 4: bottom-left -> left cheek
        path.addCurve(
            to: pt(0.00, 0.50, 0.004, 0.515),
            control1: pt(0.20, 1.00, 0.215, 0.992),
            control2: pt(0.00, 0.80, 0.004, 0.795)
        )

        // Curve 5: left upper side -> left ear crest
        path.addCurve(
            to: pt(0.18, 0.04, 0.205, 0.014),
            control1: pt(0.00, 0.28, 0.004, 0.235),
            control2: pt(0.06, 0.10, 0.115, 0.014)
        )

        // Curve 6: top-left arc -> crown valley
        path.addCurve(
            to: pt(0.50, 0.00, 0.50, 0.100),
            control1: pt(0.26, 0.00, 0.285, 0.014),
            control2: pt(0.36, 0.00, 0.375, 0.100)
        )

        path.closeSubpath()
        return path
    }

    func path(in rect: CGRect) -> Path {
        Path(Self.cgPath(in: rect, progress: progress))
    }
}

/// Pure geometric and easing helpers for the HUD pill-to-Noko-Owl liquid morph.
enum HUDMorphMath {
    nonisolated static func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        if t == 0 { return a }
        if t == 1 { return b }
        return a + (b - a) * t
    }

    nonisolated static func clamp01(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    nonisolated static func smoothstep(_ t: CGFloat, edge0: CGFloat, edge1: CGFloat) -> CGFloat {
        let span = edge1 - edge0
        guard span != 0 else {
            return t >= edge1 ? 1 : 0
        }
        let u = clamp01((t - edge0) / span)
        return u * u * (3 - 2 * u)
    }

    /// C1-continuous organic squash-and-stretch scale across `progress` in `[0, 1]`.
    /// Stretches vertically around `t ≈ 0.34` as the shell pulls out of the HUD,
    /// gently squashes horizontally around `t ≈ 0.78` on landing, and returns to
    /// exact `(1.0, 1.0)` at both `0` and `1`.
    nonisolated static func squashStretch(progress: CGFloat) -> CGSize {
        let t = clamp01(progress)
        if t == 0 || t == 1 {
            return CGSize(width: 1.0, height: 1.0)
        }

        let stretchPhase = clamp01(t / 0.68)
        let stretchLobe = sin(.pi * stretchPhase)
        let stretch = stretchLobe * stretchLobe

        let squashPhase = clamp01((t - 0.56) / 0.44)
        let squashLobe = sin(.pi * squashPhase)
        let squash = squashLobe * squashLobe

        let scaleX = 1.0 - 0.06 * stretch + 0.03 * squash
        let scaleY = 1.0 + 0.08 * stretch - 0.03 * squash
        return CGSize(width: scaleX, height: scaleY)
    }

    /// Interpolates the morphing shell size from `collapsedSize` to the Noko-Owl
    /// porcelain body dimensions (`expandedOwlSize * 43/48` by `expandedOwlSize * 43.6/48`)
    /// using a gentle elastic ease that settles cleanly at `t == 1`.
    nonisolated static func morphShellDimensions(
        progress: CGFloat,
        collapsedSize: CGSize,
        expandedOwlSize: CGFloat
    ) -> CGSize {
        let t = clamp01(progress)
        let targetWidth = max(0, expandedOwlSize * (43.0 / 48.0))
        let targetHeight = max(0, expandedOwlSize * (43.6 / 48.0))
        let startWidth = max(0, collapsedSize.width)
        let startHeight = max(0, collapsedSize.height)

        if t == 0 {
            return CGSize(width: startWidth, height: startHeight)
        }
        if t == 1 {
            return CGSize(width: targetWidth, height: targetHeight)
        }

        let inv = 1.0 - t
        let eased = 1.0 - (inv * inv) * (1.0 - 0.35 * t)

        return CGSize(
            width: max(0, lerp(startWidth, targetWidth, t: eased)),
            height: max(0, lerp(startHeight, targetHeight, t: eased))
        )
    }
}
