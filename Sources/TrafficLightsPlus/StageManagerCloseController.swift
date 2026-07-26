import AppKit
import ApplicationServices
import OSLog

private func stageManagerCloseEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<StageManagerCloseController>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.reenableClickEventTap()
        return Unmanaged.passUnretained(event)
    }
    return controller.handleClickEvent(type: type, event: event)
        ? nil
        : Unmanaged.passUnretained(event)
}

struct StageManagerGroupID: Hashable {
    let windowIDs: [CGWindowID]
}

struct StageManagerWindowRecord: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let bounds: CGRect
}

struct StageManagerWindowCandidate: Equatable {
    let title: String
    let isFocused: Bool
    let isMain: Bool
}

final class StageManagerCloseButton: NSButton {
    private var isPointerInside = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setPointerInside(_ isPointerInside: Bool) {
        guard self.isPointerInside != isPointerInside else { return }
        self.isPointerInside = isPointerInside
    }

    private func updateAppearance() {
        contentTintColor = isPointerInside
            ? NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1)
            : .secondaryLabelColor
        image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))
    }

}

final class StageManagerClosePanel: NSPanel {
    static let panelSize = CGSize(width: 28, height: 28)

    let closeButton: StageManagerCloseButton
    private var currentLanguage: AppLanguage?

    init(language: AppLanguage) {
        closeButton = StageManagerCloseButton(frame: NSRect(origin: .zero, size: Self.panelSize))
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = closeButton
        closeButton.autoresizingMask = [.width, .height]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        updateLanguage(language)
    }

    func updateLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        currentLanguage = language
        let label = AppLocalization.string(.stageManagerCloseAction, language: language)
        closeButton.toolTip = label
        closeButton.setAccessibilityLabel(label)
    }
}

final class StageManagerCloseController {
    static let closeButtonInset: CGFloat = 0
    static let closeButtonRevealPadding: CGFloat = 12

    private static let windowManagerBundleIdentifier = "com.apple.WindowManager"
    private static let scanInterval = 0.4
    private static let positionInterval = 1.0 / 30.0
    private static let dismissalDuration = 1.0

