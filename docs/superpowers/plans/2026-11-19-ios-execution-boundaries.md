# iOS 计算执行边界 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让高成本计算离开 iOS UI 执行区，并形成新功能可直接遵循的执行、缓存和生命周期规则。

**Architecture:** 保留现有 MainActor Store、Serving、reader、持久化 owner。各模块用值快照、版本检查与局部 worker 完成后台计算；编辑器用显式顺序和保存屏障，不引入通用任务中心。

**Tech Stack:** SwiftUI、Combine、Swift Concurrency、Alamofire 5.12.2、CoreFlow、BlockNoteEditor、XCTest。

**Spec:** [iOS 计算执行边界设计](../specs/2026-11-19-ios-execution-boundaries-design.md)

**Plan review:** [检查结果与已修正问题](../../qa/2026-11-19-ios-execution-plan-review.md)。静态检查完成；不代表实现测试通过。

## Global Constraints

- iOS 16.0+，iPhone；Swift package tools 5.9，保持项目现有 Swift language mode。无需升级 Swift 6、使用 @concurrent 或新增第三方框架。
- 本次性能优化不以升级语言模式或提高最低 iOS 版本为前提；同时逐步加强并发检查，为 Swift 6 迁移做好准备。
- 编辑器 protocolVersion = 3、schemaVersion = 1；不编辑生成的 JS/CSS，不调整 Web 协议。
- 不修改 NoteSync 的持久化操作、创建/重试幂等键、Merge 保存确认顺序、数据库 schema、端点或权限。
- 不新建/切换分支、不自动 commit/push；保留现有 3 个 xcuserdata 修改。执行前重新核对 HEAD 与工作区。
- 测试只使用 Local、合成 fixture 和隔离 Session；ArcNote Production 只构建，不启动连接生产数据。
- 每项先补有意义的失败用例，再实现并运行相关验证。源码文本断言不能替代取消、顺序、保存正确性的运行时测试。
- 用户已批准并开始实施。执行采用当前会话串行推进；不需要为每一步重新确认。当前证据见 [实施验证](../../qa/2026-11-19-ios-execution-validation.md)。未勾选项保留未完成的整体验收条件，不代表对应代码未实现。

## Review Focus

1. 本地/远程同 ID、换账号、同 hash 换展示 URL：旧预览不可泄漏或覆盖，见 T1。
2. 详情共享请求、会话失效、凭据交换的 401：取消真实 HTTP，保留其他读者及错误语义，见 T2。
3. 大图片换选/退出及资源首次校验期间关闭：迟到结果不得上传或加载旧视图，见 T3/T4。
4. SwiftUI 拆除、临时 inactive、账号切换与磁盘失败：已收到正文必须按旧 scope 保存，见 T5/T6。
5. 连续输入期间 Accept/Back、clean store 通知及标签变更：提交最新精确快照，不重载旧正文，见 T7。

---

## 交付顺序与依赖

| 批次 | 任务 | 可独立交付结果 |
| --- | --- | --- |
| A | T1 | 统一预览入口、测试宿主、执行规范与基线样例 |
| B | T2 → T3 → T4 | 网络解码、图片编码、资源校验各自可验收/回退 |
| C | T5 → T6 → T7 | 先建立保存生命周期，再迁移编辑器状态机与 Merge 转换 |

T2/T3/T4 只依赖 T1 的测试宿主，业务上互不依赖；执行时仍串行，避免共享 NetworkManager、NewNoteView、项目文件的改动相互覆盖。C 整批通过保存验收后才算编辑器迁移完成。没有数据迁移，回退以该任务代码改动为单位。

下文路径均相对本 iOS 仓库。未存在且标注“新增”的文件是计划产物，不是已实现接口。

## T1：统一预览与新功能接入样例

**文件**

- 修改：Packages/CoreFlow/Sources/CoreFlow/LibraryCardPreviewCache.swift、LibraryCardPreviewParser.swift。
- 新增：ArcNote/CoreFlow/CardPreviewReader.swift；从 ArcNote/CoreFlow/FlowViews.swift 提取 reader。
- 修改：ArcNote/HomeCardsManager.swift、ArcNote/NetworkModels.swift、ArcNote/HomeView.swift、ArcNote/MergeSelectionCards.swift、ArcNote/ExploreView.swift、ArcNote/CoreFlow/SparkContinuationViews.swift、ArcNote/CoreFlow/FlowViews.swift。
- 测试：Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardPreviewCacheTests.swift、LibraryCardPreviewParserTests.swift；新增 ArcNoteTests/CardPreviewReaderTests.swift、ArcNoteTests/ExecutionFixtures.swift。
- 测试宿主：新增 ArcNoteTests/ExecutionBoundaryBaselineTests.swift、ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNoteTests.xcscheme；修改 ArcNote.xcodeproj/project.pbxproj。
- 规范：新增 docs/architecture/execution.md、docs/architecture/execution.history.md，修改 AGENTS.md 加链接；实测后新增 docs/qa/2026-11-19-ios-execution-baseline.md。

