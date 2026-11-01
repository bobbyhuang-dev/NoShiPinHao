# 去除视频号（NoShiPinHao）

[English](README.en.md)

[![CI](https://github.com/bobbyhuang-dev/NoShiPinHao/actions/workflows/ci.yml/badge.svg)](https://github.com/bobbyhuang-dev/NoShiPinHao/actions/workflows/ci.yml)

一个 macOS 小工具，用来去除微信 Mac 版中的视频号和其他让人分心的功能。

手机版微信可以关闭视频号，但 Mac 版没有这个选项。这个工具补上了这一点，让你用微信时更专注：无论从“发现”进入视频号，还是打开朋友分享的视频号视频，都会被拦截。

## 工作原理

微信 4 是 Qt 应用，几乎不向辅助功能暴露任何信息，所以本工具观察微信画出的内容：

- **分享的视频** 会在微信内置的浏览器窗口中打开。这个窗口的辅助功能标题总是占位文字（`WeChat (Window)`），所以本工具只截取窗口的标题栏，用 Vision 在本机识别标签页文字，当它显示“视频号”或“Channels”时关闭窗口。同一窗口中的文章和其他网页不受影响。
- **发现 → 视频号** 显示在主窗口中。当“发现”下的视频号一行被选中、且微信在前台时，本工具会点击“发现”中的另一项（通常是朋友圈），然后把鼠标指针移回原处。“发现”本身仍可正常使用。

本工具从不修改微信。它需要 **辅助功能** 权限（用于关闭窗口和点击）和 **屏幕录制** 权限（用于查看微信窗口）。已在 Mac 版微信 4.1.5 上测试。

## 系统要求

- macOS 15.0 或更高版本
- Xcode 26 或更高版本（Swift 6）

## 快速开始

```sh
open NoShiPinHao.xcodeproj
```

如需使用自己的团队签名（这样重新构建后 macOS 隐私授权不会丢失）：

```sh
cp Config/Local.example.xcconfig Config/Local.xcconfig
# 然后在 Config/Local.xcconfig 中设置 DEVELOPMENT_TEAM 和 BUNDLE_ID_PREFIX
```

`Config/Local.xcconfig` 已被 git 忽略。没有这个文件时，应用以 ad-hoc 签名构建，Bundle Identifier 为 `com.example.NoShiPinHao`，CI 也是这样构建的。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `NoShiPinHao/` | 应用源码、资源目录、字符串目录 |
| `NoShiPinHaoTests/` | 单元测试（Swift Testing） |
| `NoShiPinHaoUITests/` | UI 测试（XCTest） |

源码文件夹与 Xcode 同步。在磁盘上新增的文件会自动出现在项目中，无需修改 `project.pbxproj`。

## 配置

- **语言：** Swift 6 语言模式，开启完整并发检查。应用 target 默认隔离到 `MainActor`，并启用 approachable concurrency。
- **安全：** 已开启 Hardened Runtime。App Sandbox 已关闭，因为沙盒中的应用无法通过辅助功能控制其他应用。
- **签名：** `Config/Signing.xcconfig` 保存签名默认值，并在 `Config/Local.xcconfig` 存在时包含它。macOS 将辅助功能和屏幕录制授权与代码签名绑定，所以 ad-hoc 构建在重新构建后可能需要重新授权；使用团队签名则不需要。
- **Info.plist：** 由 Xcode 根据 `INFOPLIST_KEY_*` 构建设置自动生成。
- **本地化：** 开发语言为简体中文（`zh-Hans`）。`Localizable.xcstrings` 会在构建时从代码中收集字符串。

## 常用命令

```sh
# 构建并运行全部测试
xcodebuild test -project NoShiPinHao.xcodeproj -scheme NoShiPinHao -destination 'platform=macOS'

# 代码检查（swift-format 随 Xcode 提供）
xcrun swift-format lint --strict --recursive NoShiPinHao NoShiPinHaoTests NoShiPinHaoUITests

# 原地格式化
xcrun swift-format format --in-place --recursive NoShiPinHao NoShiPinHaoTests NoShiPinHaoUITests
```

每次推送到 `main` 以及每个 Pull Request 都会在 CI 中运行代码检查和测试（`.github/workflows/ci.yml`）。

## 参与贡献

请阅读 [贡献指南](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE)
