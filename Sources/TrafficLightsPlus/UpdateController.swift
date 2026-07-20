import Combine
import Sparkle

final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var automaticallyDownloadsUpdates = true
    @Published private(set) var allowsAutomaticUpdates = false
    let updaterAvailable: Bool

    private let updaterController: SPUStandardUpdaterController
    private var subscriptions = Set<AnyCancellable>()

    override init() {
        updaterAvailable = Self.configurationAvailable(
            feedURL: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        observeUpdater()
    }

    func start() {
        guard updaterAvailable else { return }
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard automaticDownloadsControlEnabled else { return }
        updaterController.updater.automaticallyDownloadsUpdates = enabled
    }

    var automaticDownloadsControlEnabled: Bool {
        Self.automaticDownloadsControlEnabled(
            automaticallyChecksForUpdates: automaticallyChecksForUpdates,
            allowsAutomaticUpdates: allowsAutomaticUpdates
        )
    }

    static func automaticDownloadsControlEnabled(
        automaticallyChecksForUpdates: Bool,
        allowsAutomaticUpdates: Bool
    ) -> Bool {
        automaticallyChecksForUpdates && allowsAutomaticUpdates
    }

    static func configurationAvailable(feedURL: String?, publicKey: String?) -> Bool {
        guard let feedURL,
              let url = URL(string: feedURL),
              url.scheme?.lowercased() == "https",
              let publicKey else { return false }
        return !publicKey.isEmpty
    }

    private func observeUpdater() {
        let updater = updaterController.updater
        updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyDownloadsUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }
            .store(in: &subscriptions)
        updater.publisher(for: \.allowsAutomaticUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.allowsAutomaticUpdates = $0 }
            .store(in: &subscriptions)
    }
}
