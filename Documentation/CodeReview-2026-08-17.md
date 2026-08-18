# 未提交改动审查记录（2026-08-17）

本记录覆盖输入法切换补偿、支持诊断与发布链路相关改动。当前完整 macOS XCTest 和发布脚本测试均通过，但以下问题应在 PR 合并前处理。

## 待处理问题

### P1：发布前未验证 Homebrew 凭据

`.github/workflows/release.yml` 的发布前检查只验证 `SPARKLE_ED_PRIVATE_KEY`。如果 `HOMEBREW_TAP_TOKEN` 缺失、失效或没有 tap 写权限，GitHub Release 和 attestation 已公开后，Homebrew 同步才会失败，形成半完成发行。

建议在公开 Release 前检查 token 非空，并通过只读 GitHub API 请求确认其对 `ygsgdbd/homebrew-tap` 具备 push 权限。

### P1：不同版本的发布任务仍可并发

release concurrency group 当前包含 tag，因此只能阻止同一 tag 并发。不同 tag 可以同时修改全局 latest Release 和同一个 Homebrew cask；如果旧版本后完成，可能覆盖或降级新版本的 cask。

建议让同一仓库的所有发布共用一个 concurrency group，使完整发布链串行执行，并保持 `cancel-in-progress: false`。

### P2：诊断信息缺少 Locale

`SupportDiagnostics` 已使用 `Bundle.main.preferredLocalizations.first` 报告 App 界面语言，但没有同时记录 `Locale.current.identifier`。区域格式、排序或界面语言与地区不一致的问题仍缺少必要上下文。

建议分别输出 `App Language` 和 `Locale`，并增加二者不同及 App language 缺失时的测试。

### P2：Homebrew updater 测试未覆盖 SHA 和 URL 替换

`script/test_release_scripts.sh` 的 updater fixture 只把 version 改为旧值，SHA 和 URL 原本就是正确值，也没有逐项断言第一次更新后的结果。如果 updater 以后不再替换 SHA 或 URL，测试仍会通过。

建议让 version、sha256 和 url 三个字段全部使用旧值，并逐项断言更新后的目标内容和第二次运行的幂等性。

## 已验证

- 重新生成 Tuist 工程后的完整 macOS XCTest：126 tests，0 failures。
- `script/test_release_scripts.sh`：通过。
- Shell、Ruby、workflow YAML 和 `git diff --check`：通过。
- SwiftFormat 0.62.1：0 个文件需要格式化。
