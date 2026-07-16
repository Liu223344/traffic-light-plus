import AppKit
import ApplicationServices
import Testing
@testable import TrafficLightsPlus

@MainActor
@Test func overlayContentFillsResizedPanel() {
    let panel = OverlayPanel(action: .close)
    panel.setFrame(NSRect(x: 100, y: 100, width: 40, height: 40), display: false)
    panel.contentView?.layoutSubtreeIfNeeded()

    #expect(panel.overlayView.frame.origin == .zero)
    #expect(panel.overlayView.frame.size == NSSize(width: 40, height: 40))
    #expect(panel.level == .floating)
}

@MainActor
@Test func minimizedOverlayStaysSuppressedUntilRestored() {
    let pid = ProcessInfo.processInfo.processIdentifier
    let key = AXWindowKey(pid: pid, element: AXUIElementCreateApplication(pid))
    let overlay = WindowOverlay(key: key)

    overlay.suppressUntilRestored()
    #expect(overlay.isSuppressed)
    #expect(overlay.presentationState == .suppressed)

    overlay.restoreFromSuppression()
    #expect(!overlay.isSuppressed)
    #expect(overlay.presentationState == .hidden)
}

@MainActor
@Test func overlayColorVisibilityFollowsActivationAndHover() {
    let panel = OverlayPanel(action: .close)

    #expect(!panel.overlayView.isColorVisible)
    panel.overlayView.isGroupHovered = true
    #expect(panel.overlayView.isColorVisible)
    panel.overlayView.isGroupHovered = false
    #expect(!panel.overlayView.isColorVisible)

    panel.overlayView.isWindowActive = true
    #expect(panel.overlayView.isColorVisible)
    #expect(!panel.overlayView.isPointerHighlightVisible)
}

@Test func symbolRectUsesAnimatedBoundsInsteadOfConfiguredControlSize() throws {
    let compactBounds = NSRect(x: 0, y: 0, width: 14, height: 14)
    let symbolRect = try #require(OverlayButtonView.symbolRect(in: compactBounds, style: .macOS))

    #expect(symbolRect.minX.isFinite)
    #expect(symbolRect.minY.isFinite)
    #expect(symbolRect.width > 0)
    #expect(symbolRect.height > 0)
}

@MainActor
@Test func maximumConfiguredSizeDrawsInsideNativeSizedAnimationFrame() throws {
    for action in WindowAction.allCases {
        let panel = OverlayPanel(action: action)
        panel.overlayView.controlSize = 48
        panel.overlayView.behavior = ButtonBehavior.defaultBehavior(for: action)
        panel.setFrame(NSRect(x: 0, y: 0, width: 14, height: 14), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()

        let representation = try #require(
            panel.overlayView.bitmapImageRepForCachingDisplay(in: panel.overlayView.bounds)
        )
        panel.overlayView.cacheDisplay(in: panel.overlayView.bounds, to: representation)
    }
}
