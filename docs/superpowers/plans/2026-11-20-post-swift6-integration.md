# Swift 6 后续升级与联调 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本次交付只有排查和计划；以下任务尚未实施。

**Goal:** 在已经完成的 Swift 6 迁移上，补齐持续检查、普通账号、保留数据升级和失败恢复的证据，明确生产开放前的剩余合同。

**Architecture:** 继续使用现有 MainActor 状态所有者、模块 worker、NoteLocalStore、NoteSyncCoordinator 和 Merge 生命周期。编译门禁与真实后端联调分别验收，沿用现有测试、作用域和回执，不新建产品调度层或持久状态。后端合同变更由对应 Go 模块负责，不能通过放宽客户端校验代替。

**Tech Stack:** Swift 6、SwiftUI/WebKit、XCTest/SwiftPM、Python 检查脚本；本地 Go/PostgreSQL/Redis/对象存储与 Python Agent。

**Spec:** 用户要求“提交 push 到 main，然后排查下一步升级和联调计划”；[执行边界](../../architecture/execution.md)、[真实联调记录](../../qa/2026-11-20-ios-live-integration.md)、Go [离线同步](../../../../Chorai_Go/docs/modules/offline-sync.md)、[Merge](../../../../Chorai_Go/docs/modules/merge.md) 与[媒体合同](../../../../Chorai_Go/docs/modules/media.md)。

## 当前基线与升级判断

核对日期：2026-11-20。iOS 代码提交 `9ccbeeae866abc753618c5107f234f410484d635` 已推送 `main`；Go 排查基线为 `67de388baa5ae5a70d1beeb2b6124783476c751a`。当前运行中的本地服务不能仅凭仓库 HEAD 被认作该版本，下一次联调需要记录实际构建来源。

| 项目 | 已确认状态 | 下一步 |
| --- | --- | --- |
| 自有 Swift 代码 | App、CoreFlow、BlockNoteEditor 及测试均为 Swift 6；九组 Xcode 配置开启 complete 检查 | 迁移已完成，新增代码使用同一门禁 |
| 工具链与兼容性 | 本次 Xcode 27.2 / Swift 6.4.2；workspace 要求 Swift tools 6.2+；保留 iOS 16 | 固定可复现工具链；旧系统运行和签名发布另验 |
| 执行语义 | 默认 MainActor 与 Approachable Concurrency 均未启用 | 保持显式 worker 和当前隔离；不全局切换 |
| 自动检查 | `make check-concurrency` 完整通过；根目录尚无接入该命令的 GitHub workflow | Task 1 固化必跑模拟器检查并接入 CI |
| 真实同步 | 本轮 UI 成功路径使用管理员；常规门禁跳过六项需凭据的 M1/M2 live API 测试 | Task 2–3 使用普通用户和匹配协议分别验收 |
| App 升级 | 新版本重启已验证；未验证旧二进制覆盖安装后的数据连续性 | Task 4 保留容器覆盖安装 |
| Merge | 最终真实成功路径通过；此前 `TEXT_PROVIDER_FAILED` 原因未确认 | Task 5 补齐故障分类与恢复证据 |
| 生产同步 | Go 拒绝生产 profile 启用 M1/M2 本地开关 | 独立完成跨写入者、保留和删除合同后再开放 |

