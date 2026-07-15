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

    overlay.restoreFromSuppression()
    #expect(!overlay.isSuppressed)
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
