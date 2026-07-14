import AppKit
import ApplicationServices
import Combine
import OSLog

final class WindowTracker {
    private let preferences: Preferences
    private let panels: [WindowAction: OverlayPanel]
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "window-tracker")
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var targetButtons: [WindowAction: AXUIElement] = [:]
    private var lastExternalWindow: AXUIElement?
    private var lastDiagnostic = ""

    init(preferences: Preferences) {
        self.preferences = preferences
        panels = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map { ($0, OverlayPanel(action: $0)) })

        for panel in panels.values {
            panel.overlayView.actionHandler = { [weak self] action in self?.perform(action) }
        }

        preferences.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &subscriptions)

        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    deinit { timer?.invalidate() }

    func refresh() {
        guard preferences.enabled else { report("disabled"); hideAll(); return }
        guard AXIsProcessTrusted() else { report("accessibility permission unavailable"); hideAll(); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { report("frontmost application unavailable"); hideAll(); return }
        let window: AXUIElement
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            guard let cachedWindow = lastExternalWindow else { report("settings active without a previous target"); hideAll(); return }
            window = cachedWindow
        } else {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let focusedWindow: AXUIElement = copyAttribute(kAXFocusedWindowAttribute as CFString, from: appElement) else {
                report("focused window unavailable for \(app.localizedName ?? "unknown")")
                hideAll()
                return
            }
            window = focusedWindow
            lastExternalWindow = focusedWindow
        }

        guard
              let position: AXValue = copyAttribute(kAXPositionAttribute as CFString, from: window),
              let size: AXValue = copyAttribute(kAXSizeAttribute as CFString, from: window) else {
            report("window position or size unavailable")
            hideAll()
            return
        }

        if !preferences.showInFullScreen,
           let isFullScreen: Bool = copyAttribute("AXFullScreen" as CFString, from: window),
           isFullScreen {
            report("full-screen target hidden by preference")
            hideAll()
            return
        }

        var cgPosition = CGPoint.zero
        var cgSize = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &cgPosition),
              AXValueGetValue(size, .cgSize, &cgSize),
              cgSize.width > 100,
              cgSize.height > 60 else {
            report("invalid target window geometry")
            hideAll()
            return
        }

        let controlSize = ControlLayout.effectiveSize(preferred: preferences.size)
        let frames = ControlLayout.frames(
            style: preferences.style,
            controlSize: controlSize,
            windowOrigin: cgPosition,
            windowSize: cgSize
        )

        targetButtons.removeAll(keepingCapacity: true)
        var visibleActions: [String] = []
        for action in WindowAction.allCases {
            guard let panel = panels[action], let cgFrame = frames[action] else { continue }
            guard let button: AXUIElement = copyAttribute(attribute(for: action), from: window) else {
                panel.orderOut(nil)
                continue
            }

            targetButtons[action] = button
            visibleActions.append(String(describing: action))
            let isEnabled: Bool = copyAttribute(kAXEnabledAttribute as CFString, from: button) ?? true
            guard let origin = appKitOrigin(forCGPoint: cgFrame.origin, size: cgFrame.size) else {
                panel.orderOut(nil)
                continue
            }

            panel.overlayView.style = preferences.style
            panel.overlayView.controlSize = controlSize
            panel.overlayView.isControlEnabled = isEnabled
            let newFrame = NSRect(origin: origin, size: cgFrame.size)
            if panel.frame != newFrame { panel.setFrame(newFrame, display: true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        let closeFrame = frames[.close].map(NSStringFromRect) ?? "missing"
        report("showing \(visibleActions.joined(separator: ",")) for \(app.localizedName ?? "cached window"); window=\(NSStringFromRect(CGRect(origin: cgPosition, size: cgSize))); close=\(closeFrame)")
    }

    private func perform(_ action: WindowAction) {
        guard let button = targetButtons[action] else { return }
        if AXUIElementPerformAction(button, kAXPressAction as CFString) != .success { NSSound.beep() }
    }

    private func hideAll() {
        targetButtons.removeAll(keepingCapacity: true)
        for panel in panels.values where panel.isVisible { panel.orderOut(nil) }
    }

    private func report(_ diagnostic: String) {
        guard diagnostic != lastDiagnostic else { return }
        lastDiagnostic = diagnostic
        logger.notice("\(diagnostic, privacy: .public)")
    }

    private func attribute(for action: WindowAction) -> CFString {
        switch action {
        case .close: return kAXCloseButtonAttribute as CFString
        case .minimize: return kAXMinimizeButtonAttribute as CFString
        case .zoom: return kAXZoomButtonAttribute as CFString
        }
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }

    private func appKitOrigin(forCGPoint point: CGPoint, size: CGSize) -> CGPoint? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let cgBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            if cgBounds.contains(point) {
                return CGPoint(
                    x: screen.frame.minX + point.x - cgBounds.minX,
                    y: screen.frame.maxY - (point.y - cgBounds.minY) - size.height
                )
            }
        }
        return nil
    }
}
