import Foundation
import Testing
@testable import TrafficLightsPlus

private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "TrafficLightsPlusTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}

@Test func preferenceDefaultsAreUsable() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.enabled)
        #expect(preferences.size == 28)
        #expect(preferences.spacing == 0)
        #expect(preferences.style == .macOS)
        #expect(preferences.hiddenTrafficLightsEnabled)
        #expect(preferences.hiddenTrafficLightRevealMode == .nearest)
        #expect(!preferences.showInFullScreen)
        #expect(preferences.closeBehavior == .closeWindow)
        #expect(preferences.minimizeBehavior == .minimizeWindow)
        #expect(preferences.zoomBehavior == .zoomWindow)
    }
}

@Test func preferencesPersist() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.enabled = false
        preferences.size = 42
        preferences.spacing = 12
        preferences.style = .edgeSquares
        preferences.hiddenTrafficLightsEnabled = false
        preferences.hiddenTrafficLightRevealMode = .group
        preferences.showInFullScreen = true
        preferences.closeBehavior = .quitApplication
        preferences.minimizeBehavior = .hideApplication
        preferences.zoomBehavior = .doNothing

        let restored = Preferences(defaults: defaults)
        #expect(!restored.enabled)
        #expect(restored.size == 42)
        #expect(restored.spacing == 12)
        #expect(restored.style == .edgeSquares)
        #expect(!restored.hiddenTrafficLightsEnabled)
        #expect(restored.hiddenTrafficLightRevealMode == .group)
        #expect(restored.showInFullScreen)
        #expect(restored.closeBehavior == .quitApplication)
        #expect(restored.minimizeBehavior == .hideApplication)
        #expect(restored.zoomBehavior == .doNothing)
    }
}

@Test func corruptStoredRevealModeFallsBackToNearest() {
    withDefaults { defaults in
        defaults.set("unknown", forKey: "hiddenTrafficLightRevealMode")
        #expect(Preferences(defaults: defaults).hiddenTrafficLightRevealMode == .nearest)
    }
}

@Test func corruptStoredBehaviorsFallBackToNativeDefaults() {
    withDefaults { defaults in
        defaults.set("unknown", forKey: "closeButtonBehavior")
        defaults.set("unknown", forKey: "minimizeButtonBehavior")
        defaults.set("unknown", forKey: "zoomButtonBehavior")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.closeBehavior == .closeWindow)
        #expect(preferences.minimizeBehavior == .minimizeWindow)
        #expect(preferences.zoomBehavior == .zoomWindow)
    }
}

@Test func buttonBehaviorNativeActionMappingIsStable() {
    #expect(ButtonBehavior.closeWindow.nativeWindowAction == .close)
    #expect(ButtonBehavior.minimizeWindow.nativeWindowAction == .minimize)
    #expect(ButtonBehavior.zoomWindow.nativeWindowAction == .zoom)
    #expect(ButtonBehavior.quitApplication.nativeWindowAction == nil)
}

@Test func corruptStoredSizeIsClamped() {
    withDefaults { defaults in
        defaults.set(500, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == 48)

        defaults.set(-20, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == 18)
    }
}

@Test func corruptStoredSpacingIsClamped() {
    withDefaults { defaults in
        defaults.set(500, forKey: "controlSpacingAdjustment")
        #expect(Preferences(defaults: defaults).spacing == 32)

        defaults.set(-500, forKey: "controlSpacingAdjustment")
        #expect(Preferences(defaults: defaults).spacing == -8)
    }
}
