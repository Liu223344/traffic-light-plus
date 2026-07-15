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

private struct CGWindowRecord {
    let id: CGWindowID
    let pid: pid_t
    let bounds: CGRect
    let title: String
}

final class WindowTracker {
    private let preferences: Preferences
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "window-tracker")
    private var overlays: [AXWindowKey: WindowOverlay] = [:]
    private var applications: [pid_t: ObservedApplication] = [:]
    private var timer: Timer?
    private var positionTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshScheduled = false
    private var lastScanSummary = ""
    private var trackingCadence = TrackingCadence()
    private var trackingActivity: NSObjectProtocol?
    private var trackingActivityEndWorkItem: DispatchWorkItem?
    private var globalMouseMonitor: Any?

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

        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.refreshAllIfIdle()
        }
        // The timer matches the active tracking rate. TrackingCadence skips most
        // callbacks while idle, so 240 Hz is used only around moves and resizes.
        let positionTimer = Timer(timeInterval: TrackingCadence.activeInterval, repeats: true) { [weak self] _ in
            self?.syncWindowPositions()
        }
        positionTimer.tolerance = 0
        self.positionTimer = positionTimer
        RunLoop.main.add(positionTimer, forMode: .common)
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] _ in
            if Thread.isMainThread {
                self?.handleGlobalMouseDown()
            } else {
                DispatchQueue.main.async { self?.handleGlobalMouseDown() }
            }
        }
        refreshAll()
    }

    deinit {
        timer?.invalidate()
        positionTimer?.invalidate()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        trackingActivityEndWorkItem?.cancel()
        endTrackingActivity()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
    }

    func refreshAll() {
        refreshScheduled = false
        guard preferences.enabled, AXIsProcessTrusted() else {
            reportScan("disabled or accessibility permission unavailable")
            overlays.values.forEach { $0.hide() }
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.processIdentifier != ownPID && $0.activationPolicy == .regular
        }
        let activePIDs = Set(runningApps.map(\.processIdentifier))
        var seenWindows = Set<AXWindowKey>()

        for app in runningApps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 1.0)
            ensureObservedApplication(pid: pid, element: appElement)
            guard let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute as CFString, from: appElement) else { continue }

            for window in windows {
                let key = AXWindowKey(pid: pid, element: window)
                seenWindows.insert(key)
                if overlays[key] == nil {
                    overlays[key] = WindowOverlay(key: key)
                    registerWindowNotifications(for: key)
                }
                if overlays[key]?.update(preferences: preferences) != true {
                    overlays[key]?.hide()
                }
            }
        }

        let staleKeys = overlays.keys.filter { !seenWindows.contains($0) }
        for key in staleKeys {
            removeOverlay(for: key)
        }
        let stalePIDs = applications.keys.filter { !activePIDs.contains($0) }
        for pid in stalePIDs {
            applications.removeValue(forKey: pid)
        }
        let appNames = runningApps.compactMap(\.localizedName).sorted().joined(separator: ",")
        reportScan("apps=[\(appNames)] windows=\(seenWindows.count) overlays=\(overlays.count)")
        refreshVisibility()
    }

    private func refreshAllIfIdle() {
        let now = ProcessInfo.processInfo.systemUptime
        guard !trackingCadence.isHighFrequency(now: now) else { return }
        refreshAll()
    }

    fileprivate func handleAccessibilityNotification(element: AXUIElement, notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let key = AXWindowKey(pid: pid, element: element)

        switch notification {
        case kAXMovedNotification:
            // AX window geometry trails the compositor during an interactive drag.
            // Pull the current WindowServer frame instead of applying a stale AX frame.
            boostTracking()
            syncWindowPositions(force: true)
        case kAXResizedNotification:
            boostTracking()
            if let overlay = overlays[key] {
                _ = overlay.update(preferences: preferences, recalibrateNativeCenters: true)
                syncWindowPositions(force: true)
            } else {
                scheduleRefresh()
            }
        case kAXUIElementDestroyedNotification:
            removeOverlay(for: key)
            refreshVisibility()
        case kAXWindowMiniaturizedNotification:
            overlays[key]?.suppressUntilRestored()
        case kAXWindowDeminiaturizedNotification:
            if let overlay = overlays[key] {
                overlay.restoreFromSuppression()
                _ = overlay.update(preferences: preferences, recalibrateNativeCenters: true)
                refreshVisibility()
            } else {
                scheduleRefresh()
            }
        default:
            scheduleRefresh()
        }
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

    private func boostTracking() {
        trackingCadence.boost(now: ProcessInfo.processInfo.systemUptime)
        if trackingActivity == nil {
            trackingActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Keep traffic-light overlays synchronized during window movement"
            )
        }
        scheduleTrackingActivityEndIfNeeded()
    }

    private func scheduleTrackingActivityEndIfNeeded() {
        guard trackingActivityEndWorkItem == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delay = max(0.05, trackingCadence.highFrequencyUntil - now + 0.05)
        let workItem = DispatchWorkItem { [weak self] in self?.finishTrackingActivityIfIdle() }
        trackingActivityEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func finishTrackingActivityIfIdle() {
        trackingActivityEndWorkItem = nil
        if trackingCadence.isHighFrequency(now: ProcessInfo.processInfo.systemUptime) {
            scheduleTrackingActivityEndIfNeeded()
        } else {
            endTrackingActivity()
        }
    }

    private func handleGlobalMouseDown() {
        boostTracking()
    }

    private func endTrackingActivity() {
        guard let trackingActivity else { return }
        ProcessInfo.processInfo.endActivity(trackingActivity)
        self.trackingActivity = nil
        trackingActivityEndWorkItem = nil
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
        var shown = 0

        for overlay in overlays.values {
            guard let targetIndex = matchingRecordIndex(for: overlay, in: records) else {
                // AX and WindowServer can report a move in different frames for one run-loop turn.
                // Keep the previous frame visible instead of flashing it out during the drag.
                continue
            }
            overlay.bind(to: records[targetIndex].id)
            overlay.syncPosition(to: records[targetIndex].bounds)
            overlay.setVisible(true)
            overlay.refreshStackingOrder()
            shown += 1
        }
        logger.debug("Visible overlays: \(shown, privacy: .public) / \(self.overlays.count, privacy: .public)")
    }

    private func syncWindowPositions(force: Bool = false) {
        guard preferences.enabled, AXIsProcessTrusted(), !overlays.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard trackingCadence.shouldSync(now: now, force: force) else { return }
        let records = cgWindowRecords()
        let indicesByID = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.element.id, $0.offset) })
        let mouseLocation = NSEvent.mouseLocation

        for overlay in overlays.values {
            let targetIndex: Int?
            if let windowID = overlay.cgWindowID {
                targetIndex = indicesByID[windowID]
                if targetIndex == nil {
                    // WindowServer can omit a moving window for one compositor frame.
                    // Preserve the last overlay position instead of flashing back
                    // to the original small controls.
                    continue
                }
            } else {
                targetIndex = matchingRecordIndex(for: overlay, in: records)
            }

            guard let targetIndex else { continue }
            let record = records[targetIndex]
            overlay.bind(to: record.id)
            overlay.syncPosition(to: record.bounds)
            overlay.setVisible(true)
            overlay.reconcileHoverState(mouseLocation: mouseLocation)
        }
    }

    private func matchingRecordIndex(for overlay: WindowOverlay, in records: [CGWindowRecord]) -> Int? {
        if let windowID = overlay.cgWindowID,
           let boundIndex = records.firstIndex(where: { $0.id == windowID && $0.pid == overlay.key.pid }) {
            return boundIndex
        }
        let candidates = records.enumerated().filter { $0.element.pid == overlay.key.pid }
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
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let dictionary = info[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = dictionary["X"]?.doubleValue,
                  let y = dictionary["Y"]?.doubleValue,
                  let width = dictionary["Width"]?.doubleValue,
                  let height = dictionary["Height"]?.doubleValue,
                  case let bounds = CGRect(x: x, y: y, width: width, height: height),
                  bounds.width > 40, bounds.height > 40 else { return nil }
            return CGWindowRecord(
                id: id,
                pid: pid,
                bounds: bounds,
                title: info[kCGWindowName as String] as? String ?? ""
            )
        }
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
