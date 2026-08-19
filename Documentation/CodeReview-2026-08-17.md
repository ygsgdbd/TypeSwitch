# 未提交改动审查记录（2026-08-17）

本记录覆盖输入法切换补偿、支持诊断与发布链路相关改动。2026-08-19 已处理发布降级 P1 及以下 P2/P3。

## 已处理问题（2026-08-19）

### P2：诊断信息缺少 Locale

`SupportDiagnostics` 已使用 `Bundle.main.preferredLocalizations.first` 报告 App 界面语言，但没有同时记录 `Locale.current.identifier`。区域格式、排序或界面语言与地区不一致的问题仍缺少必要上下文。

处理：诊断报告分别输出 `App Language` 和 `Locale`，其中 Locale 来自 `Locale.current.identifier`；测试覆盖二者不同、App language 缺失及 Locale 缺失占位。

### P2：同 tag rerun 可能让 Release 正文与资产不一致

`.github/workflows/release.yml` 使用时间戳 build 重新构建产物，同时配置 `overwrite_files: false`。如果同一 tag 的首次运行已上传资产后失败，rerun 会生成新的 ZIP、checksum 和 `release-body.md`；action 会跳过同名资产，但仍可能更新 Release 正文，造成正文 checksum 指向新 ZIP、实际下载仍是旧 ZIP。

处理：新增发布前检查，仅 GitHub API 返回 404 时继续；Release 已存在、鉴权、限流、服务或网络错误均在构建前失败，`overwrite_files: false` 继续作为第二道保护。

### P2：手动切回失败目标会重新显示旧警告

`AppFeature.swift` 的确认选择流程在更新 `followLast` 前判断是否清理失败记录。场景“自动切换 A 失败 → 手动切到 B → 手动切回 A”中，旧失败会再次成为当前目标并重新显示。

处理：同 App 的手动选择匹配失败目标时直接清理旧失败记录，不再依赖更新前的 current target；回归测试覆盖“自动切换 A 失败 → 手动切到 B → 手动切回 A”。

### P2：VoiceOver 警告覆盖当前 App 状态

`AppFeature+MenuState.swift` 在存在输入法异常时只返回通用 warning，丢失原有的 configured、unconfigured 或 ignored 状态，与“先播报警告，再播报当前 App 状态”的发布说明不一致。

处理：有前台 App 时使用完整本地化文案组合“警告 + configured/unconfigured/ignored”，无前台 App 时保留通用 warning；测试覆盖三种状态和警告优先顺序。

### P3：Homebrew updater 测试未断言首次更新结果

`script/test_release_scripts.sh` 的 updater fixture 已将 version、SHA 和 URL 设为旧值，但第一次运行后直接把任意结果保存为预期内容，只验证第二次运行幂等。如果 updater 以后不再替换 SHA 或 URL，测试仍会通过。

处理：首次运行 updater 后分别断言 version、sha256 和 url 的目标值，再验证第二次运行幂等及版本降级拒绝。

### P3：发布说明仍描述已删除的 Homebrew 权限预检

`CHANGELOG.md` 仍宣称发布前会验证 Homebrew token 写权限，但当前简化流程明确以 GitHub Release 为发布事实来源，Homebrew 允许短暂延迟，token 只在 Homebrew checkout 中使用。本记录此前的同类“已处理”陈述也已不再成立。

处理：同步修订 `CHANGELOG.md` 中英文说明，保留版本回退、跨版本并发和 Sparkle 公钥校验，删除 Homebrew 权限预检表述。

## 已处理（2026-08-19）

- 发布前要求当前 tag 是 `origin/main` 上最高的严格 SemVer，阻止低版本 GitHub Release 成为 latest。
- Homebrew updater 独立拒绝版本降级，同版本保持幂等。
- 所有版本共用仓库级 release concurrency group，并使用 `queue: max`。

## 已验证

- 重新生成 Tuist 工程后的完整 macOS XCTest：131 tests，0 failures。
- `script/test_release_scripts.sh`：通过。
- Shell、Ruby、workflow YAML 和 `git diff --check`：通过。
- SwiftFormat 0.62.1：0 个文件需要格式化。