**接口与职责**

- 保留 LibraryCardPreviewInput 现有远程 initializer；增加 init(localNoteID: String, scope: NoteStoreScope, bodyRevision: Int64, content: String, contentJSON: String?)。
- 新增只读 localScope: NoteStoreScope?、allowsLocalImages: Bool；缓存身份含本地 scope/bodyRevision，allowsLocalImages 由本地输入推导。
- UserCard 增加仅客户端 localPreviewIdentity: LocalNotePreviewIdentity?（scope: NoteStoreScope、bodyRevision: Int64）；initializer 默认 nil，CodingKeys 排除该字段，远程 decode 置 nil。HomeCardsManager 的 present/update/localCard 显式传递在 library 变更回调内同步捕获的 scope；不从 AuthManager 推断旧卡归属。已有 UserCard 重建/点赞等复制路径保留该字段。本地卡缺少身份或 scope 不匹配时不创建远程输入。
- token(for: String, localScope: NoteStoreScope? = nil) -> ReadToken；原 read(_:token:) / invalidate(cardID:) / invalidateAll() 保留，token 与缓存键按相同作用域规则扩展。
- 缓存 initializer 增加 maxConcurrentParses: Int = 2。内部只运行 2 个真实解析；取消只移除等待/消费资格，不能提前释放仍运行的同步解析名额。
- CardPreviewReader.scope(for input: LibraryCardPreviewInput) -> Scope?；read(_ input: LibraryCardPreviewInput, scope: Scope) async -> LibraryCardPresentation?。Scope 持有当前 remote session 或 local NoteStoreScope 与 cache token。reader 是应用唯一预览读取入口，不负责另发网络请求。
- LibraryCardPresentation 新增 plainText: String；将 FlowTextPreview.make 的纯变换迁入后台 parser，保持原调用者的文本语义，estimatedBytes 包含该字段。统一缓存取代 FlowPreviewReader.textCache，不为纯文本另建任务/缓存系统。

- [x] 建立 ArcNoteTests host unit target，使用 Debug Local + --dev-preview；所有网络测试使用显式隔离 Session，未知请求由 stub 拒绝。保留现有 UI target。先运行一条真实存量模型行为测试确认宿主可运行。
- [ ] 记录改前基线：固定 200 张卡/1000 block 文档、重复打开相同卡、切换不同卡；synthetic 12 MP 图片和 1000 笔记列表留作后续对照。记录设备、OS、构建、数据字节数、5 次预热后 20 次采样的 p50/p95/峰值内存；数字是测量方法，不是产品性能门槛。未测项明确写未测。
- [x] 补失败测试：testLocalScopeAndRemoteInputNeverShare（两 scope 与 remote 不复用）；testSameHashChangedDisplayURLReparses；testSameInputSharesOversizedFlight（并发解析次数等于 1）；testCancelledRunningParseKeepsCapacity（真实 active 最大值不超过 2）；testLateOldVersionCannotReturnAsCurrent；testSessionChangeRejectsPreview；testLocalProjectionPreservesOriginalScopeAndRevision；testLocalIdentityNeverEntersWireJSON；testStaleLocalCardNeverFallsBackToRemote；testPlainTextPreservesScriptStyleEntityWhitespaceBehavior（与原算法 fixture 输出一致）。已有等价用例直接复用。
- [x] 运行新用例确认因缺少目标行为失败；然后扩展缓存 key/token、工作队列和时效检查。默认 parser 传入 allowsLocalImages，保持 40 项/4 MiB 上限。
- [x] 提取 CardPreviewReader 并接入所有列出入口，包含 Explore/Spark 的 FlowTextPreview 调用。远程 snapshotID 跟随已加载数据生命周期，本地使用真实 bodyRevision；body/init 只构造输入、展示已准备字段，不能为 accessibilityLabel 再全文清洗。远程授权与本地 scope 在读前/回写前双检，Local thumbnail 保留原实现。
- [ ] 运行缓存包测试及 CardPreviewReaderTests；用可控 parser probe 断言计算非主线程、UI 发布在主线程。模拟器验证缓存冷/热、离线本地图片、注销后旧内容清除；不修改视觉布局。
- [x] 写 execution.md 的 8 条接入规则与一个基于本次代码的调用例，history 记录改变和验证；更新基线记录。此后任务仅增补自己的边界与验收，不再创建平行规范。

**通过条件**：所有指定入口不再直接全文解析；重复/作用域/失效/并发测试通过，观察到主线程解析栈移出。未达到时不扩大到其他模块。

## T2：网络响应解码与详情读取取消

**文件**

