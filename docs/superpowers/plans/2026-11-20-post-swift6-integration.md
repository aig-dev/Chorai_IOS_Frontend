# Swift 6 后续优化与首次上线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 当前按本计划逐项实施；完成状态以任务复选框和验收证据为准。

**Goal:** 在已经完成的 Swift 6 迁移上，补齐并发行为、关键业务恢复和生产写入合同，使尚未上线的产品具备首次上线条件。

**Architecture:** 继续使用现有 MainActor 状态所有者、模块 worker、NoteLocalStore、NoteSyncCoordinator 和 Merge 生命周期。编译门禁与真实后端联调分别验收，沿用现有测试、作用域和回执，不新建产品调度层或持久状态。后端合同变更由对应 Go 模块负责，不能通过放宽客户端校验代替。

**Tech Stack:** Swift 6、SwiftUI/WebKit、XCTest/SwiftPM、Python 检查脚本；本地 Go/PostgreSQL/Redis/对象存储与 Python Agent。

**Spec:** 用户进一步明确：产品完全未上线，不考虑旧版本数据迁移，目标是推进到上线 ready；[执行边界](../../architecture/execution.md)、[真实联调记录](../../qa/2026-11-20-ios-live-integration.md)、Go [离线同步](../../../../Chorai_Go/docs/modules/offline-sync.md)、[Merge](../../../../Chorai_Go/docs/modules/merge.md)、[Chat](../../../../Chorai_Go/docs/modules/chat.md)、[Auth](../../../../Chorai_Go/docs/modules/auth.md) 与[媒体合同](../../../../Chorai_Go/docs/modules/media.md)。

**Scope correction:** 移除旧 App 覆盖升级、历史用户迁移和旧协议长期兼容任务。首次安装后新产生的数据仍须验证保存、断网、杀进程、换号、冲突和重试；这些属于当前产品可靠性。下文区分已确认的生产限制、代码审查发现的风险和仍需测量的优化候选，不把候选写成已复现故障。

## 当前基线与升级判断

核对日期：2026-11-20。iOS 代码提交 `9ccbeeae866abc753618c5107f234f410484d635` 已推送 `main`；Go 排查基线为 `67de388baa5ae5a70d1beeb2b6124783476c751a`。当前运行中的本地服务不能仅凭仓库 HEAD 被认作该版本，下一次联调需要记录实际构建来源。

| 项目 | 已确认状态 | 下一步 |
| --- | --- | --- |
| 自有 Swift 代码 | App、CoreFlow、BlockNoteEditor 及测试均为 Swift 6；九组 Xcode 配置开启 complete 检查 | 迁移已完成，新增代码使用同一门禁 |
| 工具链与兼容性 | 本次 Xcode 27.2 / Swift 6.4.2；workspace 要求 Swift tools 6.2+；保留 iOS 16 | 固定可复现工具链；旧系统运行和签名发布另验 |
| 执行语义 | 默认 MainActor 与 Approachable Concurrency 均未启用 | 保持显式 worker 和当前隔离；不全局切换 |
| 自动检查 | `make check-concurrency` 完整通过；根目录尚无接入该命令的 GitHub workflow | Task 1 固化必跑模拟器检查并接入 CI |
| 真实同步 | 本轮 UI 成功路径使用管理员；常规门禁跳过六项需凭据的 M1/M2 live API 测试 | Task 2–3 验证所选上线合同与普通新用户；不为历史协议单列上线门槛 |
| 聊天 | 主线程解析 SSE；SwiftUI body 调用消息排序/日期格式化；重叠消息刷新未见响应代际校验 | Task 4 先补请求归属，再消除重复计算和读取 |
| 原图与文件 | 缩略图已有有界队列；编辑器原图读取逐请求创建 Task，原文件读写使用 detached task | Task 6–7 审查取消边界、真实并发和占用；尚无真机性能结论 |
| 导入 | Task 8 已完成原子提交、请求重放与实际重启恢复 | 保留 Task 6 上传桥接时序和整体普通账号验收 |
| Merge | 最终真实成功路径通过；此前 `TEXT_PROVIDER_FAILED` 原因未确认 | Task 5 补齐故障分类与恢复证据 |
| 生产同步 | Go 拒绝生产 profile 启用 M1/M2 本地开关 | Task 2 为首次上线 P0，完成所选合同的生产接线和验收 |

