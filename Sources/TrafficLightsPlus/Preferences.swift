import Foundation

enum ControlStyle: String, CaseIterable {
    case macOS
    case edgeSquares

    var title: String {
        switch self {
        case .macOS: return "macOS 圆形"
        case .edgeSquares: return "左侧贴边方块"
        }
    }
}

final class Preferences: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let size = "controlSize"
        static let style = "controlStyle"
        static let showInFullScreen = "showInFullScreen"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    @Published var size: Double {
        didSet { defaults.set(size, forKey: Key.size) }
    }

    @Published var style: ControlStyle {
        didSet { defaults.set(style.rawValue, forKey: Key.style) }
    }

    @Published var showInFullScreen: Bool {
        didSet { defaults.set(showInFullScreen, forKey: Key.showInFullScreen) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.size: 28.0,
            Key.style: ControlStyle.macOS.rawValue,
            Key.showInFullScreen: false
        ])
        enabled = defaults.bool(forKey: Key.enabled)
        size = min(max(defaults.double(forKey: Key.size), ControlLayout.sizeRange.lowerBound), ControlLayout.sizeRange.upperBound)
        style = ControlStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .macOS
        showInFullScreen = defaults.bool(forKey: Key.showInFullScreen)
    }
}
