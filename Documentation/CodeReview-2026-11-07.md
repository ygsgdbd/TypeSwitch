# v0.10.1 之后的 PR 审计（2026-11-07）

本次审计确认 **1 项 P2 回归**，归属于 PR #46；没有发现可确认的 P0/P1 问题。该回归现已在工作区修复，修复及验证结果见文末记录。

## 范围与方法

- 将“最后提交版本”解释为最近正式发布的 `v0.10.1`，已通过 GitHub Release 验证。
- 基线：`v0.10.1`，commit `c3205c110113e67912f3b04bc6f4661f22bd6e6e`。
- 审计终点：`7dddcf97aa8c94fc85ade9c163aaa62588353b1a`；审计开始与结束时均与远端 `main` 一致。
- 范围内共有 PR #45、#46、#47、#48，全部已合并，没有未合并 PR；合计 16 个不同文件，新增 2562 行、删除 2160 行。
- 逐个核对 PR 说明、准确的 base/head diff、合并后的源码、调用路径、原有测试及新增测试，并交叉审查四个 PR 组合后的行为。
- 输入法切换、应用可用性、CI/环境设置分别独立审阅，随后统一复核证据。只将有具体触发条件和证据的新增问题计入缺陷。

## 确认的问题

### [P2] 更新应用记录后，可用性快照仍对应旧规则集合（已修复）