- 修改：ArcNote/NetworkManager.swift、ArcNote/CoreFlow/CardDetailReader.swift。
- 新增：ArcNoteTests/NetworkResponseExecutionTests.swift、ArcNoteTests/CardDetailReaderTests.swift、ArcNoteTests/StubURLProtocol.swift。
- 更新：docs/architecture/execution.md、docs/architecture/execution.history.md。

**接口与职责**

- 保持 request、requestData、getCardDetailPublisher(cardId:presentsError:) 的调用方契约与 NetworkError。
- NetworkManager 增加内部 init(baseURL: String, session: Session, startsMonitoring: Bool = false)；生产 shared 仍由 APIConfiguration 装配。
- 一个私有串行 responseDecodeQueue 执行纯响应处理；所有最终 promise、UI/认证副作用在主队列交付。不把 NetworkManager 整体变为后台 actor。
- 详情 GET 的 publisher 是按订阅启动的可取消读取；CardDetailReader 的单一底层订阅负责合并和取消。其他 mutation publisher 不在本任务改变冷热/重试语义。
- CardDetailReader 的 cached/confirmed/currentScope 语义不变；无需增加“最后一个页面离开就取消共享任务”的引用计数策略。

- [x] 补失败测试：成功/非 JSON/401/APIErrorPayload/凭据交换 200 内嵌错误的结果与原映射一致；decode probe 在非主线程，结果及错误提示 observer 在主线程。
- [x] 补取消与订阅测试：两个 confirmed 只产生一次 startLoading；取消一个 waiter 另一个仍成功；invalidate session 后 StubURLProtocol.stopLoading 被调用；迟到响应不入缓存；下一次 confirmed 重新 startLoading；两个 mutation 订阅不新增第二次写入。异步等待使用 expectation/latch，不依赖任意 sleep。
- [x] 先运行用例确认失败，然后迁移通用 request、requestData 及 avatar/card-media/image 上传回调的纯解码和错误解析。HTTP 状态与 immutable Data 可跨队列；authToken、Published、alert 留在主线程。保留 credential-exchange 分支和响应校验规则。
- [x] 实现详情读取专用的 Deferred/取消桥（或等价 Subscription），取消真实 Alamofire DataRequest。创建、取消、完成之间有一个明确同步 owner；提前取消、重复取消、完成后取消均无重复 completion。不将读取消规则传播到持久化写操作。
- [x] 检查触及的日志：不得生成/输出敏感完整 payload，也不要先转完整字符串后再截断。调试观察只保留操作类别、bytes、duration。
- [x] 运行 NetworkResponseExecutionTests、CardDetailReaderTests 与现有 API/身份相关测试；验证成功和失败回调后 loading 正确复位。更新执行规范和历史。

**通过条件**：纯响应解码离主线程；实际 HTTP 取消得到验证；重复确认、共享读、已有 mutation 语义都保持。SSE 与其他服务的 firstValue 迁移不纳入此次完成声明。

## T3：图片编码统一离开主线程

**文件**

- 新增：ArcNote/CardImagePreparation.swift、ArcNoteTests/CardImagePreparationTests.swift。
- 修改：ArcNote/EditProfileView.swift、ArcNote/ChoraIdentityGrowthSections.swift、ArcNote/NewNoteView.swift。
- 更新：项目 target membership、执行规范与历史。

**接口与职责**

- CardImagePreparation.shared.jpeg(_ image: UIImage, quality: CGFloat, filename: String) async throws -> CardEditingImage。
- 专用串行队列执行不可变 UIImage 的 jpegData，mimeType 为 image/jpeg；失败用局部 encodingFailed 错误映射到现有界面提示。
- 调用者持有选图 generation/Task，提交结果前核对选图和 editor/account 身份；不把 UIView/Store 放入编码闭包。

- [x] 补失败用例：testJPEGEncodingRunsOffMain；testOrientationAndDimensionsMatchExistingEncoding；testQualityIsForwardedUnchanged（0.82/0.88/0.9）；testReplacementRejectsOldImage；testCancelledPreparationDoesNotUpload；多个入口同时请求时 active 编码数等于或小于 1。
- [x] 运行确认失败后实现队列与取消结果处理；已运行同步编码等待真实结束，期间不再开第二个编码。队列等待者取消要释放待处理图片引用。
- [x] 替换三个入口的 jpegData 调用，先设置已有 busy 状态再 await；不缩图、不改质量，不重复编码 PhotosPicker 已取得的数据；完成时释放临时大图。
- [x] 同批调整 Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift 中强制要求原函数直接 jpegData 的旧断言，改查新的接入边界，质量/线程正确性由运行时测试保证；T1 迁移涉及的旧 Flow/Library source contracts 同理更新。
- [ ] 运行图片与资料编辑相关测试，模拟器检查换选/取消/保存按钮状态；记录 12 MP fixture 前后主线程栈、耗时和内存。更新规范/历史。

