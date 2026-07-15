import AppKit
import ApplicationServices
import OSLog

struct AXWindowKey: Hashable {
    let pid: pid_t
    let element: AXUIElement

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(CFHash(element))
    }

    static func == (lhs: AXWindowKey, rhs: AXWindowKey) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
    }
}

final class WindowOverlay {
    let key: AXWindowKey
    private let panels: [WindowAction: OverlayPanel]
    private(set) var windowFrame = CGRect.zero
    private(set) var title = ""
    private(set) var cgWindowID: CGWindowID?

    private let window: AXUIElement
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "window-overlay")
    private var targetButtons: [WindowAction: AXUIElement] = [:]
    private var nativeCenterOffsets: [WindowAction: CGPoint] = [:]
    private var preparedCGFrames: [WindowAction: CGRect] = [:]
    private var preparedActions = Set<WindowAction>()
    private var visibleActions = Set<WindowAction>()
    private var lastDiagnostic = ""
    private var hoverResetWorkItem: DispatchWorkItem?

    init(key: AXWindowKey) {
        self.key = key
        window = key.element
        panels = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map { ($0, OverlayPanel(action: $0)) })
        for panel in panels.values {
            panel.overlayView.actionHandler = { [weak self] action in self?.perform(action) }
            panel.overlayView.hoverHandler = { [weak self] hovered in self?.setGroupHovered(hovered) }
        }
    }

    @discardableResult
    func update(preferences: Preferences, recalibrateNativeCenters: Bool = true) -> Bool {
        guard let frame = axFrame(of: window), frame.width > 100, frame.height > 60 else {
            hide()
            return false
        }

        let minimized: Bool = copyAttribute(kAXMinimizedAttribute as CFString, from: window) ?? false
        let fullScreen: Bool = copyAttribute("AXFullScreen" as CFString, from: window) ?? false
        guard !minimized, preferences.showInFullScreen || !fullScreen else {
            hide()
            return false
        }

        windowFrame = frame
        title = copyAttribute(kAXTitleAttribute as CFString, from: window) ?? ""
        let appIsActive = NSRunningApplication(processIdentifier: key.pid)?.isActive ?? false
        let windowIsFocused: Bool = copyAttribute(kAXFocusedAttribute as CFString, from: window) ?? false
        let windowIsMain: Bool = copyAttribute(kAXMainAttribute as CFString, from: window) ?? false
        let isActiveWindow = appIsActive && (windowIsFocused || windowIsMain)
        let controlSize = ControlLayout.effectiveSize(preferred: preferences.size)
        var buttons: [WindowAction: AXUIElement] = [:]
        var frames: [WindowAction: CGRect] = [:]

        for action in WindowAction.allCases {
            guard let button: AXUIElement = copyAttribute(attribute(for: action), from: window) else { continue }
            buttons[action] = button
            if preferences.style == .macOS {
                if let nativeFrame = axFrame(of: button),
                   recalibrateNativeCenters || nativeCenterOffsets[action] == nil {
                    nativeCenterOffsets[action] = CGPoint(
                        x: nativeFrame.midX - frame.minX,
                        y: nativeFrame.midY - frame.minY
                    )
                }
                if let offset = nativeCenterOffsets[action] {
                    let center = CGPoint(x: frame.minX + offset.x, y: frame.minY + offset.y)
                    frames[action] = CGRect(
                        x: center.x - controlSize / 2,
                        y: center.y - controlSize / 2,
                        width: controlSize,
                        height: controlSize
                    )
                }
            }
        }

        if preferences.style == .edgeSquares {
            let edgeFrames = ControlLayout.frames(
                style: .edgeSquares,
                controlSize: controlSize,
                windowOrigin: frame.origin,
                windowSize: frame.size
            )
            for action in buttons.keys { frames[action] = edgeFrames[action] }
        }

        let nativeFrameSummary = WindowAction.allCases.map { action in
            "\(action)=\(buttons[action].flatMap(axFrame).map(NSStringFromRect) ?? "missing")"
        }.joined(separator: ";")
        report("pid=\(key.pid) title=\(title) window=\(NSStringFromRect(frame)) \(nativeFrameSummary)")

        targetButtons = buttons
        preparedCGFrames.removeAll(keepingCapacity: true)
        preparedActions.removeAll(keepingCapacity: true)
        for action in WindowAction.allCases {
            guard let panel = panels[action], let cgFrame = frames[action], buttons[action] != nil else {
                panels[action]?.orderOut(nil)
                continue
            }
            guard let origin = appKitOrigin(forCGPoint: cgFrame.origin, size: cgFrame.size) else {
                panel.orderOut(nil)
                continue
            }

            let isEnabled: Bool = copyAttribute(kAXEnabledAttribute as CFString, from: buttons[action]!) ?? true
            panel.overlayView.style = preferences.style
            panel.overlayView.controlSize = controlSize
            panel.overlayView.isControlEnabled = isEnabled
            panel.overlayView.isWindowActive = isActiveWindow
            let newFrame = NSRect(origin: origin, size: cgFrame.size)
            if panel.frame != newFrame { panel.setFrame(newFrame, display: true) }
            preparedCGFrames[action] = cgFrame
            preparedActions.insert(action)
        }

        setVisibleActions(visibleActions.intersection(preparedActions))
        return !preparedActions.isEmpty
    }

    func bind(to windowID: CGWindowID) {
        cgWindowID = windowID
    }

    var controlFrames: [WindowAction: CGRect] {
        preparedCGFrames
    }

    func syncPosition(to currentWindowFrame: CGRect) {
        let delta = CGPoint(
            x: currentWindowFrame.minX - windowFrame.minX,
            y: currentWindowFrame.minY - windowFrame.minY
        )
        guard abs(delta.x) > 0.01 || abs(delta.y) > 0.01 else { return }

        windowFrame.origin = currentWindowFrame.origin

        for action in preparedActions {
            guard let panel = panels[action], var cgFrame = preparedCGFrames[action] else { continue }
            cgFrame.origin.x += delta.x
            cgFrame.origin.y += delta.y
            preparedCGFrames[action] = cgFrame
            guard let origin = appKitOrigin(forCGPoint: cgFrame.origin, size: cgFrame.size) else { continue }
            let newFrame = NSRect(origin: origin, size: cgFrame.size)
            if panel.frame != newFrame { panel.setFrame(newFrame, display: true) }
        }
    }

    func setVisible(_ visible: Bool) {
        setVisibleActions(visible ? preparedActions : [])
    }

    func setVisibleActions(_ actions: Set<WindowAction>) {
        let nextActions = actions.intersection(preparedActions)
        guard nextActions != visibleActions else { return }
        visibleActions = nextActions

        for action in WindowAction.allCases {
            guard let panel = panels[action] else { continue }
            if nextActions.contains(action) {
                panel.orderFrontRegardless()
            } else {
                panel.overlayView.resetInteractionState()
                if panel.isVisible { panel.orderOut(nil) }
            }
        }

        if nextActions.isEmpty {
            hoverResetWorkItem?.cancel()
            hoverResetWorkItem = nil
        }
    }

    func reconcileHoverState(mouseLocation: NSPoint) {
        guard !visibleActions.isEmpty else { return }
        var pointerInsideGroup = false
        for action in visibleActions {
            guard let panel = panels[action] else { continue }
            let pointerInsideButton = panel.frame.contains(mouseLocation)
            panel.overlayView.setPointerInside(pointerInsideButton)
            pointerInsideGroup = pointerInsideGroup || pointerInsideButton
        }
        setGroupHovered(pointerInsideGroup)
    }

    func hide() {
        visibleActions.removeAll(keepingCapacity: true)
        hidePanels()
    }

    private func hidePanels() {
        hoverResetWorkItem?.cancel()
        hoverResetWorkItem = nil
        panels.values.forEach { $0.overlayView.resetInteractionState() }
        for panel in panels.values where panel.isVisible { panel.orderOut(nil) }
    }

    private func setGroupHovered(_ hovered: Bool) {
        if hovered {
            hoverResetWorkItem?.cancel()
            hoverResetWorkItem = nil
            panels.values.forEach { $0.overlayView.isGroupHovered = true }
            return
        }

        guard hoverResetWorkItem == nil,
              panels.values.contains(where: { $0.overlayView.isGroupHovered }) else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panels.values.forEach { $0.overlayView.isGroupHovered = false }
            self.hoverResetWorkItem = nil
        }
        hoverResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func perform(_ action: WindowAction) {
        guard let button = targetButtons[action] else { return }
        if AXUIElementPerformAction(button, kAXPressAction as CFString) != .success { NSSound.beep() }
    }

    private func attribute(for action: WindowAction) -> CFString {
        switch action {
        case .close: return kAXCloseButtonAttribute as CFString
        case .minimize: return kAXMinimizeButtonAttribute as CFString
        case .zoom: return kAXZoomButtonAttribute as CFString
        }
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = copyAttribute(kAXPositionAttribute as CFString, from: element),
              let size: AXValue = copyAttribute(kAXSizeAttribute as CFString, from: element) else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }

    private func report(_ diagnostic: String) {
        guard diagnostic != lastDiagnostic else { return }
        lastDiagnostic = diagnostic
        logger.notice("\(diagnostic, privacy: .public)")
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
