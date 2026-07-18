import Foundation

enum ButtonBehavior: String, CaseIterable, Identifiable {
    case closeWindow
    case quitApplication
    case minimizeWindow
    case zoomWindow
    case hideApplication
    case doNothing

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .closeWindow: return AppLocalization.string(.behaviorCloseWindow, language: language)
        case .quitApplication: return AppLocalization.string(.behaviorQuitApplication, language: language)
        case .minimizeWindow: return AppLocalization.string(.behaviorMinimizeWindow, language: language)
        case .zoomWindow: return AppLocalization.string(.behaviorZoomWindow, language: language)
        case .hideApplication: return AppLocalization.string(.behaviorHideApplication, language: language)
        case .doNothing: return AppLocalization.string(.behaviorDoNothing, language: language)
        }
    }

    var nativeWindowAction: WindowAction? {
        switch self {
        case .closeWindow: return .close
        case .minimizeWindow: return .minimize
        case .zoomWindow: return .zoom
        case .quitApplication, .hideApplication, .doNothing: return nil
        }
    }

    static func defaultBehavior(for action: WindowAction) -> ButtonBehavior {
        switch action {
        case .close: return .closeWindow
        case .minimize: return .minimizeWindow
        case .zoom: return .zoomWindow
        }
    }
}
