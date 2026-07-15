# Traffic Lights+

[![CI](https://github.com/Liu223344/supper-traffic/actions/workflows/ci.yml/badge.svg)](https://github.com/Liu223344/supper-traffic/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Traffic Lights+ 是一个轻量的原生 macOS 菜单栏工具，为当前窗口提供更大、更容易点击的红绿灯按钮。它不修改系统文件，也不需要关闭 SIP。

## 功能

- 在 `18-48 pt` 之间自由调整红绿灯大小
- 可在系统圆心布局基础上单独调节三个圆形按钮的间距
- 实时预览，修改后立即应用到所有可见窗口
- 经典圆形与左上角无间隙贴边方块两种外观
- 三个独立命中区域，圆形按钮之间仍可正常拖动标题栏
- 激活窗口使用原版红黄绿，后台窗口使用原版非激活灰色并在悬停时恢复彩色
- 可分别设置红、黄、绿按钮为关闭窗口、退出应用、最小化、缩放、隐藏应用或无操作
- 最小化开始时提前隐藏覆盖层，从 Dock 恢复后再重新出现
- 不因其他窗口遮挡而把大号按钮切回原生小尺寸
- 跟随所有可见窗口与多显示器，可选择是否在全屏显示
- 直接调用窗口原生关闭、最小化和缩放操作
- 无网络请求、无分析统计、无用户数据收集

## 安装

解压 `Traffic-Lights-Plus-1.0.0.zip`，将 `Traffic Lights Plus.app` 拖入“应用程序”，再从“应用程序”文件夹启动。也可以打开 DMG 后完成同样操作。首次运行会请求辅助功能权限。

如果应用没有自动出现在列表中：

1. 打开 Traffic Lights+ 菜单栏图标中的“设置”。
2. 点击“打开辅助功能设置”。
3. 点击系统设置页面的 `+`，选择“应用程序”中的 Traffic Lights Plus。
4. 开启权限后重新启动应用。

未经 Apple Developer ID 公证的本地构建可能需要右键应用并选择“打开”。正式公开发布时应使用 Developer ID 签名并提交 Apple 公证。

## 本地构建

要求 macOS 13 或更高版本，以及 Xcode Command Line Tools。

```sh
./scripts/build-app.sh
open "build/Traffic Lights Plus.app"
```

生成 DMG：

```sh
./scripts/package-dmg.sh
```

生成 ZIP：

```sh
./scripts/package-zip.sh
```

默认使用 ad-hoc 签名。发布者可提供 Developer ID：

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-dmg.sh
```

运行测试：

```sh
swift test
```

## 兼容性

- macOS 13 Ventura 或更高版本
- Apple Silicon（M 系列芯片）
- 使用标准 macOS 辅助功能窗口按钮的应用
- 部分自行绘制标题栏的应用可能无法提供可操作的标准按钮，此时对应覆盖按钮不会显示

macOS 没有公开 API 可以全局修改原生红绿灯尺寸，因此本工具使用三个独立、非激活的透明窗口覆盖标准按钮。窗口移动期间通过 WindowServer 的窗口帧和窗口 ID 做高频同步，辅助功能 API 只用于发现标准按钮和执行原生操作。这是可逆的用户空间实现，不注入其他进程，也不修改系统文件。

为了让覆盖层在其他应用窗口之间保持自然前后关系，并降低拖动同步延迟，Apple Silicon 构建会在运行时尝试使用未公开的 SkyLight 窗口排序与整组移动接口；接口不可用时会自动回退到 AppKit。由于这不是 Apple 的公开兼容性承诺，macOS 大版本更新后可能需要适配，也不适合提交 Mac App Store。

AppKit 可以通过 `standardWindowButton(_:)` 修改当前进程自己拥有的窗口按钮，也可以用 `addChildWindow(_:ordered:)` 让同一进程持有的子窗口随父窗口同步移动。但全局工具通过辅助功能只能获得其他应用的 `AXUIElement`，无法取得对应的 `NSWindow` 对象。因此跨应用实现若不使用私有 WindowServer API、不关闭 SIP、不向目标应用注入代码，就无法把覆盖层真正挂进目标窗口的合成树。

## 隐私与许可

隐私说明见 [PRIVACY.md](PRIVACY.md)。项目采用 [MIT License](LICENSE)。

问题反馈与贡献请前往 [Liu223344/supper-traffic](https://github.com/Liu223344/supper-traffic)。
