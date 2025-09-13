# TypeSwitch 🔄

<div align="center">

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013.0+-blue.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Homebrew](https://img.shields.io/badge/homebrew-available-brightgreen.svg)](https://github.com/ygsgdbd/homebrew-tap)
[![Release](https://img.shields.io/github/v/release/ygsgdbd/TypeSwitch?include_prereleases)](https://github.com/ygsgdbd/TypeSwitch/releases)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/ygsgdbd/TypeSwitch/pulls)

[🇨🇳 中文文档](README.zh-CN.md) | [📦 Installation](#-installation) | [📖 Usage](#-usage)

</div>

TypeSwitch is a modern macOS menu bar application built with SwiftUI for automatically switching input methods across different applications. It runs quietly in the background and provides an elegant menu bar interface for managing input method preferences per application.

✨ **Featuring macOS 26 Liquid Glass Design** - Experience the beautiful translucent interface with cutting-edge macOS 26 liquid glass effects, creating an elegant and modern user experience that seamlessly integrates with your system.

## ✨ Screenshots

<div align="center">
  <img src="Screenshots/main-20250913-220809.png" width="400" alt="Main Interface">
  <p><em>Menu Bar Interface - Set default input method for different applications</em></p>
</div>


## 🎯 Features

- 🔄 **Auto Switch**: Automatically switch to preset input methods when changing applications
- 📱 **Menu Bar Interface**: Clean and intuitive menu bar interface for easy access
- 🎯 **Per-App Settings**: Set independent input method preferences for each application
- 🚀 **Auto Start**: Support automatic startup at login
- 📋 **Running Apps**: View and configure currently running applications
- ⚙️ **Installed Apps**: Manage input method settings for all installed applications
- ⌨️ **Keyboard Shortcuts**:
  - `⌘ + Q` - Quit application
- 🔗 **Quick Links**: Direct access to GitHub repository and latest releases

## 🔧 System Requirements

- 🖥 macOS 13.0 or later (compatible up to macOS 26)
- 🔐 Accessibility permission for monitoring application switches
- ⌨️ Input method switching permission

## 📦 Installation

### 🍺 Option 1: Homebrew

```bash
brew install ygsgdbd/tap/typeswitch --cask
```

### 💾 Option 2: Manual Installation

1. Download the latest version from [Releases](https://github.com/ygsgdbd/TypeSwitch/releases)
2. Drag the application to Applications folder
3. Grant necessary system permissions on first launch

## 📖 Usage

1. After launching, the app icon (⌨️) appears in the menu bar
2. Click the menu bar icon to open the dropdown menu
3. The menu shows two sections:
   - **Running Apps**: Currently running applications
   - **Configured Apps**: Applications with input method settings
4. Click on any application to set its input method:
   - Select "Default" to use system default input method
   - Select any installed input method to set as default for that app
5. The input method will automatically switch when you switch to that application
6. Use the settings section to enable auto-launch at login

## 🔒 Security

TypeSwitch takes user privacy and security seriously:

- 🏠 All data is stored locally, nothing is uploaded to the network
- 🚫 No user information or usage data is collected
- 📖 Source code is fully open source and welcome for review
- 🛡️ Uses Swift's built-in security features
- 🔐 Permission usage:
  - Accessibility: Only used for detecting application switches
  - Input method switching: Only used for switching input methods
  - Auto-start: Only used for launching at startup

## Dependencies

This project uses the following open source libraries:

- [Defaults](https://github.com/sindresorhus/Defaults) (7.3.1) - For persistent settings storage
- [SwiftUIX](https://github.com/SwiftUIX/SwiftUIX) (0.2.3) - Provides additional SwiftUI components
- [SwifterSwift](https://github.com/SwifterSwift/SwifterSwift) (8.0.0) - Swift native extensions

Build tools:
- [Tuist](https://github.com/tuist/tuist) - For project generation and management

## Development

### Requirements

- Xcode 15.0+
- Swift 5.9+
- macOS 13.0+ (compatible up to macOS 26)
- [Tuist](https://github.com/tuist/tuist)

### Build Steps

1. Install [Tuist](https://github.com/tuist/tuist#install-▶️)

2. Clone repository
```bash
git clone https://github.com/ygsgdbd/TypeSwitch.git
cd TypeSwitch
```

3. Generate Xcode project
```bash
tuist generate
```

4. Open and build
```bash
open TypeSwitch.xcworkspace
```

### Automated Build and Release

This project uses GitHub Actions for automated building and releasing:

1. Push a new version tag to trigger automatic build:
```bash
git tag v1.0.0
git push origin v1.0.0
```

2. GitHub Actions will automatically:
   - Build the application
   - Create DMG package
   - Release new version
   - Generate changelog

3. Build artifacts can be downloaded from [Releases](https://github.com/ygsgdbd/TypeSwitch/releases)

### Project Structure

```
TypeSwitch/
├── Project.swift                    # Tuist project configuration
├── Tuist/                          # Tuist configuration files
│   └── Signing/
│       └── TypeSwitch.entitlements
├── TypeSwitch/                     # Main source code
│   ├── Sources/
│   │   ├── App/                    # App entry point
│   │   │   └── TypeSwitchApp.swift
│   │   ├── Core/                   # Core models and extensions
│   │   │   ├── Models/
│   │   │   │   ├── AppInfo.swift
│   │   │   │   ├── InputMethod.swift
│   │   │   │   └── InputSourceProperties.swift
│   │   │   └── Extensions/
│   │   │       └── Defaults+Extensions.swift
│   │   ├── Services/               # Business logic services
│   │   │   ├── AppManagement/
│   │   │   │   ├── AppInfoService.swift
│   │   │   │   └── AppListService.swift
│   │   │   ├── InputMethod/
│   │   │   │   ├── InputMethodManager.swift
│   │   │   │   └── InputMethodService.swift
│   │   │   └── System/
│   │   │       └── LaunchAtLoginService.swift
│   │   └── UI/                     # User interface
│   │       └── Views/
│   │           └── MenuBar/        # Menu bar interface
│   │               ├── MenuBarView.swift
│   │               ├── RunningAppsView.swift
│   │               ├── ConfiguredAppsView.swift
│   │               ├── AppRowView.swift
│   │               ├── SettingsView.swift
│   │               └── AppInfoView.swift
│   └── Resources/                  # App resources
│       ├── Assets.xcassets/        # App icons and images
│       └── *.lproj/               # Localization files
└── Screenshots/                   # App screenshots
```

## Contributing

Pull requests and issues are welcome. Before submitting a PR, please ensure:

1. Code follows project style
2. Necessary tests are added
3. Documentation is updated

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) file for details.

## Acknowledgments 🙏

This project was inspired by and received help from:
- [SwitchKey](https://github.com/itsuhane/SwitchKey) - An excellent input method switcher that provided valuable reference
- Swift and SwiftUI community
- All contributors and users who provided feedback
