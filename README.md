# 去除视频号（NoShiPinHao）

[English](README.en.md)

[![CI](https://github.com/bobbyhuang-dev/NoShiPinHao/actions/workflows/ci.yml/badge.svg)](https://github.com/bobbyhuang-dev/NoShiPinHao/actions/workflows/ci.yml)

一个 macOS 小工具，用来去除微信 Mac 版中的视频号和其他让人分心的功能。

手机版微信可以关闭视频号，但 Mac 版没有这个选项。这个工具补上了这一点，让你用微信时更专注。

## 系统要求

- macOS 15.0 或更高版本
- Xcode 26 或更高版本（Swift 6）

## 快速开始

```sh
open NoShiPinHao.xcodeproj
```

发布前，请在 **Signing & Capabilities** 中设置你的 Development Team，并替换 `com.example` 开头的 Bundle Identifier。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `NoShiPinHao/` | 应用源码、资源目录、字符串目录 |
| `NoShiPinHaoTests/` | 单元测试（Swift Testing） |
| `NoShiPinHaoUITests/` | UI 测试（XCTest） |

源码文件夹与 Xcode 同步。在磁盘上新增的文件会自动出现在项目中，无需修改 `project.pbxproj`。

## 配置

- **语言：** Swift 6 语言模式，开启完整并发检查。应用 target 默认隔离到 `MainActor`，并启用 approachable concurrency。
- **安全：** 已开启 App Sandbox 和 Hardened Runtime。应用可以读取用户选择的文件。可在 **Signing & Capabilities** 中修改权限。
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
