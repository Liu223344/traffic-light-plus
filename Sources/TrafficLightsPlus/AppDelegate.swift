import AppKit
import SwiftUI
import Combine
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum MenuTag {
        static let settings = 99
        static let overlaysEnabled = 100
        static let dockClickEnabled = 101
        static let checkForUpdates = 102
        static let quit = 103
    }
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "lifecycle")
    private let preferences = Preferences()
    private let updateController = UpdateController()
    private var tracker: WindowTracker?
    private var dockClickController: DockClickController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("Application finished launching")
        NSApp.setActivationPolicy(.accessory)
        updateController.start()
        tracker = WindowTracker(preferences: preferences)
        dockClickController = DockClickController(
            preferences: preferences,
            minimizeHandler: { [weak self] pid in
                self?.minimizeWindowFromDock(pid: pid) ?? false
            }
        )
        configureStatusItem()
        preferences.$language
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] language in self?.applyLanguage(language) }
            .store(in: &subscriptions)
        preferences.$menuBarIconVisible
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in self?.statusItem?.isVisible = isVisible }
            .store(in: &subscriptions)
        if Self.shouldOpenSettingsAtLaunch(menuBarIconVisible: preferences.menuBarIconVisible) {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    static func shouldOpenSettingsAtLaunch(menuBarIconVisible: Bool) -> Bool {
        !menuBarIconVisible
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Traffic Lights+")
        item.isVisible = preferences.menuBarIconVisible

        let menu = NSMenu()
        menu.delegate = self
        let settingsItem = menu.addItem(
            withTitle: localized(.menuSettings),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.tag = MenuTag.settings
        settingsItem.target = self
        menu.addItem(NSMenuItem.separator())
        let overlayToggle = NSMenuItem(
            title: localized(.menuEnableOverlays),
            action: #selector(toggleOverlaysEnabled(_:)),
            keyEquivalent: ""
        )
        overlayToggle.tag = MenuTag.overlaysEnabled
        overlayToggle.target = self
        overlayToggle.state = preferences.enabled ? .on : .off
        menu.addItem(overlayToggle)
        let dockClickToggle = NSMenuItem(
            title: localized(.menuEnableDockClick),
            action: #selector(toggleDockClickEnabled(_:)),
            keyEquivalent: ""
        )
        dockClickToggle.tag = MenuTag.dockClickEnabled
        dockClickToggle.target = self
        dockClickToggle.state = preferences.dockClickMinimizesActiveWindow ? .on : .off
        menu.addItem(dockClickToggle)
        menu.addItem(NSMenuItem.separator())
        let checkForUpdatesItem = menu.addItem(
            withTitle: localized(.checkForUpdates),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.tag = MenuTag.checkForUpdates
        checkForUpdatesItem.target = self
        checkForUpdatesItem.isEnabled = updateController.canCheckForUpdates
        menu.addItem(NSMenuItem.separator())
        let quitItem = menu.addItem(
            withTitle: localized(.menuQuit),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.tag = MenuTag.quit
        quitItem.target = self
        item.menu = menu
        statusItem = item
    }

    @objc func showSettings() {
        logger.notice("Showing settings window")
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(
                preferences: preferences,
                updateController: updateController
            ))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 480, height: 680))
            window.title = localized(.settingsWindowTitle)
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        let changedPolicy = NSApp.setActivationPolicy(.regular)
        logger.notice("Regular activation policy result: \(changedPolicy, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        if let window = settingsWindow {
            logger.notice("Settings window visible: \(window.isVisible, privacy: .public)")
        }
    }

    @objc private func toggleOverlaysEnabled(_ sender: NSMenuItem) {
        preferences.enabled.toggle()
        sender.state = preferences.enabled ? .on : .off
    }

    @objc private func toggleDockClickEnabled(_ sender: NSMenuItem) {
        preferences.dockClickMinimizesActiveWindow.toggle()
        sender.state = preferences.dockClickMinimizesActiveWindow ? .on : .off
    }

    @objc private func checkForUpdates() {
        updateController.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func applyLanguage(_ language: AppLanguage) {
        statusItem?.menu?.item(withTag: MenuTag.settings)?.title = localized(.menuSettings, language: language)
        statusItem?.menu?.item(withTag: MenuTag.overlaysEnabled)?.title = localized(
            .menuEnableOverlays,
            language: language
        )
        statusItem?.menu?.item(withTag: MenuTag.dockClickEnabled)?.title = localized(
            .menuEnableDockClick,
            language: language
        )
        statusItem?.menu?.item(withTag: MenuTag.checkForUpdates)?.title = localized(
            .checkForUpdates,
            language: language
        )
        statusItem?.menu?.item(withTag: MenuTag.quit)?.title = localized(.menuQuit, language: language)
        settingsWindow?.title = localized(.settingsWindowTitle, language: language)
    }

    private func localized(_ key: AppString, language: AppLanguage? = nil) -> String {
        AppLocalization.string(key, language: language ?? preferences.language)
    }

    private func minimizeWindowFromDock(pid: pid_t) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier {
            guard let settingsWindow, settingsWindow.isVisible, !settingsWindow.isMiniaturized else { return false }
            settingsWindow.miniaturize(nil)
            return true
        }
        return tracker?.minimizeFocusedWindow(of: pid) ?? false
    }

}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        applyLanguage(preferences.language)
        menu.item(withTag: MenuTag.overlaysEnabled)?.state = preferences.enabled ? .on : .off
        menu.item(withTag: MenuTag.dockClickEnabled)?.state = preferences.dockClickMinimizesActiveWindow ? .on : .off
        menu.item(withTag: MenuTag.checkForUpdates)?.isEnabled = updateController.canCheckForUpdates
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        logger.notice("Settings window closed; returning to menu bar mode")
        NSApp.setActivationPolicy(.accessory)
    }
}
