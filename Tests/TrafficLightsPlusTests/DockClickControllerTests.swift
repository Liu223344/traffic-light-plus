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
        allowRestoreInterception: true
    ) == .minimize)
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        hasVisibleWindow: false,
        hasMinimizedWindow: true,
        allowRestoreInterception: true
    ) == .restore)
    #expect(DockClickController.clickIntent(
        featureEnabled: false,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        hasVisibleWindow: false,
        hasMinimizedWindow: true,
        allowRestoreInterception: true
    ) == nil)
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Browser",
        hasVisibleWindow: true,
        hasMinimizedWindow: false,
        allowRestoreInterception: true
    ) == nil)
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        hasVisibleWindow: false,
        hasMinimizedWindow: true,
        allowRestoreInterception: false
    ) == nil)
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
