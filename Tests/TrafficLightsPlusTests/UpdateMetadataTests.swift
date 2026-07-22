import Foundation
import Testing
@testable import TrafficLightsPlus

@Test func updateMetadataEnablesChecksAndDownloadsByDefault() throws {
    let info = try sourceInfoPlist()
    #expect(info["CFBundleShortVersionString"] as? String == "1.4.1")
    #expect(info["CFBundleVersion"] as? String == "6")
    #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
    #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
    #expect((info["SUPublicEDKey"] as? String)?.isEmpty == false)
}

@Test func softwareUpdateCopyIsLocalizedInBothLanguages() {
    #expect(AppLocalization.string(.softwareUpdates, language: .simplifiedChinese) == "软件更新")
    #expect(AppLocalization.string(.softwareUpdates, language: .english) == "Software Updates")
    #expect(AppLocalization.string(.checkForUpdates, language: .simplifiedChinese) == "检查更新…")
    #expect(AppLocalization.string(.checkForUpdates, language: .english) == "Check for Updates…")
}

private func sourceInfoPlist() throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Info.plist"))
    let value = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(value as? [String: Any])
}
