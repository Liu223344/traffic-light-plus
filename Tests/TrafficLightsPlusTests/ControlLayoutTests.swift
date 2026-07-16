import CoreGraphics
import Testing
@testable import TrafficLightsPlus

@Test func preferredSizeIsClampedToSupportedRange() {
    #expect(ControlLayout.effectiveSize(preferred: 4) == 18)
    #expect(ControlLayout.effectiveSize(preferred: 32) == 32)
    #expect(ControlLayout.effectiveSize(preferred: 100) == 48)
}

@Test func circleFrameUsesNativeButtonCenter() {
    let native = CGRect(x: 20, y: 12, width: 14, height: 14)
    let enlarged = ControlLayout.frameCentered(on: native, controlSize: 28)

    #expect(enlarged == CGRect(x: 13, y: 5, width: 28, height: 28))
    #expect(enlarged.midX == native.midX)
    #expect(enlarged.midY == native.midY)
}

@Test func spacingAdjustmentKeepsCloseCenteredAndMovesFollowingButtons() {
    let nativeCenter = CGPoint(x: 100, y: 20)

    #expect(ControlLayout.centerByAdjustingSystemSpacing(
        nativeCenter,
        action: .close,
        adjustment: 6
    ) == nativeCenter)
    #expect(ControlLayout.centerByAdjustingSystemSpacing(
        nativeCenter,
        action: .minimize,
        adjustment: 6
    ) == CGPoint(x: 106, y: 20))
    #expect(ControlLayout.centerByAdjustingSystemSpacing(
        nativeCenter,
        action: .zoom,
        adjustment: 6
    ) == CGPoint(x: 112, y: 20))
}

@Test func occlusionHidesOnlyTheCoveredTrafficLight() {
    let frames: [WindowAction: CGRect] = [
        .close: CGRect(x: 100, y: 100, width: 30, height: 30),
        .minimize: CGRect(x: 138, y: 100, width: 30, height: 30),
        .zoom: CGRect(x: 176, y: 100, width: 30, height: 30)
    ]
    let foregroundWindow = CGRect(x: 190, y: 80, width: 500, height: 500)

    let visible = ControlLayout.unobscuredActions(
        controlFrames: frames,
        coveringFrames: [foregroundWindow]
    )

    #expect(visible == Set([.close, .minimize]))
}

@Test func activationRegionWrapsVisibleTrafficLightsWithPadding() throws {
    let frames: [WindowAction: CGRect] = [
        .close: CGRect(x: 100, y: 80, width: 28, height: 28),
        .minimize: CGRect(x: 140, y: 80, width: 28, height: 28),
        .zoom: CGRect(x: 180, y: 80, width: 28, height: 28)
    ]

    let region = try #require(ControlLayout.activationRegion(
        controlFrames: frames,
        actions: [.close, .minimize, .zoom]
    ))
    #expect(region == CGRect(x: 94, y: 74, width: 120, height: 40))

    let partiallyVisible = try #require(ControlLayout.activationRegion(
        controlFrames: frames,
        actions: [.close, .minimize]
    ))
    #expect(partiallyVisible == CGRect(x: 94, y: 74, width: 80, height: 40))
}

@Test func presentationFrameInterpolatesWithoutJumping() {
    let native = CGRect(x: 100, y: 80, width: 14, height: 14)
    let enlarged = CGRect(x: 93, y: 73, width: 28, height: 28)

    #expect(ControlLayout.interpolatedFrame(from: native, to: enlarged, progress: 0) == native)
    #expect(ControlLayout.interpolatedFrame(from: native, to: enlarged, progress: 0.5)
        == CGRect(x: 96.5, y: 76.5, width: 21, height: 21))
    #expect(ControlLayout.interpolatedFrame(from: native, to: enlarged, progress: 1) == enlarged)
}

@Test func presentationProgressSupportsImmediateReversal() {
    let expandedHalfway = ControlLayout.nextPresentationProgress(
        current: 0,
        elapsed: 0.05,
        expanding: true,
        duration: 0.10
    )
    #expect(expandedHalfway == 0.5)

    let reversed = ControlLayout.nextPresentationProgress(
        current: expandedHalfway,
        elapsed: 0.02,
        expanding: false,
        duration: 0.10
    )
    #expect(abs(reversed - 0.3) < 0.0001)
    #expect(ControlLayout.nextPresentationProgress(
        current: 0.95,
        elapsed: 1,
        expanding: true,
        duration: 0.10
    ) == 1)
    #expect(ControlLayout.nextPresentationProgress(
        current: 0.05,
        elapsed: 1,
        expanding: false,
        duration: 0.10
    ) == 0)
}

@Test func minimizeDismissalShrinksToNativeSizeInSixtyMilliseconds() {
    let halfway = ControlLayout.nextPresentationProgress(
        current: 1,
        elapsed: WindowOverlay.minimizeDismissDuration / 2,
        expanding: false,
        duration: WindowOverlay.minimizeDismissDuration
    )
    let hidden = ControlLayout.nextPresentationProgress(
        current: 1,
        elapsed: WindowOverlay.minimizeDismissDuration,
        expanding: false,
        duration: WindowOverlay.minimizeDismissDuration
    )

    #expect(abs(halfway - 0.5) < 0.0001)
    #expect(hidden == 0)
}

