# Contributing

感谢参与 Traffic Lights+。

## 开发流程

1. Fork 仓库并从 `main` 创建功能分支。
2. 保持改动聚焦，避免提交 `.build/`、`build/` 或个人系统文件。
3. 运行 `swift test`。
4. 运行 `./scripts/build-app.sh` 并验证应用签名。
5. 提交 Pull Request，说明行为变化和验证方式。

涉及窗口定位、按钮行为或多显示器逻辑的修改，请补充对应测试，并在真实 macOS 窗口上验证。
