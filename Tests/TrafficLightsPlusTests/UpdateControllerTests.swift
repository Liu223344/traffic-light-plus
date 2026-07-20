import Testing
@testable import TrafficLightsPlus

@Test func automaticDownloadControlRequiresAutomaticChecksAndUpdaterSupport() {
    #expect(UpdateController.automaticDownloadsControlEnabled(
        automaticallyChecksForUpdates: true,
        allowsAutomaticUpdates: true
    ))
    #expect(!UpdateController.automaticDownloadsControlEnabled(
        automaticallyChecksForUpdates: false,
        allowsAutomaticUpdates: true
    ))
    #expect(!UpdateController.automaticDownloadsControlEnabled(
        automaticallyChecksForUpdates: true,
        allowsAutomaticUpdates: false
    ))
}

@Test func updaterConfigurationRequiresAnHTTPSFeedAndPublicKey() {
    #expect(UpdateController.configurationAvailable(
        feedURL: "https://example.com/appcast.xml",
        publicKey: "public-key"
    ))
    #expect(!UpdateController.configurationAvailable(feedURL: nil, publicKey: "public-key"))
    #expect(!UpdateController.configurationAvailable(
        feedURL: "http://example.com/appcast.xml",
        publicKey: "public-key"
    ))
    #expect(!UpdateController.configurationAvailable(
        feedURL: "https://example.com/appcast.xml",
        publicKey: ""
    ))
}
