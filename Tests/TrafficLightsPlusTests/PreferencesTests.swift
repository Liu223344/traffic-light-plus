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
        #expect(preferences.style == .macOS)
        #expect(!preferences.showInFullScreen)
    }
}

@Test func preferencesPersist() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.enabled = false
        preferences.size = 42
        preferences.style = .edgeSquares
        preferences.showInFullScreen = true

        let restored = Preferences(defaults: defaults)
        #expect(!restored.enabled)
        #expect(restored.size == 42)
        #expect(restored.style == .edgeSquares)
        #expect(restored.showInFullScreen)
    }
}

@Test func corruptStoredSizeIsClamped() {
    withDefaults { defaults in
        defaults.set(500, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == 48)

        defaults.set(-20, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == 18)
    }
}