**通过条件**：编码非主线程、过期结果无上传、输出方向/大小与现有行为一致。保留 LocalNoteThumbnail 的异步缩略图实现。

## T4：编辑器资源校验复用

**文件**

- 新增：Packages/BlockNoteEditor/Sources/BlockNoteEditor/BlockNoteResourceValidator.swift。
- 修改：Packages/BlockNoteEditor/Sources/BlockNoteEditor/BlockNoteEditorResources.swift、BlockNoteEditorCoordinator.swift。
- 测试：Packages/BlockNoteEditor/Tests/BlockNoteEditorTests/BlockNoteEditorResourceTests.swift；新增 BlockNoteResourceValidatorTests.swift。
- 更新：执行规范/历史。

**接口与职责**

- 内部 actor BlockNoteResourceValidator，shared.validateBundledResources() async throws -> BlockNoteEditorResourceManifest。
- 复用现有同步校验函数作为非主执行的纯实现；一次目录/版本身份只有一个在途任务，缓存成功结果。测试可注入独立目录与校验闭包。
- coordinator 只在 await 成功且仍为原 attachment 时设置 navigationGate 并在主线程 loadFileURL。

- [x] 用计数与 gate 测试：同时 2 个编辑器仅校验 1 次；再次打开不重读；坏 hash/manifest 不加载；关闭一个 waiter 不影响另一个；关闭后成功结果也不触发旧视图加载；不同测试资源实例不共享成功。
- [x] 确认失败后实现 actor/single-flight 与 attachment 检查；不漏掉协议/schema/SHA 验证，错误沿用 resource_validation_failed。
- [ ] 运行资源、导航策略及现有 WK runtime 测试；测量首次/再次打开。成功标准是校验离主线程且复用，不能把“启动了 Task”当作证据。更新规范/历史。

## T5：普通笔记的排空与最终保存生命周期

本任务先保留 bridge 当前同步计算；为 T6 建立可单独验证的保存合同。使用可延迟的测试 binding 验证真实生命周期等待，不做源码字符串代替测试。

**文件**

- 修改：Packages/BlockNoteEditor/Sources/BlockNoteEditor/BlockNoteEditorView.swift（controller 在此文件）、BlockNoteEditorCoordinator.swift；ArcNote/CardEditor/BlockNoteCardEditor.swift、ArcNote/NewNoteView.swift、ArcNote/CoreFlow/LocalNotesController.swift、ArcNote/ContentView.swift。
- 新增：ArcNote/CoreFlow/LocalNoteEditorPersistenceSession.swift、ArcNoteTests/LocalNoteEditorPersistenceSessionTests.swift。
- 修改测试：Packages/BlockNoteEditor/Tests/BlockNoteEditorTests/BlockNoteEditorControllerTests.swift。
- 更新：执行规范/历史。

**接口与职责**

- controller 增加 drainAcceptedEvents() async 与内部 beginClosing()（同步幂等）；drain 完成表示 cutoff 前有效正文已经应用，而非只算完。正常关闭不使该 drain 失败；错误事件仍应用现有错误状态并保留最后有效正文。
- controller 为每次 attachment 提供唯一 ID 和 closing 回调；detach 即刻停止新 WK 操作/失败未完成 snapshot，但仍保留已接收事件的 drain completion。closing 回调同时固定旧 attachment 的 completion/handle；等待期间不能再从 bodyModel.controller 取一个可能已替换的新 binding。
- LocalNoteEditorPersistenceSession 是现有 editor registration 的具体生命周期 owner，固定 id、旧 NoteStoreScope、原 CardEditingStore 和 body model；接口 flushAcceptedEdits() async -> Bool、bindingWillClose(_ id: UUID)、closeForScopeChange() async -> Bool、setVisible(_ visible: Bool)。不是通用后台任务框架。
- 每个 session 只有一个 finalFlushTask；关闭 completion 与保存 Task 分离，禁止 save→drain→等待 save 自己的循环。
- LocalNotesController 的注册表持有 persistence session，范围切换先暂停旧 scope 云同步、关闭并等待旧 session。新增 NoteScopeTransitionState（ready/flushing/failed）与只读 published scopeTransition，retryScopeTransition() 复用串行 accessTask 链。保存失败保留 dirty session/错误，不标为成功或注销，暂不 configure 新 scope。
- ContentView 直接按 auth.currentNoteScope 与 library.scope 是否一致及 scopeTransition 控制笔记根视图；不等待异步刷新才遮住旧内容。切换中显示“Saving your notes…”；失败显示“Couldn't save your last note. Retry to continue.”与“Retry”，不显示旧正文。

