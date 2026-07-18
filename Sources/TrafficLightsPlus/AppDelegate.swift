import AppKit
import SwiftUI
import ApplicationServices
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum MenuTag { static let enabled = 100 }
    private let logger = Logger(subsystem: "app.trafficlightsplus.mac", category: "lifecycle")
    private let preferences = Preferences()
    private var tracker: WindowTracker?
    private var dockClickController: DockClickController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("Application finished launching")
        NSApp.setActivationPolicy(.accessory)
        tracker = WindowTracker(preferences: preferences)
        dockClickController = DockClickController(
            preferences: preferences,
            minimizeHandler: { [weak self] pid in
                self?.minimizeWindowFromDock(pid: pid) ?? false
            },
            restoreHandler: { [weak self] pid in
                self?.restoreWindowFromDock(pid: pid) ?? false
            }
        )
        configureStatusItem()
        DispatchQueue.main.async { [weak self] in self?.showSettings() }

        if !AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Traffic Lights+")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(NSMenuItem.separator())
        let toggle = NSMenuItem(title: "启用", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggle.tag = MenuTag.enabled
        toggle.target = self
        toggle.state = preferences.enabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 Traffic Lights+", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc func showSettings() {
        logger.notice("Showing settings window")
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(preferences: preferences))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 480, height: 680))
            window.title = "Traffic Lights+ 设置"
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

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        preferences.enabled.toggle()
        sender.state = preferences.enabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func minimizeWindowFromDock(pid: pid_t) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier {
            guard let settingsWindow, settingsWindow.isVisible, !settingsWindow.isMiniaturized else { return false }
            settingsWindow.miniaturize(nil)
            return true
        }
        return tracker?.minimizeFocusedWindow(of: pid) ?? false
    }

    private func restoreWindowFromDock(pid: pid_t) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier {
            guard let settingsWindow, settingsWindow.isMiniaturized else { return false }
            settingsWindow.deminiaturize(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }
        return tracker?.restoreMinimizedWindow(of: pid) ?? false
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: MenuTag.enabled)?.state = preferences.enabled ? .on : .off
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        logger.notice("Settings window closed; returning to menu bar mode")
        NSApp.setActivationPolicy(.accessory)
    }
}
