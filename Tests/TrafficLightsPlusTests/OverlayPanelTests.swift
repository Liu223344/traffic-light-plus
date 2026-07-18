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
@Test func periodicWindowStateRecoversFromMissedDeminiaturizeNotification() {
    let pid = ProcessInfo.processInfo.processIdentifier
    let key = AXWindowKey(pid: pid, element: AXUIElementCreateApplication(pid))
    let overlay = WindowOverlay(key: key)

    #expect(!overlay.reconcileMinimizedState(true))
    #expect(overlay.isSuppressed)

    // Stage Manager does not consistently deliver AXWindowDeminiaturized.
    // The next periodic AX state refresh must still restore the overlay.
    #expect(overlay.reconcileMinimizedState(false))
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

@MainActor
@Test func overlayTooltipUpdatesWhenLanguageChanges() {
    let panel = OverlayPanel(action: .close)
    panel.overlayView.behavior = .quitApplication
    panel.overlayView.language = .simplifiedChinese
    #expect(panel.overlayView.toolTip == "退出当前应用")

    panel.overlayView.language = .english
    #expect(panel.overlayView.toolTip == "Quit Current Application")
}

@Test func zoomMenuEligibilityRequiresZoomBehaviorAndActiveSupportedControl() {
    #expect(WindowOverlay.zoomMenuHoverDelay == 0.5)
    #expect(WindowOverlay.shouldOfferZoomMenu(
        behavior: .zoomWindow,
        isActiveWindow: true,
        isControlEnabled: true,
        supportsShowMenu: true
    ))
    #expect(!WindowOverlay.shouldOfferZoomMenu(
        behavior: .closeWindow,
        isActiveWindow: true,
        isControlEnabled: true,
        supportsShowMenu: true
    ))
    #expect(!WindowOverlay.shouldOfferZoomMenu(
        behavior: .zoomWindow,
        isActiveWindow: false,
        isControlEnabled: true,
        supportsShowMenu: true
    ))
    #expect(!WindowOverlay.shouldOfferZoomMenu(
        behavior: .zoomWindow,
        isActiveWindow: true,
        isControlEnabled: false,
        supportsShowMenu: true
    ))
    #expect(!WindowOverlay.shouldOfferZoomMenu(
        behavior: .zoomWindow,
        isActiveWindow: true,
        isControlEnabled: true,
        supportsShowMenu: false
    ))
}

@Test func zoomClickWaitsOnlyForARecentlyTriggeredHoverMenu() {
    #expect(WindowOverlay.zoomActionDelay(menuTriggeredAt: nil, now: 10) == 0)
    #expect(WindowOverlay.zoomActionDelay(menuTriggeredAt: 10, now: 10.5) == 0.12)
    #expect(WindowOverlay.zoomActionDelay(menuTriggeredAt: 10, now: 11.01) == 0)
    #expect(WindowOverlay.zoomActionDelay(menuTriggeredAt: 11, now: 10) == 0)
}

@MainActor
@Test func overlayPressHandlerRunsOnMouseDown() throws {
    let panel = OverlayPanel(action: .zoom)
    var pressedAction: WindowAction?
    panel.overlayView.pressHandler = { pressedAction = $0 }
    let event = try #require(NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    ))

    panel.overlayView.mouseDown(with: event)
    #expect(pressedAction == .zoom)
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
