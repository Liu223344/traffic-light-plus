import CoreGraphics
import Testing
@testable import TrafficLightsPlus

@Test func preferredSizeIsClampedToSupportedRange() {
    #expect(ControlLayout.effectiveSize(preferred: 4) == 18)
    #expect(ControlLayout.effectiveSize(preferred: 32) == 32)
    #expect(ControlLayout.effectiveSize(preferred: 100) == 48)
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
