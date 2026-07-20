# Privacy Policy

Traffic Lights+ 不收集、上传、出售或共享个人数据。应用不包含分析统计、广告、账号系统或第三方遥测 SDK。启用软件更新时，Sparkle 会通过 HTTPS 读取与当前芯片架构对应的 appcast，并从 GitHub Release 下载用户选择安装的更新包。

## 读取的数据

为了定位并操作其他应用的标准窗口按钮，Traffic Lights+ 会在运行期间读取：

- 正在运行的普通 macOS 应用和它们可访问的窗口；
- 窗口位置、尺寸、层级、最小化状态和标准关闭、最小化、缩放按钮；
- 窗口标题，仅用于在辅助功能窗口与 WindowServer 窗口记录之间进行本地匹配；
- 当前鼠标位置，用于判断隐藏式红绿灯的显示目标。
- 鼠标是否点击 Dock 应用图标及该应用的 Bundle ID，用于判断是否执行再次点击最小化。

这些窗口和鼠标信息只在内存中用于界面定位、遮挡判断和执行用户操作，不会写入项目文件或发送到任何服务器。

## 本地存储

设置通过 macOS `UserDefaults` 保存在当前用户的标准偏好数据库中，包括开关、按钮尺寸、间距、外观、按钮操作和 Sparkle 更新偏好。应用不存储窗口标题、Dock 点击记录、鼠标轨迹或操作历史。

## 软件更新网络访问

- arm64 构建读取 `https://liu223344.github.io/traffic-light-plus/appcast-arm64.xml`。
- x86_64 构建读取 `https://liu223344.github.io/traffic-light-plus/appcast-x86_64.xml`。
- 更新归档从本项目的 GitHub Releases 下载，并使用内置 EdDSA 公钥验证。

更新请求会向 GitHub 及其 Pages/CDN 基础设施暴露常规网络元数据，例如 IP 地址、请求时间和 User-Agent。Traffic Lights+ 不在 appcast URL 中附加窗口、鼠标、应用使用情况或其他个人数据。

## 日志

诊断日志只记录应用生命周期、窗口和覆盖层数量等技术状态，不记录应用名称、窗口标题或文件内容。

## 辅助功能权限

macOS 辅助功能权限仅用于：

- 发现标准窗口和红绿灯按钮；
- 读取窗口及按钮的位置和状态；
- 执行用户触发的关闭、最小化和缩放操作。
- 识别 Dock 应用图标的再次点击并最小化当前窗口。

用户可以随时在“系统设置 > 隐私与安全性 > 辅助功能”中撤销权限。撤销后 Traffic Lights+ 将停止显示和操作覆盖按钮。

## Network and data collection

Traffic Lights+ does not collect or transmit personal data and contains no analytics, advertising, account system, or telemetry SDK. When software updates are enabled, Sparkle fetches the architecture-specific appcast over HTTPS and downloads update archives from this project's GitHub Releases. These requests expose ordinary network metadata to GitHub and its Pages/CDN infrastructure, but do not include window, pointer, or application-usage data.
