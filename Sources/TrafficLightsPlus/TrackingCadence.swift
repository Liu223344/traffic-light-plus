import Foundation

struct TrackingCadence {
    static let idleInterval = 1.0 / 10.0
    static let activeInterval = 1.0 / 240.0
    static let activeDuration = 0.35

    private(set) var highFrequencyUntil = 0.0
    private var lastSync = 0.0

    mutating func boost(now: TimeInterval) {
        highFrequencyUntil = max(highFrequencyUntil, now + Self.activeDuration)
    }

    func isHighFrequency(now: TimeInterval) -> Bool {
        now < highFrequencyUntil
    }

    mutating func shouldSync(now: TimeInterval, force: Bool = false) -> Bool {
        let interval = now < highFrequencyUntil ? Self.activeInterval : Self.idleInterval
        guard force || now - lastSync >= interval else { return false }
        lastSync = now
        return true
    }
}
