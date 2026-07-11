# Changelog

## v0.7.1

### 🇨🇳 中文

#### 修复

- 修复系统登录启动已启用后，旧 fallback LaunchAgent 未被清理的问题。

#### 优化

- 完善支持浅色、深色和单色外观的自适应 App 图标。
- 优化 README 品牌展示。

### 🇺🇸 English

#### Fixes

- Fixed an issue where the legacy fallback LaunchAgent was not removed after system launch-at-login became enabled.

#### Improvements

- Refined the adaptive app icon with light, dark, and monochrome appearances.
- Improved the README brand presentation.

## v0.7.0

### 🇨🇳 中文

#### 功能

- 为已配置应用、失效应用、默认输入法、切换统计、检查更新、GitHub 和退出等菜单项新增图标，信息层级更清晰。

#### 优化

- 更新 App 图标及其深色外观设计资源。
- 将 Sparkle 更新说明渲染为 HTML，提升更新弹窗中的排版效果。
- 新增可重复生成且不包含用户隐私数据的 README 截图流程，并更新中英文文档与截图。

### 🇺🇸 English

#### Features

- Added icons to configured apps, unavailable apps, default input method, switch statistics, update checking, GitHub, quit, and other menu items for clearer visual hierarchy.

#### Improvements

- Refreshed the app icon and its dark appearance design assets.
- Rendered Sparkle release notes as HTML for improved formatting in the update dialog.
- Added a deterministic, privacy-safe README screenshot workflow and refreshed the English and Chinese documentation and screenshots.

## v0.6.0

### 🇨🇳 中文

#### 功能

- 新增菜单栏“检查更新...”功能，手动安装版可直接从 GitHub Releases 检查更新。
- 新增 Sparkle 签名 appcast，并在更新弹窗中嵌入本版本更新说明。

#### 优化

- 将运行中 App 拆分为“未配置”和“运行中”分组，未设置规则的 App 更容易集中处理。
- 优化菜单文案：默认规则改为“未配置应用规则”，“忽略”改为“不自动切换”，“记住上次”改为“记住上次切换”。
- 优化切换统计、退出按钮和清理失效设置等菜单文案。
- 简化底部项目入口为 GitHub 链接，移除重复的关于/最新版本入口。
- 更新 README 截图、功能说明、安装更新说明和发布流程说明。
- 更新依赖并移除 SwiftUIX 依赖，补充本地化占位符一致性测试。

### 🇺🇸 English

#### Features

- Added a Check for Updates item to the menu bar app so manual installs can check GitHub Releases directly.
- Added a signed Sparkle appcast with embedded release notes for the update dialog.

#### Improvements

- Split running apps into Unconfigured and Running groups so apps without rules are easier to review.
- Improved menu wording: Default Rule is now Unconfigured Apps, Ignore is now Don't Switch, and Remember Last is now Last Switch.
- Refined wording for switch statistics, quit, and unavailable-settings cleanup actions.
- Simplified the footer project entry to a GitHub link and removed duplicate about/latest-release entries.
- Updated README screenshots, feature descriptions, install/update notes, and release workflow documentation.
- Updated dependencies, removed SwiftUIX, and added localization placeholder consistency tests.
