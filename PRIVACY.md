# Privacy Policy

Traffic Lights+ 在本机运行，不收集、上传、出售或共享个人数据。应用不包含网络请求、分析统计、广告、账号系统或第三方遥测 SDK。

## 读取的数据

为了定位并操作其他应用的标准窗口按钮，Traffic Lights+ 会在运行期间读取：

- 正在运行的普通 macOS 应用和它们可访问的窗口；
- 窗口位置、尺寸、层级、最小化状态和标准关闭、最小化、缩放按钮；
- 窗口标题，仅用于在辅助功能窗口与 WindowServer 窗口记录之间进行本地匹配；
- 当前鼠标位置，用于判断隐藏式红绿灯的显示目标。

这些信息只在内存中用于界面定位、遮挡判断和执行用户操作，不会写入项目文件或发送到任何服务器。

## 本地存储

设置通过 macOS `UserDefaults` 保存在当前用户的标准偏好数据库中，包括开关、按钮尺寸、间距、外观和按钮操作。应用不存储窗口标题、应用列表、鼠标轨迹或操作历史。

## 日志

诊断日志只记录应用生命周期、窗口和覆盖层数量等技术状态，不记录应用名称、窗口标题或文件内容。

## 辅助功能权限

macOS 辅助功能权限仅用于：

- 发现标准窗口和红绿灯按钮；
- 读取窗口及按钮的位置和状态；
- 执行用户触发的关闭、最小化和缩放操作。

用户可以随时在“系统设置 > 隐私与安全性 > 辅助功能”中撤销权限。撤销后 Traffic Lights+ 将停止显示和操作覆盖按钮。

## Network and data collection

Traffic Lights+ performs all processing locally. It has no analytics, advertising, account system, telemetry SDK, or application network code, and does not transmit personal data.
