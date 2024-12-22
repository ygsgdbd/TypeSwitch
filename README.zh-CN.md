# TypeSwitch 🔄

<div align="center">

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013.0+-blue.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Build Status](https://github.com/ygsgdbd/TypeSwitch/actions/workflows/build.yml/badge.svg)](https://github.com/ygsgdbd/TypeSwitch/actions)
[![Homebrew](https://img.shields.io/badge/homebrew-available-brightgreen.svg)](https://github.com/ygsgdbd/homebrew-tap)
[![Release](https://img.shields.io/github/v/release/ygsgdbd/TypeSwitch?include_prereleases)](https://github.com/ygsgdbd/TypeSwitch/releases)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/ygsgdbd/TypeSwitch/pulls)

[🇺🇸 English](README.md) | [📦 安装方法](#安装方法) | [📖 使用说明](#使用说明)

</div>

TypeSwitch 是一个基于 SwiftUI 开发的现代 macOS 应用，用于自动切换不同应用的输入法。采用新的 Swift 特性和原生 macOS 功能，为用户提供流畅高效的输入法管理体验。

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
- 🚀 开机启动：支持开机自动启动
- ⌨️ 快捷键支持：
  - `⌘ + F` - 快速搜索应用
  - `⌘ + R` - 刷新应用列表
  - `⌘ + Q` - 退出应用
- 🎯 快速切换：支持自定义快捷键切换当前应用的默认输入法

## 系统要求

- 🖥 macOS 13.0 或更高版本
- 🔐 需要辅助功能权限用于监控应用切换
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
3. 首次启动时授予必要系统权限

## 使用���明

1. 启动后，应用图标会出现在菜单栏
2. 点击菜单栏图标打开主界面
3. 在列表中找到要配置的应用
4. 选择该应用的默认输入法
5. 切换到该应用时会自动切换到设定的输入法

## 🔒 安全

TypeSwitch 非常重视用户隐私和安全：

- 🏠 所有数据本地存储，不会上传网络
- 🚫 不收集任何用户信息或使用数据
- 📖 源代码完全开放，欢迎审查
- 🛡️ 使用 Swift 内置的安全特性
- 🔐 权限使用说明：
  - 辅助功能：仅用于检测应用切换
  - 输入法切换：仅用于切换输入法
  - 自动启动：仅用于开机启动

## 依赖说明

本项目使用以下开源库：

- [Defaults](https://github.com/sindresorhus/Defaults) (9.0.0) - 用于持久化存储设置
- [SwiftUIX](https://github.com/SwiftUIX/SwiftUIX) (0.1.9) - 提供额外的 SwiftUI 组件
- [SwifterSwift](https://github.com/SwifterSwift/SwifterSwift) (7.0.0) - Swift 原生扩展
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (2.2.2) - 添加用户自定义全局快捷键

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
│   ├── Models/        # 数据模型
│   ├── Views/         # SwiftUI 视图
│   ├── ViewModels/    # 视图模型
│   └── Utils/         # 工具类
└── Tests/            # 测试文件
```

## 贡献指南

欢迎提交 Pull Request 和创建 Issue，在提交 PR 之前，请确保：

1. 代码符合项目的代码风格
2. 添加了必要的测试
3. 更新了相关文档

## 许可证

本项目基于 MIT 许可证开源。详见 [LICENSE](LICENSE) 文件。

## 致谢 🙏

本项目受到以下项目和社区的启发和帮助：
- [SwitchKey](https://github.com/itsuhane/SwitchKey) - 一个优秀的输入法切换工具，为本项目提供了宝贵的参考
- Swift 和 SwiftUI 社区
- 所有提供反馈和贡献者和用户
