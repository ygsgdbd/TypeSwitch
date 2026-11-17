# TypeSwitch 警告修复与验收（2026-11-17）

## 改动

- 保留 `SMAppService` 优先、用户 LaunchAgent 备用的策略，以及原有重复配置清理时机。
- 备用开启只原子写入 plist，关闭和迁移只删除 plist；配置供下次登录加载，运行中的应用不执行 `bootstrap/bootout`。
- 移除命令执行器和对应内部环境字段。文件缺失按幂等情况处理；其他读取、解析、写入及删除失败记录操作、目标路径和底层 `NSError`。
- 设置后重新查询状态；写入失败不会伪报开启，删除失败且配置仍有效时继续反映开启。
- 外部 `LaunchAtLoginClient`、`LaunchAtLoginStatus` 与菜单接口不变。内部错误回调用于稳定验证文件错误。

用户 LaunchAgent 的登录加载行为参考 [Apple 的 launchd 文档](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)。

## 自动检查

在最终代码上运行 `just check`，使用仓库要求的 SwiftFormat **0.62.1**；本机全局 0.64.7 未替换，仅为该命令调整工具查找路径。

- 格式检查通过。
- 全部 **169 项 XCTest 通过，0 失败**，其中自启动服务 17 项。
- 发布脚本测试通过。
- 自启动测试覆盖首次及重复开启、旧路径更新、关闭与缺失幂等、SM 注册迁移、注册/注销失败、四种系统状态、损坏配置，以及真实或注入的文件读写/删除失败。

最终 XCTest 结果：`Test-TypeSwitch-2026.11.17_12-17-11-+0800.xcresult`。

## 本机运行时验收

环境：macOS **27.2 / 26B123**，Xcode **27.2 / 27B52**，arm64，双显示器。使用本轮构建的临时副本和独立 bundle ID `top.ygsgdbd.TypeSwitch.warning-01a1e782`，运行正常服务与更新器。

| 场景 | 结果与证据 |
| --- | --- |
| 自启动开关 | 三轮开启/关闭；菜单动作后读取系统 `SMAppService` 状态，依次为 `1→0`、`1→0`、`1→0`。三轮期间 PID 始终为 48935。 |
| 策略与忽略恢复 | 三轮原生 AXPress；访达规则的实际持久化结果均为 `followLast → ignored → followLast → none`，并逐轮核对已配置/已忽略菜单画面。 |
| 鼠标展开子菜单 | 三轮真实鼠标悬停，画面确认访达子菜单展开。 |
| 键盘导航与关闭 | 三轮真实 Down/Right 展开、Left 返回、Escape 关闭；动画结束后核对画面。 |
| 点击外部关闭 | 三轮点击菜单外空白区域，画面确认关闭。 |
| 前台应用切换 | 三轮 `ChatGPT → Google Chrome`，在各应用所在显示器打开菜单，核对“当前应用”更新。 |
| 更新结果返回 | 一次菜单检查和两次正常重启后的静默检查，均捕获 `recordAvailableUpdate(_:)` 回调，并核对“新版本 0.10.2 可用…”菜单。范围为检查结果与菜单状态，安装流程未验收。 |

双屏验收必须使用实际显示菜单的屏幕；点击另一屏菜单栏可能改变前台应用。起初可访问性树保留了另一显示器的坐标，已通过双屏截图校正后完成上述验收。

更新检查中的重复点击受同一 Sparkle 更新会话限制，因此后两轮使用正常退出/重新启动验证独立的真实结果返回。

## 窗口警告归因

在 `_NSDetectedLayoutRecursion` 和 `-[NSWindow makeKeyWindow]` 设置自动继续的符号断点，完整保存主线程调用栈；后者记录接收对象地址，与 `_NSGlassEffectWindow` 警告关联。

- 布局重入可在菜单栏项初始化时复现。代表栈经过 `NSStatusItem` / `NSSceneStatusItem` 的场景建立及 AppKit 布局；应用帧仅为 `TypeSwitchApp.$main` 和 `main`。
- 玻璃窗口焦点警告的代表栈经过 `NSContextMenuImpl` / `NSPopupMenuWindow` 和 AppKit 窗口排序，再进入 `makeKeyWindow`。
- 本机采样支持框架内部路径，未发现本项目直接触发布局或窗口焦点的错误调用。三轮交互正常，本次保持 UI 实现。
- 这些系统警告仍会输出，不应将本次结果表述为已消除它们。AppIntents/XPC、task-name-port 日志亦未纳入代码修改；用户确认的手动停止 `code 9` 无需修复。

完整代表栈见 [WarningCleanup-2026-11-17-stacks.txt](WarningCleanup-2026-11-17-stacks.txt)。本轮三个异步诊断进程的 stderr 中，`Boot-out failed` 为 **0**。

## 清理与待验收

- 原始备用 plist 在测试前后均不存在，原始 legacy LaunchAgent 在测试前后均未加载。
- 测试 bundle 的登录项已注销，最后读取系统状态为 **0 / notRegistered**。
- 诊断应用、原生测试会话和 LLDB 均已退出；独立规则数据未写入原应用的存储目录。
- 完整本地原始日志、界面画面和结构化结果保存在 `/private/tmp/typeswitch-warning-runtime-01a1e782/`；自动检查日志为 `/private/tmp/typeswitch-warning-check-final.log`。临时目录不是持久归档。
- **真实下次登录仍待用户在方便时验收**：开启后注销/登录确认自动启动，再关闭并重复确认不自动启动。备用文件路径的单元测试和本轮 SM 开关测试不能替代这一项。
