# TypeSwitch 🔄

<div align="center">

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013.0+-blue.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Build Status](https://github.com/ygsgdbd/TypeSwitch/actions/workflows/build.yml/badge.svg)](https://github.com/ygsgdbd/TypeSwitch/actions)
[![Homebrew](https://img.shields.io/badge/homebrew-available-brightgreen.svg)](https://github.com/ygsgdbd/homebrew-tap)
[![Release](https://img.shields.io/github/v/release/ygsgdbd/TypeSwitch?include_prereleases)](https://github.com/ygsgdbd/TypeSwitch/releases)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/ygsgdbd/TypeSwitch/pulls)

[🇨🇳 中文说明](#中文说明) | [📦 安装方法](#安装方法) | [📖 使用说明](#使用说明) | [❓ 常见问题](#常见问题)

</div>

TypeSwitch is a macOS application that automatically switches input methods for different applications. It remembers input method preferences for each application and automatically switches to the corresponding input method when switching applications.

## ✨ Screenshots

<div align="center">
  <img src="Screenshots/main.png" width="600" alt="Main Interface">
  <p><em>Main Interface - Set default input method for different applications</em></p>
</div>

<div align="center">
  <img src="Screenshots/search.png" width="600" alt="Search Feature">
  <p><em>Search Feature - Quickly find and configure applications</em></p>
</div>

## 🎯 Features

- 🔄 **Auto Switch**: Automatically switch to preset input methods when changing applications
- 🔍 **Quick Search**: Support fuzzy search for applications
- 🎯 **Precise Match**: Set independent input method preferences for each application
- 🚀 **Auto Start**: Support automatic startup
- ⌨️ **Keyboard Shortcuts**:
  - `⌘ + F` - Quick search applications
  - `⌘ + R` - Refresh application list
  - `⌘ + Q` - Quit application

## 🔧 System Requirements

- 🖥 macOS 13.0 or later
- 🔐 Accessibility permission for monitoring application switches
- ⌨️ Input method switching permission

## 📦 Installation

### 🍺 Option 1: Homebrew

```bash
# Add tap
brew tap ygsgdbd/tap

# Install application
brew install --cask typeswitch
```

### 💾 Option 2: Manual Installation

1. Download the latest version from [Releases](https://github.com/ygsgdbd/TypeSwitch/releases)
2. Drag the application to Applications folder
3. Grant necessary system permissions on first launch

## 📖 Usage

1. After launching, the app icon appears in the menu bar
2. Click the menu bar icon to open the main interface
3. Find the application you want to configure in the list
4. Select the default input method for the application
5. The input method will automatically switch when you switch to that application

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

- [Defaults](https://github.com/sindresorhus/Defaults) (9.0.0) - For persistent settings storage
- [SwiftUIX](https://github.com/SwiftUIX/SwiftUIX) (0.2.3) - Provides additional SwiftUI components
- [Swift Syntax](https://github.com/swiftlang/swift-syntax) (600.0.1) - For project generation

Build tools:
- [Tuist](https://github.com/tuist/tuist) - For project generation and management

## Development

### Requirements

- Xcode 15.0+
- Swift 5.9+
- macOS 13.0+
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
├── Project.swift       # Tuist project configuration
├── Tuist/             # Tuist configuration files
├── Sources/           # Source code
│   ├── Models/        # Data models
│   ├── Views/         # SwiftUI views
│   ├── ViewModels/    # View models
│   └── Utils/         # Utility classes
└── Tests/            # Test files
```

## Contributing

Pull requests and issues are welcome. Before submitting a PR, please ensure:

1. Code follows project style
2. Necessary tests are added
3. Documentation is updated

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) file for details.

## FAQ

- Q: Why can't I switch input methods in some applications?
  - A: Some applications may require additional permissions. Please ensure TypeSwitch has accessibility access.

- Q: Does TypeSwitch work with all input methods?
  - A: Yes, TypeSwitch works with all input methods available in macOS System Settings.

- Q: Will TypeSwitch affect system performance?
  - A: No, TypeSwitch is designed to be lightweight and efficient, using minimal system resources.

- Q: Does it work with virtual machines or remote desktop applications?
  - A: Yes, TypeSwitch works with any application that appears in macOS, including virtual machines and remote desktop clients.

## Changelog

### v0.1.0
- Initial release
- Basic input method switching functionality
- Menu bar interface
- Application list with search
- Automatic startup option
- Homebrew support

## Acknowledgments

This project was inspired by and learned from:
- [SwitchKey](https://github.com/itsuhane/SwitchKey) - An excellent input method switcher that provided valuable insights
- The Swift and SwiftUI communities
- All contributors and users who provided feedback

---

# 中文说明 <a name="中文说明"></a>

<div align="center">

[🇺🇸 English](#typeswitch-) | [📦 安装方法](#安装方法) | [📖 使用说明](#使用说明) | [❓ 常见问题](#常见问题)

</div>

TypeSwitch 是一个 macOS 应用程序，用于自动切换不同应用的输入法。它可以记住每个应用程序的输入法偏好，并在应用程序切换时自动切换到对应的输入法。

## 截图预览

<div align="center">
  <img src="Screenshots/main.png" width="600" alt="主界面">
  <p><em>主界面 - 为不同应用设置默认输入法</em></p>
</div>

<div align="center">
  <img src="Screenshots/search.png" width="600" alt="搜索功能">
  <p><em>搜索功能 - 快速查找应用并设置输入法</em></p>
</div>

## 功能特点

- 🔄 自动切换：在切换应用时自动切换到预设的输入法
- 🔍 快速搜索：支持模糊搜索应用程序
- 🎯 精确匹配：为每个应用设置独立的输入法偏好
- 🚀 开机启���：支持开机自动启动
- ⌨️ 快捷键支持：
  - `⌘ + F` - 快速搜索应用
  - `⌘ + R` - 刷新应用列表
  - `⌘ + Q` - 退出应用

## 系统要求

- 🖥 macOS 13.0 或更高版本
- 🔐 需要辅助功能权限用于监控应用程序切换
- ⌨️ 需要输入法切换权限

## 安装方法

### 🍺 方式一：Homebrew

```bash
# 添加 tap
brew tap ygsgdbd/tap

# 安装应用
brew install --cask typeswitch
```

### 💾 方式二：手动安装

1. 从 [Releases](https://github.com/ygsgdbd/TypeSwitch/releases) 下载最新版本
2. 将应用拖入应用程序文件夹
3. 首次启动时授予必要的系统权限

## 使用说明

1. 启动后，应用图标会出现在菜单栏
2. 点击菜单栏图标打开主界面
3. 在列表中找到要配置的应用
4. 选择该应用的默认输入法
5. 切换到该应用时会自动切换到设定的输入法

## 安全性

TypeSwitch 高度重视用户隐私和安全：

- 🏠 所有数据本地存储，不会上传网络
- 🚫 不收集任何用户信息或使用数据
- 📖 源代码完全开源，欢迎审查
- 🛡️ 使用 Swift 内置的安全特性
- 🔐 权限使用说明：
  - 辅助功能：仅用于检测应用程序切换
  - 输入法切换：仅用于切换输入法
  - 自动启动：仅用于开机启动

## 依赖说明

本项目使用以下开源库：

- [Defaults](https://github.com/sindresorhus/Defaults) (9.0.0) - 用于持久化存储设
- [SwiftUIX](https://github.com/SwiftUIX/SwiftUIX) (0.2.3) - 提供额外的 SwiftUI 组件
- [Swift Syntax](https://github.com/swiftlang/swift-syntax) (600.0.1) - 用于项目生成

构建工具：
- [Tuist](https://github.com/tuist/tuist) - 用于项目生成和管理

## 开发相关

### 环境要求

- Xcode 15.0+
- Swift 5.9+
- macOS 13.0+
- [Tuist](https://github.com/tuist/tuist)

### 构建步骤

1. 安装 [Tuist](https://github.com/tuist/tuist#install-▶️)

2. 克隆仓库
```bash
git clone https://github.com/ygsgdbd/TypeSwitch.git
cd TypeSwitch
```

3. 生成 Xcode 项目
```bash
tuist generate
```

4. 打开项目并构建
```bash
open TypeSwitch.xcworkspace
```

### 自动构建和发布

本项目使用 GitHub Actions 进行自动构建和发布：

1. 推送新的版本标签会触发自动构建：
```bash
git tag v1.0.0
git push origin v1.0.0
```

2. GitHub Actions 会自动：
   - 构建应用
   - 创建 DMG 安装包
   - 发布新版本
   - 生成更新日志

3. 构建产物可在 [Releases](https://github.com/ygsgdbd/TypeSwitch/releases) 页面下载

### 项目结构

```
TypeSwitch/
├── Project.swift       # Tuist 项目配置
├── Tuist/             # Tuist 配置文件
├── Sources/           # 源代码
│   ├── Models/        # 数据型
│   ├── Views/         # SwiftUI 视图
│   ├── ViewModels/    # 视图模型
│   └── Utils/         # 工具类
└── Tests/            # 测试文件
```

## 贡献指南

欢迎提交 Pull Request 或创建 Issue，在提交 PR 之前，请确保：

1. 代码符合项目的代码风格
2. 添加了必要的测试
3. 更新了相关文档

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 常见问题

- Q: 为什么在某些应用中无法切换输入法？
  - A: 某些应用可能需要额外的权限。请确保 TypeSwitch 有辅助功能访问权限。

- Q: TypeSwitch 是否支持所有输入法？
  - A: 是的，TypeSwitch 支持所有在 macOS 系统设置中可用的输入法。

- Q: TypeSwitch 会影响系统性能吗？
  - A: 不会，TypeSwitch 设计轻量高效，占用极少的系统资源。

- Q: 是否支持虚拟机或远程桌面应用？
  - A: 是的，TypeSwitch 支持所有在 macOS 中显示的应用程序，包括虚拟机和远程桌面客户端。

## 更新日志

### v0.1.0
- 首次发布
- 基本的输入法切换功能
- 菜单栏界面
- 应用程序列表搜索
- 开机自启动选项
- Homebrew 支持

## 致谢

本项目受到以下项目的启发和帮助：
- [SwitchKey](https://github.com/itsuhane/SwitchKey) - 一个优秀的输入法切换工具，为本项目提供了宝贵的参考
- Swift 和 SwiftUI 社区
- 所有提供反馈的贡献者和用户
