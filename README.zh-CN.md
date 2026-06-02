# TypeSwitch 🔄

<div align="center">

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013.0+-blue.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Homebrew](https://img.shields.io/badge/homebrew-available-brightgreen.svg)](https://github.com/ygsgdbd/homebrew-tap)
[![Release](https://img.shields.io/github/v/release/ygsgdbd/TypeSwitch?include_prereleases)](https://github.com/ygsgdbd/TypeSwitch/releases)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/ygsgdbd/TypeSwitch/pulls)

[🇺🇸 English](README.md) | [📦 安装方法](#安装方法) | [📖 使用说明](#使用说明)

</div>

TypeSwitch 是一个 macOS 菜单栏工具，用于按 App 自动切换输入法。

✨ **系统原生外观** - 使用 SwiftUI 菜单栏控件，跟随系统浅色和深色模式。

## 截图预览

<div align="center">
  <img src="Screenshots/main-20260602-kuxy.png" width="382" alt="TypeSwitch 菜单栏界面">
  <p><em>菜单栏界面 - 管理 App 规则、默认规则、不可用项和切换统计</em></p>
</div>


## 功能特点

- 🔄 自动切换：切换 App 时切换输入法
- 🧭 当前应用：在菜单顶部直接配置当前 App
- 📱 菜单栏界面：快速查看和设置
- 📋 运行中应用：直接配置打开中的 App
- ⚙️ 已配置应用：管理已有 App 规则
- 🎯 默认规则：设置未单独配置 App 的输入法策略
- 🧹 不可用应用：查看并清理已失效 App 规则
- 📊 切换统计：查看每个 App 的成功切换次数，可清零
- 🚀 开机启动：登录后自动运行
- ⌨️ 快捷键支持：
  - `⌘ + Q` - 退出应用
- 🔗 快速链接：直接访问 GitHub 仓库和最新发布版本

## 系统要求

- 🖥 macOS 14.0 或更高版本
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

## 使用说明

1. 启动后，应用图标（⌨️）会出现在菜单栏中
2. 点击菜单栏图标打开下拉菜单
3. 用“当前应用”或“运行中应用”配置当前或打开中的 App
4. 用“已配置应用”管理已保存的 App 规则
5. 选择“默认”“记住上次”“忽略”或指定输入法
6. 在主菜单设置“默认规则”和“开机启动”
7. 按需查看“不可用”和“切换统计”

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

- [Defaults](https://github.com/sindresorhus/Defaults) (7.3.1) - 用于持久化存储设置
- [SwiftUIX](https://github.com/SwiftUIX/SwiftUIX) (0.2.3) - 提供额外的 SwiftUI 组件
- [SwifterSwift](https://github.com/SwifterSwift/SwifterSwift) (8.0.0) - Swift 原生扩展

构建工具：
- [Tuist](https://github.com/tuist/tuist) - 用于项目生成和管理

## 开发相关

### 环境要求

- Xcode 15.0+
- Swift 5.9+
- macOS 14.0+
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