- [x] 补测试：testDisappearBeforeAppliedEventSavesFinalRevision；testDismantleAfterDisappearTriggersFinalFlush；testInactiveThenActiveStillAcceptsInput；testCloseFlushDoesNotAwaitItself；testScopeChangeWaitsForOldScopedSave；testSaveFailureRetainsSessionAndDoesNotSwitchScope；testOldBindingCannotUnregisterReplacement；testScopeMismatchHidesOldNotesImmediately；testRetryUsesLatestAuthTarget。
- [x] 确认失败后实现 controller drain/closing 合同；当前同步 session 下 drain 可立即完成。调用 save 前必须先 drain，再判断 isDirty/isUntouchedNewDraft；避免新正文尚未应用时直接 return。
- [x] 把 View 内最终保存职责迁到 LocalNoteEditorPersistenceSession：普通 autosave、inactive、onDisappear 做 watermark drain→save；不永久封口。dismantle 同步封口并通知 registration 启动/复用最终保存；不依赖 View Task 存活。
- [x] 账号切换先以原 library.scope 调用 configure(scope:cloudEnabled: false) 暂停旧同步，再同步 seal 旧 binding、等待 drain→旧作用域落盘。成功后重新读取当前认证目标再 configure；保留 accessTask 串行链，不能回放等待期间已经失效的目标。失败隔离笔记根视图并保留重试；不修改 AuthManager 的账号认证结论，不让旧内容展示到新账号。
- [x] 明确 release 条件：父编辑页不再显示、对应 binding 已关闭、末次保存成功时才注销；编辑器失败后 native 标题仍可编辑、重新出现/重建 binding 时保持注册且以 ID 防止旧任务清理新会话。
- [ ] 运行 lifecycle 和 NoteLibraryStore/NoteSyncCoordinator 测试，模拟器验证输入后立即退出、相机/系统弹层返回、切后台再返回、换账号和注入磁盘失败。保持已有短暂本地保存后台 allowance，不延长为持续后台计算。更新规范/历史。

**通过条件**：异步计算即使尚未加入，延迟 binding 测试已证明旧 scope/最终保存合同。不得仅修改 onDisappear 后开始 T6。

## T6：按序迁移完整原生编辑器计算

**文件**

- 新增：Packages/BlockNoteEditor/Sources/BlockNoteEditor/BlockNoteBridgeWorker.swift、BlockNoteBridgeMailbox.swift。
- 修改：同目录 BlockNoteEditorCoordinator.swift、BlockNoteEditorState.swift、BlockNoteEditorMessage.swift、BlockNoteEditorView.swift。
- 新增测试：Packages/BlockNoteEditor/Tests/BlockNoteEditorTests/BlockNoteBridgeExecutionTests.swift。
- 复用：BlockNoteBridgeSessionTests.swift、BlockNoteEditorControllerTests.swift、BlockNoteMergeRuntimeTests.swift、BlockNoteFocusRuntimeTests.swift；T5 的 app tests。
- 更新：执行规范/历史。

**接口与职责**

- BlockNoteBridgeInput: Sendable：navigationFinished、message(envelope)、command、malformedMessage、bridgeFailure、close 等现有状态机输入。
- BlockNoteBridgeEnvelope: Sendable 只含当前协议认可的标量/字符串和小型 selection DTO；原 String body 保持 String 交 worker 解码。不得在 WK callback 重新序列化整份 contentJSON。
- actor BlockNoteBridgeWorker.apply(_ input: BlockNoteBridgeInput) -> BlockNotePreparedOutput；actor 独占现有完整 BridgeSession。
- BlockNotePreparedOutput: Sendable 包含现有 session output、已编码 command scripts 及只读状态摘要。不要在 MainActor 重新 encode initialize/document。
- MainActor BlockNoteBridgeMailbox 负责顺序号、attachment generation、唯一 drain Task、已应用 watermark。worker 只管计算；mailbox 不另建业务状态机。主线程 apply 完成后才推进 watermark。

