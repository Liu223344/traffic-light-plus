import SwiftUI
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                header
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
                Text("更大、更顺手的窗口控制按钮")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("启用", isOn: $preferences.enabled)
                .toggleStyle(.switch)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("实时预览")
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
                size: size
            )
                .frame(width: size, height: size)
            PreviewControl(
                action: .minimize,
                behavior: preferences.minimizeBehavior,
                style: preferences.style,
                size: size
            )
                .frame(width: size, height: size)
            PreviewControl(
                action: .zoom,
                behavior: preferences.zoomBehavior,
                style: preferences.style,
                size: size
            )
                .frame(width: size, height: size)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("外观")
                    .font(.headline)
                Picker("外观", selection: $preferences.style) {
                    ForEach(ControlStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("按钮大小")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(preferences.size)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("恢复默认") { preferences.size = 28 }
                        .buttonStyle(.link)
                }
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Slider(value: $preferences.size, in: ControlLayout.sizeRange, step: 1)
                        .accessibilityLabel("按钮大小")
                        .accessibilityValue("\(Int(preferences.size)) pt")
                    Image(systemName: "circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            if preferences.style == .macOS {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("按钮间距")
                            .font(.headline)
                        Spacer()
                        Text(spacingDescription)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("恢复系统间距") { preferences.spacing = 0 }
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
                        .accessibilityLabel("按钮间距")
                        .accessibilityValue(spacingDescription)
                        Image(systemName: "arrow.left.and.right")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle("在全屏窗口中显示", isOn: $preferences.showInFullScreen)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("按钮功能")
                        .font(.headline)
                    Spacer()
                    Button("恢复默认") { preferences.resetButtonBehaviors() }
                        .buttonStyle(.link)
                }
                behaviorRow(
                    title: "红色按钮",
                    color: Color(red: 1.0, green: 0.37255, blue: 0.34118),
                    selection: $preferences.closeBehavior
                )
                behaviorRow(
                    title: "黄色按钮",
                    color: Color(red: 0.99608, green: 0.73725, blue: 0.18039),
                    selection: $preferences.minimizeBehavior
                )
                behaviorRow(
                    title: "绿色按钮",
                    color: Color(red: 0.15686, green: 0.78431, blue: 0.25098),
                    selection: $preferences.zoomBehavior
                )
            }
        }
    }

    private var spacingDescription: String {
        let spacing = Int(preferences.spacing)
        if spacing == 0 { return "系统" }
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
                    Text(behavior.title).tag(behavior)
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
                Text(accessibilityGranted ? "辅助功能权限已开启" : "需要辅助功能权限才能控制窗口")
                    .foregroundStyle(.secondary)
                Spacer()
                if !accessibilityGranted {
                    Button("打开辅助功能设置") { requestAccessibility() }
                }
            }
            if !accessibilityGranted {
                Text("若列表中没有本应用，请点击“+”并选择 Traffic Lights Plus.app。")
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
}

private struct PreviewControl: NSViewRepresentable {
    let action: WindowAction
    let behavior: ButtonBehavior
    let style: ControlStyle
    let size: CGFloat

    func makeNSView(context: Context) -> OverlayButtonView {
        OverlayButtonView(action: action)
    }

    func updateNSView(_ view: OverlayButtonView, context: Context) {
        view.style = style
        view.controlSize = size
        view.behavior = behavior
        view.isWindowActive = true
        view.needsDisplay = true
    }
}
