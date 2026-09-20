import AppKit
import ApplicationServices
import Combine
import OSLog

private func accessibilityObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    if Thread.isMainThread {
        tracker.handleAccessibilityNotification(element: element, notification: notification as String)
    } else {
        DispatchQueue.main.async {
            tracker.handleAccessibilityNotification(element: element, notification: notification as String)
        }
    }
}

private final class ObservedApplication {
    let pid: pid_t
    let element: AXUIElement
    let observer: AXObserver
    var windowKeys = Set<AXWindowKey>()

    init(pid: pid_t, element: AXUIElement, observer: AXObserver) {
        self.pid = pid
        self.element = element
        self.observer = observer
    }

    deinit {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}

struct CGWindowRecord {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
    let title: String
}

final class WindowTracker {
    private let preferences: Preferences
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "window-tracker")
    private var overlays: [AXWindowKey: WindowOverlay] = [:]
    private var applications: [pid_t: ObservedApplication] = [:]
    private var timer: Timer?
    private var pointerMonitors: [Any] = []
    private var positionUpdateScheduled = false
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshScheduled = false
    private var lastScanSummary = ""
    private var quitOnCloseWindowKeys = Set<AXWindowKey>()

    init(preferences: Preferences) {
        self.preferences = preferences
        preferences.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refreshAll() } }
            .store(in: &subscriptions)

        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification
        ] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleRefresh()
            })
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.refreshAll() }
        timer?.tolerance = 0.08
        // Pointer events wake hidden controls; there is no continuous position poll.
        let pointerEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents, handler: { [weak self] _ in
            self?.handlePointerMovement()
        }) { pointerMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents, handler: { [weak self] event in
            self?.handlePointerMovement()
            return event
        }) { pointerMonitors.append(monitor) }
        refreshAll()
    }

    deinit {
        timer?.invalidate()
        pointerMonitors.forEach { NSEvent.removeMonitor($0) }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
    }

    func refreshAll() {
        refreshScheduled = false
        let shouldTrackWindows = Self.shouldTrackWindows(
            overlaysEnabled: preferences.enabled,
            quitOnCloseEnabled: preferences.quitOnCloseEnabled,
            hasQuitOnCloseApplications: !preferences.quitOnCloseApplications.isEmpty
        )
        guard shouldTrackWindows, AXIsProcessTrusted() else {
            quitOnCloseWindowKeys.removeAll(keepingCapacity: true)
            reportScan("disabled or accessibility permission unavailable")
            overlays.values.forEach { $0.hide() }
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated
                && $0.processIdentifier != ownPID
                && $0.activationPolicy == .regular
                && (preferences.enabled || preferences.shouldQuitOnClose(bundleIdentifier: $0.bundleIdentifier))
        }
        let activePIDs = Set(runningApps.map(\.processIdentifier))
        var seenWindows = Set<AXWindowKey>()
        var nextQuitOnCloseWindowKeys = Set<AXWindowKey>()

        for app in runningApps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 1.0)
            ensureObservedApplication(pid: pid, element: appElement)
            guard let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute as CFString, from: appElement) else { continue }

            for window in windows {
                let key = AXWindowKey(pid: pid, element: window)
                seenWindows.insert(key)
                if applications[pid]?.windowKeys.contains(key) != true {
                    registerWindowNotifications(for: key)
                }

                let closeButton: AXUIElement? = copyAttribute(
                    kAXCloseButtonAttribute as CFString,
                    from: window
                )
                if preferences.shouldQuitOnClose(bundleIdentifier: app.bundleIdentifier), closeButton != nil {
                    nextQuitOnCloseWindowKeys.insert(key)
                }

                guard preferences.enabled else {
                    overlays[key]?.hide()
                    continue
                }
                if overlays[key] == nil {
                    overlays[key] = WindowOverlay(key: key)
                }
                if overlays[key]?.update(preferences: preferences) != true {
                    overlays[key]?.hide()
                }
            }
        }

        quitOnCloseWindowKeys = nextQuitOnCloseWindowKeys
        let observedWindowKeys = applications.values.reduce(into: Set<AXWindowKey>()) {
            $0.formUnion($1.windowKeys)
        }
        let staleKeys = Set(overlays.keys).union(observedWindowKeys).filter { !seenWindows.contains($0) }
        for key in staleKeys {
            removeOverlay(for: key)
        }
        let stalePIDs = applications.keys.filter { !activePIDs.contains($0) }
        for pid in stalePIDs {
            applications.removeValue(forKey: pid)
        }
        reportScan("apps=\(runningApps.count) windows=\(seenWindows.count) overlays=\(overlays.count)")
        if preferences.enabled { refreshVisibility() }
    }

    fileprivate func handleAccessibilityNotification(element: AXUIElement, notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let key = AXWindowKey(pid: pid, element: element)

        switch notification {
        case kAXMovedNotification:
            // AX window geometry trails the compositor during an interactive drag.
            // Pull the current WindowServer frame instead of applying a stale AX frame.
            if preferences.enabled { schedulePositionUpdate() }
        case kAXResizedNotification:
            if preferences.enabled, let overlay = overlays[key] {
                _ = overlay.update(preferences: preferences, recalibrateNativeCenters: true)
                refreshVisibility()
            } else if preferences.enabled {
                scheduleRefresh()
            }
        case kAXUIElementDestroyedNotification:
            let shouldQuitApplication = quitOnCloseWindowKeys.remove(key) != nil
            removeOverlay(for: key)
            if preferences.enabled { refreshVisibility() }
            if shouldQuitApplication,
               let application = NSRunningApplication(processIdentifier: pid),
               preferences.shouldQuitOnClose(bundleIdentifier: application.bundleIdentifier),
               !application.isTerminated {
                logger.notice("Quitting pid=\(pid, privacy: .public) after a tracked window closed")
                if !application.terminate() {
                    logger.error("Unable to quit pid=\(pid, privacy: .public) after window close")
                }
            }
        case kAXWindowMiniaturizedNotification:
            overlays[key]?.suppressUntilRestored()
        case kAXWindowDeminiaturizedNotification:
            if preferences.enabled, let overlay = overlays[key] {
                overlay.restoreFromSuppression()
                _ = overlay.update(preferences: preferences, recalibrateNativeCenters: true)
                refreshVisibility()
            } else if preferences.enabled {
                scheduleRefresh()
            }
        default:
            scheduleRefresh()
        }
    }

    @discardableResult
    func minimizeFocusedWindow(of pid: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        let focusedWindow: AXUIElement? = copyAttribute(kAXFocusedWindowAttribute as CFString, from: application)
        let mainWindow: AXUIElement? = copyAttribute(kAXMainWindowAttribute as CFString, from: application)
        let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute as CFString, from: application) ?? []
        let preferredWindows = uniqueElements([focusedWindow, mainWindow].compactMap { $0 } + windows)
        guard let window = preferredWindows.first(where: { window in
            let minimized: Bool = copyAttribute(kAXMinimizedAttribute as CFString, from: window) ?? false
            return !minimized && canMinimize(window)
        }) else { return false }

        let key = AXWindowKey(pid: pid, element: window)
        let overlay = overlays[key]
        if Self.shouldUseOverlayMinimize(
            overlaysEnabled: preferences.enabled,
            overlayAvailable: overlay != nil
        ), overlay?.minimizeWindow() == true {
            return true
        }

        logger.debug("Dock minimize using direct Accessibility path")

        if let button: AXUIElement = copyAttribute(kAXMinimizeButtonAttribute as CFString, from: window),
           copyAttribute(kAXEnabledAttribute as CFString, from: button) ?? true {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard AXUIElementPerformAction(button, kAXPressAction as CFString) != .success else { return }
                _ = AXUIElementSetAttributeValue(
                    window,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanTrue
                )
                self?.logger.error("Dock minimize button action failed; used AXMinimized fallback")
            }
            return true
        }

        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            window,
            kAXMinimizedAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else { return false }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanTrue
            )
        }
        return true
    }

    static func shouldUseOverlayMinimize(overlaysEnabled: Bool, overlayAvailable: Bool) -> Bool {
        overlaysEnabled && overlayAvailable
    }

    static func shouldTrackWindows(
        overlaysEnabled: Bool,
        quitOnCloseEnabled: Bool,
        hasQuitOnCloseApplications: Bool
    ) -> Bool {
        overlaysEnabled || (quitOnCloseEnabled && hasQuitOnCloseApplications)
    }

    private func canMinimize(_ window: AXUIElement) -> Bool {
        if let button: AXUIElement = copyAttribute(kAXMinimizeButtonAttribute as CFString, from: window),
           copyAttribute(kAXEnabledAttribute as CFString, from: button) ?? true {
            return true
        }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            window,
            kAXMinimizedAttribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }

    private func uniqueElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var result: [AXUIElement] = []
        for element in elements where !result.contains(where: { CFEqual($0, element) }) {
            result.append(element)
        }
        return result
    }

    private func ensureObservedApplication(pid: pid_t, element: AXUIElement) {
        guard applications[pid] == nil else { return }
        var observerRef: AXObserver?
        guard AXObserverCreate(pid, accessibilityObserverCallback, &observerRef) == .success,
              let observer = observerRef else { return }

        let app = ObservedApplication(pid: pid, element: element, observer: observer)
        applications[pid] = app
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [
            kAXWindowCreatedNotification,
            kAXFocusedWindowChangedNotification,
            kAXApplicationActivatedNotification
        ] {
            _ = AXObserverAddNotification(observer, element, notification as CFString, context)
        }
    }

    private func registerWindowNotifications(for key: AXWindowKey) {
        guard let app = applications[key.pid] else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification
        ] {
            _ = AXObserverAddNotification(app.observer, key.element, notification as CFString, context)
        }
        app.windowKeys.insert(key)
    }

    private func removeOverlay(for key: AXWindowKey) {
        quitOnCloseWindowKeys.remove(key)
        overlays.removeValue(forKey: key)?.hide()
        guard let app = applications[key.pid] else { return }
        for notification in [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification
        ] {
            _ = AXObserverRemoveNotification(app.observer, key.element, notification as CFString)
        }
        app.windowKeys.remove(key)
    }

    private func refreshVisibility() {
        let records = cgWindowRecords()
        let overlayWindowIDs = Set(overlays.values.flatMap(\.panelWindowIDs))
        let mouseLocation = NSEvent.mouseLocation
        var shown = 0

        for overlay in overlays.values {
            guard let targetIndex = matchingRecordIndex(for: overlay, in: records) else {
                // AX and WindowServer can report a move in different frames for one run-loop turn.
                // Keep the previous frame visible instead of flashing it out during the drag.
                continue
            }
            overlay.bind(to: records[targetIndex].id)
            overlay.syncPosition(to: records[targetIndex].bounds)
            let visibleActions = unobscuredActions(
                for: overlay,
                above: targetIndex,
                in: records,
                ignoring: overlayWindowIDs
            )
            overlay.updatePresentation(
                availableActions: visibleActions,
                mouseLocation: mouseLocation,
                hiddenModeEnabled: preferences.hiddenTrafficLightsEnabled,
                revealMode: preferences.hiddenTrafficLightRevealMode
            )
            if !visibleActions.isEmpty { shown += 1 }
        }
        logger.debug("Visible overlays: \(shown, privacy: .public) / \(self.overlays.count, privacy: .public)")
    }

    private func handlePointerMovement() {
        guard preferences.enabled, preferences.hiddenTrafficLightsEnabled else { return }
        let location = NSEvent.mouseLocation
        guard overlays.values.contains(where: { $0.needsPointerUpdate(at: location) }) else { return }
        schedulePositionUpdate()
    }

    private func schedulePositionUpdate() {
        guard !positionUpdateScheduled else { return }
        positionUpdateScheduled = true
        // Coalesce high-rate mouse/AX events without keeping an idle timer alive.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
            guard let self else { return }
            self.positionUpdateScheduled = false
            self.syncWindowPositions()
        }
    }

    private func syncWindowPositions() {
        guard preferences.enabled, AXIsProcessTrusted(), !overlays.isEmpty else { return }
        let records = cgWindowRecords()
        let indicesByID = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.element.id, $0.offset) })
        let overlayWindowIDs = Set(overlays.values.flatMap(\.panelWindowIDs))
        let mouseLocation = NSEvent.mouseLocation

        for overlay in overlays.values {
            let targetIndex: Int?
            if let windowID = overlay.cgWindowID {
                targetIndex = indicesByID[windowID]
                if targetIndex == nil {
                    // A stale overlay is more visible than a one-frame hide while
                    // WindowServer replaces or removes a window record.
                    overlay.hide()
                    continue
                }
            } else {
                targetIndex = matchingRecordIndex(for: overlay, in: records)
            }

            guard let targetIndex else { continue }
            let record = records[targetIndex]
            overlay.bind(to: record.id)
            overlay.syncPosition(to: record.bounds)
            let visibleActions = unobscuredActions(
                for: overlay,
                above: targetIndex,
                in: records,
                ignoring: overlayWindowIDs
            )
            overlay.updatePresentation(
                availableActions: visibleActions,
                mouseLocation: mouseLocation,
                hiddenModeEnabled: preferences.hiddenTrafficLightsEnabled,
                revealMode: preferences.hiddenTrafficLightRevealMode
            )
        }
    }

    private func unobscuredActions(
        for overlay: WindowOverlay,
        above targetIndex: Int,
        in records: [CGWindowRecord],
        ignoring windowIDs: Set<CGWindowID>
    ) -> Set<WindowAction> {
        let coveringFrames = Self.coveringFrames(
            above: targetIndex,
            in: records,
            ignoring: windowIDs
        )
        return ControlLayout.unobscuredActions(
            controlFrames: overlay.controlFrames,
            coveringFrames: coveringFrames
        )
    }

    static func coveringFrames(
        above targetIndex: Int,
        in records: [CGWindowRecord],
        ignoring windowIDs: Set<CGWindowID>
    ) -> [CGRect] {
        guard records.indices.contains(targetIndex) else { return [] }
        return records[..<targetIndex]
            .filter { !windowIDs.contains($0.id) }
            .map(\.bounds)
    }

    private func matchingRecordIndex(for overlay: WindowOverlay, in records: [CGWindowRecord]) -> Int? {
        if let windowID = overlay.cgWindowID,
           let boundIndex = records.firstIndex(where: {
               $0.id == windowID && $0.pid == overlay.key.pid && $0.layer == 0
           }) {
            return boundIndex
        }
        let candidates = records.enumerated().filter {
            $0.element.pid == overlay.key.pid && $0.element.layer == 0
        }
        return candidates.min { lhs, rhs in
            matchScore(record: lhs.element, overlay: overlay) < matchScore(record: rhs.element, overlay: overlay)
        }.flatMap { matchScore(record: $0.element, overlay: overlay) < 24 ? $0.offset : nil }
    }

    private func matchScore(record: CGWindowRecord, overlay: WindowOverlay) -> CGFloat {
        let frame = overlay.windowFrame
        var score = abs(record.bounds.minX - frame.minX)
            + abs(record.bounds.minY - frame.minY)
            + abs(record.bounds.width - frame.width)
            + abs(record.bounds.height - frame.height)
        if !overlay.title.isEmpty, !record.title.isEmpty, overlay.title != record.title { score += 100 }
        return score
    }

    private func cgWindowRecords() -> [CGWindowRecord] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let dictionary = info[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = dictionary["X"]?.doubleValue,
                  let y = dictionary["Y"]?.doubleValue,
                  let width = dictionary["Width"]?.doubleValue,
                  let height = dictionary["Height"]?.doubleValue,
                  case let bounds = CGRect(x: x, y: y, width: width, height: height),
                  Self.shouldIncludeWindowRecord(
                      layer: layer,
                      alpha: alpha,
                      bounds: bounds
                  ) else { return nil }
            return CGWindowRecord(
                id: id,
                pid: pid,
                layer: layer,
                bounds: bounds,
                title: info[kCGWindowName as String] as? String ?? ""
            )
        }
    }

    static func shouldIncludeWindowRecord(layer: Int, alpha: Double, bounds: CGRect) -> Bool {
        let dockWindowLevel = Int(CGWindowLevelForKey(.dockWindow))
        return layer >= 0
            && layer < dockWindowLevel
            && alpha > 0.01
            && bounds.width > 40
            && bounds.height > 40
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in self?.refreshAll() }
    }

    private func reportScan(_ summary: String) {
        guard summary != lastScanSummary else { return }
        lastScanSummary = summary
        logger.notice("\(summary, privacy: .public)")
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }
}