- [x] 补失败测试：人为阻塞首个工作后输入连续 revisions/命令/snapshot，结果严格按输入顺序；ready 时 queued commands 先于 ready event；旧 generation 不作用于新 editor；read-only/compatibility 不能 mutation；decode/adapter/command encode 的 probe 均不在主线程。
- [x] 覆盖 requestSnapshot 5_000_000_000 ns 端到端期限（测试用注入短时钟）、取消/teardown exactly once、超时后迟到 snapshot 和 T5 最终正文。新增 testFocusImmediatelyAfterQueuedReadyIsPreserved、testNaturalFocusInvalidatesOlderDOMProbe；超时不能因 worker 排队而重新计时。
- [x] 确认失败后实现顶层 envelope 和 actor；MainActor 用唯一 drain 顺序调用 apply、应用结果。完整 runtime adapter 随 session 搬迁，避免将有状态 ID 映射拆成多个无序任务。T6 单独落地时仅 standard profile 使用新执行器，mergeArtifact 保持现有同步 session；T7 的生命周期门槛通过后再移除这个局部过渡分支，不新增持久化配置/协议字段。
- [x] 将 commands→snapshot completion/failure→events 的现有 dispatch 顺序接到 prepared scripts；WK 操作和事件回写均留主线程。自然 focus 入口先更新 focusObservationRevision 并入 FIFO，不能按主线程旧 readiness 拦掉；DOM probe 带 revision 入同一 FIFO，在出队及应用时核对。closing 立即禁止新 mutation/焦点，但继续交付 cutoff 之前的正文；结束后释放队列与捕获对象。
- [x] 第一版不合并全文事件。用 1000 block 文档的持续输入与混合快照压力测试记录 queue peak/bytes、排空和内存释放；若输入停止后持续积压或保存屏障超时，则本阶段验收失败，不以丢事件绕过。
- [ ] 运行整个 BlockNoteEditor 包与 T5 app tests，并在模拟器复测长文、undo/redo、图片、键盘焦点、只读兼容、关闭保存。更新规范/历史。

**通过条件**：顺序与保存合同成立；原生全文转换/命令编码离主线程。不声称 WK 内容进程内的 JavaScript stringify/Markdown 生成已由本次迁走。

## T7：Merge 生命周期排空、投影与转换版本化

**文件**

- 新增：Packages/CoreFlow/Sources/CoreFlow/MergeArtifactEditorWorker.swift、Packages/CoreFlow/Tests/CoreFlowTests/MergeArtifactEditorWorkerTests.swift。
- 修改：ArcNote/CoreFlow/MergeArtifactDraftController.swift、MergeTaskRail.swift、MergeLifecycleViews.swift；Packages/CoreFlow/Sources/CoreFlow/MergeTaskCoordinator.swift、MergeSessionStore.swift；T6 中的 profile 过渡分支。
- 新增：ArcNoteTests/MergeArtifactDraftExecutionTests.swift、ArcNoteTests/MergeEditorRetirementTests.swift。
- 复用：Packages/CoreFlow/Tests/CoreFlowTests/MergeArtifactEditorCodecTests.swift、MergeSessionStoreArtifactTests.swift、MergeSessionStoreCommitTests.swift、MergeTaskCoordinatorTests.swift。
- 更新：执行规范/历史。

**接口与职责**

- 新增 Sendable 值 MergeArtifactPreparedProjection，字段 editable: MergeArtifactEditableDocument、unresolvedMediaReferences: [String]、displayURLsByMediaReference: [String: String]；新增 MergeArtifactPreparedDraft，字段 documentJSON: Data、unresolvedMediaReferences: [String]。
- actor MergeArtifactEditorWorker.project(cardDocumentJSON: Data, displayURLsByMediaReference: [String: String]) throws -> MergeArtifactPreparedProjection；prepareDraft(blockNoteJSON: String, preserving: Data, displayURLsByMediaReference: [String: String]) throws -> MergeArtifactPreparedDraft。内部调用现有 lossless codec，并搬入原 URL 校验/引用解析的纯逻辑。方法从 actor 外通过 await 调用，不能在 MainActor 再 parse 一遍引用。
- manifest 选择保持现有规则：draft 的非空 preservationManifest 优先于 decode 新生成值；失败保持原只读 fallback 与 compatibility 提示。
- MergeTaskCoordinator 增加 registerEditorDrain(id: UUID, jobID: String, beginClosing: @MainActor () -> Void, drain: @MainActor () async -> Bool) / unregisterEditorDrain(id: UUID)。注册持有原 controller 的排空能力；host 消失不提前注销，binding ID 防止清理替代实例。Controller 增加 flushAcceptedDraft() async -> Bool，等待原 binding 的 drain，再等待当前转换完成并更新原 store。
- synchronizeLifecycle/activate/deactivate 收敛到 coordinator 的同一转移入口：无编辑器时保留同步快路径；有编辑器时同步隔离 UI/封口，只有一个 retirement Task 等待排空。后续调用仅更新最新目标，不提前恢复旧网络、不发起第二个退休任务。返回的 actorDidChange 表示目标身份变化；onboarding reset/load 与实际 Merge runtime 的就绪分开，Merge UI只在转移完成且身份匹配时展示。
- 新增只读 transitionState（ready/draining/failed）供 Portal 隔离旧 rail/fullScreenCover、阻止新动作并提供 retryEditorDrain()。直接 activate/deactivate 也不能绕过排空；scene inactive 做 watermark flush，不永久关闭可返回的 editor。
- MergeSessionStore.beginLocalEditorDrain() 是内部“停止网络、仍允许排空前已接受本地正文”的入口：使旧 async 结果/token 失效，取消 operation/debounce/save 等待，禁止新远端动作，保留 phase 的本地可保存状态、snapshot 和 pendingSaveWasAttempted。此处不得调用会重置 attempted 的 cancelDraftWork，也不得提前 invalidateLifetime。
- Controller 为 projection generation、editor instance、local revision 绑定结果；pendingLocalRevision 在提交异步工作前设置。state owner 不放到 worker。
- 初始化/reload 显示现有 loading/read-only presentation，待当前 decode 成功才安装可编辑 model；转换期间 canAccept 为 false。普通输入串行转换，排队的未开始普通正文允许只留最新值；显式 snapshot 工作不可合并/丢弃。
- persistCurrentSnapshot() async -> Bool 必须 await 精确 snapshot 的 prepareDraft 和主线程 store.updateArtifactDraft。保持现有 tags，不用旧完整 snapshot 替换 store。
- pendingFinalAction: FinalAction? 携带 UUID 和 accept/back 类型；两种动作先收尾 pending tag，再建立动作锁、捕获 snapshot。锁阻止用户继续修改，但内部精确 snapshot 转换不得被 canEdit=false 拒绝；旧 action 回调不能解锁新 action。Accept 继续 await flushArtifactDraft 后 commit；Back 在本地 draft 更新确认后 minimize，不新增等待云端保存。失败解除当前动作锁并保留草稿。