    private let preferences: Preferences
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "stage-manager-close")
    private let scanQueue = DispatchQueue(
        label: "app.trafficlightsplus.mac.stage-manager-close.scan",
        qos: .utility
    )
    private let actionQueue = DispatchQueue(
        label: "app.trafficlightsplus.mac.stage-manager-close.action",
        qos: .userInitiated
    )
    private var scanTimer: Timer?
    private var positionTimer: Timer?
    private var clickEventTap: CFMachPort?
    private var clickRunLoopSource: CFRunLoopSource?
    private var clickEventTapRetryTimer: Timer?
    private var scanInProgress = false
    private var trackedGroups: [StageManagerGroupID] = []
    private var closableWindowIDs = Set<CGWindowID>()
    private var panels: [StageManagerGroupID: StageManagerClosePanel] = [:]
    private var visibleCloseFrames: [StageManagerGroupID: CGRect] = [:]
    private var dismissedWindowIDs: [CGWindowID: TimeInterval] = [:]
    private var isConsumingCloseClick = false

    init(preferences: Preferences) {
        self.preferences = preferences
        scanTimer = Timer.scheduledTimer(withTimeInterval: Self.scanInterval, repeats: true) { [weak self] _ in
            self?.refreshGroups()
        }
        scanTimer?.tolerance = 0.08
        positionTimer = Timer(timeInterval: Self.positionInterval, repeats: true) { [weak self] _ in
            self?.refreshPositions()
        }
        positionTimer?.tolerance = 1.0 / 120.0
        if let positionTimer { RunLoop.main.add(positionTimer, forMode: .common) }
        installClickEventTapIfPossible()
        scheduleClickEventTapRetryIfNeeded()
        refreshGroups()
    }

    deinit {
        scanTimer?.invalidate()
        positionTimer?.invalidate()
        clickEventTapRetryTimer?.invalidate()
        invalidateClickEventTap()
        panels.values.forEach { $0.orderOut(nil) }
    }

    static func closeButtonFrame(for thumbnailFrame: CGRect) -> CGRect {
        CGRect(
            x: thumbnailFrame.minX + closeButtonInset,
            y: thumbnailFrame.minY + closeButtonInset,
            width: StageManagerClosePanel.panelSize.width,
            height: StageManagerClosePanel.panelSize.height
        )
    }

    static func frontmostRecord(
        for group: StageManagerGroupID,
        in records: [StageManagerWindowRecord]
    ) -> StageManagerWindowRecord? {
        records.first { group.windowIDs.contains($0.id) }
    }

    static func shouldRevealCloseButton(mouseLocation: CGPoint, panelFrame: CGRect) -> Bool {
        panelFrame.insetBy(
            dx: -closeButtonRevealPadding,
            dy: -closeButtonRevealPadding
        ).contains(mouseLocation)
    }

    static func closeButtonContainsClick(_ location: CGPoint, frame: CGRect) -> Bool {
        frame.contains(location)
    }

    static func matchingCandidateIndex(
        recordTitle: String,
        candidates: [StageManagerWindowCandidate]
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let exactMatches = candidates.indices.filter {
            !recordTitle.isEmpty && candidates[$0].title == recordTitle
        }
        if exactMatches.count == 1 { return exactMatches[0] }
        if exactMatches.count > 1 {
            let preferred = exactMatches.filter {
                candidates[$0].isFocused || candidates[$0].isMain
            }
            return preferred.count == 1 ? preferred[0] : nil
        }
        return candidates.count == 1 ? 0 : nil
    }

    private func refreshGroups() {
        guard preferences.stageManagerCloseButtonsEnabled,
              AXIsProcessTrusted(),
              Self.stageManagerIsEnabled() else {
            trackedGroups = []
            closableWindowIDs = []
            hideAllPanels()
            return
        }
        guard !scanInProgress else { return }
        scanInProgress = true
        scanQueue.async { [weak self] in
            let groups = Self.queryStageManagerGroups()
            let records = Self.onScreenWindowRecords()
            let closableWindowIDs = Set(groups.compactMap { group -> CGWindowID? in
                guard let record = Self.frontmostRecord(for: group, in: records),
                      Self.resolveCloseButton(for: record) != nil else { return nil }
                return record.id
            })
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scanInProgress = false
                self.apply(groups: groups, closableWindowIDs: closableWindowIDs)
            }
        }
    }

    private func apply(groups: [StageManagerGroupID], closableWindowIDs: Set<CGWindowID>) {
        trackedGroups = groups
        self.closableWindowIDs = closableWindowIDs
        let activeGroups = Set(groups)
        let staleGroups = panels.keys.filter { !activeGroups.contains($0) }
        for id in staleGroups {
            panels.removeValue(forKey: id)?.orderOut(nil)
        }
        refreshPositions()
    }

    private func refreshPositions() {
        guard preferences.stageManagerCloseButtonsEnabled,
              clickEventTap != nil,
              !trackedGroups.isEmpty else {
            hideAllPanels()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        dismissedWindowIDs = dismissedWindowIDs.filter { $0.value > now }
        let records = Self.onScreenWindowRecords()
        let mouseLocation = NSEvent.mouseLocation
        var nextVisibleCloseFrames: [StageManagerGroupID: CGRect] = [:]

        for group in trackedGroups {
            guard let record = Self.frontmostRecord(for: group, in: records),
                  closableWindowIDs.contains(record.id),
                  dismissedWindowIDs[record.id] == nil,
                  let cgFrame = Self.visibleThumbnailFrame(for: record),
                  let panelFrame = appKitFrame(for: Self.closeButtonFrame(for: cgFrame)) else {
                panels[group]?.orderOut(nil)
                continue
            }

            let panel = panels[group] ?? makePanel(for: group)
            panel.updateLanguage(preferences.language)
            if panel.frame != panelFrame { panel.setFrame(panelFrame, display: true) }
            if Self.shouldRevealCloseButton(
                mouseLocation: mouseLocation,
                panelFrame: panelFrame
            ) {
                panel.closeButton.setPointerInside(panelFrame.contains(mouseLocation))
                if !panel.isVisible { panel.orderFrontRegardless() }
                nextVisibleCloseFrames[group] = Self.closeButtonFrame(for: cgFrame)
            } else if panel.isVisible {
                panel.orderOut(nil)
            }
        }
        visibleCloseFrames = nextVisibleCloseFrames
    }

    private func makePanel(for group: StageManagerGroupID) -> StageManagerClosePanel {
        let panel = StageManagerClosePanel(language: preferences.language)
        panels[group] = panel
        return panel
    }

    private func closeFrontmostWindow(in group: StageManagerGroupID, panel: StageManagerClosePanel?) {
        let records = Self.onScreenWindowRecords()
        guard let record = Self.frontmostRecord(for: group, in: records) else { return }
        visibleCloseFrames.removeValue(forKey: group)
        dismissedWindowIDs[record.id] = ProcessInfo.processInfo.systemUptime + Self.dismissalDuration
        panel?.orderOut(nil)

        actionQueue.async { [weak self] in
            let closed = Self.closeWindow(record)
            guard !closed else { return }
            DispatchQueue.main.async { [weak self] in
                self?.dismissedWindowIDs.removeValue(forKey: record.id)
                NSSound.beep()
            }
        }
    }

    private func hideAllPanels() {
        visibleCloseFrames.removeAll()
        panels.values.forEach { panel in
            if panel.isVisible { panel.orderOut(nil) }
        }
    }

    fileprivate func handleClickEvent(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .leftMouseDown:
            guard preferences.stageManagerCloseButtonsEnabled,
                  let target = visibleCloseFrames.first(where: {
                      Self.closeButtonContainsClick(event.location, frame: $0.value)
                  }) else {
                isConsumingCloseClick = false
                return false
            }
            isConsumingCloseClick = true
            closeFrontmostWindow(in: target.key, panel: panels[target.key])
            return true
        case .leftMouseUp:
            guard isConsumingCloseClick else { return false }
            isConsumingCloseClick = false
            return true
        default:
            return false
        }
    }

    fileprivate func reenableClickEventTap() {
        guard let clickEventTap else {
            installClickEventTapIfPossible()
            return
        }
        CGEvent.tapEnable(tap: clickEventTap, enable: true)
    }

    private func installClickEventTapIfPossible() {
        guard clickEventTap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: stageManagerCloseEventTapCallback,
            userInfo: context
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Unable to install Stage Manager close click event tap")
            return
        }
        clickEventTap = tap
        clickRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        clickEventTapRetryTimer?.invalidate()
        clickEventTapRetryTimer = nil
        logger.notice("Stage Manager close click event tap installed")
    }

    private func scheduleClickEventTapRetryIfNeeded() {
        guard clickEventTap == nil, clickEventTapRetryTimer == nil else { return }
        clickEventTapRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.installClickEventTapIfPossible()
        }
    }

    private func invalidateClickEventTap() {
        if let clickRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), clickRunLoopSource, .commonModes)
        }
        if let clickEventTap { CFMachPortInvalidate(clickEventTap) }
        clickRunLoopSource = nil
        clickEventTap = nil
    }

    private static func queryStageManagerGroups() -> [StageManagerGroupID] {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: windowManagerBundleIdentifier
        ).first else { return [] }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        var buttons: [AXUIElement] = []
        collectStageManagerButtons(from: root, depth: 0, into: &buttons)

        var seen = Set<StageManagerGroupID>()
        return buttons.compactMap { button in
            guard let numbers: [NSNumber] = copyAttribute("AXWindowsIDs" as CFString, from: button) else {
                return nil
            }
            let ids = numbers.map(\.uint32Value).sorted()
            guard !ids.isEmpty else { return nil }
            let group = StageManagerGroupID(windowIDs: ids)
            return seen.insert(group).inserted ? group : nil
        }
    }

    private static func collectStageManagerButtons(
        from element: AXUIElement,
        depth: Int,
        into result: inout [AXUIElement]
    ) {
        guard depth < 6 else { return }
        let role: String? = copyAttribute(kAXRoleAttribute as CFString, from: element)
        if role == (kAXButtonRole as String),
           let ids: [NSNumber] = copyAttribute("AXWindowsIDs" as CFString, from: element),
           !ids.isEmpty {
            result.append(element)
            return
        }
        let children: [AXUIElement] = copyAttribute(kAXChildrenAttribute as CFString, from: element) ?? []
        for child in children {
            collectStageManagerButtons(from: child, depth: depth + 1, into: &result)
        }
    }

    private static func onScreenWindowRecords() -> [StageManagerWindowRecord] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return windows.compactMap { info in
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let dictionary = info[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = dictionary["X"]?.doubleValue,
                  let y = dictionary["Y"]?.doubleValue,
                  let width = dictionary["Width"]?.doubleValue,
                  let height = dictionary["Height"]?.doubleValue else { return nil }
            return StageManagerWindowRecord(
                id: id,
                pid: pid,
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }

    private static func visibleThumbnailFrame(for record: StageManagerWindowRecord) -> CGRect? {
        guard record.bounds.width >= 48,
              record.bounds.height >= 48,
              record.bounds.width <= 420,
              record.bounds.height <= 320 else { return nil }
        return record.bounds
    }

    private static func closeWindow(_ record: StageManagerWindowRecord) -> Bool {
        guard let closeButton = resolveCloseButton(for: record) else { return false }
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    private static func resolveCloseButton(for record: StageManagerWindowRecord) -> AXUIElement? {
        let application = AXUIElementCreateApplication(record.pid)
        let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute as CFString, from: application) ?? []
        let candidates = windows.map { window in
            StageManagerWindowCandidate(
                title: copyAttribute(kAXTitleAttribute as CFString, from: window) ?? "",
                isFocused: copyAttribute(kAXFocusedAttribute as CFString, from: window) ?? false,
                isMain: copyAttribute(kAXMainAttribute as CFString, from: window) ?? false
            )
        }
        guard let index = matchingCandidateIndex(recordTitle: record.title, candidates: candidates),
              windows.indices.contains(index),
              let closeButton: AXUIElement = copyAttribute(
                  kAXCloseButtonAttribute as CFString,
                  from: windows[index]
              ),
              copyAttribute(kAXEnabledAttribute as CFString, from: closeButton) ?? true else {
            return nil
        }
        return closeButton
    }

    private static func stageManagerIsEnabled() -> Bool {
        let applicationID = windowManagerBundleIdentifier as CFString
        CFPreferencesAppSynchronize(applicationID)
        return (CFPreferencesCopyAppValue(
            "GloballyEnabled" as CFString,
            applicationID
        ) as? NSNumber)?.boolValue ?? false
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

    private static func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }
}
