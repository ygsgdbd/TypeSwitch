# Changelog

## Unreleased

### 🇨🇳 中文

#### 功能

- 新增输入法健康诊断：输入法列表为空、读取失败或自动切换失败时，菜单会显示具体状态，并提供重新加载输入法、重试当前 App 和打开键盘设置等恢复操作。
- 恢复启动时静默检查并开启定时自动检查；发现新版本后，一级菜单会显示具体版本，只有用户点击后才会打开 Sparkle 更新窗口。

#### 优化

- 将版本、项目主页、开发者、帮助、诊断和问题反馈收进“帮助与关于”子菜单，减少低频支持入口对一级菜单空间的占用。
- 移除旧 Defaults 到当前 Sharing 存储的升级迁移代码；从本版本起仅保证从 v0.9.0 及以上版本直接升级时保留配置，更早版本直接升级可能无法恢复旧 App 规则。

#### 修复

- 修复恢复已忽略 App 时丢失原输入法策略的问题，并为菜单栏图标补充当前 App 状态的 VoiceOver 描述。
- 修复输入法目录加载期间激活 App 时可能漏掉自动切换的问题；目录加载完成后仅补偿处理此前被跳过的当前 App。
- 修复手动切换到正确输入法后仍保留失败警告，以及系统已确认自动切换成功后被后续瞬时验证失败覆盖的问题；同时让 VoiceOver 在输入法异常时优先播报警告状态。
- 加固发布链路：阻止版本回退和跨版本并发，校验 Sparkle 签名与 App 内置公钥一致，并为发布失败后残留的草稿 Release 提供安全恢复指引。

### 🇺🇸 English

#### Features

- Added input method health diagnostics. When the input method catalog is empty, fails to load, or an automatic switch fails, the menu now explains the state and offers recovery actions to reload input methods, retry the current app, or open Keyboard Settings.
- Restored a silent startup check and enabled scheduled automatic checks. When an update is available, the root menu shows its version, and Sparkle presents its update window only after the user clicks it.

#### Improvements

- Moved version, project, developer, help, diagnostics, and issue-reporting information into a `Help & About` submenu so low-frequency support actions no longer crowd the root menu.
- Removed the upgrade migration from legacy Defaults to the current Sharing store. Starting with this release, configuration preservation is guaranteed only when upgrading directly from v0.9.0 or later; direct upgrades from earlier versions may not restore legacy app rules.

#### Fixes

- Fixed restored ignored apps losing their previous input method strategy, and added VoiceOver descriptions for the current app state in the menu bar icon.
- Fixed automatic switching being skipped when an app activates while the input method catalog is loading; TypeSwitch now retries only the current app whose activation was deferred.
- Fixed stale failure warnings after manually selecting the correct input method, and prevented a later transient verification failure from overriding a confirmed automatic switch; VoiceOver now announces input method warnings before the current app state.
- Hardened releases against version rollback and cross-version races, verified Sparkle signatures against the public key embedded in the app, and added safe recovery guidance for draft Releases left by failed publishes.

## v0.9.0

### 🇨🇳 中文

#### 功能

- 新增“忽略此 App”：可让指定 App 完全跳过自动输入法切换，并从普通应用列表和切换统计中隐藏。
- 新增“已忽略 App”菜单，支持单独恢复或恢复全部；恢复后 App 会重新继承未配置 App 的默认规则。

#### 优化

- 重新整理应用管理、设置和常用操作的菜单分组，减少不必要的分隔线，使菜单层级更清晰。
- 更新中英文 README 以及浅色、深色界面截图。

#### 修复

- 修复部分旧版本应用规则可能在升级迁移时被跳过的问题，并在恢复旧规则时保留用户当前选择、应用名称和路径等数据。
- 修复快速切换 App、退出 App 或忽略当前 App 时，旧的自动切换任务仍可能继续执行，导致输入法错误切换或切换统计不准确的问题。

#### 工程

- 发布构建号统一使用 UTC 生成，避免运行环境时区变化导致构建号回退。

### 🇺🇸 English

#### Features

- Added Ignore This App so selected apps can completely skip automatic input method switching and stay hidden from regular app lists and switch statistics.
- Added an Ignored Apps menu with individual and restore-all actions. Restored apps inherit the default rule for unconfigured apps again.

#### Improvements

- Regrouped application management, settings, and common actions with fewer unnecessary separators for a clearer menu hierarchy.
- Updated the English and Chinese READMEs and refreshed the light and dark interface screenshots.

#### Fixes

- Fixed an upgrade migration issue that could skip some legacy application rules, while preserving current choices, application names, paths, and other existing data during recovery.
- Fixed stale automatic switching tasks that could continue after quickly changing, quitting, or ignoring apps, causing an incorrect input method switch or inaccurate switch statistics.

#### Engineering

- Standardized release build-number generation on UTC to prevent build numbers from moving backward when the runner time zone changes.

## v0.8.0

### 🇨🇳 中文

#### 功能

- 新增启动时静默检查更新；发现新版本后，菜单项会显示“发现新版本…”，仅在用户点击后才显示 Sparkle 更新窗口，不会自动弹窗、下载或安装。

#### 优化

- 统一运行中应用、已配置应用、失效应用、默认规则和切换统计等菜单文案，并重新整理菜单分组，使规则和常用操作更容易浏览。
- 更新中英文 README、菜单截图和 Homebrew tap trust 安装说明。

#### 工程

- 新增固定版本的 SwiftFormat、仓库管理的 pre-commit hook，以及 PR 的格式和测试质量门禁。

### 🇺🇸 English

#### Features

- Added a silent update check at startup. When a new release is found, the menu item changes to “New Version Available…”. The standard Sparkle update window appears only after the user clicks it; TypeSwitch does not automatically present UI, download, or install updates.

#### Improvements

- Unified menu wording for running, configured, and unavailable apps, the default rule, and switch statistics, and reorganized menu sections so rules and common actions are easier to scan.
- Updated the English and Chinese READMEs, menu screenshots, and Homebrew tap trust installation guidance.

#### Engineering

- Added a pinned SwiftFormat setup, a repository-managed pre-commit hook, and required pull-request formatting and test gates.

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
