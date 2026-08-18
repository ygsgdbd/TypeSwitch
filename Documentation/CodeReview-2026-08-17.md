# 未提交改动审查记录（2026-08-17）

本记录覆盖输入法切换补偿、支持诊断与发布链路相关改动。2026-08-19 已处理发布降级 P1；以下 P2/P3 仅记录，尚未修复。

## 待处理问题

### P2：诊断信息缺少 Locale

`SupportDiagnostics` 已使用 `Bundle.main.preferredLocalizations.first` 报告 App 界面语言，但没有同时记录 `Locale.current.identifier`。区域格式、排序或界面语言与地区不一致的问题仍缺少必要上下文。

建议分别输出 `App Language` 和 `Locale`，并增加二者不同及 App language 缺失时的测试。

### P2：同 tag rerun 可能让 Release 正文与资产不一致

`.github/workflows/release.yml` 使用时间戳 build 重新构建产物，同时配置 `overwrite_files: false`。如果同一 tag 的首次运行已上传资产后失败，rerun 会生成新的 ZIP、checksum 和 `release-body.md`；action 会跳过同名资产，但仍可能更新 Release 正文，造成正文 checksum 指向新 ZIP、实际下载仍是旧 ZIP。

建议后续在构建前检测该 tag 的 GitHub Release 是否已存在并直接失败，避免对不可变 Release 做同 tag 重建。

### P2：手动切回失败目标会重新显示旧警告

`AppFeature.swift` 的确认选择流程在更新 `followLast` 前判断是否清理失败记录。场景“自动切换 A 失败 → 手动切到 B → 手动切回 A”中，旧失败会再次成为当前目标并重新显示。

建议先更新 `followLast` 再清理，或在确认选择匹配失败目标时直接清理，并增加对应回归测试。

### P2：VoiceOver 警告覆盖当前 App 状态

`AppFeature+MenuState.swift` 在存在输入法异常时只返回通用 warning，丢失原有的 configured、unconfigured 或 ignored 状态，与“先播报警告，再播报当前 App 状态”的发布说明不一致。

建议组合“警告 + 当前状态”，并覆盖异常下 configured/unconfigured 状态及播报顺序。

### P3：Homebrew updater 测试未断言首次更新结果

`script/test_release_scripts.sh` 的 updater fixture 已将 version、SHA 和 URL 设为旧值，但第一次运行后直接把任意结果保存为预期内容，只验证第二次运行幂等。如果 updater 以后不再替换 SHA 或 URL，测试仍会通过。

建议让 version、sha256 和 url 三个字段全部使用旧值，并逐项断言更新后的目标内容和第二次运行的幂等性。

### P3：发布说明仍描述已删除的 Homebrew 权限预检

`CHANGELOG.md` 仍宣称发布前会验证 Homebrew token 写权限，但当前简化流程明确以 GitHub Release 为发布事实来源，Homebrew 允许短暂延迟，token 只在 Homebrew checkout 中使用。本记录此前的同类“已处理”陈述也已不再成立。

建议后续同步修订 `CHANGELOG.md`，保留“阻止版本回退”的描述，删除 Homebrew 权限预检已完成的表述。

## 已处理（2026-08-19）

- 发布前要求当前 tag 是 `origin/main` 上最高的严格 SemVer，阻止低版本 GitHub Release 成为 latest。
- Homebrew updater 独立拒绝版本降级，同版本保持幂等。
- 所有版本共用仓库级 release concurrency group，并使用 `queue: max`。

## 已验证

- 重新生成 Tuist 工程后的完整 macOS XCTest：128 tests，0 failures。
- `script/test_release_scripts.sh`：通过。
- Shell、Ruby、workflow YAML 和 `git diff --check`：通过。
- SwiftFormat 0.62.1：0 个文件需要格式化。
