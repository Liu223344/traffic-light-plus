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
