# Traffic Lights+

[![CI](https://github.com/Liu223344/supper-traffic/actions/workflows/ci.yml/badge.svg)](https://github.com/Liu223344/supper-traffic/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Liu223344/supper-traffic)](https://github.com/Liu223344/supper-traffic/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Traffic Lights+ 是一个原生 macOS 菜单栏工具，可以把其他应用窗口左上角的关闭、最小化和缩放按钮放大，让它们更容易看清和点击。它不修改系统文件、不注入其他进程，也不需要关闭 SIP。

## 下载

从 [Releases](https://github.com/Liu223344/supper-traffic/releases/latest) 下载最新版：

- `Traffic-Lights-Plus-1.1.0.dmg`：推荐，打开后拖入“应用程序”。
- `Traffic-Lights-Plus-1.1.0.zip`：解压后直接获得应用。
- `SHA256SUMS.txt`：用于校验下载文件。

当前公开构建使用 ad-hoc 签名，尚未经过 Apple 公证。macOS 首次阻止启动时，请在 Finder 中右键应用并选择“打开”。

## 功能

- 红绿灯尺寸可在 `18-48 pt` 范围内调整。
- 圆形按钮支持自定义间距，也可切换为左上角贴边方块。
- “隐藏式红绿灯”支持靠近时放大“整组”或仅放大“单个”最近按钮。
- 窗口拖动期间以 120 Hz 同步位置，并实时处理按钮级遮挡。
- 最小化前快速缩小并隐藏覆盖按钮，避免覆盖层留在系统动画中。
- 可分别把红、黄、绿按钮设置为关闭窗口、退出应用、最小化、缩放、隐藏应用或无操作。
- 支持所有可见窗口、多显示器和可选的全屏窗口显示。
- 设置即时生效并通过 `UserDefaults` 保存在本机。
- 无网络请求、无分析统计、无广告和账号系统。

## 系统要求

- macOS 13 Ventura 或更高版本。
- Apple Silicon Mac（当前发布脚本生成 arm64 应用）。
- 目标应用需要提供标准 macOS 辅助功能窗口按钮。

## 安装与权限

1. 下载并打开 DMG，将 `Traffic Lights Plus.app` 拖入“应用程序”。
2. 启动 Traffic Lights+，从菜单栏图标打开“设置”。
3. 点击“打开辅助功能设置”，在“隐私与安全性 > 辅助功能”中允许 Traffic Lights+。
4. 如果应用已在权限列表中但仍未生效，请关闭并重新启动应用。

辅助功能权限仅用于发现标准窗口按钮、读取窗口位置并执行用户配置的窗口操作。完整说明见 [PRIVACY.md](PRIVACY.md)。

## 使用

Traffic Lights+ 启动后常驻菜单栏。设置页可以调整：

- 总开关、尺寸、外观和圆形按钮间距；
- 隐藏式红绿灯及“整组/单个”放大方式；
- 红、黄、绿三个按钮各自的操作；
- 是否在全屏窗口上显示覆盖按钮。

隐藏模式开启时，将鼠标移到窗口左上角红绿灯区域即可显示放大按钮。单个模式会选择距离鼠标最近的可见按钮，按钮被其他窗口遮挡时不会显示或参与选择。

## 已知限制

- 使用自行绘制标题栏、未暴露标准 AX 按钮的应用可能无法使用。
- 覆盖按钮属于独立的非激活面板，无法真正加入其他应用的窗口合成树。
- 当前公开构建未公证，因此首次启动可能出现 Gatekeeper 提示。
- Intel Mac 尚未提供预编译版本；可自行调整构建目标尝试编译。

## 从源码构建

需要 Xcode Command Line Tools：

```sh
git clone https://github.com/Liu223344/supper-traffic.git
cd supper-traffic
swift test
./scripts/build-app.sh
open "build/Traffic Lights Plus.app"
```

生成发布文件：

```sh
./scripts/package-dmg.sh
./scripts/package-zip.sh
```

默认使用 ad-hoc 签名。持有 Developer ID 的发布者可以设置：

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-dmg.sh
```

## 实现方式

macOS 没有公开 API 可以跨进程修改原生红绿灯尺寸。本项目使用辅助功能 API 获取标准窗口按钮和执行操作，使用 WindowServer 窗口信息匹配位置与遮挡，再通过三个独立的非激活透明面板绘制放大按钮。所有处理均在本机完成。

## 参与贡献

提交改动前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，并至少运行：

```sh
swift test
./scripts/build-app.sh
codesign --verify --deep --strict "build/Traffic Lights Plus.app"
```

安全问题请按 [SECURITY.md](SECURITY.md) 中的方式报告，不要直接公开未修复漏洞。

## 许可证

Traffic Lights+ 采用 [MIT License](LICENSE)。
