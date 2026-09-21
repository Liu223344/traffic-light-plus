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

enum OverlayPresentationState {
    case hidden
    case expanding
    case visible
    case collapsing
    case suppressed
}

// Tickets prevent a queued menu completion from clicking after cancellation.
struct NativeZoomClickRequest {
    private(set) var generation = 0
    private(set) var isInFlight = false

    mutating func begin() -> Int? {
        guard !isInFlight else { return nil }
        generation += 1
        isInFlight = true
        return generation
    }

    func isCurrent(_ ticket: Int) -> Bool { isInFlight && generation == ticket }

    mutating func cancel() {
        isInFlight = false
        generation += 1
    }
}

final class WindowOverlay {
    static let zoomMenuHoverDelay = 0.5
    static let zoomMenuClickRecoveryDelay = 0.12
    static let zoomMenuClickRecoveryWindow = 1.0
    static let nativeZoomClickPassThroughDuration = 0.10
    // After a native zoom click the pointer still rests on the restored control;
    // suppress the hover menu briefly so it cannot pop again unprompted.
    static let nativeZoomMenuSuppressionInterval = 1.5
    static let closeDismissalDuration = 1.0
    private static let revealDuration = 0.10

    let key: AXWindowKey
    private let panels: [WindowAction: OverlayPanel]
    private(set) var windowFrame = CGRect.zero
    private(set) var title = ""
    private(set) var cgWindowID: CGWindowID?

