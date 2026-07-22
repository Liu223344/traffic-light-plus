import CoreGraphics
import Testing
@testable import TrafficLightsPlus

@Test func dockClickIntentDistinguishesMinimizeRestoreAndNormalActivation() {
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "COM.EXAMPLE.EDITOR",
        hasVisibleWindow: true,
        hasMinimizedWindow: false,
        detectPendingSystemRestore: true
    ) == .minimize)
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        hasVisibleWindow: false,
        hasMinimizedWindow: true,
        detectPendingSystemRestore: true
    ) == .restoreNatively)
    #expect(DockClickController.clickIntent(
        featureEnabled: false,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        hasVisibleWindow: false,
        hasMinimizedWindow: true,
        detectPendingSystemRestore: true
    ) == nil)
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Browser",
        hasVisibleWindow: true,
        hasMinimizedWindow: false,
        detectPendingSystemRestore: true
    ) == nil)
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        hasVisibleWindow: false,
        hasMinimizedWindow: true,
        detectPendingSystemRestore: false
    ) == nil)
}

@Test func stageManagerRestoreUsesWindowVisibilityBeforeTheDockHandlesTheClick() {
    #expect(DockClickController.observedClickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        wasMinimizedByDock: false,
        hadVisibleWindowAtMouseDown: false,
        hasVisibleWindowAfterDock: false,
        hasMinimizedWindowAfterDock: true
    ) == .restoreNatively)
    #expect(DockClickController.observedClickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        wasMinimizedByDock: false,
        hadVisibleWindowAtMouseDown: true,
        hasVisibleWindowAfterDock: true,
        hasMinimizedWindowAfterDock: false
    ) == .minimize)
    #expect(DockClickController.observedClickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        wasMinimizedByDock: false,
        hadVisibleWindowAtMouseDown: false,
        hasVisibleWindowAfterDock: true,
        hasMinimizedWindowAfterDock: false
    ) == nil)
    #expect(DockClickController.observedClickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Browser",
        wasMinimizedByDock: false,
        hadVisibleWindowAtMouseDown: false,
        hasVisibleWindowAfterDock: false,
        hasMinimizedWindowAfterDock: true
    ) == .restoreNatively)
    #expect(DockClickController.observedClickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        wasMinimizedByDock: false,
        hadVisibleWindowAtMouseDown: true,
        hasVisibleWindowAfterDock: false,
        hasMinimizedWindowAfterDock: true
    ) == .restoreNatively)
    #expect(DockClickController.observedClickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        wasMinimizedByDock: true,
        hadVisibleWindowAtMouseDown: true,
        hasVisibleWindowAfterDock: true,
        hasMinimizedWindowAfterDock: false
    ) == .restoredBySystem)
    #expect(DockClickController.observedClickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        wasMinimizedByDock: true,
        hadVisibleWindowAtMouseDown: false,
        hasVisibleWindowAfterDock: false,
        hasMinimizedWindowAfterDock: true
    ) == .restoreNatively)
}

@Test func dockClickCandidateRejectsDragsAndDifferentDockItems() {
    let candidate = DockClickCandidate(
        pid: 42,
        bundleIdentifier: "com.example.Editor",
        location: CGPoint(x: 100, y: 800),
        timestamp: 10,
        intent: .minimize
    )

    #expect(candidate.matches(
        bundleIdentifier: "COM.EXAMPLE.EDITOR",
        location: CGPoint(x: 104, y: 803),
        timestamp: 10.2
    ))
    #expect(!candidate.matches(
        bundleIdentifier: "com.example.Browser",
        location: CGPoint(x: 104, y: 803),
        timestamp: 10.2
    ))
    #expect(!candidate.matches(
        bundleIdentifier: "com.example.Editor",
        location: CGPoint(x: 120, y: 800),
        timestamp: 10.2
    ))
    #expect(!candidate.matches(
        bundleIdentifier: "com.example.Editor",
        location: CGPoint(x: 100, y: 800),
        timestamp: 11.1
    ))
}