- [x] 补失败测试：testPendingLocalEditBlocksCanonicalReload；testOlderConversionCannotReplaceLatestBody；testTagsChangedDuringEncodeArePreserved；testAcceptWaitsForExactSnapshotThenFlushesThenCommits；testBackWaitsBeforeMinimize；testFinalActionBlocksFurtherInputButAllowsSnapshotConversion；testFinalActionIncludesPendingTag；testReloadOrDiscardRejectsOldProjection；testLosslessFailureKeepsDraftAndBlocksAccept。
- [x] 先补 retirement 回归：gate 阻塞 bridge 或 codec 时触发 401/deactivate/换账号，旧 actor snapshot 最后正文必须保存后才 invalidate；新账号不见旧 rail/editor；失败保留旧注册与重试；重复切换仅激活最后目标；迟到网络响应不能覆盖排空结果；已发送 pendingSave 的 key/body 不因排空改写；inactive→active 可继续输入；View 消失后 drain 仍完成。
- [x] 保持 Merge 同步计算先实现两段生命周期和注册接线。beginClosing 撤销未完成 finalAction 的后续用户动作，允许内部本地 drain；旧 store 在排空完成前保留，转换错误保留未处理正文/owner 并进入 failed。本地成功按现有同步 persistence.save 契约确认后，才执行原 clearRuntimeState。这里不改变 UserDefaults 保存 API，也不承诺新增磁盘耐久性级别。
- [x] 运行确认失败后迁移初始化/reload 的 decode 和 documentDidChange/snapshot 的 encode/引用解析。worker 只访问 immutable Data/String；主线程更新 projectedDraftIdentity 的顺序保持在 store.updateArtifactDraft 之前。
- [x] 修改 reconcileCanonicalProjectionAfterStoreChange：有未处理本地 revision 不重载旧 canonical；主动 reload/discard/换实例先使 pending 工作失效。只对当前 generation 的最终结果清理 pending 状态。
- [x] Accept/Back 等待 T6 snapshot、T7 转换和现有持久化确认；异常保留当前草稿/错误，不以 Task fire-and-forget 提前返回成功。
- [ ] 运行 worker/codec/store/coordinator 单测及两个 app test suites；通过 gate 阻塞下的生命周期测试后，为 mergeArtifact 启用 T6 执行器并再跑同一组用例。模拟器快速输入后 Accept/Back、退出账号/401、重试、标签并发与任务恢复。重新测量剩余 MergeSessionPersistence 的 JSON 写入；记录未迁移成本，不把它包装成已消除。
- [x] 更新规范/历史与最终验证记录。

## 验证命令与最终验收

执行目录为 iOS 仓库。先查看可用模拟器，给专用测试设备设置 CHORAI_TEST_DEVICE 和临时派生目录 CHORAI_TEST_DERIVED_DATA；不清空当前用户已启动设备。

~~~sh
xcrun simctl list devices available
swift test --package-path Packages/CoreFlow --filter LibraryCardPreviewCacheTests
swift test --package-path Packages/CoreFlow --filter 'NoteLibraryStoreTests|NoteSyncCoordinatorTests|MergeArtifactEditorCodecTests|MergeSessionStoreArtifactTests|MergeSessionStoreCommitTests'
swift test --package-path Packages/BlockNoteEditor
xcodebuild -project ArcNote.xcodeproj -scheme ArcNoteTests -destination "platform=iOS Simulator,id=$CHORAI_TEST_DEVICE" -derivedDataPath "$CHORAI_TEST_DERIVED_DATA" test
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
git diff --check
~~~