Swift 的 `NonisolatedNonsendingByDefault` 会改变 nonisolated async 的执行位置，`@concurrent` 可显式离开调用者 actor；因此不能把新并发开关当作无行为变化的配置升级。参见 [Swift 官方说明](https://docs.swift.org/latest/documentation/diagnostics/nonisolated-nonsending-by-default/)。现有 `@unchecked Sendable` 需要按锁、SDK 和对象寿命逐个审查，不以数量归零为目标，也不批量升级无具体问题的依赖。

## Global Constraints

- 保留 iOS 16.0、package macOS 13、Swift 6 与 `SWIFT_STRICT_CONCURRENCY = complete`；workspace 要求 Swift tools 6.2 或更新。
- `SWIFT_DEFAULT_ACTOR_ISOLATION` 保持 nonisolated，`SWIFT_APPROACHABLE_CONCURRENCY` 保持 NO。
- UI、鉴权决定和发布留在 MainActor；昂贵计算使用显式后台执行边界；迟到结果必须复核账号、环境、修订和操作身份。
- 已接受的编辑事件须 drain 并按原 scope 持久化；重试复用冻结 operation ID 和请求正文。
- 默认 Local；Production 只构建。本计划不启用生产同步、不发布、不修改既有用户数据。
- 使用专用模拟器、测试账号和隔离存储；凭据不进入仓库、日志或结果摘要。
- 各任务先复现缺口，再做最小改动；源码变更同时更新执行边界、历史和验收记录。后端变更遵循所属模块及 `make check-docs`。

## Review Focus

1. 没有模拟器、selector 拼错或测试被跳过时，CI 不能显示完整回归通过（Task 1）。
2. 普通用户被拒绝、撤权或换号后，旧本地内容和迟到 ACK 不能进入新账号；合法离线授权仍按当前合同生效（Task 2–3）。
3. 旧版本存在未同步图文和冻结操作时，覆盖升级不能换本地 ID、丢附件或产生重复版本（Task 4）。
4. 上传/写入已提交但回执丢失时，重试不能更换请求身份；冲突必须保留两份内容（Task 2）。
5. 模型调用失败、取消或结果未知时，重启和重试不能绕过权限、产生重复提交或无证据重复付费（Task 5）。

## Task 1 — P0：把本地门禁接成持续检查

**Files:** 修改 `scripts/check-concurrency.py`、`scripts/tests/test_check_concurrency.py`、`Makefile`；新增 `scripts/ios-ui-gate-selectors.json`、`.github/workflows/ios-concurrency.yml`；更新执行边界及历史。

**Interfaces:** 现有命令兼容保留；新增 `--require-simulator` 与 `--ui-selectors-file <path>`。selector 文件为完整 `bundle/class/method` 字符串数组。CI 必须指定前者和明确的模拟器 UUID；不指定新参数时仍可进行原有本地检查。

- [ ] 增加 runner 回归：缺少必需模拟器须在构建前失败；空/重复/非法 selector 拒绝；不同 class 的同名方法不能互相替代；missing、Skipped、Failed 或混合结果均失败；仅全量 Passed 成功。先运行 `python3 -B -m unittest discover -s scripts/tests -p 'test_*.py'`，确认新增条件失败。
- [ ] 将既有 xcresult 精确匹配逻辑推广到传入的完整 selector；沿用当前临时编译目录、日志与结果留存，不另造测试框架。
- [ ] 将现有六项 editor UI 加上下列四项形成十项日常门禁。保留历史 47 项迁移清单原样。

```text
ArcNoteUITests/ArcNoteUITests/testMergeArtifactEditsInPlaceAndRestoresDraft
ArcNoteUITests/ArcNoteUITests/testNativeFidelityHomeMenuOpensRealUnboxedEditor
ArcNoteUITests/NativeRemediationVisualTests/testTrashCancelAndRejectedDeleteKeepTheOriginalNote
ArcNoteUITests/ArcNoteUITests/testHomeRemovalKeepsLocalTrashWhenSyncIsUnavailable
```

- [ ] 核实仓库可用的 macOS runner，再固定 workflow 的 runner、`DEVELOPER_DIR`、Xcode/runtime 版本与专用模拟器创建步骤。目标复用本次通过的 Xcode 27.2；替代工具链先跑同一门禁，不能假设 `macos-latest` 自带所需版本。没有兼容 runner 时记录“尚未接入 CI”，保留可运行本地门禁，不能宣称 CI 已完成。
- [ ] workflow 在 PR/main 执行强制模拟器门禁，凭据权限只读；只缓存下载，不复用编译产物；失败也保留日志/xcresult。生产环境仍只构建。
- [ ] 运行 runner 回归与 `IOS_DEVICE=<专用 UUID> python3 scripts/check-concurrency.py --require-simulator --ui-selectors-file scripts/ios-ui-gate-selectors.json`。验收：三种构建、两个 package、App 测试和十项 UI 全部通过；六项 opt-in API 跳过在结果中单独声明。再核对实际 CI run 后独立提交。

## Task 2 — P1：在真实后端重跑现有六项同步合同

**Files:** 复用 `Packages/CoreFlow/Tests/CoreFlowTests/NoteSyncLiveAPITests.swift`、`NoteSyncM2LiveAPITests.swift`；在 `docs/qa/` 新增本轮协议验收记录。只有发现实际缺陷才修改对应 store/coordinator/service，并增加失败回归。

**Interfaces:** M1 使用 `CHORAI_M1_SESSION_FILE`；M2 使用 `CHORAI_M2_SESSION_FILE` 和 `CHORAI_M2_IMAGE_FILE`。会话文件沿用现有 `{login: {data: {user: {id}, token}}, api_base_url}`，只允许 loopback。测试主体为普通账号，具有通过现有服务授予的有效准入；不能用 admin bypass 替代。

- [ ] 通过现有账号/准入流程准备普通测试账号，核对实际 access 状态与离线资格。记录真实构建的 iOS、Go、Agent 版本、runtime 和协议；健康检查不能代替来源核对。
- [ ] 在隔离 dev/test 后端分别启用 M1 protocol 2、M2 protocol 3。两开关互斥；不能拿同一次 M2 配置认定 M1 通过。M2 使用合格且身份分离的 history/staging 对象存储。
- [ ] 带对应私有环境文件执行 `swift test --package-path Packages/CoreFlow --filter NoteSyncLiveAPITests`，逐项核对三项结果：已提交回执丢失后重放同一版本；并发写冲突保留双方且另存不覆盖；删除恢复拒绝旧正文基准。
- [ ] 切换匹配的隔离协议与会话后，执行 `swift test --package-path Packages/CoreFlow --filter NoteSyncM2LiveAPITests`，逐项核对三项结果：上传/正文回执丢失仍复用身份；离线删除恢复保留脏图文；持久 transient failure 以冻结请求恢复。
- [ ] 验收每组恰好三项 Passed、零 skipped/failed，正文与附件 hash、operation ID、请求字节及 receipt 断言均生效；保留脱敏证据。缺凭据或缺后端明确判为未完成，不把普通门禁中的 skip 转述为通过。按实际失败补回归，完成后独立提交证据/修复。

## Task 3 — P1：普通账号的原生 UI 与换号隔离

**Files:** `ArcNoteUITests/ArcNoteUITests.swift`、现有 `RecentNotesSyncUITests.swift` 夹具；复用 `ArcNoteTests/AuthNoteAccessTests.swift` 与 CoreFlow access/offline 测试。必要修复仍归 `AuthManager`、`LocalNotesController`、`NoteSyncCoordinator`。

**Interfaces:** 使用 Task 2 的普通账号 A，再准备互不授权的账号 B；沿用现有 loopback fixture 的阻塞/放行控制和本地后端辅助方法。不能通过任意 sleep 模拟迟到回执，也不能直接写入离线授权文件绕过真实准入。

- [ ] 新增 `testLocalGoOrdinaryAccountOfflineReopenAndSync`：A 在线获得合法准入，编辑图文；断开测试网络后修改并终止；重启保留正文/附件与未同步状态；恢复后同一笔记同步，API 与显示内容一致。
- [ ] 新增 `testLocalGoAccountSwitchRejectsOldSync`：在 A 请求待返回时退出并登录 B，再放行旧响应；B 无 A 的正文、缩略图或状态；回到 A 时原操作按其真实提交状态恢复。用确定性夹具钉住时序，再在真实 API 验证两账号数据隔离。
- [ ] 复用 `testRevokedSessionRelaunchReturnsToWelcome`、`testOfflineSessionVerificationKeepsRestoredShell` 和现有 access tests；补齐普通账号 denied/revoked/expired 组合。按现有 access 合同区分“在线拒绝”和“原有离线资格”，不能因错误响应发放新 grant。
- [ ] 以普通账号重跑本次 Home 编辑/重启/Trash/恢复/永久删除流程、profile/settings 和 search/detail；逐项验 exact selector、服务器内容和截图。永久删除只用该任务数据。
- [ ] 验收上述新 UI、现有鉴权/生命周期回归与三构建通过；记录账号类型，不记录 token。发现产品问题先有失败证据再最小修复，独立提交。

## Task 4 — P1：旧版覆盖升级，保留未同步数据

**Files:** 新增 `scripts/check-ios-upgrade.sh`（仅构建/安装顺序与结果收集）、`docs/qa/` 升级记录；在 `ArcNoteUITests/ArcNoteUITests.swift` 加升级后的断言。复用现有持久化模型，不预设需要 schema 迁移。

**Interfaces:** 脚本接收明确的旧版本 `.app`、新版本 `.app`、专用模拟器 UUID 和结果目录；校验相同 bundle ID 后使用 `simctl install` 覆盖。旧版本取迁移前 `a46f21e982be4ab752629e9076e159f89a0adb1d` 的隔离 checkout/构建产物；不切换或 reset 当前工作区。

- [ ] 用旧 App 实际创建已同步文字、带图未同步草稿、已冻结待确认操作和 Trash 数据；在 Task 2 的普通账号/协议下记录本地 UUID、正文/附件 hash、修订与待提交身份，日志不包含正文或凭据。
- [ ] 终止旧 App，覆盖安装新版本；禁止 uninstall、erase 或新建替代数据，测试启动参数不得重置本机库或离线授权。记录安装前后同一 app 数据容器与笔记身份。
- [ ] 新增 `testLocalGoUpgradePreservesPendingNoteAndAttachments`：新 App 重开后断言记录保留；UI 可编辑、图片可见、Trash 正确；网络恢复后精确 ACK 清理对应操作且无重复版本。
- [ ] 再验证升级后立刻退出/换号与 editor drain；旧 scope 的草稿不得泄露给新账号。若发现持久格式不兼容，先明确可逆迁移与回退合同，再更改存储实现。
- [ ] 验收真实覆盖安装记录、精确数据一致性断言及相关 CoreFlow/hosted/UI 回归通过；独立提交脚本、测试和证据。普通新装/重启通过不能代替本项。

## Task 5 — P2：Merge 故障定位与图文/导入分支

**Files:** Go 仓库内先读 `chorai-go/internal/merge/vnext/app/run.go`、`chorai-go/internal/merge/vnext/app/worker_failure.go`、`chorai-go/internal/merge/vnext/tools/runtime/types.go`、`chorai-go/internal/merge/vnext/observability/context.go`，以及 `Chorai_Agent/agents/merge_vnext/provider_wiring.py`、`Chorai_Agent/agents/merge_vnext/pipeline.py` 与现有测试；iOS 复用 `ArcNoteUITests/ArcNoteUITests.swift` 和 `Packages/CoreFlow/Tests/CoreFlowTests/NoteImportStoreTests.swift`。

**Interfaces:** 沿用现有 job/stage correlation 与 `DispatchCode` 类型，核对既有 generation/provider trace。只有现有证据确实丢失分类时才在所属边界补最小诊断；不新建诊断数据库，不记录 prompt、URL、token 或原始模型正文。

- [ ] 对之前 `TEXT_PROVIDER_FAILED` 尝试关联原 job、stage、Go dispatch 和 Python provider 证据。当前只证明后续成功，尚未证明首次失败原因；若原证据不足，保留“原因未确认”。
- [ ] 通过受控 provider/transport 故障覆盖 unavailable、timeout、非法输出、明确拒绝、取消和调用结果未知。断言持久终态、客户端可恢复动作、晚到结果拒绝与原有调用预算，不把结果未知当成未调用自动重试。
- [ ] 使用既有 `worker_failure_test.go`、`test_provider_wiring.py` 和 UI cancel/relaunch 用例验证分类或恢复修复；先 RED 后 GREEN。真实 gRPC 联调确认同一 job/stage 的端到端诊断，不改公开错误语义来掩盖内部问题。
- [ ] 补真实多图来源 Merge：上传与 visual evidence 就绪 → 冻结来源版本 → 生成 → 编辑/提交 → 重启；核对媒体、来源关系和权限。文字成功路径不代表视觉路由已覆盖。
- [ ] 检查文件导入取消与上传结束的寿命边界，确保 security-scoped 文件直到传输终止才释放。Go 逐项 import 的 Action/source-state/archive/outcome 非原子问题另作所属模块的恢复设计，不能以客户端取消测试认定已解决。
- [ ] 验收相关 Go/Python 测试、gRPC 和 iOS 精确场景通过后，分别在拥有改动的仓库提交，并更新对应当前模块与历史。

## 后续独立项目：生产开放与发布验收

这部分不能与 Swift 语言迁移合并为“升级已完成”。进入实施前，在 Go 离线同步/Merge/媒体模块记录短设计和验收。

1. 列出所有 NOTE 写入者：原生编辑、Web、Import/Fork/Merge、Link/Unlink、分享与修复入口；逐项证明 base、Action、幂等 receipt、权限再校验及媒体保留归属。
2. 在真实 PostgreSQL 与 versioned object store 验证并发提交、撤权、删除/恢复、永久擦除、崩溃与回执丢失。生产配置仍拒绝本地协议开关，不能只删掉 guard 来“上线”。
3. 合同与服务能力通过后，再验签名 Archive/TestFlight、真实 Apple/Google 登录、最低支持系统、权限取消、后台/终止和覆盖升级。实际发布按届时授权执行。
4. 真机性能采样恢复后补时延与内存数据；它不阻塞上述编译、模拟器和故障合同验证。本计划不作未经测量的性能提升承诺。

## 执行顺序与完成条件

推荐从 Task 1 开始，再做 Task 2 → Task 3/4 → Task 5；每个任务独立提交、保留证据。生产开放另起明确设计，避免边补测试边改变跨端写入合同。

计划自查：五项 Review Focus 均有对应任务；历史缺陷没有被移出验收或重复算作本次通过；保留普通用户与管理员区别、M1/M2 配置互斥、实际运行版本与仓库 HEAD 区别；CI runner、旧系统运行、签名发布和生产合同均明确为尚未验收。此计划没有执行上述新任务。
