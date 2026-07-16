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

enum HiddenTrafficLightRevealMode: String, CaseIterable {
    case group
    case nearest

    var title: String {
        switch self {
        case .group: return "整组"
        case .nearest: return "单个"
        }
    }
}

final class Preferences: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let size = "controlSize"
        static let spacing = "controlSpacingAdjustment"
        static let style = "controlStyle"
        static let hiddenTrafficLightsEnabled = "hiddenTrafficLightsEnabled"
        static let hiddenTrafficLightRevealMode = "hiddenTrafficLightRevealMode"
        static let showInFullScreen = "showInFullScreen"
        static let closeBehavior = "closeButtonBehavior"
        static let minimizeBehavior = "minimizeButtonBehavior"
        static let zoomBehavior = "zoomButtonBehavior"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    @Published var size: Double {
        didSet { defaults.set(size, forKey: Key.size) }
    }

    @Published var spacing: Double {
        didSet { defaults.set(spacing, forKey: Key.spacing) }
    }

    @Published var style: ControlStyle {
        didSet { defaults.set(style.rawValue, forKey: Key.style) }
    }

    @Published var hiddenTrafficLightsEnabled: Bool {
        didSet { defaults.set(hiddenTrafficLightsEnabled, forKey: Key.hiddenTrafficLightsEnabled) }
    }

    @Published var hiddenTrafficLightRevealMode: HiddenTrafficLightRevealMode {
        didSet { defaults.set(hiddenTrafficLightRevealMode.rawValue, forKey: Key.hiddenTrafficLightRevealMode) }
    }

    @Published var showInFullScreen: Bool {
        didSet { defaults.set(showInFullScreen, forKey: Key.showInFullScreen) }
    }

    @Published var closeBehavior: ButtonBehavior {
        didSet { defaults.set(closeBehavior.rawValue, forKey: Key.closeBehavior) }
    }

    @Published var minimizeBehavior: ButtonBehavior {
        didSet { defaults.set(minimizeBehavior.rawValue, forKey: Key.minimizeBehavior) }
    }

    @Published var zoomBehavior: ButtonBehavior {
        didSet { defaults.set(zoomBehavior.rawValue, forKey: Key.zoomBehavior) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.size: 28.0,
            Key.spacing: 0.0,
            Key.style: ControlStyle.macOS.rawValue,
            Key.hiddenTrafficLightsEnabled: true,
            Key.hiddenTrafficLightRevealMode: HiddenTrafficLightRevealMode.nearest.rawValue,
            Key.showInFullScreen: false,
            Key.closeBehavior: ButtonBehavior.closeWindow.rawValue,
            Key.minimizeBehavior: ButtonBehavior.minimizeWindow.rawValue,
            Key.zoomBehavior: ButtonBehavior.zoomWindow.rawValue
        ])
        enabled = defaults.bool(forKey: Key.enabled)
        size = min(max(defaults.double(forKey: Key.size), ControlLayout.sizeRange.lowerBound), ControlLayout.sizeRange.upperBound)
        spacing = min(
            max(defaults.double(forKey: Key.spacing), ControlLayout.spacingAdjustmentRange.lowerBound),
            ControlLayout.spacingAdjustmentRange.upperBound
        )
        style = ControlStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .macOS
        hiddenTrafficLightsEnabled = defaults.bool(forKey: Key.hiddenTrafficLightsEnabled)
        hiddenTrafficLightRevealMode = HiddenTrafficLightRevealMode(
            rawValue: defaults.string(forKey: Key.hiddenTrafficLightRevealMode) ?? ""
        ) ?? .nearest
        showInFullScreen = defaults.bool(forKey: Key.showInFullScreen)
        closeBehavior = ButtonBehavior(rawValue: defaults.string(forKey: Key.closeBehavior) ?? "") ?? .closeWindow
        minimizeBehavior = ButtonBehavior(rawValue: defaults.string(forKey: Key.minimizeBehavior) ?? "") ?? .minimizeWindow
        zoomBehavior = ButtonBehavior(rawValue: defaults.string(forKey: Key.zoomBehavior) ?? "") ?? .zoomWindow
    }

    func behavior(for action: WindowAction) -> ButtonBehavior {
        switch action {
        case .close: return closeBehavior
        case .minimize: return minimizeBehavior
        case .zoom: return zoomBehavior
        }
    }

    func resetButtonBehaviors() {
        closeBehavior = .closeWindow
        minimizeBehavior = .minimizeWindow
        zoomBehavior = .zoomWindow
    }
}
