# NoShiPingHao

[![CI](https://github.com/bobbyhuang-dev/NoShiPingHao/actions/workflows/ci.yml/badge.svg)](https://github.com/bobbyhuang-dev/NoShiPingHao/actions/workflows/ci.yml)

A macOS app built with SwiftUI.

## Requirements

- macOS 15.0 or later
- Xcode 26 or later (Swift 6)

## Getting started

```sh
open NoShiPingHao.xcodeproj
```

Before you ship, set your Development Team and replace the `com.example` bundle identifiers under **Signing & Capabilities**.

## Project layout

| Path | Contents |
| --- | --- |
| `NoShiPingHao/` | App sources, asset catalog, string catalog |
| `NoShiPingHaoTests/` | Unit tests (Swift Testing) |
| `NoShiPingHaoUITests/` | UI tests (XCTest) |

The source folders are synchronized with Xcode. Files you add on disk show up in the project without editing `project.pbxproj`.

## Configuration

- **Language:** Swift 6 language mode with complete concurrency checking. The app target isolates to `MainActor` by default and enables approachable concurrency.
- **Security:** App Sandbox and Hardened Runtime are on. The app can read files the user selects. Change capabilities under **Signing & Capabilities**.
- **Info.plist:** Xcode generates it from `INFOPLIST_KEY_*` build settings.
- **Localization:** `Localizable.xcstrings` collects strings from the code at build time.

## Commands

```sh
# Build and run all tests
xcodebuild test -project NoShiPingHao.xcodeproj -scheme NoShiPingHao -destination 'platform=macOS'

# Lint (swift-format ships with Xcode)
xcrun swift-format lint --strict --recursive NoShiPingHao NoShiPingHaoTests NoShiPingHaoUITests

# Format in place
xcrun swift-format format --in-place --recursive NoShiPingHao NoShiPingHaoTests NoShiPingHaoUITests
```

CI runs lint and tests on every push to `main` and on every pull request (`.github/workflows/ci.yml`).

## License

[MIT](LICENSE)
