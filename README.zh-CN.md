<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Design/AppIcon/Previews/typeswitch-icon-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="Design/AppIcon/Previews/typeswitch-icon-default.png">
    <img src="Design/AppIcon/Previews/typeswitch-icon-default.png" width="160" alt="TypeSwitch 图标">
  </picture>
</p>

<h1 align="center">TypeSwitch</h1>

<p align="center">TypeSwitch 是一款按 App 自动切换输入法的原生 macOS 菜单栏工具。为每个 App 选择输入法策略，设置未配置 App 的默认规则，并在前台 App 切换时自动切到对应输入法。</p>

<p align="center">
  <a href="https://swift.org"><img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-orange.svg"></a>
  <a href="https://www.apple.com/macos/"><img alt="Platform" src="https://img.shields.io/badge/Platform-macOS%2014.0+-blue.svg"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-MIT-green.svg"></a>
  <a href="https://github.com/ygsgdbd/homebrew-tap"><img alt="Homebrew" src="https://img.shields.io/badge/homebrew-available-brightgreen.svg"></a>
  <a href="https://github.com/ygsgdbd/TypeSwitch/releases"><img alt="Release" src="https://img.shields.io/github/v/release/ygsgdbd/TypeSwitch?include_prereleases"></a>
  <a href="https://github.com/ygsgdbd/TypeSwitch/pulls"><img alt="PRs Welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

<p align="center">🇨🇳 <strong>简体中文</strong> · 🇺🇸 <a href="README.md">English</a></p>

## 🖼️ 截图预览

