import CoreGraphics
import Testing
@testable import TrafficLightsPlus

@Test func dockClickIntentDistinguishesMinimizeRestoreAndNormalActivation() {
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "COM.EXAMPLE.EDITOR",
        hasVisibleWindow: true,
        hasMinimizedWindow: false
    ) == .minimize)
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        hasVisibleWindow: false,
        hasMinimizedWindow: true
    ) == .restore)
    #expect(DockClickController.clickIntent(
        featureEnabled: false,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Editor",
        hasVisibleWindow: false,
        hasMinimizedWindow: true
    ) == nil)
    #expect(DockClickController.clickIntent(
        featureEnabled: true,
        clickedBundleIdentifier: "com.example.Editor",
        frontmostBundleIdentifier: "com.example.Browser",
        hasVisibleWindow: true,
        hasMinimizedWindow: false
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