@Test func nearestActionUsesDirectHitsAndGapDistance() {
    let frames: [WindowAction: CGRect] = [
        .close: CGRect(x: 0, y: 0, width: 12, height: 12),
        .minimize: CGRect(x: 20, y: 0, width: 12, height: 12),
        .zoom: CGRect(x: 40, y: 0, width: 12, height: 12)
    ]
    let actions = Set(WindowAction.allCases)

    #expect(ControlLayout.nearestAction(
        to: CGPoint(x: 4, y: 6),
        controlFrames: frames,
        actions: actions,
        currentAction: .zoom
    ) == .close)
    #expect(ControlLayout.nearestAction(
        to: CGPoint(x: 18, y: 6),
        controlFrames: frames,
        actions: actions,
        currentAction: nil
    ) == .minimize)
}

@Test func nearestActionUsesFourPointHysteresisInGaps() {
    let frames: [WindowAction: CGRect] = [
        .close: CGRect(x: 0, y: 0, width: 12, height: 12),
        .minimize: CGRect(x: 20, y: 0, width: 12, height: 12),
        .zoom: CGRect(x: 40, y: 0, width: 12, height: 12)
    ]
    let actions = Set(WindowAction.allCases)

    #expect(ControlLayout.nearestAction(
        to: CGPoint(x: 16, y: 16),
        controlFrames: frames,
        actions: actions,
        currentAction: .close
    ) == .close)
    #expect(ControlLayout.nearestAction(
        to: CGPoint(x: 19, y: 16),
        controlFrames: frames,
        actions: actions,
        currentAction: .close
    ) == .minimize)
    #expect(ControlLayout.nearestAction(
        to: CGPoint(x: 45, y: 6),
        controlFrames: frames,
        actions: [.close, .zoom],
        currentAction: .minimize
    ) == .zoom)
}

@Test func nearestActionUsesHysteresisInOverlappingButtonFrames() {
    let frames: [WindowAction: CGRect] = [
        .close: CGRect(x: 0, y: 0, width: 28, height: 28),
        .minimize: CGRect(x: 20, y: 0, width: 28, height: 28)
    ]
    let actions: Set<WindowAction> = [.close, .minimize]

    #expect(ControlLayout.nearestAction(
        to: CGPoint(x: 25, y: 14),
        controlFrames: frames,
        actions: actions,
        currentAction: .close
    ) == .close)
    #expect(ControlLayout.nearestAction(
        to: CGPoint(x: 28, y: 14),
        controlFrames: frames,
        actions: actions,
        currentAction: .close
    ) == .minimize)
}

@Test func revealModeSelectsGroupOrNearestAction() {
    let frames: [WindowAction: CGRect] = [
        .close: CGRect(x: 0, y: 0, width: 12, height: 12),
        .minimize: CGRect(x: 20, y: 0, width: 12, height: 12),
        .zoom: CGRect(x: 40, y: 0, width: 12, height: 12)
    ]
    let actions = Set(WindowAction.allCases)

    #expect(ControlLayout.revealActions(
        mode: .group,
        pointer: CGPoint(x: 24, y: 6),
        controlFrames: frames,
        actions: actions,
        currentAction: nil
    ) == actions)
    #expect(ControlLayout.revealActions(
        mode: .nearest,
        pointer: CGPoint(x: 24, y: 6),
        controlFrames: frames,
        actions: actions,
        currentAction: nil
    ) == [.minimize])
}

@Test func macOSFramesHaveDraggableGaps() throws {
    let frames = ControlLayout.frames(
        style: .macOS,
        controlSize: 28,
        windowOrigin: CGPoint(x: 100, y: 50),
        windowSize: CGSize(width: 900, height: 600)
    )

    #expect(frames[.close] == CGRect(x: 112, y: 54, width: 28, height: 28))
    #expect(frames[.minimize] == CGRect(x: 148, y: 54, width: 28, height: 28))
    #expect(frames[.zoom] == CGRect(x: 184, y: 54, width: 28, height: 28))
}

@Test func squareFramesTouchWindowEdgesAndEachOther() throws {
    let frames = ControlLayout.frames(
        style: .edgeSquares,
        controlSize: 32,
        windowOrigin: CGPoint(x: 100, y: 50),
        windowSize: CGSize(width: 900, height: 600)
    )

    #expect(frames[.close] == CGRect(x: 100, y: 50, width: 32, height: 32))
    #expect(frames[.minimize] == CGRect(x: 132, y: 50, width: 32, height: 32))
    #expect(frames[.zoom] == CGRect(x: 164, y: 50, width: 32, height: 32))
}

@Test func onlyLeftSideStylesAreExposed() {
    #expect(ControlStyle.allCases == [.macOS, .edgeSquares])
    #expect(ControlLayout.displayOrder(for: .macOS) == [.close, .minimize, .zoom])
    #expect(ControlLayout.displayOrder(for: .edgeSquares) == [.close, .minimize, .zoom])
}