![TypeSwitch 浅色模式主菜单和当前 App 输入法策略](Documentation/Screenshots/zh-Hans-light.png#gh-light-mode-only)

![TypeSwitch 暗色模式主菜单和当前 App 输入法策略](Documentation/Screenshots/zh-Hans-dark.png#gh-dark-mode-only)

## ✨ 功能亮点

- **按 App 自动切换。** TypeSwitch 会监听当前前台 App，在你切换 App 时自动应用已保存的输入法规则，已忽略的 App 除外。
- **选择适合自己的切换方式。** 可让 App 继承默认规则、记住上次切换、指定输入法，或忽略不希望 TypeSwitch 管理的 App。
- **随时配置遇到的 App。** 可直接设置当前 App，从按配置状态分组的运行中 App 里选择，或在菜单栏中管理全部已保存规则。
- **保持规则与统计整洁。** 查找不存在 App 的规则、移除失效设置、查看成功切换次数，并按需清零统计。
- **融入日常工作流程。** 支持登录时打开、通过 Sparkle 检查更新、访问 GitHub 仓库，以及使用 `Command + Q` 退出。

## 🪶 原生与轻量

- **真正原生。** TypeSwitch 的 App 业务代码使用 Swift 编写，并采用 SwiftUI 和 The Composable Architecture（TCA）架构。它基于 `MenuBarExtra` 与 `LSUIElement` 构建，不包含 Electron 运行时，也没有嵌入 WebView。
- **专注且轻量。** TypeSwitch 作为菜单栏工具运行，无需附带浏览器引擎或服务端组件。App 规则、默认规则和切换统计都保存在你的 Mac 上。
- **自然融入 macOS。** 界面会自动适配浅色与暗色模式。在 macOS 26 上，原生 SwiftUI 控件会在适用位置呈现系统提供的 Liquid Glass 外观；macOS 14 与 macOS 15 则保持各自的原生系统样式。TypeSwitch 不使用自定义视觉效果模拟 Liquid Glass。
- **同时支持新旧 Mac。** Release workflow 使用 Xcode 26.2，并验证每个发布版本都是同时支持 Apple Silicon 与 Intel Mac 的 Universal Binary。

## 💻 系统要求

- macOS 14.0 或更高版本
- 已启用的 macOS 键盘布局或输入法
- macOS 对应用激活监听、系统输入法切换和可选登录项所需的权限

## 📦 安装方法

### Homebrew

`brew trust` 命令首次随 Homebrew 5.1.15 于 2026 年 6 月 3 日发布。在 Homebrew 5.1.15–5.x 中，只有设置了 `HOMEBREW_REQUIRE_TAP_TRUST=1` 才会要求信任。从 2026 年 6 月 11 日发布的 Homebrew 6.0.0 开始，默认要求显式信任非官方 tap 中的 cask。

```bash
brew tap ygsgdbd/tap
brew trust --cask ygsgdbd/tap/typeswitch
brew install --cask typeswitch
```

这只会信任 `typeswitch` cask，不会信任整个 tap。Homebrew 会保存信任记录，因此通常只需执行一次 trust 命令。详情请参阅 Homebrew 官方的 [Tap Trust 文档](https://docs.brew.sh/Tap-Trust)。

Homebrew 5.1.14 及更早版本没有 `brew trust`，也不需要执行该命令：

```bash
brew tap ygsgdbd/tap
brew install --cask typeswitch
```

如果执行 `brew trust` 时出现 `Unknown command: trust`，请跳过该命令，或运行 `brew update` 升级 Homebrew。

Homebrew 安装版使用以下命令更新：

```bash
brew upgrade typeswitch
```

#### Tap Trust 故障排查

- 如果 Homebrew 提示 `Refusing to load cask ... from untrusted tap`，请执行 `brew trust --cask ygsgdbd/tap/typeswitch`，然后重新安装或升级。
- 如果 `brew doctor` 报告 `ygsgdbd/tap` 未受信任，只需使用上述命令信任 TypeSwitch cask，不需要信任整个 tap。
- 如果已有安装在 Homebrew 升级到 6.0.0 或更高版本后无法更新，请先信任该 cask，再重试 `brew upgrade typeswitch`。
- 如果确实希望信任 tap 中所有当前及未来的 formula、cask 和 external command，可以使用 `brew trust ygsgdbd/tap`。该命令授权范围更大，不作为推荐方案。

### 手动安装

1. 从 [Releases](https://github.com/ygsgdbd/TypeSwitch/releases) 下载最新构建。
2. 将 `TypeSwitch.app` 拖入“应用程序”文件夹。
3. 启动 TypeSwitch，并授予 macOS 请求的系统权限。
4. 后续可在菜单栏应用中使用“检查更新…”从 GitHub Releases 检查更新。

## 🧭 使用说明

1. 启动 TypeSwitch，键盘图标会出现在菜单栏中。
2. 打开菜单，用“当前应用”配置当前前台 App。
3. 用“运行中 · 未配置”为还没有规则的运行中 App 设置规则。
4. 用“运行中 · 已配置”和“全部已配置 App”查看并修改已有 App 规则。
5. 为每个 App 选择“默认”以继承兜底规则，或选择“记住上次切换”及指定输入法。
6. 选择“忽略此 App”可停止自动切换并将其从普通列表隐藏；可在“已忽略 App”中单项恢复或恢复全部。
7. 用“未配置 App 的默认规则”设置没有单独规则的 App 的默认行为。
8. 按需查看“找不到的 App”和“切换统计”，清理缺失规则或查看成功切换次数。

## 🔒 隐私与权限

- App 规则、未配置 App 的默认规则和切换统计都存储在本地。
- 本仓库中没有服务端组件。
- 菜单中的“GitHub 仓库”和“检查更新…”只会在你主动使用时访问 GitHub。
- 输入法切换使用 macOS 系统输入源。
- “登录时打开”使用 macOS 登录项；必要时会回退到 LaunchAgent。

## 🧰 技术栈

本项目使用：

- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) `1.26.0`：应用架构和状态管理
- [Sharing](https://github.com/pointfreeco/swift-sharing) `2.9.1`：基于文件的共享状态持久化
- [Sparkle](https://github.com/sparkle-project/Sparkle) `2.9.4`：手动检查更新和 appcast 支持
- [SwifterSwift](https://github.com/SwifterSwift/SwifterSwift) `8.0.0`：Swift 扩展
- Point-Free 支持库：CasePaths、Dependencies、PerceptionCore
- [Tuist](https://github.com/tuist/tuist)：项目生成和构建配置

## 🧪 开发相关

### 环境要求

- Xcode 15.0+
- Swift 5.9+
- macOS 14.0+
- [Tuist](https://github.com/tuist/tuist)
- [ImageMagick](https://imagemagick.org/)
- RTK（`rtk`，截图生成脚本需要）

### 构建步骤

安装 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
```

克隆仓库并生成 Xcode 项目：

```bash
git clone https://github.com/ygsgdbd/TypeSwitch.git
cd TypeSwitch
tuist generate
open TypeSwitch.xcworkspace
```

运行测试：

```bash
tuist test
```

如需重新生成内容固定且不包含用户真实规则、输入法或统计信息的 README 截图，请先为终端或 Codex 授予“屏幕与系统音频录制”和“辅助功能”权限，退出其他正在运行的 TypeSwitch 实例，然后执行：

```bash
./script/generate_readme_screenshots.sh
```

### 发布流程

推送 `vX.Y.Z` 标签后，GitHub Actions 会构建正式版本：

```bash
git tag v0.6.0
git push origin v0.6.0
```

发布 workflow 会校验标签、运行测试、构建 universal macOS app、打包 zip、生成 checksums、创建已签名的 Sparkle `appcast.xml`、发布 GitHub Release，并更新 Homebrew cask。

## 🙏 致谢

TypeSwitch 受到以下项目和社区启发：

- [SwitchKey](https://github.com/itsuhane/SwitchKey)，一款 macOS 输入法切换工具
- Swift 和 SwiftUI 社区
- 提供反馈的贡献者和用户