Swift 的 `NonisolatedNonsendingByDefault` 会改变 nonisolated async 的执行位置，`@concurrent` 可显式离开调用者 actor；因此不能把新并发开关当作无行为变化的配置升级。参见 [Swift 官方说明](https://docs.swift.org/latest/documentation/diagnostics/nonisolated-nonsending-by-default/)。现有 `@unchecked Sendable` 需要按锁、SDK 和对象寿命逐个审查，不以数量归零为目标，也不批量升级无具体问题的依赖。

## Global Constraints

- 保留 iOS 16.0、package macOS 13、Swift 6 与 `SWIFT_STRICT_CONCURRENCY = complete`；workspace 要求 Swift tools 6.2 或更新。
- `SWIFT_DEFAULT_ACTOR_ISOLATION` 保持 nonisolated，`SWIFT_APPROACHABLE_CONCURRENCY` 保持 NO。
- UI、鉴权决定和发布留在 MainActor；昂贵计算使用显式后台执行边界；迟到结果必须复核账号、环境、修订和操作身份。
- 已接受的编辑事件须 drain 并按原 scope 持久化；重试复用冻结 operation ID 和请求正文。
- 当前排查默认 Local、Production 只构建。生产同步接线先完成所属模块设计，再做隔离生产配置验收；实际部署另按届时授权执行。
- 使用专用模拟器、测试账号和隔离存储；凭据不进入仓库、日志或结果摘要。
- 各任务先复现缺口，再做最小改动；源码变更同时更新执行边界、历史和验收记录。后端变更遵循所属模块及 `make check-docs`。

## Review Focus

1. 没有模拟器、selector 拼错或测试被跳过时，CI 不能显示完整回归通过（Task 1）。
2. 普通用户被拒绝、撤权或换号后，旧本地内容和迟到 ACK 不能进入新账号；合法离线授权仍按当前合同生效（Task 2–3）。
3. 聊天事件连发、断线重放或读取乱序时，旧结果不能覆盖新消息、结束新一轮等待或重复发布（Task 4）。
4. 上传/写入已提交但回执丢失时，重试不能更换请求身份；冲突必须保留两份内容（Task 2）。
5. 模型/导入调用失败、取消或结果未知时，重启和重试不能绕过权限、产生重复提交或无证据重复付费（Task 5、8）；图片任务取消也不能提前释放仍被占用的资源名额（Task 6–7）。

## Task 1 — 横向保障：把本地门禁接成持续检查

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
- [ ] 运行 runner 回归与 `IOS_DEVICE=<专用 UUID> python3 scripts/check-concurrency.py --require-simulator --ui-selectors-file scripts/ios-ui-gate-selectors.json`。验收：三种构建、两个 package、App 测试和十项 UI 全部通过；六项 opt-in API 跳过在结果中单独声明。独立提交本地门禁。
- [ ] 接入后核对实际 PR/main CI run、日志和 xcresult。

本地入口为 `make check-concurrency-required IOS_DEVICE=<专用 UUID>`。仓库可用的 macOS runner 和 Xcode 27.2 / iOS runtime 兼容性尚待核实，门禁尚未接入 CI。

## Task 2 — P0：普通笔记生产同步闭环

**Files:** iOS 复用 `Packages/CoreFlow/Tests/CoreFlowTests/NoteSyncLiveAPITests.swift`、`NoteSyncM2LiveAPITests.swift` 及现有 store/coordinator/service。Go 从 `docs/modules/offline-sync.md`、`offline-sync.history.md`、`chorai-go/cmd/server/note_sync_local.go` 和 `chorai-go/internal/ontology/services/card_sync_*.go` 进入；更改合同先记录短设计。

**Interfaces:** 生产采用一个明确的写入合同，复用既有 preparation、条件 Action、exact store 和 receipt；不引入新协议来绕过现有权限/版本/保留约束。现有 M2 测试使用 `CHORAI_M2_SESSION_FILE` 与 `CHORAI_M2_IMAGE_FILE`，会话文件沿用 `{login: {data: {user: {id}, token}}, api_base_url}`，只允许 loopback。普通账号通过现有服务获得有效准入，不能用 admin bypass 替代。

- [ ] 通过现有账号/准入流程准备普通测试账号，核对实际 access 状态与离线资格。记录真实构建的 iOS、Go、Agent 版本、runtime 和协议；健康检查不能代替来源核对。
- [ ] 对首发可达的原生编辑、Web、Import/Fork/Merge、Link/Unlink、分享入口列出 base、权限、Action、receipt 和媒体保留归属；功能范围未明确裁剪前，不默认为某入口已下线。排除旧用户迁移任务，保留这些入口新产生数据的一致性要求。
- [ ] 在 Go 模块明确最终服务组合和能力探测，复用现有实现补齐生产路径；不能只移除 dev/test guard。M2 本地测试先使用合格且身份分离的 history/staging 存储，之后对最终生产合同复验同一业务断言。
- [x] 执行 `swift test --package-path Packages/CoreFlow --filter NoteSyncM2LiveAPITests`，要求三项 Passed、零 skipped/failed：上传/正文丢回执复用身份、离线删除恢复保留脏图文、持久 transient failure 以冻结请求恢复。
- [ ] 将现有 M1 测试中并发冲突保留双方、另存不覆盖和旧基准拒绝等必要断言用于所选上线合同。M1 可继续作为历史回归，不因未上线产品而要求上线兼容两种本地协议。
- [ ] 用真实 PostgreSQL 和 versioned 对象存储验正文、附件、删除/恢复/永久擦除、撤权、第二写入者及提交中断。验收当前客户端不再依赖 dev-only 开关即可按最终合同同步，operation ID/请求/receipt 精确，且没有重复事实或误删媒体。缺能力明确失败，不能显示已同步。

普通账号基线与分享缺图修复见 [2026-11-21 验收](../../qa/2026-11-21-ordinary-note-sync.md)。当前 dev protocol 3 的六项实际 API 与完整 CoreFlow 1071 项通过、零跳过；最终生产合同及生命周期接线仍未完成。

后续关联切片见 [Link / 生命周期验收](../../qa/2026-11-21-link-lifecycle.md)：公开 Link / Unlink、条件删除／恢复与 iOS / Web 精确请求已接线，双向关联删除、恢复不复活、旧请求不误删新关联以及真实编辑器通过；审查修复自动保存／关联读取竞态后，完整门禁更新为 CoreFlow 1,089、编辑器 76、App 101 和六项 UI，零跳过。永久删除仍缺完整执行编排，现有 preparation / proof 组件不能等同完整 runner；擦除、Merge 来源与全部写入者生产组合保持未完成。

## Task 3 — P0：首次使用、普通账号与换号隔离

**Files:** `ArcNoteUITests/ArcNoteUITests.swift`、现有 `RecentNotesSyncUITests.swift` 夹具；复用 `ArcNoteTests/AuthNoteAccessTests.swift` 与 CoreFlow access/offline 测试。必要修复仍归 `AuthManager`、`LocalNotesController`、`NoteSyncCoordinator`。

**Interfaces:** 使用 Task 2 的普通账号 A，再准备互不授权的账号 B；沿用现有 loopback fixture 的阻塞/放行控制和本地后端辅助方法。不能通过任意 sleep 模拟迟到回执，也不能直接写入离线授权文件绕过真实准入。

- [ ] 新增 `testLocalGoOrdinaryAccountOfflineReopenAndSync`：A 在线获得合法准入，编辑图文；断开测试网络后修改并终止；重启保留正文/附件与未同步状态；恢复后同一笔记同步，API 与显示内容一致。
- [ ] 从空容器/普通新账号走真实注册或登录 → 准入 → 当前 iOS canonical onboarding v1 → 第一篇笔记 → Explore/Spark/Merge → Chat。逐项核对真实状态推进，不用管理员账号或 preview 跳过前置条件；后端默认 v2 不代表需要改动原生已选流程。
- [ ] 新增 `testLocalGoAccountSwitchRejectsOldSync`：在 A 请求待返回时退出并登录 B，再放行旧响应；B 无 A 的正文、缩略图或状态；回到 A 时原操作按其真实提交状态恢复。用确定性夹具钉住时序，再在真实 API 验证两账号数据隔离。
- [ ] 复用 `testRevokedSessionRelaunchReturnsToWelcome`、`testOfflineSessionVerificationKeepsRestoredShell` 和现有 access tests；补齐普通账号 denied/revoked/expired 组合。按现有 access 合同区分“在线拒绝”和“原有离线资格”，不能因错误响应发放新 grant。
- [ ] 以普通账号重跑本次 Home 编辑/重启/Trash/恢复/永久删除流程、profile/settings 和 search/detail；逐项验 exact selector、服务器内容和截图。永久删除只用该任务数据。
- [ ] 验收上述新 UI、现有鉴权/生命周期回归与三构建通过；记录账号类型，不记录 token。发现产品问题先有失败证据再最小修复，独立提交。

## Task 4 — P0 正确性 / P1 性能：聊天读取、SSE 与展示准备

**Files:** `ArcNote/Models/ChatModels.swift`、`ArcNote/ChatDetailView.swift`、`ArcNote/NetworkManager.swift`、`Packages/CoreFlow/Sources/CoreFlow/ChatAgentDelivery.swift`、`ChatHistoryVisibility.swift`；新增并注册 `ArcNoteTests/ChatDetailManagerTests.swift`，复用既有 CoreFlow Chat tests。

**Interfaces:** 聊天 manager 继续拥有 UI 与会话；读请求绑定账号/会话/请求代际，SSE 保持当前 cursor 与 source-message 语义。准备好的展示值只在消息/权限/头像/时间显示条件变化时更新，View 不重新完成排序和日期解析。

- [x] 用可控 fetcher 添加 `testOlderMessageRefreshCannotReplaceNewerResponse`、`testEventBurstCoalescesRefreshWithoutLosingLatestMessage`、`testRetiredConversationRejectsLateMessagesAndHydration`，先证明当前重叠读取行为。断言旧响应、旧错误和旧 loading completion 均不能更新新请求状态。
- [x] 在现有 manager 内合并同会话刷新并复核请求身份；请求中发生的新事件须触发一次后续读取，不能简单丢弃。停止会话时取消所属读取及 hydration，并拒绝迟到回调；保留当前最新页语义，不先新增消息 API。
- [x] 补 SSE 断线重连、重复事件、旧消息失败与新回复等待同时存在的运行测试，沿用 cursor 和消息 ID；不得以“编译通过”代替顺序/去重验证。
- [x] 记录现有 20 条分页和独立压力样本下的排序、时间解析、事件解析及请求次数。`convertToChatMessages()` 当前在 View body 被调用，比较器反复创建日期 formatter；先复用已有日期原语、预解析并缓存展示结果，移除重复工作。
- [x] 对仍有显著计算的准备/流解析使用模块已有执行边界或一个确有职责的 worker，保留事件顺序与最终 MainActor 发布；不为小对象机械创建 detached task。性能证据标明模拟器/合成样本，不能当作真机 p95。
- [ ] 验收真实 Chat 发送、回复、断线恢复、切会话和换号；相关 CoreFlow/hosted/UI 测试、三构建与完整并发门禁通过，独立提交。

当前实施证据：[Chat 执行与验收](../../qa/2026-11-20-chat-execution.md)。普通账号与完整上线验收仍未关闭。

## Task 5 — P0：Merge 故障定位与图文恢复

**Files:** Go 仓库内先读 `chorai-go/internal/merge/vnext/app/run.go`、`chorai-go/internal/merge/vnext/app/worker_failure.go`、`chorai-go/internal/merge/vnext/tools/runtime/types.go`、`chorai-go/internal/merge/vnext/observability/context.go`，以及 `Chorai_Agent/agents/merge_vnext/provider_wiring.py`、`Chorai_Agent/agents/merge_vnext/pipeline.py` 与现有测试；iOS 复用 `ArcNoteUITests/ArcNoteUITests.swift` 和 `Packages/CoreFlow/Tests/CoreFlowTests/NoteImportStoreTests.swift`。

**Interfaces:** 沿用现有 job/stage correlation 与 `DispatchCode` 类型，核对既有 generation/provider trace。只有现有证据确实丢失分类时才在所属边界补最小诊断；不新建诊断数据库，不记录 prompt、URL、token 或原始模型正文。

- [x] 对之前 `TEXT_PROVIDER_FAILED` 尝试关联原 job、stage、Go dispatch 和 Python provider 证据。已从隔离主库定位原任务、首次 text_fusion 派发及失败时间；保留日志没有对应 job correlation，首次失败原因仍未确认。见 [边界检查](../../qa/2026-11-21-prelaunch-boundaries.md)。
- [ ] 通过受控 provider/transport 故障覆盖 unavailable、timeout、非法输出、明确拒绝、取消和调用结果未知。断言持久终态、客户端可恢复动作、晚到结果拒绝与原有调用预算，不把结果未知当成未调用自动重试。
- [ ] 使用既有 `worker_failure_test.go`、`test_provider_wiring.py` 和 UI cancel/relaunch 用例验证分类或恢复修复；先 RED 后 GREEN。真实 gRPC 联调确认同一 job/stage 的端到端诊断，不改公开错误语义来掩盖内部问题。
- [ ] 补真实多图来源 Merge：上传与 visual evidence 就绪 → 冻结来源版本 → 生成 → 编辑/提交 → 重启；核对媒体、来源关系和权限。文字成功路径不代表视觉路由已覆盖。
- [ ] 验证离开编辑器、切后台、任务重启与账号切换后，原任务结果和未提交编辑仍归原 owner；已提交结果回放不再执行模型或重复生成 NOTE。
- [ ] 验收相关 Go/Python 测试、gRPC 和 iOS 精确场景通过后，分别在拥有改动的仓库提交，并更新对应当前模块与历史。

## Task 6 — P1：Swift 6 不能静态证明的边界

**Files:** `ArcNote/CoreFlow/NetworkNoteImportService.swift`、`ArcNote/CardImagePreparation.swift`、`ArcNote/NetworkManager.swift`、`ArcNote/HTMLWebView.swift`、`Packages/CoreFlow/Sources/CoreFlow/PendingInvitationCodePersistence.swift`、`ChatHistoryVisibility.swift`、`CoreNoteImportService.swift`。

**Interfaces:** 保留 Combine/SDK 的合法桥接以及现有锁；区分 DEBUG fixture 和生产类型。审核结果记录每个 unchecked/assumeIsolated 的拥有者、同步机制、调用线程及释放条件，不以数量归零作为验收。

- [ ] 对 completion/cancel 同时发生、订阅同步完成、取消早于注册、重复通知/信号添加确定性测试，要求 continuation 恰好恢复一次、无悬挂、权限撤销仍同步生效。
- [ ] 对 UserDefaults 包装的复合读改写检查实际并发调用者；只有跨线程或异步覆盖风险成立才收紧 owner/锁，不能仅因存在 unchecked 就判定有 bug。
- [ ] 复核上传结束前 security-scoped 文件访问不被提前释放，JPEG 取消后正在运行的编码仍占用名额；对尚未覆盖的边界补运行测试。
- [ ] 对适用的原生宿主测试运行 Thread Sanitizer，结合任务身份回归；TSan 无报告不能替代迟到结果/业务顺序断言。保持当前语言及默认隔离设置，独立提交必要修复和证据。

## Task 7 — P1：编辑器原图与文件 I/O 的资源上限

**Files:** `Packages/CoreFlow/Sources/CoreFlow/NoteLibraryStore.swift`、`NoteAttachmentFiles.swift`、`Packages/BlockNoteEditor/Sources/BlockNoteEditor/BlockNoteLocalImages.swift`；复用 `NoteDownloadedImageTests.swift`、`NoteAttachmentFilesTests.swift` 和编辑器图片运行测试。

**Interfaces:** 缩略图与编辑器原图是不同通道。原图保留完整字节/hash/MIME 与 note scope；参考已有有界队列，限制真正运行的读取/校验及在途字节。不得为降低占用破坏原图或原有 25 MiB 单图合同。

- [ ] 先测多图同时请求、同图重复请求、迅速退出/重进和取消后的实际工作数及占用；当前逐请求 Task/独立 detached 文件操作没有显示统一并发上限，尚未测出真实 OOM 或卡顿。
- [ ] 为已复现的重叠/重复工作补有界调度与共享；取消一个消费者不能影响其他消费者，取消运行中的同步 I/O 也不能提前释放真实名额。
- [ ] 验证图片下载期间编辑/删除/换号、文件损坏、空间不足及读取失败；显示失败可重试，原稿和其他附件不被覆盖。运行既有附件/下载/编辑器图片回归并记录占用条件。

## Task 8 — P0：文件导入的中断恢复

**Files:** Go `chorai-go/internal/importnotes/worker.go`、相应 job/item/source-state repositories 与现有测试；`docs/modules/media.md` 及历史。iOS 复用 `NoteImportStoreTests.swift` 与上传桥接测试。

**Interfaces:** 沿用现有 job/item 身份和 Action 入口，先在媒体模块记录提交与恢复边界。原问题是 Action 成功后 archive/source-state/outcome 独立写入、失败只记录日志；现已通过同库事务与 item 终态复用已提交结果。

- [x] 在 Action 已成功、source-state/outcome 未完成处注入失败/终止并重启 worker，断言用户可见状态与实际内容一致、重试无重复 Asset/版本/Activity。
- [x] 补齐同一工作项的提交/回执或可重放修复路径；数据库内能共享事务的写入使用现有事务，外部副作用由既有任务身份恢复，不预设新增通用工作流引擎。
- [x] 验证部分成功、用户取消、撤权和同文件重试；保留已成功项，失败项可恢复，不能整批假报成功。真实数据库和 iOS 导入状态联调后更新模块验收。

实施与验收已完成：[导入恢复记录](../../qa/2026-11-21-import-recovery.md)。额外关闭请求身份缺失、客户端旧 Soul 字段解码失败和终态重启丢显示；上传桥接终止时序的专项检查仍归 Task 6。

## Task 9 — 上线验收：用发布配置贯穿真实新用户流程

- [ ] Task 2 生产合同与服务能力通过后，验证隔离生产配置的空库启动/schema reconcile、权限、对象存储资格、API 与客户端能力一致；不使用管理员绕过或 dev-only 开关。
- [ ] 验证签名 Archive/TestFlight、真实 Apple/Google 登录、首次安装、最低支持系统、权限取消及后台/终止；首发可达入口逐项登记成功/失败/恢复验收，未验收不得写 ready。实际发布按届时授权执行。
- [ ] 关联可脱敏的 job/request/operation 证据与错误终态，能定位同步、聊天、Merge 和导入失败；复用现有诊断，不记录用户正文/凭据。
- [ ] 真机性能采样恢复后补时延与内存数据；它不阻塞编译、模拟器和故障合同工作。缺真机/签名证据时记录剩余发布验收，不把模拟器通过写成全面上线验收完成。

## 执行顺序与完成条件

客户端下一包推荐 Task 4（聊天请求正确性与重复工作）和 Task 6（Swift 6 桥接边界）；已有明确 Merge 失败按 Task 5 处理。上线主线从 Task 2 的生产合同开始，再用 Task 3 的普通新用户贯穿，Task 8 导入恢复必须在对应功能上线前完成。Task 1 是贯穿保障，Task 7 按测量和故障证据优化，最后执行 Task 9。各任务独立提交，跨端写入合同先在所属模块明确设计。

计划自查：旧版本迁移按用户明确范围移除，当前新数据可靠性仍保留；五项 Review Focus 均有任务；生产限制由代码确认，聊天/原图风险未伪装成已复现故障；不增加并行协议兼容负担，也不擅自删除首发功能。CI、最低系统运行、签名发布和生产合同仍待验收。当前 Task 4 已有实现与定向验证，Task 8 导入恢复已完成；其余任务和完整首发验收仍在推进。