    private let window: AXUIElement
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "window-overlay")
    private var targetButtons: [WindowAction: AXUIElement] = [:]
    private var nativeCenterOffsets: [WindowAction: CGPoint] = [:]
    private var nativeFrameOffsets: [WindowAction: CGRect] = [:]
    private var preparedCGFrames: [WindowAction: CGRect] = [:]
    private var preparedActions = Set<WindowAction>()
    private var availableActions = Set<WindowAction>()
    private var visibleActions = Set<WindowAction>()
    private var configuredBehaviors: [WindowAction: ButtonBehavior] = [:]
    private var isActiveWindowForZoomMenu = false
    private(set) var isSuppressed = false
    private var isEligibleForDisplay = true
    private var lastDiagnostic = ""
    private var hoverResetWorkItem: DispatchWorkItem?
    private var zoomMenuWorkItem: DispatchWorkItem?
    private var hoveredZoomMenuAction: WindowAction?
    private var zoomMenuTriggeredAt: TimeInterval?
    private var zoomMenuWasRequested = false
    private var nativeZoomRequest = NativeZoomClickRequest()
    private var isNativeZoomClickInFlight: Bool { nativeZoomRequest.isInFlight }
    private var nativeZoomPanelsHidden = false
    private var nativeZoomTimeout: DispatchWorkItem?
    private var nativeZoomClickCompletedAt: TimeInterval?
    private lazy var zoomAccessibilityQueue = DispatchQueue(
        label: "app.trafficlightsplus.mac.zoom-action.\(key.pid)",
        qos: .userInitiated
    )
    private lazy var zoomMenuAccessibilityQueue = DispatchQueue(
        label: "app.trafficlightsplus.mac.zoom-menu.\(key.pid)",
        qos: .userInitiated
    )
    private var minimizeRequestGeneration = 0
    private var isMinimizeDismissalInProgress = false
    private var minimizePendingUntil: TimeInterval = 0
    private var closeDismissalDeadline: TimeInterval?
    private var hiddenModeEnabled = true
    private var revealMode = HiddenTrafficLightRevealMode.nearest
    private var isRevealEngaged = false
    private var presentationProgressByAction = Dictionary(
        uniqueKeysWithValues: WindowAction.allCases.map { ($0, CGFloat.zero) }
    )
    private var selectedNearestAction: WindowAction?
    private var interactiveActions = Set<WindowAction>()
    private var lastDesiredActions = Set<WindowAction>()
    private var lastPresentationUpdate = 0.0
    private var presentationTimer: Timer?
    private var pointerActivationRegion: CGRect?
    private var pointerActivationRegionIsValid = false
    private(set) var presentationState = OverlayPresentationState.hidden

    init(key: AXWindowKey) {
        self.key = key
        window = key.element
        panels = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map { ($0, OverlayPanel(action: $0)) })
        for (action, panel) in panels {
            panel.overlayView.actionHandler = { [weak self] action in self?.perform(action) }
            panel.overlayView.pressHandler = { [weak self] _ in self?.cancelZoomMenuRequest() }
            panel.overlayView.hoverHandler = { [weak self] hovered in
                self?.handleHover(for: action, hovered: hovered)
            }
        }
    }

    deinit {
        presentationTimer?.invalidate()
    }

    // Hidden windows only need an occlusion query when the pointer reaches their
    // native controls. Visible/animating controls must also handle pointer exit.
    func needsPointerUpdate(at location: CGPoint) -> Bool {
        guard !isSuppressed, isEligibleForDisplay else { return false }
        if presentationState != .hidden || presentationTimer != nil { return true }
        if !pointerActivationRegionIsValid {
            pointerActivationRegion = ControlLayout.activationRegion(
                controlFrames: appKitNativeControlFrames(actions: preparedActions),
                actions: preparedActions
            )
            pointerActivationRegionIsValid = true
        }
        return pointerActivationRegion?.contains(location) == true
    }

    private func startPresentationTimer() {
        guard presentationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updatePresentation(
                availableActions: self.availableActions,
                mouseLocation: NSEvent.mouseLocation,
                hiddenModeEnabled: self.hiddenModeEnabled,
                revealMode: self.revealMode
            )
        }
        presentationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPresentationTimer() {
        presentationTimer?.invalidate()
        presentationTimer = nil
    }

    @discardableResult
    func update(preferences: Preferences, recalibrateNativeCenters: Bool = true) -> Bool {
        pointerActivationRegionIsValid = false
        guard let frame = axFrame(of: window), frame.width > 100, frame.height > 60 else {
            isEligibleForDisplay = false
            hide()
            return false
        }

        let minimized: Bool = copyAttribute(kAXMinimizedAttribute as CFString, from: window) ?? false
        guard reconcileMinimizedState(minimized) else { return false }
        let fullScreen: Bool = copyAttribute("AXFullScreen" as CFString, from: window) ?? false
        guard preferences.showInFullScreen || !fullScreen else {
            isEligibleForDisplay = false
            hide()
            return false
        }

        isEligibleForDisplay = true

        windowFrame = frame
        title = copyAttribute(kAXTitleAttribute as CFString, from: window) ?? ""
        let application = NSRunningApplication(processIdentifier: key.pid)
        let appIsActive = application?.isActive ?? false
        let windowIsFocused: Bool = copyAttribute(kAXFocusedAttribute as CFString, from: window) ?? false
        let windowIsMain: Bool = copyAttribute(kAXMainAttribute as CFString, from: window) ?? false
        let isActiveWindow = appIsActive && (windowIsFocused || windowIsMain)
        isActiveWindowForZoomMenu = isActiveWindow
        if !isActiveWindow { cancelZoomMenuRequest(clearTriggeredState: true) }
        configuredBehaviors = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map {
            ($0, preferences.effectiveBehavior(
                for: $0,
                bundleIdentifier: application?.bundleIdentifier
            ))
        })
        if let hoveredZoomMenuAction,
           configuredBehaviors[hoveredZoomMenuAction] != .zoomWindow {
            cancelZoomMenuRequest(clearTriggeredState: true)
        }
        let controlSize = ControlLayout.effectiveSize(preferred: preferences.size)
        var buttons: [WindowAction: AXUIElement] = [:]
        var frames: [WindowAction: CGRect] = [:]

        for action in WindowAction.allCases {
            guard let button: AXUIElement = copyAttribute(attribute(for: action), from: window) else { continue }
            buttons[action] = button
            if let nativeFrame = axFrame(of: button),
               recalibrateNativeCenters || nativeFrameOffsets[action] == nil {
                nativeFrameOffsets[action] = CGRect(
                    x: nativeFrame.minX - frame.minX,
                    y: nativeFrame.minY - frame.minY,
                    width: nativeFrame.width,
                    height: nativeFrame.height
                )
                nativeCenterOffsets[action] = CGPoint(
                    x: nativeFrame.midX - frame.minX,
                    y: nativeFrame.midY - frame.minY
                )
            }
            if preferences.style == .macOS {
                if let offset = nativeCenterOffsets[action] {
                    let nativeCenter = CGPoint(x: frame.minX + offset.x, y: frame.minY + offset.y)
                    let center = ControlLayout.centerByAdjustingSystemSpacing(
                        nativeCenter,
                        action: action,
                        adjustment: ControlLayout.effectiveSpacingAdjustment(preferred: preferences.spacing)
                    )
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

        report("pid=\(key.pid) controls=\(buttons.count)")

        targetButtons = buttons
        if targetButtons[.zoom] == nil { cancelZoomMenuRequest(clearTriggeredState: true) }
        preparedCGFrames.removeAll(keepingCapacity: true)
        preparedActions.removeAll(keepingCapacity: true)
        for action in WindowAction.allCases {
            guard let panel = panels[action], let cgFrame = frames[action], buttons[action] != nil else {
                if let panel = panels[action], panel.isVisible { panel.orderOut(nil) }
                continue
            }
            guard let origin = appKitOrigin(forCGPoint: cgFrame.origin, size: cgFrame.size) else {
                if panel.isVisible { panel.orderOut(nil) }
                continue
            }

            let behavior = configuredBehaviors[action] ?? ButtonBehavior.defaultBehavior(for: action)
            panel.overlayView.style = preferences.style
            panel.overlayView.controlSize = controlSize
            panel.overlayView.language = preferences.language
            panel.overlayView.behavior = behavior
            panel.overlayView.isControlEnabled = isBehaviorEnabled(behavior, buttons: buttons)
            panel.overlayView.isWindowActive = isActiveWindow
            let newFrame = NSRect(origin: origin, size: cgFrame.size)
            if !panel.isVisible, panel.frame != newFrame { panel.setFrame(newFrame, display: true) }
            preparedCGFrames[action] = cgFrame
            preparedActions.insert(action)
        }

        availableActions.formIntersection(preparedActions)
        for action in WindowAction.allCases where !preparedActions.contains(action) {
            if let panel = panels[action], panel.isVisible { panel.orderOut(nil) }
            visibleActions.remove(action)
        }
        return !preparedActions.isEmpty
    }

    func bind(to windowID: CGWindowID) {
        cgWindowID = windowID
    }

    var controlFrames: [WindowAction: CGRect] {
        preparedCGFrames
    }

    var panelWindowIDs: Set<CGWindowID> {
        Set(panels.values.compactMap { panel in
            guard panel.windowNumber > 0 else { return nil }
            return CGWindowID(panel.windowNumber)
        })
    }

    func syncPosition(to currentWindowFrame: CGRect) {
        guard !isSuppressed else { return }
        let delta = CGPoint(
            x: currentWindowFrame.minX - windowFrame.minX,
            y: currentWindowFrame.minY - windowFrame.minY
        )
        guard abs(delta.x) > 0.01 || abs(delta.y) > 0.01 else { return }

        pointerActivationRegionIsValid = false
        windowFrame.origin = currentWindowFrame.origin

        for action in preparedActions {
            guard var cgFrame = preparedCGFrames[action] else { continue }
            cgFrame.origin.x += delta.x
            cgFrame.origin.y += delta.y
            preparedCGFrames[action] = cgFrame
        }
    }

    func updatePresentation(
        availableActions actions: Set<WindowAction>,
        mouseLocation: NSPoint,
        hiddenModeEnabled: Bool,
        revealMode: HiddenTrafficLightRevealMode,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.hiddenModeEnabled = hiddenModeEnabled
        self.revealMode = revealMode
        if let closeDismissalDeadline {
            guard now >= closeDismissalDeadline else {
                _ = transitionToHiddenState(.hidden)
                return
            }
            self.closeDismissalDeadline = nil
        }
        guard !isSuppressed, isEligibleForDisplay else {
            _ = transitionToHiddenState(isSuppressed ? .suppressed : .hidden)
            return
        }

        availableActions = actions.intersection(preparedActions)
        guard !availableActions.isEmpty else {
            _ = transitionToHiddenState(.hidden)
            return
        }

        let desiredActions = isMinimizeDismissalInProgress
            ? Set<WindowAction>()
            : desiredExpandedActions(mouseLocation: mouseLocation)
        // An idle interval is not animation time: start a newly triggered reveal
        // from its current size instead of jumping halfway through the animation.
        let startingAnimation = presentationTimer == nil && desiredActions != lastDesiredActions
        let elapsed = !startingAnimation && lastPresentationUpdate > 0
            ? min(max(now - lastPresentationUpdate, 0), 0.05) : 0
        lastPresentationUpdate = now

        for action in WindowAction.allCases {
            guard availableActions.contains(action) else {
                presentationProgressByAction[action] = 0
                continue
            }
            if !hiddenModeEnabled {
                presentationProgressByAction[action] = 1
            } else {
                presentationProgressByAction[action] = ControlLayout.nextPresentationProgress(
                    current: presentationProgressByAction[action] ?? 0,
                    elapsed: elapsed,
                    expanding: desiredActions.contains(action),
                    duration: Self.revealDuration
                )
            }
        }

        updatePresentationState(desiredActions: desiredActions)
        renderPresentation(desiredActions: desiredActions, mouseLocation: mouseLocation)
        if Self.needsPresentationAnimation(
            progress: presentationProgressByAction,
            availableActions: availableActions,
            desiredActions: desiredActions
        ) {
            startPresentationTimer()
        } else {
            stopPresentationTimer()
        }
    }

    static func needsPresentationAnimation(
        progress: [WindowAction: CGFloat],
        availableActions: Set<WindowAction>,
        desiredActions: Set<WindowAction>
    ) -> Bool {
        availableActions.contains { action in
            let target: CGFloat = desiredActions.contains(action) ? 1 : 0
            return (progress[action] ?? 0) != target
        }
    }

    private func renderPresentation(
        desiredActions: Set<WindowAction>,
        mouseLocation: NSPoint
    ) {
        // Keep the native controls exposed until the posted click is delivered.
        guard !nativeZoomPanelsHidden else { return }
        var nextVisibleActions = Set<WindowAction>()
        var pointerInsideButton = false

        for action in WindowAction.allCases {
            guard let panel = panels[action] else { continue }
            let linearProgress = presentationProgressByAction[action] ?? 0
            let progress = linearProgress * linearProgress * (3 - 2 * linearProgress)
            guard progress > 0, availableActions.contains(action) else {
                panel.ignoresMouseEvents = true
                panel.overlayView.resetInteractionState()
                if panel.isVisible { panel.orderOut(nil) }
                continue
            }

            let frame: NSRect?
            if let nativeFrame = nativeCGFrame(for: action),
                      let targetFrame = preparedCGFrames[action] {
                let cgFrame = ControlLayout.interpolatedFrame(
                    from: nativeFrame,
                    to: targetFrame,
                    progress: progress
                )
                frame = appKitFrame(for: cgFrame)
            } else {
                frame = nil
            }

            guard let frame else {
                if panel.isVisible { panel.orderOut(nil) }
                continue
            }

            if panel.frame != frame { panel.setFrame(frame, display: true) }
            panel.alphaValue = 1
            panel.ignoresMouseEvents = isNativeZoomClickInFlight
                || isMinimizeDismissalInProgress
                || !desiredActions.contains(action)
            if !panel.isVisible { panel.orderFrontRegardless() }
            nextVisibleActions.insert(action)

            let pointerInside = !isNativeZoomClickInFlight
                && desiredActions.contains(action)
                && frame.contains(mouseLocation)
            panel.overlayView.setPointerInside(pointerInside)
            pointerInsideButton = pointerInsideButton || pointerInside
        }

        visibleActions = nextVisibleActions
        interactiveActions = desiredActions.intersection(nextVisibleActions)
        if let hoveredZoomMenuAction,
           !interactiveActions.contains(hoveredZoomMenuAction) {
            cancelZoomMenuRequest(clearTriggeredState: true)
        }
        if desiredActions != lastDesiredActions {
            for action in ControlLayout.displayOrder(for: .macOS) where interactiveActions.contains(action) {
                panels[action]?.orderFrontRegardless()
            }
            lastDesiredActions = desiredActions
        }
        if visibleActions.isEmpty {
            hoverResetWorkItem?.cancel()
            hoverResetWorkItem = nil
            cancelZoomMenuRequest(clearTriggeredState: true)
        } else {
            setGroupHovered(pointerInsideButton)
        }
    }

    private func desiredExpandedActions(mouseLocation: NSPoint) -> Set<WindowAction> {
        guard hiddenModeEnabled else {
            isRevealEngaged = false
            selectedNearestAction = nil
            return availableActions
        }

        return Self.desiredRevealActions(
            pointer: mouseLocation,
            mode: revealMode,
            nativeFrames: appKitNativeControlFrames(actions: availableActions),
            expandedFrames: appKitControlFrames(actions: availableActions),
            actions: availableActions,
            isEngaged: &isRevealEngaged,
            selectedAction: &selectedNearestAction
        )
    }

    static func desiredRevealActions(
        pointer: CGPoint,
        mode: HiddenTrafficLightRevealMode,
        nativeFrames: [WindowAction: CGRect],
        expandedFrames: [WindowAction: CGRect],
        actions: Set<WindowAction>,
        isEngaged: inout Bool,
        selectedAction: inout WindowAction?
    ) -> Set<WindowAction> {
        guard !actions.isEmpty,
              let nativeRegion = ControlLayout.activationRegion(
                  controlFrames: nativeFrames,
                  actions: actions
              ) else {
            isEngaged = false
            selectedAction = nil
            return []
        }

        if !isEngaged {
            guard nativeRegion.contains(pointer) else {
                selectedAction = nil
                return []
            }
            isEngaged = true
        }

        switch mode {
        case .group:
            selectedAction = nil
            let retentionFrames: [WindowAction: CGRect] = Dictionary(
                uniqueKeysWithValues: actions.compactMap { action -> (WindowAction, CGRect)? in
                    guard let nativeFrame = nativeFrames[action],
                          let expandedFrame = expandedFrames[action] else { return nil }
                    return (action, nativeFrame.union(expandedFrame))
                }
            )
            guard let retentionRegion = ControlLayout.activationRegion(
                controlFrames: retentionFrames,
                actions: actions
            ), retentionRegion.contains(pointer) else {
                isEngaged = false
                return []
            }
            return actions

        case .nearest:
            if nativeRegion.contains(pointer) {
                selectedAction = ControlLayout.nearestAction(
                    to: pointer,
                    controlFrames: nativeFrames,
                    actions: actions,
                    currentAction: selectedAction
                )
            }

            guard let selectedAction,
                  actions.contains(selectedAction),
                  let nativeFrame = nativeFrames[selectedAction],
                  let expandedFrame = expandedFrames[selectedAction],
                  nativeFrame.union(expandedFrame)
                      .insetBy(dx: -ControlLayout.activationPadding, dy: -ControlLayout.activationPadding)
                      .contains(pointer) else {
                isEngaged = false
                selectedAction = nil
                return []
            }
            return [selectedAction]
        }
    }

    private func updatePresentationState(desiredActions: Set<WindowAction>) {
        let visibleProgress = presentationProgressByAction.filter { $0.value > 0 }
        guard !visibleProgress.isEmpty else {
            presentationState = .hidden
            return
        }
        if desiredActions.contains(where: { (presentationProgressByAction[$0] ?? 0) < 1 }) {
            presentationState = .expanding
        } else if visibleProgress.contains(where: { !desiredActions.contains($0.key) }) {
            presentationState = .collapsing
        } else {
            presentationState = .visible
        }
    }

    private func resetPresentationProgress() {
        for action in WindowAction.allCases { presentationProgressByAction[action] = 0 }
        isRevealEngaged = false
        interactiveActions.removeAll(keepingCapacity: true)
        lastDesiredActions.removeAll(keepingCapacity: true)
    }

    private func appKitControlFrames(actions: Set<WindowAction>) -> [WindowAction: CGRect] {
        Dictionary(uniqueKeysWithValues: actions.compactMap { action in
            guard let cgFrame = preparedCGFrames[action], let frame = appKitFrame(for: cgFrame) else { return nil }
            return (action, frame)
        })
    }

    private func appKitNativeControlFrames(actions: Set<WindowAction>) -> [WindowAction: CGRect] {
        Dictionary(uniqueKeysWithValues: actions.compactMap { action in
            guard let cgFrame = nativeCGFrame(for: action),
                  let frame = appKitFrame(for: cgFrame) else { return nil }
            return (action, frame)
        })
    }

    private func nativeCGFrame(for action: WindowAction) -> CGRect? {
        if let offset = nativeFrameOffsets[action] {
            return CGRect(
                x: windowFrame.minX + offset.minX,
                y: windowFrame.minY + offset.minY,
                width: offset.width,
                height: offset.height
            )
        }
        guard let targetFrame = preparedCGFrames[action] else { return nil }
        return ControlLayout.frameCentered(on: targetFrame, controlSize: min(14, targetFrame.width))
    }

    private func appKitFrame(for cgFrame: CGRect) -> NSRect? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let cgBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard cgBounds.intersects(cgFrame) else { continue }
            return NSRect(
                x: screen.frame.minX + cgFrame.minX - cgBounds.minX,
                y: screen.frame.maxY - (cgFrame.minY - cgBounds.minY) - cgFrame.height,
                width: cgFrame.width,
                height: cgFrame.height
            )
        }
        return nil
    }

    @discardableResult
    func hide() -> Bool {
        let hiddenState: OverlayPresentationState = isSuppressed ? .suppressed : .hidden
        return transitionToHiddenState(hiddenState)
    }

    private func transitionToHiddenState(_ hiddenState: OverlayPresentationState) -> Bool {
        if isNativeZoomClickInFlight { finishNativeZoomClick(restorePresentation: false) }
        stopPresentationTimer()
        guard presentationState != hiddenState || panels.values.contains(where: \.isVisible) else {
            return false
        }
        resetPresentationProgress()
        selectedNearestAction = nil
        lastPresentationUpdate = 0
        presentationState = hiddenState
        visibleActions.removeAll(keepingCapacity: true)
        hidePanels()
        return true
    }

    func suppressUntilRestored() {
        isMinimizeDismissalInProgress = false
        minimizePendingUntil = 0
        minimizeRequestGeneration += 1
        isSuppressed = true
        isEligibleForDisplay = false
        hide()
    }

    @discardableResult
    func reconcileMinimizedState(_ minimized: Bool) -> Bool {
        if minimized {
            suppressUntilRestored()
            return false
        }
        // AX can still report the pre-animation state while minimizing.
        guard !isMinimizeDismissalInProgress,
              ProcessInfo.processInfo.systemUptime >= minimizePendingUntil else { return false }
        if isSuppressed { restoreFromSuppression() }
        return true
    }

    func restoreFromSuppression() {
        minimizePendingUntil = 0
        minimizeRequestGeneration += 1
        isSuppressed = false
        isEligibleForDisplay = true
        isMinimizeDismissalInProgress = false
        resetPresentationProgress()
        selectedNearestAction = nil
        lastPresentationUpdate = 0
        presentationState = .hidden
    }

    @discardableResult
    func minimizeWindow() -> Bool {
        guard !isSuppressed,
              !isMinimizeDismissalInProgress,
              let button = targetButtons[.minimize]
                ?? copyAttribute(kAXMinimizeButtonAttribute as CFString, from: window),
              copyAttribute(kAXEnabledAttribute as CFString, from: button) ?? true else { return false }
        performMinimize(using: button)
        return true
    }

    private func hidePanels() {
        hoverResetWorkItem?.cancel()
        hoverResetWorkItem = nil
        cancelZoomMenuRequest(clearTriggeredState: true)
        visibleActions.removeAll(keepingCapacity: true)
        interactiveActions.removeAll(keepingCapacity: true)
        lastDesiredActions.removeAll(keepingCapacity: true)
        panels.values.forEach { $0.overlayView.resetInteractionState() }
        for panel in panels.values {
            panel.alphaValue = 1
            panel.ignoresMouseEvents = true
            if panel.isVisible { panel.orderOut(nil) }
        }
    }

    private func setGroupHovered(_ hovered: Bool) {
        if hovered {
            hoverResetWorkItem?.cancel()
            hoverResetWorkItem = nil
            for (action, panel) in panels {
                panel.overlayView.isGroupHovered = interactiveActions.contains(action)
            }
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

    private func handleHover(for action: WindowAction, hovered: Bool) {
        setGroupHovered(hovered)
        if hovered {
            scheduleZoomMenu(for: action)
        } else if hoveredZoomMenuAction == action {
            cancelZoomMenuRequest()
        }
    }

    private func isWithinNativeZoomMenuSuppression() -> Bool {
        guard let completedAt = nativeZoomClickCompletedAt else { return false }
        return ProcessInfo.processInfo.systemUptime - completedAt < Self.nativeZoomMenuSuppressionInterval
    }

    private func scheduleZoomMenu(for action: WindowAction) {
        cancelZoomMenuRequest(clearTriggeredState: true)
        guard !isNativeZoomClickInFlight,
              !isWithinNativeZoomMenuSuppression(),
              interactiveActions.contains(action),
              let panel = panels[action],
              let zoomButton = currentButton(for: .zoom) else { return }

        let supportsShowMenu = supportsAccessibilityAction(kAXShowMenuAction as CFString, on: zoomButton)
        guard Self.shouldOfferZoomMenu(
            behavior: configuredBehaviors[action] ?? ButtonBehavior.defaultBehavior(for: action),
            isActiveWindow: isActiveWindowForZoomMenu,
            isControlEnabled: panel.overlayView.isControlEnabled,
            supportsShowMenu: supportsShowMenu
        ) else { return }

        hoveredZoomMenuAction = action
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.hoveredZoomMenuAction == action,
                  self.interactiveActions.contains(action),
                  let panel = self.panels[action],
                  let zoomButton = self.currentButton(for: .zoom) else { return }

            let supportsShowMenu = self.supportsAccessibilityAction(
                kAXShowMenuAction as CFString,
                on: zoomButton
            )
            guard Self.shouldOfferZoomMenu(
                behavior: self.configuredBehaviors[action] ?? ButtonBehavior.defaultBehavior(for: action),
                isActiveWindow: self.targetWindowIsActive(),
                isControlEnabled: panel.overlayView.isControlEnabled,
                supportsShowMenu: supportsShowMenu
            ) else {
                self.cancelZoomMenuRequest()
                return
            }

            self.zoomMenuWorkItem = nil
            self.zoomMenuTriggeredAt = ProcessInfo.processInfo.systemUptime
            self.zoomMenuWasRequested = true
            // Some Web App windows block AXShowMenu until the menu is dismissed.
            // The native click queue uses this call as its completion barrier.
            let menuQueue = self.zoomMenuAccessibilityQueue
            menuQueue.async {
                _ = AXUIElementPerformAction(zoomButton, kAXShowMenuAction as CFString)
            }
        }
        zoomMenuWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.zoomMenuHoverDelay, execute: workItem)
    }

    private func cancelZoomMenuRequest(clearTriggeredState: Bool = false) {
        zoomMenuWorkItem?.cancel()
        zoomMenuWorkItem = nil
        hoveredZoomMenuAction = nil
        if clearTriggeredState { zoomMenuTriggeredAt = nil }
    }

    static func shouldOfferZoomMenu(
        behavior: ButtonBehavior,
        isActiveWindow: Bool,
        isControlEnabled: Bool,
        supportsShowMenu: Bool
    ) -> Bool {
        behavior == .zoomWindow && isActiveWindow && isControlEnabled && supportsShowMenu
    }

    static func zoomActionDelay(
        menuTriggeredAt: TimeInterval?,
        now: TimeInterval
    ) -> TimeInterval {
        guard let menuTriggeredAt,
              now >= menuTriggeredAt,
              now - menuTriggeredAt <= zoomMenuClickRecoveryWindow else { return 0 }
        return zoomMenuClickRecoveryDelay
    }

    static func shouldUseNativeZoomClick(
        menuWasRequested: Bool,
        isClickInFlight: Bool
    ) -> Bool {
        menuWasRequested && !isClickInFlight
    }

    static func nativeZoomClickPoint(
        in buttonFrame: CGRect,
        targetWindowFrame: CGRect,
        displayFrames: [CGRect]
    ) -> CGPoint? {
        guard isFiniteNonEmpty(buttonFrame),
              isFiniteNonEmpty(targetWindowFrame) else { return nil }
        let clickPoint = CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)
        guard clickPoint.x.isFinite,
              clickPoint.y.isFinite,
              targetWindowFrame.contains(clickPoint),
              displayFrames.contains(where: {
                  isFiniteNonEmpty($0) && $0.contains(clickPoint)
              }) else { return nil }
        return clickPoint
    }

    static func nativeZoomClickEvents(
        at clickPoint: CGPoint,
        restoringPointerTo pointerPoint: CGPoint
    ) -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let mouseDown = CGEvent(
                  mouseEventSource: source,
                  mouseType: .leftMouseDown,
                  mouseCursorPosition: clickPoint,
                  mouseButton: .left
              ),
              let mouseUp = CGEvent(
                  mouseEventSource: source,
                  mouseType: .leftMouseUp,
                  mouseCursorPosition: clickPoint,
                  mouseButton: .left
              ),
              let restorePointer = CGEvent(
                  mouseEventSource: source,
                  mouseType: .mouseMoved,
                  mouseCursorPosition: pointerPoint,
                  mouseButton: .left
              ) else { return nil }

        let flags = CGEventSource.flagsState(.combinedSessionState)
        mouseDown.flags = flags
        mouseUp.flags = flags
        restorePointer.flags = flags
        mouseDown.setIntegerValueField(.mouseEventClickState, value: 1)
        mouseUp.setIntegerValueField(.mouseEventClickState, value: 1)
        return [mouseDown, mouseUp, restorePointer]
    }

    private func perform(_ action: WindowAction) {
        let behavior = configuredBehaviors[action] ?? ButtonBehavior.defaultBehavior(for: action)
        let zoomActionDelay = behavior == .zoomWindow
            ? Self.zoomActionDelay(
                menuTriggeredAt: zoomMenuTriggeredAt,
                now: ProcessInfo.processInfo.systemUptime
            )
            : 0
        cancelZoomMenuRequest(clearTriggeredState: true)

        if let nativeAction = behavior.nativeWindowAction {
            if behavior == .zoomWindow, zoomMenuWasRequested {
                guard Self.shouldUseNativeZoomClick(
                    menuWasRequested: true,
                    isClickInFlight: isNativeZoomClickInFlight
                ) else { return }
                performNativeZoomClick()
                return
            }
            guard let button = currentButton(for: nativeAction) else { NSSound.beep(); return }
            if behavior == .minimizeWindow {
                performMinimize(using: button)
                return
            }
            if behavior == .zoomWindow {
                performZoom(using: button, delay: zoomActionDelay)
                return
            }
            if Self.shouldDismissImmediately(behavior: behavior) {
                beginCloseDismissal()
            }
            if AXUIElementPerformAction(button, kAXPressAction as CFString) != .success {
                cancelCloseDismissal()
                NSSound.beep()
            }
            return
        }

        guard let application = NSRunningApplication(processIdentifier: key.pid) else {
            NSSound.beep()
            return
        }
        switch behavior {
        case .quitApplication:
            beginCloseDismissal()
            if !application.terminate() {
                cancelCloseDismissal()
                NSSound.beep()
            }
        case .hideApplication:
            if !application.hide() { NSSound.beep() }
        case .doNothing:
            break
        case .closeWindow, .minimizeWindow, .zoomWindow:
            break
        }
    }

    static func shouldDismissImmediately(behavior: ButtonBehavior) -> Bool {
        behavior == .closeWindow || behavior == .quitApplication
    }

    private func beginCloseDismissal() {
        closeDismissalDeadline = ProcessInfo.processInfo.systemUptime + Self.closeDismissalDuration
        _ = transitionToHiddenState(.hidden)
    }

    private func cancelCloseDismissal() {
        closeDismissalDeadline = nil
        lastPresentationUpdate = 0
    }

    private func performZoom(using button: AXUIElement, delay: TimeInterval) {
        zoomAccessibilityQueue.asyncAfter(deadline: .now() + delay) {
            let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            guard result != .success else { return }
            DispatchQueue.main.async { NSSound.beep() }
        }
    }

    private func performNativeZoomClick() {
        guard !isSuppressed, isEligibleForDisplay,
              let generation = nativeZoomRequest.begin() else { return }
        // Background controls remain clickable: the final hit test, rather than
        // application focus, decides whether this native button can receive input.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.nativeZoomRequest.isCurrent(generation) else { return }
            self.finishNativeZoomClick(failureStage: "menu-timeout")
        }
        nativeZoomTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: timeout)

        // AXShowMenu may block until its menu closes. Never send a delayed click
        // after a timeout, window hide, or a newer request has invalidated it.
        zoomMenuAccessibilityQueue.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isNativeZoomClickInFlight,
                      self.nativeZoomRequest.isCurrent(generation) else { return }
                guard !self.isSuppressed, self.isEligibleForDisplay else {
                    self.finishNativeZoomClick(failureStage: "inactive-window")
                    return
                }
                self.nativeZoomPanelsHidden = true
                self.panels.values.forEach {
                    $0.ignoresMouseEvents = true
                    $0.overlayView.resetInteractionState()
                    $0.orderOut(nil)
                }
                // Let WindowServer remove our panels before AX hit testing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    guard let self, self.nativeZoomRequest.isCurrent(generation) else { return }
                    self.postNativeZoomClick(generation: generation)
                }
            }
        }
    }

    private func postNativeZoomClick(generation: Int) {
        guard isNativeZoomClickInFlight, nativeZoomRequest.isCurrent(generation) else { return }
        guard !isSuppressed, isEligibleForDisplay,
              let button = copyFreshButton(for: .zoom).button,
              copyAttribute(kAXEnabledAttribute as CFString, from: button) ?? true,
              let buttonFrame = axFrame(of: button),
              let targetWindowFrame = axFrame(of: window),
              let clickPoint = Self.nativeZoomClickPoint(
                  in: buttonFrame,
                  targetWindowFrame: targetWindowFrame,
                  displayFrames: Self.activeDisplayFrames()
              ) else {
            finishNativeZoomClick(failureStage: "target-validation")
            return
        }
        // Valid geometry alone is insufficient: a sheet, menu, or floating
        // window may cover the button while the target remains the main window.
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(clickPoint.x), Float(clickPoint.y), &hit) == .success,
              let hit, CFEqual(hit, button) else {
            finishNativeZoomClick(failureStage: "hit-test")
            return
        }
        guard let pointerPoint = CGEvent(source: nil)?.location,
              let events = Self.nativeZoomClickEvents(at: clickPoint, restoringPointerTo: pointerPoint) else {
            finishNativeZoomClick(failureStage: "event-creation")
            return
        }
        events.forEach { $0.post(tap: .cghidEventTap) }
        logger.notice("Native zoom click posted pid=\(self.key.pid, privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.nativeZoomClickPassThroughDuration) { [weak self] in
            guard let self, self.nativeZoomRequest.isCurrent(generation) else { return }
            // The window is zooming right now; restoring the panels with their
            // pre-zoom geometry would leave a stale control floating over the
            // changed window. Let resize/move notifications re-present instead.
            self.finishNativeZoomClick(restorePresentation: false)
        }
    }

    private func finishNativeZoomClick(failureStage: String? = nil, restorePresentation: Bool = true) {
        guard isNativeZoomClickInFlight else { return }
        nativeZoomRequest.cancel()
        nativeZoomPanelsHidden = false
        nativeZoomTimeout?.cancel()
        nativeZoomTimeout = nil
        nativeZoomClickCompletedAt = ProcessInfo.processInfo.systemUptime
        lastPresentationUpdate = 0
        if restorePresentation {
            // There is no continuous position timer. Restore input now,
            // including on failure, rather than waiting for the next scan.
            updatePresentation(
                availableActions: availableActions,
                mouseLocation: NSEvent.mouseLocation,
                hiddenModeEnabled: hiddenModeEnabled,
                revealMode: revealMode
            )
        }
        if let failureStage {
            logger.error("Native zoom click cancelled: \(failureStage, privacy: .public)")
            NSSound.beep()
        }
    }

    private func performMinimize(using button: AXUIElement) {
        guard !isSuppressed, !isMinimizeDismissalInProgress else { return }
        beginMinimizeDismissal()
        let generation = minimizeRequestGeneration
        let targetWindow = window
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            // Some apps complete the action but return an AX error. Check the
            // resulting state instead of retrying a press or restoring a ghost.
            var value: CFTypeRef?
            let stateResult = AXUIElementCopyAttributeValue(
                targetWindow, kAXMinimizedAttribute as CFString, &value
            )
            let minimized = stateResult == .success && (value as? Bool == true)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.minimizeRequestGeneration else { return }
                self.isMinimizeDismissalInProgress = false
                if result != .success && !minimized {
                    self.logger.error("Minimize AX action returned \(result.rawValue); waiting for window state refresh")
                }
                // Leave panels hidden. Periodic AX reconciliation restores them
                // if minimizing failed, or after the window is deminiaturized.
            }
        }
    }

    func beginMinimizeDismissal() {
        // Remove independent overlay windows before the system captures/animates
        // the target window, and reject duplicate requests during the transition.
        suppressUntilRestored()
        isMinimizeDismissalInProgress = true
        minimizePendingUntil = ProcessInfo.processInfo.systemUptime + 1.0
    }

    private func isBehaviorEnabled(
        _ behavior: ButtonBehavior,
        buttons: [WindowAction: AXUIElement]
    ) -> Bool {
        if let nativeAction = behavior.nativeWindowAction {
            guard let button = buttons[nativeAction] else { return false }
            return copyAttribute(kAXEnabledAttribute as CFString, from: button) ?? true
        }
        switch behavior {
        case .quitApplication, .hideApplication:
            return NSRunningApplication(processIdentifier: key.pid) != nil
        case .doNothing:
            return false
        case .closeWindow, .minimizeWindow, .zoomWindow:
            return false
        }
    }

    private func attribute(for action: WindowAction) -> CFString {
        switch action {
        case .close: return kAXCloseButtonAttribute as CFString
        case .minimize: return kAXMinimizeButtonAttribute as CFString
        case .zoom: return kAXZoomButtonAttribute as CFString
        }
    }

    private func currentButton(for action: WindowAction) -> AXUIElement? {
        if let button: AXUIElement = copyAttribute(attribute(for: action), from: window) {
            targetButtons[action] = button
            return button
        }
        return targetButtons[action]
    }

    private func copyFreshButton(
        for action: WindowAction
    ) -> (button: AXUIElement?, error: AXError) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, attribute(for: action), &value)
        guard result == .success else { return (nil, result) }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, .failure) }
        return (unsafeBitCast(value, to: AXUIElement.self), .success)
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

    private func supportsAccessibilityAction(_ action: CFString, on element: AXUIElement) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              let actionNames = actions as? [String] else { return false }
        return actionNames.contains(action as String)
    }

    private static func isFiniteNonEmpty(_ frame: CGRect) -> Bool {
        !frame.isEmpty
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
    }

    private static func activeDisplayFrames() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        }
    }

    private func targetWindowIsActive() -> Bool {
        let appIsActive = NSRunningApplication(processIdentifier: key.pid)?.isActive ?? false
        let windowIsFocused: Bool = copyAttribute(kAXFocusedAttribute as CFString, from: window) ?? false
        let windowIsMain: Bool = copyAttribute(kAXMainAttribute as CFString, from: window) ?? false
        return appIsActive && (windowIsFocused || windowIsMain)
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