各任务先用上述命令的 --filter / -only-testing 选择对应测试；新增 worker 测试纳入对应过滤器。最终各包完整运行一次，明确区分跳过的 live API 测试和已执行测试。macOS SwiftPM 通过不能代替 iOS host/UIKit/WK 流程通过。

关键测试断言合同如下；变量由各任务的 fixture/probe/gate 记录，不在产品中新增观测状态：

~~~swift
// T1: 同输入共享；取消后真实运行量仍受限。
XCTAssertEqual(parseCountForSameInput, 1)
XCTAssertLessThanOrEqual(peakRunningParses, 2)
XCTAssertNil(resultAfterScopeInvalidation)
// T2: 两个 confirmed 合并；会话失效传到实际传输。
XCTAssertEqual(startLoadingCountForTwoWaiters, 1)
XCTAssertEqual(stopLoadingCountAfterSessionInvalidation, 1)
XCTAssertFalse(decodeRanOnMainThread)
XCTAssertTrue(deliveryRanOnMainThread)
// T3: 不改变质量，换选不上传旧输入。
XCTAssertEqual(recordedQualities, [0.82, 0.88, 0.9])
XCTAssertEqual(uploadedSelectionIDs, [latestSelectionID])
// T4: 共享首次校验；关闭中的旧视图不加载。
XCTAssertEqual(validationCountForTwoEditors, 1)
XCTAssertEqual(closedWebViewLoadCount, 0)
// T5: gate 打开前不能切 scope；失败仍保留会话。
XCTAssertFalse(configuredScopesBeforeDrain.contains(newScope))
XCTAssertEqual(savedBodyRevision, lastAcceptedBodyRevision)
XCTAssertTrue(failedSaveSessionRemainsRegistered)
// T6: 四个受控输入按序应用；超时/关闭只完成一次。
XCTAssertEqual(appliedSequences, [1, 2, 3, 4])
XCTAssertEqual(snapshotContinuationCompletionCount, 1)
// T7: 退休前的最新正文写到旧账号；尝试过的操作不可被重写。
XCTAssertEqual(oldActorPersistedBody, lastAcceptedBody)
XCTAssertEqual(pendingSaveAfterDrain, attemptedPendingSave)
XCTAssertEqual(acceptTrace, ["snapshot", "prepare", "localSave", "flush", "commit"])
~~~

- [ ] 以相同基线 fixture/设备/构建重测：主线程栈、总延迟 p50/p95、峰值内存、解析/请求次数。使用 Instruments Time Profiler/Hangs；结果写入 docs/qa/2026-11-19-ios-execution-validation.md。没有真机结果时明确写“仅模拟器”。
- [x] 对照 T1–T7 验收项及全部 5 类 Review Focus；不只检查“加了 async/actor”。记录测试命令、结果、未运行理由与剩余成本。
- [ ] 核对 Local 杀进程后图标重启仍为 Local；只构建 Production。检查所有新文件 target membership、文档链接、用户已有改动保留。
- [ ] 每批任务只有指定正确性测试、相关构建、实际流程通过才能标记完成；后续任务不掩盖前一批失败。图表/性能记录不能替代保存和隔离正确性。

## 明确不纳入本轮

全局网络缓存框架、全体 Serving 改 actor、Swift 6 升级、图片库替换、跨端协议改版、SSE 重构、所有 firstValue 取消桥重写、HomeCardsManager 全量列表异步化、Merge 全量持久化 API 异步化、持续 OS 后台运行。发现这些成为主要瓶颈时，携带基线与失败模式单独立项。

## 本轮交付状态

T1–T7 的代码迁移、运行时正确性回归和一次完整独立审查修复已实施。CoreFlow 1042 项（6 项在线测试跳过）、BlockNoteEditor 76 项、应用 48 项通过；4 条普通编辑器流程与 7 条选定 Merge/账号生命周期流程通过，Local/Production 均构建成功。改动保留在当前工作区，未提交/推送。

未勾选的复合验收项仍按原条件保留：没有真机/峰值进程内存/1000 笔记滚动的完整性能对照；部分模拟器手工矩阵由运行时测试覆盖，尚未逐项手测；字面意义的图标点击无法通过当前 CUA 验证，已验证终止后无启动参数重启仍为 Local。现有 Home fixture 与长文顶部几何断言的失败分别记录，后者在精确 HEAD 基线重现。严格并发诊断已执行，NetworkManager/Combine 的类型迁移尚未完成。

剩余同步 makeCleanDraft 解码及 UserDefaults 保存、完整证据和审查裁定见 [实施验证](../../qa/2026-11-19-ios-execution-validation.md)。这份状态不把代码迁移完成等同于全部性能/视觉验收完成。
