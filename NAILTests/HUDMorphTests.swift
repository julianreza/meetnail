import CoreGraphics
import SwiftUI
import XCTest
@testable import NAIL

final class HUDMorphTests: XCTestCase {
    func testPillToOwlMorphShapeProducesValidFiniteBoundingBoxesAcrossProgressSteps() {
        let rect = CGRect(x: 10, y: 20, width: 120, height: 110)
        let steps: [CGFloat] = [0.0, 0.25, 0.5, 0.75, 1.0]

        for progress in steps {
            let cgPath = PillToOwlMorphShape.cgPath(in: rect, progress: progress)
            XCTAssertFalse(cgPath.isEmpty, "Path should not be empty at progress \(progress)")

            let box = cgPath.boundingBoxOfPath
            XCTAssertTrue(box.minX.isFinite && box.minY.isFinite)
            XCTAssertTrue(box.width.isFinite && box.height.isFinite)
            XCTAssertGreaterThan(box.width, rect.width * 0.9)
            XCTAssertGreaterThan(box.height, rect.height * 0.9)
            XCTAssertGreaterThanOrEqual(box.minX, rect.minX - 0.5)
            XCTAssertLessThanOrEqual(box.maxX, rect.maxX + 0.5)
            XCTAssertGreaterThanOrEqual(box.minY, rect.minY - 0.5)
            XCTAssertLessThanOrEqual(box.maxY, rect.maxY + 0.5)
        }
    }

