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
        if controller.handleEvent(type: type, event: event) { return nil }
    }
    return Unmanaged.passUnretained(event)
}

enum DockClickIntent {
    case minimize
    case restore
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
    private let restoreHandler: (pid_t) -> Bool
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "dock-click")
    private let systemWideElement = AXUIElementCreateSystemWide()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var candidate: DockClickCandidate?

    init(
        preferences: Preferences,
        minimizeHandler: @escaping (pid_t) -> Bool,
        restoreHandler: @escaping (pid_t) -> Bool
    ) {
        self.preferences = preferences
        self.minimizeHandler = minimizeHandler
        self.restoreHandler = restoreHandler
        installEventTapIfPossible()
        if eventTap == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.installEventTapIfPossible()
            }
        }
    }

    deinit {
        retryTimer?.invalidate()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
    }

    static func clickIntent(
        featureEnabled: Bool,
        clickedBundleIdentifier: String?,
        frontmostBundleIdentifier: String?,
        hasVisibleWindow: Bool,
        hasMinimizedWindow: Bool
    ) -> DockClickIntent? {
        guard featureEnabled, let clickedBundleIdentifier else { return nil }
        if hasVisibleWindow,
           let frontmostBundleIdentifier,
           clickedBundleIdentifier.caseInsensitiveCompare(frontmostBundleIdentifier) == .orderedSame {
            return .minimize
        }
        if !hasVisibleWindow, hasMinimizedWindow { return .restore }
        return nil
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        let featureEnabled = preferences.enabled && preferences.dockClickMinimizesActiveWindow
        guard featureEnabled else {
            candidate = nil
            return false
        }

        let location = event.location
        let timestamp = ProcessInfo.processInfo.systemUptime
        switch type {
        case .leftMouseDown:
            let clickedBundleIdentifier = dockApplicationBundleIdentifier(at: location)
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            guard let clickedBundleIdentifier,
                  let clickedApplication = runningApplication(
                    bundleIdentifier: clickedBundleIdentifier,
                    preferredPID: frontmostApplication?.processIdentifier
                  ) else {
                candidate = nil
                return false
            }
            let state = windowState(pid: clickedApplication.processIdentifier)
            guard let intent = Self.clickIntent(
                featureEnabled: featureEnabled,
                clickedBundleIdentifier: clickedBundleIdentifier,
                frontmostBundleIdentifier: frontmostApplication?.bundleIdentifier,
                hasVisibleWindow: state.hasVisibleWindow,
                hasMinimizedWindow: state.hasMinimizedWindow
            ) else {
                candidate = nil
                return false
            }
            candidate = DockClickCandidate(
                pid: clickedApplication.processIdentifier,
                bundleIdentifier: clickedBundleIdentifier,
                location: location,
                timestamp: timestamp,
                intent: intent
            )
            logger.debug("Dock click intent: \(intent == .restore ? "restore" : "minimize", privacy: .public)")
            return intent == .restore
        case .leftMouseUp:
            guard let candidate else { return false }
            self.candidate = nil
            let clickedBundleIdentifier = dockApplicationBundleIdentifier(at: location)
            let matches = candidate.matches(
                bundleIdentifier: clickedBundleIdentifier,
                location: location,
                timestamp: timestamp
            )
            guard matches else { return candidate.intent == .restore }
            switch candidate.intent {
            case .minimize:
                DispatchQueue.main.async { [weak self] in
                    _ = self?.minimizeHandler(candidate.pid)
                }
                return false
            case .restore:
                logger.debug("Restoring minimized window without Dock animation path")
                DispatchQueue.main.async { [weak self] in
                    _ = self?.restoreHandler(candidate.pid)
                }
                return true
            }
        default:
            return false
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
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: dockClickEventTapCallback,
            userInfo: context
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Unable to install Dock click event tap")
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        retryTimer?.invalidate()
        retryTimer = nil
        logger.notice("Dock click event tap installed")
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
        let hasMinimizedWindow = windows.contains {
            copyAttribute(kAXMinimizedAttribute as CFString, from: $0) ?? false
        }
        return (hasOnScreenWindow(pid: pid), hasMinimizedWindow)
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