归属：[PR #46](https://github.com/ygsgdbd/TypeSwitch/pull/46)。

位置：`TypeSwitch/Sources/App/AppFeature+MenuState.swift:220`；相关更新入口位于 `TypeSwitch/Sources/App/AppFeature.swift:273–278`，快照刷新位于同文件第 136–143 行。

菜单打开时，`appAvailability` 仅探测当时已有规则的路径。此后 `.response(.runningApps)` 仍会通过 `upsertRecord` 新增应用记录或替换路径，应用激活也可以更新记录，但这些更新没有同步更新快照。

`unavailableApps` 把不在 `availablePaths` 中的路径直接判为不可用；`configuredApps` 同样要求路径已经出现在快照中。因此会出现以下两种情况：

1. 菜单打开后，异步运行应用列表返回一个此前没有记录的应用。应用进入运行列表，同时也被加入“不可用应用”。
2. 已配置应用的记录更新为另一个有效路径。该应用从已配置分组消失，并被加入“不可用应用”。

关闭并重新打开菜单后，快照重新探测，分类才恢复正常。原有“冻结策略”逻辑只冻结 `menuStrategiesAtPresentation`，没有冻结规则或运行应用列表，因而不能阻止上述状态组合。

#### 验证证据

首先分别抽取 PR #46 base 与当前 HEAD 的原始模型、upsert 和菜单投影代码，创建真实目录并执行对照：

```text
PR #46 base:
new rule: running=["editor"], unavailable=[]
changed path: configured=["editor"], unavailable=[]

当前 HEAD:
new rule: running=["editor"], unavailable=["editor"]
changed path: configured=[], unavailable=["editor"]
path physically exists=true

重新刷新快照后:
configured=["editor"], unavailable=[]
```

随后在隔离副本中使用实际 `AppFeature` 和 `TestStore`，追加两项测试：

- `testAuditNewRunningAppRemainsAvailableWhileMenuIsOpen`
- `testAuditChangedRunningAppPathRemainsAvailableWhileMenuIsOpen`

两项测试都按 `.menuPresented → .response(.runningApps(...))` 发送真实 reducer 动作，注入始终返回存在的路径探测器；都只在“不可用列表应为空”的断言处失败。关闭、重开菜单后的恢复断言均通过。

#### 影响与修复方向

影响是错误的不可用提示、同一应用重复出现在不同分组，以及有效配置在当前菜单中错误消失。清理规则会重新探测，因此本复现不会直接误删规则。

建议在新增规则或路径变化时更新相应路径的探测结果，或让整个菜单使用一致的规则快照。保留上述两项 reducer 回归测试，同时覆盖应用激活更新路径的入口。

## 各 PR 的审计结果

| PR | 改动与审查重点 | 结果 |
| --- | --- | --- |
| [#45](https://github.com/ygsgdbd/TypeSwitch/pull/45) | `SwitchingFeature` 抽取、根 reducer 路由、菜单投影、共享规则/统计存储、测试迁移及 `CONTEXT.md` | 未发现确定回归 |
| [#46](https://github.com/ygsgdbd/TypeSwitch/pull/46) | 可用性客户端/快照、规则模型、菜单分组、启动与清理、README 演示及测试 | 确认上述 1 项 P2 |
| [#47](https://github.com/ygsgdbd/TypeSwitch/pull/47) | 两个 workflow 中六处 checkout 升级、runner 兼容性、tag/commit 校验、发布权限与产物链路 | 未发现确定回归 |
| [#48](https://github.com/ygsgdbd/TypeSwitch/pull/48) | CodeGraph 可选初始化、`set -e`、工具缺失与命令失败的退出行为 | 未发现确定回归 |

### #45：输入法切换与恢复

- 对比了 7 个响应/系统动作分支及 6 段切换、目录刷新、目标解析、前台重试辅助逻辑。归一化状态路径和 `upsertRecord` 调用后，迁移的核心逻辑与基线一致。
- 忽略和退出应用仍在同一次根动作处理中调用子 reducer；启动和取消使用相同的子 reducer cancellation ID。
- 根级测试实际覆盖查询挂起时忽略应用、选择通知到达而切换仍挂起时退出应用，以及连续激活、过期结果和目录恢复交错。
- 启动仍只加载前台应用与输入法目录；新增集成测试验证启动不触发切换/统计，以及根规则编辑和子模块统计共享同一存储。
- 基线的 81 个 `AppFeature` 测试名称全部保留。逐方法比较后，XCTest 断言表达式在归一化状态访问路径后完全一致，动作收发及 `finish` 数量也一致；20 项迁入子模块，新增 2 项根级集成测试。
- `AppRulesStore.upsertRecord` 保留原来的插入、名称/路径更新、时间戳及策略保留逻辑；没有改变持久化字段。

### #46：应用可用性

- 核对启动、菜单重复展示/重开、运行列表/激活更新、清理、忽略与恢复、统计信息及 README demo 投影。
- 清理前会重新探测，能够保留菜单打开后恢复的应用及所有实际 `.ignored` 规则。
- README demo 的快照使用确定数据，相关动作不会调用真实文件系统探测。
- 用 base/HEAD 的真实模型执行编码与旧格式解码对照：JSON 编码一致，旧 ignored 规则缺省字段解码成功。
- 核查了清理在 Shared 锁外创建快照的并发疑点：当前文件通知及 reducer 更新路径在主线程串行，没有找到可达的并发误删证据。
- 现有 4 项可用性测试覆盖重开、清理重探测、路径失效和 live adapter；缺少本次发现的“菜单打开后更新规则”交错。

### #47：CI 与发布

- 六处 diff 均仅将 `actions/checkout@v4` 升级到 `v5`。触发条件、权限、checkout 输入、tag 恢复与验证、Homebrew 发布 commit/PAT 用途均保留。
- [checkout v5 官方说明](https://github.com/actions/checkout/releases/tag/v5.0.0)要求 runner 至少为 `2.327.1`；核查到 PR #47 实际为 `2.337.0`，PR #48 为 `2.338.2`，对应 checkout 均成功。
- 审阅相关版本、tag、main 祖先关系、产物 SHA-256 和 Homebrew 更新校验；发布脚本测试及 workflow 静态校验通过。

### #48：本地环境初始化

- 从当前 TOML 解析完整 setup 脚本，在临时目录用命令替身测试 `sh`、`bash`、`zsh`，共 15/15 场景通过。
- CodeGraph 缺失时退出 `0`，存在且初始化成功时退出 `0`；Tuist 失败保留 `31/32` 且不继续索引；索引失败保留 `33`。
- 已安装的 CodeGraph 初始化失败时终止，符合该 PR 明确说明的行为。

## 验证结果与环境限制

| 检查 | 结果 |
| --- | --- |
| 四个 PR 的 GitHub CI | 12 个检查全部成功：各 PR 的 Format、Tests、Release Scripts |
| 本地 `tuist generate --no-open` | 通过，Tuist `4.214.1` |
| 原始 HEAD 的 macOS 测试构建 | 编译、链接通过；测试宿主建立连接前崩溃，未执行测试 |
| 隔离副本的完整 XCTest | 143 项：原有 141 项逐一通过；新增的 2 项审计回归用例按预期失败 |
| SwiftFormat `0.62.1` | 48 个文件中 0 个需要格式化；下载包与仓库固定 SHA-256 一致 |
| actionlint `1.7.12` | 两个 workflow 均通过；下载包已按官方 checksum 验证 |
| `script/test_release_scripts.sh` | 通过 |
| `git diff --check v0.10.1..HEAD` | 通过 |
| setup 命令替身 | 3 种 shell × 5 场景，15/15 通过 |

本机仅有 Xcode `27.2`；PR CI 使用 Xcode `26.5`。原始测试启动崩溃的调用链为 `AppFeature.State` 的 file storage 默认值 → `Dependencies.TestContext` → `IssueReporting._currentTest()` → Swift Testing 类型信息 → Objective-C runtime，异常为 `EXC_BREAKPOINT`。

隔离副本额外将锁定版本 `1.9.0` 已提供的动态产品 `IssueReportingTestSupport` 链接到 App 和测试目标，改用库的测试桥接入口，随后测试宿主正常启动。15 个依赖 pin 与仓库锁文件逐项一致，业务源码保持 HEAD 内容；仅额外追加了上述两个测试。官方测试桥接机制可见[项目文档](https://github.com/pointfreeco/xctest-dynamic-overlay/blob/main/_autodocs/api-reference/09-IssueReportingTestSupport.md)。

因此，隔离验证不能表述为“原始 HEAD 在 Xcode 27.2 原样通过完整测试”。原始宿主崩溃属于本次验证限制，尚未证明由这四个 PR 引入；本次范围没有修改依赖锁文件、工程 manifest 或 App 启动入口。

未执行真实系统输入法切换、macOS 14 实机/UI 测试或真实发布流程。checkout 升级后的发布分支通过静态及脚本验证，尚无该升级后的真实 release workflow 执行记录。

## 本地证据

以下为本次审计的临时产物，位于 `/tmp`，系统清理临时目录后可能失效：

- PR 元数据、编译/测试日志和校验摘要：`/tmp/typeswitch-pr-audit-20261107/`。
- 原始宿主失败结果：`/tmp/typeswitch-pr-audit-20261107/FullTestsPinned.xcresult`。
- 隔离测试结果：`/tmp/typeswitch-pr-audit-20261107/IsolatedTests.xcresult`。
- 两项 reducer 测试附加代码：`/tmp/typeswitch-pr-audit-20261107/AvailabilityAuditRegressionTests.swift`。
- 测试迁移逐方法 diff：`/tmp/typeswitch-pr-audit-20261107/test-migration.diff`。
- base/HEAD 的纯 Swift 目录及存储对照：`/private/tmp/typeswitch-availability-pr46-repro/`。

上述审计阶段未修改业务代码和已有测试，复现和兼容性实验均在临时目录完成；后续修复记录如下。

## 修复记录（2026-11-07）

- 根 `AppFeature` 以规则路径的值副本比较动作处理前后的变化，同步探测新增或变化的路径并更新可用性。这也覆盖 `SwitchingFeature` 通过 Shared 存储更新记录的应用激活、启动加载和前台重试入口。
- 探测结果为不存在时移除对应的旧可用结果；名称或策略变化不会触发路径探测。菜单只读计算、重复展示和 README demo 保持不访问真实文件系统的行为。
- 增加 5 项测试：菜单期间新增运行应用、运行应用路径变化、激活更新路径、名称/策略变化不重复探测、重新探测已缓存但失效的路径。既有清理重探测与 ignored 规则保护测试继续通过。
- `CHANGELOG.md` 的 `Unreleased` 已补充中英文修复说明。

验证过程与结果：

1. 在修复前运行前两项回归测试，两项均失败，确认能够复现原问题。
2. 修复后在同一隔离环境运行完整 XCTest：**146 项通过，0 失败**。
3. 核对隔离副本中全部 44 个业务/测试 Swift 文件，均与当前工作区逐字一致；15 个依赖 pin 与仓库锁文件一致。
4. SwiftFormat `0.62.1`：48 个 Swift 文件中 0 个需要格式调整；`git diff --check` 与 `script/test_release_scripts.sh` 通过。

本机 Xcode 27.2 的原始测试宿主兼容性限制仍存在，完整测试继续使用前述隔离工程的同版本 `IssueReportingTestSupport` 桥接库；工作区工程配置和依赖未因该实验而修改。

修复验证证据位于 `/tmp/typeswitch-pr-audit-20261107/`：`FixRedTests.xcresult`、`FixGreenTests.xcresult`、`fix-red-tests.log`、`fix-green-tests.log` 和 `fix-verification-summary.json`。

## 修复后的复审（2026-11-07）

业务逻辑与测试证据分别进行独立复核后，未发现新的需修复问题。

- 核对 TCA 1.26.0 的实际 `onChange` 实现及所有记录更新入口，确认路径字典的值副本能检测子模块通过 Shared 同步更新的路径，且没有改变取消和过期结果守卫的顺序。
- 独立核对日志、xcresult 测试树、实际依赖 checkout 和工程差异，确认原有 141 项测试保留，隔离副本与当前业务/测试源码一致；测试桥接库的失败入口确实转发 `XCTest.XCTFail`。
- 重新运行完整 XCTest：**146 项通过，0 失败**。另在独立临时副本增加 3 项边界测试，覆盖非空路径到空路径再恢复、首次前台加载及有效/过期重试、README demo 路径变化不探测，**3 项全部通过**。
- SwiftFormat 与 `git diff --check` 再次通过。本轮没有修改业务代码或正式测试文件。

验证继续使用同版本测试桥接库的隔离工程，不能视为原始工程已在 Xcode 27.2 原样运行测试。真实输入法、macOS 14 和 UI 行为仍未执行实机验证。

复审证据：`/tmp/typeswitch-pr-audit-20261107/RereviewTests.xcresult`、`RereviewBoundaryTests.xcresult`、`rereview-tests.log`、`rereview-boundary-tests.log`、`rereview-boundary-tests.swift`。