    func testPillToOwlMorphShapeClampsOutOfRangeAndNonFiniteProgress() {
        let rect = CGRect(x: 0, y: 0, width: 88, height: 90)
        let boxAtZero = PillToOwlMorphShape.cgPath(in: rect, progress: 0.0).boundingBoxOfPath
        let boxAtOne = PillToOwlMorphShape.cgPath(in: rect, progress: 1.0).boundingBoxOfPath

        for low in [CGFloat(-0.5), -10.0, .nan, -.infinity, .infinity] {
            let path = PillToOwlMorphShape.cgPath(in: rect, progress: low)
            XCTAssertFalse(path.isEmpty)
            let box = path.boundingBoxOfPath
            XCTAssertEqual(box.minX, boxAtZero.minX, accuracy: 0.001)
            XCTAssertEqual(box.minY, boxAtZero.minY, accuracy: 0.001)
            XCTAssertEqual(box.width, boxAtZero.width, accuracy: 0.001)
            XCTAssertEqual(box.height, boxAtZero.height, accuracy: 0.001)
        }

        for high in [CGFloat(1.5), 42.0] {
            let path = PillToOwlMorphShape.cgPath(in: rect, progress: high)
            XCTAssertFalse(path.isEmpty)
            let box = path.boundingBoxOfPath
            XCTAssertEqual(box.minX, boxAtOne.minX, accuracy: 0.001)
            XCTAssertEqual(box.minY, boxAtOne.minY, accuracy: 0.001)
            XCTAssertEqual(box.width, boxAtOne.width, accuracy: 0.001)
            XCTAssertEqual(box.height, boxAtOne.height, accuracy: 0.001)
        }

        XCTAssertTrue(PillToOwlMorphShape.cgPath(in: .zero, progress: 0.5).isEmpty)
        XCTAssertTrue(PillToOwlMorphShape.cgPath(in: .null, progress: 0.5).isEmpty)
        XCTAssertTrue(PillToOwlMorphShape.cgPath(in: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 20), progress: 0.5).isEmpty)
        XCTAssertTrue(PillToOwlMorphShape.cgPath(in: CGRect(x: 0, y: 0, width: 0, height: 20), progress: 0.5).isEmpty)
    }

    func testPillToOwlMorphShapeMatchesNokoOwlAtOneAndDiffersAtZero() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let pillPath = PillToOwlMorphShape.cgPath(in: rect, progress: 0.0)
        let morphedOwlPath = PillToOwlMorphShape.cgPath(in: rect, progress: 1.0)
        let referenceOwlPath = NokoOwlSilhouetteShape.cgPath(in: rect, flipY: false)

        let pillBox = pillPath.boundingBoxOfPath
        let morphedBox = morphedOwlPath.boundingBoxOfPath
        let referenceBox = referenceOwlPath.boundingBoxOfPath

        XCTAssertEqual(morphedBox.minX, referenceBox.minX, accuracy: 0.5)
        XCTAssertEqual(morphedBox.minY, referenceBox.minY, accuracy: 0.5)
        XCTAssertEqual(morphedBox.width, referenceBox.width, accuracy: 0.5)
        XCTAssertEqual(morphedBox.height, referenceBox.height, accuracy: 0.5)

        // At progress == 0.0, top crown is at y = 0.0; at progress == 1.0, crown dips to y = 10.0 while ear-tufts peak around y = 1.4.
        XCTAssertGreaterThan(abs(pillBox.minY - morphedBox.minY), 1.0)
        XCTAssertGreaterThan(abs(pillBox.height - morphedBox.height), 1.0)

        // Verify the crown valley dip directly via hit testing at top-center (50, 4):
        // inside the pill at t = 0, outside the dipped owl crown valley at t = 1.
        let crownProbe = CGPoint(x: 50, y: 4)
        XCTAssertTrue(pillPath.contains(crownProbe))
        XCTAssertFalse(morphedOwlPath.contains(crownProbe))
        XCTAssertFalse(referenceOwlPath.contains(crownProbe))

        var animShape = PillToOwlMorphShape(progress: 0.25)
        XCTAssertEqual(animShape.animatableData, 0.25, accuracy: 0.0001)
        animShape.animatableData = 1.0
        XCTAssertEqual(animShape.progress, 1.0, accuracy: 0.0001)
        let swiftUIPathBox = animShape.path(in: rect).cgPath.boundingBoxOfPath
        XCTAssertEqual(swiftUIPathBox.width, referenceBox.width, accuracy: 0.5)
    }

    func testSquashStretchEndpointAndMidMorphInvariants() {
        let start = HUDMorphMath.squashStretch(progress: 0.0)
        let end = HUDMorphMath.squashStretch(progress: 1.0)
        XCTAssertEqual(start.width, 1.0, accuracy: 0.0001)
        XCTAssertEqual(start.height, 1.0, accuracy: 0.0001)
        XCTAssertEqual(end.width, 1.0, accuracy: 0.0001)
        XCTAssertEqual(end.height, 1.0, accuracy: 0.0001)

        // Out-of-range inputs clamp cleanly to endpoints (1, 1).
        let under = HUDMorphMath.squashStretch(progress: -0.5)
        let over = HUDMorphMath.squashStretch(progress: 1.5)
        XCTAssertEqual(under.width, 1.0, accuracy: 0.0001)
        XCTAssertEqual(under.height, 1.0, accuracy: 0.0001)
        XCTAssertEqual(over.width, 1.0, accuracy: 0.0001)
        XCTAssertEqual(over.height, 1.0, accuracy: 0.0001)

        for step in stride(from: 0.0, through: 1.0, by: 0.025) {
            let scale = HUDMorphMath.squashStretch(progress: CGFloat(step))
            XCTAssertTrue(scale.width.isFinite && scale.height.isFinite)
            XCTAssertGreaterThanOrEqual(scale.width, 0.85)
            XCTAssertLessThanOrEqual(scale.width, 1.20)
            XCTAssertGreaterThanOrEqual(scale.height, 0.85)
            XCTAssertLessThanOrEqual(scale.height, 1.20)
        }

        // Mid-morph (0.3...0.45) exhibits non-trivial vertical elongation out of the pill/notch.
        var maxVerticalElongation: CGFloat = 0
        for step in stride(from: 0.30, through: 0.45, by: 0.02) {
            let scale = HUDMorphMath.squashStretch(progress: CGFloat(step))
            XCTAssertGreaterThan(scale.height, 1.03, "Expected vertical stretch at progress \(step)")
            XCTAssertLessThan(scale.width, 0.98, "Expected horizontal narrowing at progress \(step)")
            maxVerticalElongation = max(maxVerticalElongation, scale.height - scale.width)
        }
        XCTAssertGreaterThan(maxVerticalElongation, 0.10)
    }

    func testMorphShellDimensionsEndpointsAndMonotonicInterpolation() {
        let collapsed = CGSize(width: 46, height: 36)
        let expandedOwlSize: CGFloat = 88
        let expectedTargetWidth = expandedOwlSize * (43.0 / 48.0)
        let expectedTargetHeight = expandedOwlSize * (43.6 / 48.0)

        let atZero = HUDMorphMath.morphShellDimensions(
            progress: 0.0,
            collapsedSize: collapsed,
            expandedOwlSize: expandedOwlSize
        )
        XCTAssertEqual(atZero.width, collapsed.width, accuracy: 0.0001)
        XCTAssertEqual(atZero.height, collapsed.height, accuracy: 0.0001)

        let atOne = HUDMorphMath.morphShellDimensions(
            progress: 1.0,
            collapsedSize: collapsed,
            expandedOwlSize: expandedOwlSize
        )
        XCTAssertEqual(atOne.width, expectedTargetWidth, accuracy: 0.0001)
        XCTAssertEqual(atOne.height, expectedTargetHeight, accuracy: 0.0001)

        var previous = atZero
        for step in stride(from: 0.05, through: 1.0, by: 0.05) {
            let current = HUDMorphMath.morphShellDimensions(
                progress: CGFloat(step),
                collapsedSize: collapsed,
                expandedOwlSize: expandedOwlSize
            )
            XCTAssertGreaterThan(current.width, previous.width)
            XCTAssertGreaterThan(current.height, previous.height)
            XCTAssertLessThanOrEqual(current.width, expectedTargetWidth + 0.0001)
            XCTAssertLessThanOrEqual(current.height, expectedTargetHeight + 0.0001)
            previous = current
        }
    }

    func testSmoothstepLerpAndClamp01BoundaryInvariants() {
        XCTAssertEqual(HUDMorphMath.lerp(12, 64, t: 0.0), 12, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.lerp(12, 64, t: 1.0), 64, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.lerp(12, 64, t: 0.5), 38, accuracy: 0.0001)

        XCTAssertEqual(HUDMorphMath.clamp01(-1.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.clamp01(0.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.clamp01(0.42), 0.42, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.clamp01(1.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.clamp01(2.5), 1.0, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.clamp01(.nan), 0.0, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.clamp01(.infinity), 0.0, accuracy: 0.0001)

        XCTAssertEqual(HUDMorphMath.smoothstep(-0.2, edge0: 0.2, edge1: 0.8), 0.0, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.smoothstep(0.2, edge0: 0.2, edge1: 0.8), 0.0, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.smoothstep(0.5, edge0: 0.2, edge1: 0.8), 0.5, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.smoothstep(0.8, edge0: 0.2, edge1: 0.8), 1.0, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.smoothstep(1.2, edge0: 0.2, edge1: 0.8), 1.0, accuracy: 0.0001)

        // Degenerate zero-span edge0 == edge1 must remain finite.
        XCTAssertEqual(HUDMorphMath.smoothstep(0.4, edge0: 0.5, edge1: 0.5), 0.0, accuracy: 0.0001)
        XCTAssertEqual(HUDMorphMath.smoothstep(0.5, edge0: 0.5, edge1: 0.5), 1.0, accuracy: 0.0001)

        var prevSmooth: CGFloat = 0
        for step in stride(from: 0.2, through: 0.8, by: 0.05) {
            let value = HUDMorphMath.smoothstep(CGFloat(step), edge0: 0.2, edge1: 0.8)
            XCTAssertGreaterThanOrEqual(value, prevSmooth)
            prevSmooth = value
        }
    }

    func testHUDMorphShellShapeProducesValidPathsForFloatingAndNotchModes() {
        let floatingShape = HUDMorphShellShape(topFlare: 0, topRadius: 18, bottomRadius: 18)
        let notchShape = HUDMorphShellShape(topFlare: 8, topRadius: 0, bottomRadius: 12)

        let floatingRect = CGRect(x: 0, y: 0, width: 46, height: 36)
        let notchRect = CGRect(x: 0, y: 0, width: 58, height: 34)

        let floatingBox = floatingShape.path(in: floatingRect).cgPath.boundingBoxOfPath
        let notchBox = notchShape.path(in: notchRect).cgPath.boundingBoxOfPath

        XCTAssertEqual(floatingBox.width, floatingRect.width, accuracy: 0.5)
        XCTAssertEqual(floatingBox.height, floatingRect.height, accuracy: 0.5)
        XCTAssertEqual(notchBox.width, notchRect.width, accuracy: 0.5)
        XCTAssertEqual(notchBox.height, notchRect.height, accuracy: 0.5)
    }
}
