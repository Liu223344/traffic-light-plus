import AppKit
import ApplicationServices
import OSLog

private func dockClickEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<DockClickController>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.reenableEventTap()
    } else {
        controller.handleEvent(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

enum DockClickIntent {
    case minimize
    case restoreNatively
    case restoredBySystem
}

enum DockClickHandlingMode: Equatable {
    case ignore
    case observeOnly
}

struct DockClickCandidate {
    let pid: pid_t
    let bundleIdentifier: String
    let location: CGPoint
    let timestamp: TimeInterval
    let intent: DockClickIntent

    func matches(bundleIdentifier: String?, location: CGPoint, timestamp: TimeInterval) -> Bool {
        guard let bundleIdentifier,
              self.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame,
              timestamp >= self.timestamp,
              timestamp - self.timestamp <= DockClickController.maximumClickDuration else { return false }
        return hypot(location.x - self.location.x, location.y - self.location.y)
            <= DockClickController.maximumClickTravel
    }
}

final class DockClickController {
    static let maximumClickDuration = 1.0
    static let maximumClickTravel: CGFloat = 8
    private static let dockBundleIdentifier = "com.apple.dock"

    private let preferences: Preferences
    private let minimizeHandler: (pid_t) -> Bool
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "dock-click")
    private let systemWideElement = AXUIElementCreateSystemWide()
    private let dockFrameQueryQueue = DispatchQueue(
        label: "app.trafficlightsplus.mac.dock-frame",
        qos: .utility
    )
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var installedEventTapOptions: CGEventTapOptions?
    private var retryTimer: Timer?
    private var dockFrameTimer: Timer?
    private var stageManagerTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var candidate: DockClickCandidate?
    private var cachedDockFrame: CGRect?
    private var cachedStageManagerEnabled = false
    private var cachedFrontmostBundleIdentifier: String?
    private var cachedFrontmostPID: pid_t?
    private var dockMinimizedApplicationPIDs = Set<pid_t>()
    private var dockFrameQueryInProgress = false

    init(
        preferences: Preferences,
        minimizeHandler: @escaping (pid_t) -> Bool
    ) {
        self.preferences = preferences
        self.minimizeHandler = minimizeHandler
        refreshCachedSystemState()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            self?.cachedFrontmostBundleIdentifier = application?.bundleIdentifier
            self?.cachedFrontmostPID = application?.processIdentifier
        }
        dockFrameTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshDockFrame()
        }
        stageManagerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshStageManagerState()
        }
        installEventTapIfPossible()
        scheduleEventTapRetryIfNeeded()
    }

    deinit {
        retryTimer?.invalidate()
        dockFrameTimer?.invalidate()
        stageManagerTimer?.invalidate()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        invalidateEventTap()
    }

    static func clickIntent(
        featureEnabled: Bool,
        clickedBundleIdentifier: String?,
        frontmostBundleIdentifier: String?,
        hasVisibleWindow: Bool,
        hasMinimizedWindow: Bool,
        detectPendingSystemRestore: Bool
    ) -> DockClickIntent? {
        guard featureEnabled, let clickedBundleIdentifier else { return nil }
        if hasVisibleWindow,
           let frontmostBundleIdentifier,
           clickedBundleIdentifier.caseInsensitiveCompare(frontmostBundleIdentifier) == .orderedSame {
            return .minimize
        }
        if detectPendingSystemRestore, !hasVisibleWindow, hasMinimizedWindow {
            return .restoreNatively
        }
        return nil
    }

    static func summarizedWindowState(
        minimizedStates: [Bool],
        hasOnScreenWindow: Bool
    ) -> (hasVisibleWindow: Bool, hasMinimizedWindow: Bool) {
        let hasUnminimizedWindow = minimizedStates.contains(false)
        return (
            hasVisibleWindow: hasOnScreenWindow && hasUnminimizedWindow,
            hasMinimizedWindow: minimizedStates.contains(true)
        )
    }

    static func observedClickIntent(
        featureEnabled: Bool,
        clickedBundleIdentifier: String?,
        frontmostBundleIdentifier: String?,
        wasMinimizedByDock: Bool,
        hadVisibleWindowAtMouseDown: Bool,
        hasVisibleWindowAfterDock: Bool,
        hasMinimizedWindowAfterDock: Bool
    ) -> DockClickIntent? {
        guard featureEnabled, let clickedBundleIdentifier else { return nil }
        if wasMinimizedByDock {
            return hasVisibleWindowAfterDock ? .restoredBySystem : .restoreNatively
        }
        if !hasVisibleWindowAfterDock, hasMinimizedWindowAfterDock { return .restoreNatively }
        if hadVisibleWindowAtMouseDown,
           let frontmostBundleIdentifier,
           clickedBundleIdentifier.caseInsensitiveCompare(frontmostBundleIdentifier) == .orderedSame {
            return .minimize
        }
        return nil
    }

    static func handlingMode(
        featureEnabled: Bool,
        stageManagerEnabled: Bool,
        location: CGPoint,
        dockFrame: CGRect?
    ) -> DockClickHandlingMode {
        guard featureEnabled,
              let dockFrame,
              dockFrame.insetBy(dx: -16, dy: -16).contains(location) else { return .ignore }
        return .observeOnly
    }

    static func eventTapOptions(stageManagerEnabled: Bool) -> CGEventTapOptions {
        .listenOnly
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        let featureEnabled = preferences.dockClickMinimizesActiveWindow
        guard featureEnabled else {
            candidate = nil
            return
        }

        let location = event.location
        let timestamp = ProcessInfo.processInfo.systemUptime
        let handlingMode = Self.handlingMode(
            featureEnabled: featureEnabled,
            stageManagerEnabled: cachedStageManagerEnabled,
            location: location,
            dockFrame: cachedDockFrame
        )
        guard handlingMode != .ignore else {
            candidate = nil
            return
        }

        let frontmostBundleIdentifier = cachedFrontmostBundleIdentifier
        let frontmostPID = cachedFrontmostPID
        // AX minimized state is reliable here; Stage Manager can keep minimized
        // windows in WindowServer's on-screen list.
        let hadVisibleWindow = type == .leftMouseDown
            && frontmostPID.map { windowState(pid: $0).hasVisibleWindow } == true
        DispatchQueue.main.async { [weak self] in
            self?.handleObservedEvent(
                type: type,
                location: location,
                timestamp: timestamp,
                frontmostBundleIdentifier: frontmostBundleIdentifier,
                frontmostPID: frontmostPID,
                hadVisibleWindow: hadVisibleWindow
            )
        }
    }

    fileprivate func reenableEventTap() {
        candidate = nil
        guard let eventTap else {
            installEventTapIfPossible()
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func installEventTapIfPossible() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let options = Self.eventTapOptions(stageManagerEnabled: cachedStageManagerEnabled)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: dockClickEventTapCallback,
            userInfo: context
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Unable to install Dock click event tap")
            return
        }

        eventTap = tap
        runLoopSource = source
        installedEventTapOptions = options
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        retryTimer?.invalidate()
        retryTimer = nil
        logger.notice("Dock click event tap installed; listenOnly=\(options == .listenOnly, privacy: .public)")
    }

    private func scheduleEventTapRetryIfNeeded() {
        guard eventTap == nil, retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.installEventTapIfPossible()
        }
    }

    private func invalidateEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
        installedEventTapOptions = nil
    }

    private func refreshStageManagerState() {
        let enabled = stageManagerIsEnabled()
        guard enabled != cachedStageManagerEnabled else { return }
        cachedStageManagerEnabled = enabled
        candidate = nil

        let requiredOptions = Self.eventTapOptions(stageManagerEnabled: enabled)
        guard installedEventTapOptions != requiredOptions else { return }
        invalidateEventTap()
        installEventTapIfPossible()
        scheduleEventTapRetryIfNeeded()
    }

    private func handleObservedEvent(
        type: CGEventType,
        location: CGPoint,
        timestamp: TimeInterval,
        frontmostBundleIdentifier: String?,
        frontmostPID: pid_t?,
        hadVisibleWindow: Bool
    ) {
        switch type {
        case .leftMouseDown:
            candidate = makeCandidate(
                location: location,
                timestamp: timestamp,
                frontmostBundleIdentifier: frontmostBundleIdentifier,
                frontmostPID: frontmostPID,
                detectPendingSystemRestore: false,
                hasVisibleWindowAtEvent: hadVisibleWindow
            )
        case .leftMouseUp:
            finishCandidate(location: location, timestamp: timestamp)
        default:
            break
        }
    }

    private func makeCandidate(
        location: CGPoint,
        timestamp: TimeInterval,
        frontmostBundleIdentifier: String?,
        frontmostPID: pid_t?,
        detectPendingSystemRestore: Bool,
        hasVisibleWindowAtEvent: Bool? = nil
    ) -> DockClickCandidate? {
        guard let clickedBundleIdentifier = dockApplicationBundleIdentifier(at: location),
              let clickedApplication = runningApplication(
                bundleIdentifier: clickedBundleIdentifier,
                preferredPID: frontmostPID
              ) else { return nil }
        let intent: DockClickIntent?
        if let hasVisibleWindowAtEvent {
            let state = windowState(pid: clickedApplication.processIdentifier)
            intent = Self.observedClickIntent(
                featureEnabled: preferences.dockClickMinimizesActiveWindow,
                clickedBundleIdentifier: clickedBundleIdentifier,
                frontmostBundleIdentifier: frontmostBundleIdentifier,
                wasMinimizedByDock: dockMinimizedApplicationPIDs.contains(
                    clickedApplication.processIdentifier
                ),
                hadVisibleWindowAtMouseDown: hasVisibleWindowAtEvent,
                hasVisibleWindowAfterDock: state.hasVisibleWindow,
                hasMinimizedWindowAfterDock: state.hasMinimizedWindow
            )
            logger.debug(
                "Observed Dock state: beforeVisible=\(hasVisibleWindowAtEvent, privacy: .public), afterVisible=\(state.hasVisibleWindow, privacy: .public), afterMinimized=\(state.hasMinimizedWindow, privacy: .public)"
            )
        } else {
            let state = windowState(pid: clickedApplication.processIdentifier)
            intent = Self.clickIntent(
                featureEnabled: preferences.dockClickMinimizesActiveWindow,
                clickedBundleIdentifier: clickedBundleIdentifier,
                frontmostBundleIdentifier: frontmostBundleIdentifier,
                hasVisibleWindow: state.hasVisibleWindow,
                hasMinimizedWindow: state.hasMinimizedWindow,
                detectPendingSystemRestore: detectPendingSystemRestore
            )
        }
        guard let intent else { return nil }

        let intentDescription = switch intent {
        case .minimize: "minimize"
        case .restoreNatively: "restore-natively"
        case .restoredBySystem: "restored-by-system"
        }
        logger.debug("Dock click intent: \(intentDescription, privacy: .public)")
        return DockClickCandidate(
            pid: clickedApplication.processIdentifier,
            bundleIdentifier: clickedBundleIdentifier,
            location: location,
            timestamp: timestamp,
            intent: intent
        )
    }

    private func finishCandidate(location: CGPoint, timestamp: TimeInterval) {
        guard let candidate else { return }
        self.candidate = nil
        let clickedBundleIdentifier = dockApplicationBundleIdentifier(at: location)
        guard candidate.matches(
            bundleIdentifier: clickedBundleIdentifier,
            location: location,
            timestamp: timestamp
        ) else { return }

        switch candidate.intent {
        case .minimize:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let minimized = self.minimizeHandler(candidate.pid)
                if minimized { self.dockMinimizedApplicationPIDs.insert(candidate.pid) }
                self.logger.debug("Dock minimize result: \(minimized, privacy: .public)")
            }
        case .restoreNatively, .restoredBySystem:
            dockMinimizedApplicationPIDs.remove(candidate.pid)
            logger.debug("Leaving minimized-window restoration to the Dock")
        }
    }

    private func refreshCachedSystemState() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        cachedFrontmostBundleIdentifier = frontmostApplication?.bundleIdentifier
        cachedFrontmostPID = frontmostApplication?.processIdentifier
        cachedStageManagerEnabled = stageManagerIsEnabled()
        refreshDockFrame()
    }

    private func refreshDockFrame() {
        guard preferences.dockClickMinimizesActiveWindow,
              AXIsProcessTrusted() else {
            cachedDockFrame = nil
            return
        }
        guard !dockFrameQueryInProgress else { return }
        dockFrameQueryInProgress = true
        dockFrameQueryQueue.async { [weak self] in
            let frame = self?.queryDockFrame()
            DispatchQueue.main.async { [weak self] in
                self?.cachedDockFrame = frame
                self?.dockFrameQueryInProgress = false
            }
        }
    }

    private func queryDockFrame() -> CGRect? {
        guard let dockApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.dockBundleIdentifier
        ).first else { return nil }
        let dockElement = AXUIElementCreateApplication(dockApplication.processIdentifier)
        let children: [AXUIElement] = copyAttribute(kAXChildrenAttribute as CFString, from: dockElement) ?? []
        guard let dockList = children.first(where: {
            let role: String? = copyAttribute(kAXRoleAttribute as CFString, from: $0)
            return role == (kAXListRole as String)
        }), let positionValue: AXValue = copyAttribute(kAXPositionAttribute as CFString, from: dockList),
              let sizeValue: AXValue = copyAttribute(kAXSizeAttribute as CFString, from: dockList) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0, size.height > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func dockApplicationBundleIdentifier(at location: CGPoint) -> String? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(location.x),
            Float(location.y),
            &element
        ) == .success, let element else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == Self.dockBundleIdentifier,
              let subrole: String = copyAttribute(kAXSubroleAttribute as CFString, from: element),
              subrole == "AXApplicationDockItem",
              let url: URL = copyAttribute("AXURL" as CFString, from: element) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    private func runningApplication(bundleIdentifier: String, preferredPID: pid_t?) -> NSRunningApplication? {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
        if let preferredPID,
           let preferred = applications.first(where: { $0.processIdentifier == preferredPID }) {
            return preferred
        }
        return applications.first
    }

    private func windowState(pid: pid_t) -> (hasVisibleWindow: Bool, hasMinimizedWindow: Bool) {
        let application = AXUIElementCreateApplication(pid)
        let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute as CFString, from: application) ?? []
        let focusedWindow: AXUIElement? = copyAttribute(kAXFocusedWindowAttribute as CFString, from: application)
        let mainWindow: AXUIElement? = copyAttribute(kAXMainWindowAttribute as CFString, from: application)
        let candidateWindows = [focusedWindow, mainWindow].compactMap { $0 } + windows
        let minimizedStates = candidateWindows.map {
            copyAttribute(kAXMinimizedAttribute as CFString, from: $0) ?? false
        }
        return Self.summarizedWindowState(
            minimizedStates: minimizedStates,
            hasOnScreenWindow: hasOnScreenWindow(pid: pid)
        )
    }

    private func stageManagerIsEnabled() -> Bool {
        let applicationID = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(applicationID)
        return (CFPreferencesCopyAppValue(
            "GloballyEnabled" as CFString,
            applicationID
        ) as? NSNumber)?.boolValue ?? false
    }

    private func hasOnScreenWindow(pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? [String: NSNumber],
                  let width = bounds["Width"]?.doubleValue,
                  let height = bounds["Height"]?.doubleValue else { return false }
            return width > 40 && height > 40
        }
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }
}