@Test func dockWindowStateUsesAnyUnminimizedAXWindowWhenFocusAttributesAreUnavailable() {
    let visible = DockClickController.summarizedWindowState(
        minimizedStates: [false],
        hasOnScreenWindow: true
    )
    #expect(visible.hasVisibleWindow)
    #expect(!visible.hasMinimizedWindow)

    let mixed = DockClickController.summarizedWindowState(
        minimizedStates: [true, false],
        hasOnScreenWindow: true
    )
    #expect(mixed.hasVisibleWindow)
    #expect(mixed.hasMinimizedWindow)

    let minimized = DockClickController.summarizedWindowState(
        minimizedStates: [true],
        hasOnScreenWindow: true
    )
    #expect(!minimized.hasVisibleWindow)
    #expect(minimized.hasMinimizedWindow)

    let offScreen = DockClickController.summarizedWindowState(
        minimizedStates: [false],
        hasOnScreenWindow: false
    )
    #expect(!offScreen.hasVisibleWindow)
}

@Test func dockClickHandlingSkipsDesktopBeforeAccessibilityHitTesting() {
    let dockFrame = CGRect(x: 100, y: 800, width: 600, height: 80)

    #expect(DockClickController.handlingMode(
        featureEnabled: true,
        stageManagerEnabled: true,
        location: CGPoint(x: 400, y: 400),
        dockFrame: dockFrame
    ) == .ignore)
    #expect(DockClickController.handlingMode(
        featureEnabled: true,
        stageManagerEnabled: true,
        location: CGPoint(x: 400, y: 840),
        dockFrame: dockFrame
    ) == .observeOnly)
    #expect(DockClickController.handlingMode(
        featureEnabled: true,
        stageManagerEnabled: false,
        location: CGPoint(x: 400, y: 840),
        dockFrame: dockFrame
    ) == .observeOnly)
    #expect(DockClickController.handlingMode(
        featureEnabled: false,
        stageManagerEnabled: false,
        location: CGPoint(x: 400, y: 840),
        dockFrame: dockFrame
    ) == .ignore)
    #expect(DockClickController.handlingMode(
        featureEnabled: true,
        stageManagerEnabled: false,
        location: CGPoint(x: 400, y: 840),
        dockFrame: nil
    ) == .ignore)
}

@Test func stageManagerUsesANonBlockingEventTap() {
    #expect(DockClickController.eventTapOptions(stageManagerEnabled: true) == .listenOnly)
    #expect(DockClickController.eventTapOptions(stageManagerEnabled: false) == .listenOnly)
}

@Test func dockMinimizeNeverUsesStaleOverlaysWhenTrafficLightsAreDisabled() {
    #expect(WindowTracker.shouldUseOverlayMinimize(
        overlaysEnabled: true,
        overlayAvailable: true
    ))
    #expect(!WindowTracker.shouldUseOverlayMinimize(
        overlaysEnabled: false,
        overlayAvailable: true
    ))
    #expect(!WindowTracker.shouldUseOverlayMinimize(
        overlaysEnabled: true,
        overlayAvailable: false
    ))
}

@Test func windowTrackingStopsOnlyWhenBothIndependentFeaturesAreInactive() {
    #expect(WindowTracker.shouldTrackWindows(
        overlaysEnabled: true,
        quitOnCloseEnabled: false,
        hasQuitOnCloseApplications: false
    ))
    #expect(WindowTracker.shouldTrackWindows(
        overlaysEnabled: false,
        quitOnCloseEnabled: true,
        hasQuitOnCloseApplications: true
    ))
    #expect(!WindowTracker.shouldTrackWindows(
        overlaysEnabled: false,
        quitOnCloseEnabled: true,
        hasQuitOnCloseApplications: false
    ))
}
