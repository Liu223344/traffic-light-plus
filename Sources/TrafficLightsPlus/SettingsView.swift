import SwiftUI
import ApplicationServices
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var updateController: UpdateController
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var isShowingAppSelectionError = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                header
                languageSelector
                menuBarIconToggle
                overlayToggle
                Divider()
                preview
                controls
                Divider()
                permissionStatus
            }
            .padding(24)
        }
        .frame(width: 480, height: 680)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
        .alert(localized(.cannotAddApplication), isPresented: $isShowingAppSelectionError) {
            Button(localized(.ok), role: .cancel) {}
        } message: {
            Text(localized(.missingBundleIdentifier))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Traffic Lights+")
                    .font(.title2.bold())
                Text(localized(.settingsSubtitle))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var languageSelector: some View {
        HStack(spacing: 12) {
            Text(localized(.languageLabel))
                .font(.headline)
            Spacer()
            Picker(localized(.languageLabel), selection: $preferences.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
        }
    }

    private var overlayToggle: some View {
        HStack {
            Text(localized(.overlayEnabled))
                .font(.headline)
            Spacer()
            Toggle("", isOn: $preferences.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(localized(.overlayEnabled))
        }
    }

    private var menuBarIconToggle: some View {
        HStack {
            Text(localized(.menuBarIconVisible))
                .font(.headline)
            Spacer()
            Toggle("", isOn: $preferences.menuBarIconVisible)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(localized(.menuBarIconVisibleHelp))
                .accessibilityLabel(localized(.menuBarIconVisible))
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized(.livePreview))
                .font(.headline)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 1)
                    }
                previewButtons
                    .padding(.leading, preferences.style == .macOS ? 12 : 0)
                    .padding(.top, preferences.style == .macOS ? 8 : 0)
            }
            .frame(height: max(64, CGFloat(preferences.size) + 16))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var previewButtons: some View {
        let size = CGFloat(preferences.size)
        let spacing: CGFloat = preferences.style == .macOS
            ? max(-size + 4, 8 + CGFloat(preferences.spacing))
            : 0
        return HStack(spacing: spacing) {
            PreviewControl(
                action: .close,
                behavior: preferences.closeBehavior,
                style: preferences.style,
                size: size,
                language: preferences.language
            )
                .frame(width: size, height: size)
            PreviewControl(
                action: .minimize,
                behavior: preferences.minimizeBehavior,
                style: preferences.style,
                size: size,
                language: preferences.language
            )
                .frame(width: size, height: size)
            PreviewControl(
                action: .zoom,
                behavior: preferences.zoomBehavior,
                style: preferences.style,
                size: size,
                language: preferences.language
            )
                .frame(width: size, height: size)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized(.appearance))
                    .font(.headline)
                Picker(localized(.appearance), selection: $preferences.style) {
                    ForEach(ControlStyle.allCases, id: \.self) { style in
                        Text(style.title(language: preferences.language)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(localized(.buttonSize))
                        .font(.headline)
                    Spacer()
                    Text("\(Int(preferences.size)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button(localized(.restoreDefault)) { preferences.size = ControlLayout.defaultSize }
                        .buttonStyle(.link)
                }
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Slider(value: $preferences.size, in: ControlLayout.sizeRange, step: 1)
                        .accessibilityLabel(localized(.buttonSize))
                        .accessibilityValue("\(Int(preferences.size)) pt")
                    Image(systemName: "circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            if preferences.style == .macOS {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(localized(.buttonSpacing))
                            .font(.headline)
                        Spacer()
                        Text(spacingDescription)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button(localized(.restoreSystemSpacing)) {
                            preferences.spacing = ControlLayout.defaultSpacingAdjustment
                        }
                            .buttonStyle(.link)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.left.and.right")
                            .foregroundStyle(.secondary)
                        Slider(
                            value: $preferences.spacing,
                            in: ControlLayout.spacingAdjustmentRange,
                            step: 1
                        )
                        .accessibilityLabel(localized(.buttonSpacing))
                        .accessibilityValue(spacingDescription)
                        Image(systemName: "arrow.left.and.right")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle(localized(.hiddenTrafficLights), isOn: $preferences.hiddenTrafficLightsEnabled)

            if preferences.hiddenTrafficLightsEnabled {
                Picker(localized(.revealMode), selection: $preferences.hiddenTrafficLightRevealMode) {
                    ForEach(HiddenTrafficLightRevealMode.allCases, id: \.self) { mode in
                        Text(mode.title(language: preferences.language)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle(localized(.fullScreenInDevelopment), isOn: .constant(false))
                .disabled(true)

            HStack {
                Text(localized(.dockClickMinimize))
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $preferences.dockClickMinimizesActiveWindow)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(localized(.dockClickMinimizeHelp))
                    .accessibilityLabel(localized(.dockClickMinimize))
            }

            quitOnCloseApplications

            softwareUpdates

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(localized(.buttonActions))
                        .font(.headline)
                    Spacer()
                    Button(localized(.restoreDefault)) { preferences.resetButtonBehaviors() }
                        .buttonStyle(.link)
                }
                behaviorRow(
                    title: localized(.redButton),
                    color: Color(red: 1.0, green: 0.37255, blue: 0.34118),
                    selection: $preferences.closeBehavior
                )
                behaviorRow(
                    title: localized(.yellowButton),
                    color: Color(red: 0.99608, green: 0.73725, blue: 0.18039),
                    selection: $preferences.minimizeBehavior
                )
                behaviorRow(
                    title: localized(.greenButton),
                    color: Color(red: 0.15686, green: 0.78431, blue: 0.25098),
                    selection: $preferences.zoomBehavior
                )
            }

        }
    }

    private var softwareUpdates: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized(.softwareUpdates))
                .font(.headline)
            Toggle(
                localized(.automaticallyCheckForUpdates),
                isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: updateController.setAutomaticallyChecksForUpdates
                )
            )
            .disabled(!updateController.updaterAvailable)
            Toggle(
                localized(.automaticallyDownloadUpdates),
                isOn: Binding(
                    get: { updateController.automaticallyDownloadsUpdates },
                    set: updateController.setAutomaticallyDownloadsUpdates
                )
            )
            .disabled(!updateController.automaticDownloadsControlEnabled)
            Button(action: updateController.checkForUpdates) {
                Label(localized(.checkForUpdates), systemImage: "arrow.clockwise")
            }
            .disabled(!updateController.canCheckForUpdates)
            if !updateController.updaterAvailable {
                Text(localized(.updatesUnavailable))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quitOnCloseApplications: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localized(.quitOnCloseEnabled))
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $preferences.quitOnCloseEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(localized(.quitOnCloseHelp))
                    .accessibilityLabel(localized(.quitOnCloseEnabled))
            }

            if preferences.quitOnCloseEnabled {
                HStack {
                    Text(localized(.quitOnCloseApplications))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(action: chooseQuitOnCloseApplication) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(localized(.addApplication))
                    .accessibilityLabel(localized(.addApplicationAccessibility))
                }

                if preferences.quitOnCloseApplications.isEmpty {
                    Text(localized(.noApplicationsAdded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preferences.quitOnCloseApplications) { application in
                        HStack(spacing: 10) {
                            Image(nsImage: icon(for: application))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(application.displayName)
                                    .lineLimit(1)
                                Text(application.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                preferences.removeQuitOnCloseApplication(
                                    bundleIdentifier: application.bundleIdentifier
                                )
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(localized(.removeApplication))
                            .accessibilityLabel(localized(
                                .removeApplicationAccessibility,
                                arguments: application.displayName
                            ))
                        }
                    }
                }
            }
        }
    }

    private var spacingDescription: String {
        let spacing = Int(preferences.spacing)
        if spacing == 0 { return localized(.systemSpacing) }
        return spacing > 0 ? "+\(spacing) pt" : "\(spacing) pt"
    }

    private func behaviorRow(
        title: String,
        color: Color,
        selection: Binding<ButtonBehavior>
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(ButtonBehavior.allCases) { behavior in
                    Text(behavior.title(language: preferences.language)).tag(behavior)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private var permissionStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accessibilityGranted ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(localized(accessibilityGranted ? .accessibilityGranted : .accessibilityRequired))
                    .foregroundStyle(.secondary)
                Spacer()
                if !accessibilityGranted {
                    Button(localized(.openAccessibilitySettings)) { requestAccessibility() }
                }
            }
            if !accessibilityGranted {
                Text(localized(.accessibilityInstructions))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func chooseQuitOnCloseApplication() {
        let panel = NSOpenPanel()
        panel.title = localized(.chooseQuitOnCloseApplication)
        panel.prompt = localized(.addPickerPrompt)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }

        var encounteredInvalidApplication = false
        for url in panel.urls {
            guard let bundle = Bundle(url: url),
                  let bundleIdentifier = bundle.bundleIdentifier,
                  !bundleIdentifier.isEmpty else {
                encounteredInvalidApplication = true
                continue
            }

            let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            _ = preferences.addQuitOnCloseApplication(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName
            )
        }

        if encounteredInvalidApplication {
            isShowingAppSelectionError = true
        }
    }

    private func icon(for application: QuitOnCloseApplication) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: application.bundleIdentifier
        ) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: application.displayName)
            ?? NSImage(size: NSSize(width: 28, height: 28))
    }

    private func localized(_ key: AppString, arguments: CVarArg...) -> String {
        AppLocalization.string(key, language: preferences.language, arguments: arguments)
    }
}

private struct PreviewControl: NSViewRepresentable {
    let action: WindowAction
    let behavior: ButtonBehavior
    let style: ControlStyle
    let size: CGFloat
    let language: AppLanguage

    func makeNSView(context: Context) -> OverlayButtonView {
        OverlayButtonView(action: action)
    }

    func updateNSView(_ view: OverlayButtonView, context: Context) {
        view.style = style
        view.controlSize = size
        view.language = language
        view.behavior = behavior
        view.isWindowActive = true
        view.needsDisplay = true
    }
}
