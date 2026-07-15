import Testing
@testable import TrafficLightsPlus

@Test func trackingCadenceUsesIdleAndActiveRates() {
    var cadence = TrackingCadence()

    let first = cadence.shouldSync(now: 1.0, force: true)
    let earlyIdle = cadence.shouldSync(now: 1.01)
    let nextIdle = cadence.shouldSync(now: 1.11)
    #expect(first)
    #expect(!earlyIdle)
    #expect(nextIdle)

    cadence.boost(now: 2.0)
    #expect(cadence.isHighFrequency(now: 2.1))
    #expect(!cadence.isHighFrequency(now: 2.36))
    let firstActive = cadence.shouldSync(now: 2.0)
    let earlyActive = cadence.shouldSync(now: 2.002)
    let nextActive = cadence.shouldSync(now: 2.005)
    #expect(firstActive)
    #expect(!earlyActive)
    #expect(nextActive)
    #expect(cadence.highFrequencyUntil == 2.35)
}

@Test func forcedTrackingSyncBypassesCadenceLimit() {
    var cadence = TrackingCadence()
    let first = cadence.shouldSync(now: 10.0, force: true)
    let second = cadence.shouldSync(now: 10.001, force: true)
    #expect(first)
    #expect(second)
}
