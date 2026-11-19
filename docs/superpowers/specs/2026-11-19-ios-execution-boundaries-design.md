# iOS 计算执行边界设计

日期：2026-11-19。状态：待执行；本文描述目标，不代表已经实现。

代码基线：Chorai_IOS_Frontend c5f005037f2c88bdccdbc5209060a62f68d40bd0。
范围：iOS 客户端；不改变 Go/Web API、数据归属、编辑器协议或服务端幂等语义。
配套：[实施计划](../plans/2026-11-19-ios-execution-boundaries.md)。

## 1. 决策与现状

沿用 View → MainActor Store/Controller → Serving → 具体实现的结构。
UI 状态仍由现有 Store 管理；纯计算由所属模块的 actor 或串行队列执行；数据库与可恢复任务继续由现有 owner 管理。
新增功能使用这套边界，不新增通用任务中心、全局业务事件总线或一套替代 CoreFlow 的框架。

现有基础已经成立：CardDetailReader 合并并发详情读取并管理会话失效，LibraryCardPreviewCache 在后台解析，NoteLocalStore 使用后台 Core Data context，NoteSyncCoordinator 管理持久化同步操作，MergeTaskCoordinator 管理应用级任务。
本次补齐入口绕行、执行上下文、结果时效和退出时的保存屏障。

| 已核对入口 | 当前情况 | 本次处理 |
| --- | --- | --- |
| HomeView.LibraryCardContentPreview、SparkContinuationViews | 构造/body 内同步解析全文 | 统一经过有版本和作用域的预览缓存 |
| FlowViews.FlowPreviewReader | 已有缓存与失效逻辑 | 提取复用，保留权限确认语义 |
| FlowTextPreview.make → Explore / Spark | 独立主线程正则清洗与 textCache | 保留文本变换语义，纳入同一后台展示准备与缓存 |
| NetworkManager.request/requestData、图片上传响应 | responseData 默认主队列，回调内手动解码 | 纯解码移到专用队列，UI/认证副作用回主线程 |
| EditProfileView、ChoraIdentityGrowthSections、NewNoteView 相机入口 | 同步 jpegData | 有界图片编码队列 |
| BlockNoteEditorResources / makeWebView | 每次创建同步读资源并做 SHA 校验 | 进程内 single-flight，后台校验后加载 |
| BlockNoteEditorCoordinator / BridgeSession | 主线程消息解码、文档映射、命令编码 | 按序迁移，先保证保存与关闭语义 |
| MergeArtifactDraftController | 主线程投影与全文 encode | 版本化异步转换，Accept/Back 等待精确结果 |

这与 Apple 的响应性建议及公开大型内容应用的方向一致：缩小 UI 执行区、控制并发、维护明确 owner、以测量验收。这不意味着主流内容社区都采用同一种 MVVM/Store 框架，也不据此宣称 Chorai 已达到大型社区的性能水平。

## 2. 新功能必须遵守的接入规则

1. View 只提交意图和展示值；body/init 不解析整份文档、不编码图片、不做磁盘 I/O。
2. MainActor Store/Controller 持有界面状态、操作版本和任务引用。用明确的非 MainActor worker 执行重计算；Task {} 或 async 本身不保证离开主线程。
3. 网络仍经 NetworkManager/APIConfiguration。读缓存复用现有领域 reader；缓存展示值不能替代操作前的权限/存在性确认。
4. worker 接收不可变值，返回不可变值。不得捕获 View、WKWebView、可变 Store 或 NSManagedObject 后跨执行域访问。
5. 写回时核对账号/环境、对象身份和输入版本。取消后还要拒绝迟到结果；同步 CPU 工作不因 cancel() 立即停止。
6. 页面读任务、共享读取、持久化写入各有现有 owner。页面退出不能任意取消可能已提交的写入，也不能创建新幂等键重试同一操作。
7. 每项计算说明最大同时执行数、缓存身份、失效条件和退出行为。无需给所有服务都包一层 actor。
8. 后台线程与 iOS 应用后台运行是两件事。同步仍遵守现有前台条件；短暂系统后台时间只用于必要的本地落盘。

这些规则在首个实现中写入 docs/architecture/execution.md，并从 AGENTS.md 链接。只建立一个长期规范入口，设计与计划保留为历史依据。

## 3. 预览：首个完整样例

- 保留一个共享 LibraryCardPreviewCache，总缓存上限仍为 40 项、4 MiB；不另建各页面缓存。
- 增加本地输入构造器：localNoteID、NoteStoreScope、bodyRevision、content、contentJSON。本地作用域属于缓存身份，允许本地图片从该输入推导；不能仅以相同 cardID 或正文 hash 复用本地/远程结果。
- HomeCardsManager 在接收当前 library 的主线程变更时同步捕获 scope，与 OfflineNote.bodyRevision 一起带入 UserCard 的仅客户端展示身份；ownerActorId 也取这个 scope。不能在视图中用当前 AuthManager 补旧卡片归属。该身份不进入服务端 JSON；本地身份缺失/不匹配时拒绝展示，不降级为远程读取。
- 远程输入沿用 contentHash 或稳定 snapshotID；正文与展示 URL 字符串仍参与相等判断。同 hash 下 URL 更新必须重新解析；不要在每次 body 执行时生成 UUID。
- 缓存键至少区分 cardID 与本地 scope；同 cardID 失效覆盖其相关入口，会话切换清空。Reader 在读前和回写前验证当前授权/本地 scope。缓存身份本身不授予访问权。
- 每个缓存最多 2 个实际执行中的解析。这是初始实现配置，不是测出的最优值。待执行的同键旧版本可以丢弃；已开始的同步解析要等真实结束才释放并发名额。
- 相同输入只解析一次；结果过大时可以不缓存，但同一次并发读取仍共享结果。过期版本既不能入缓存，也不能覆盖界面。
- 提取 CardPreviewReader，接入 Flow、Library、Merge 选卡、Explore 和 Spark 延续。FlowTextPreview 的现有纯文本算法移到后台 presentation 准备，返回 plainText 字段供原调用者使用，保持 script/style/实体/空白处理语义；删除它的独立 textCache，该字段计入共享缓存字节预算。加载中沿用现有占位，不改卡片排序、布局和交互。

## 4. 网络、图片、资源的执行规则

### 网络

NetworkManager 持有一个串行 responseDecodeQueue。回调在该队列完成 JSON/APIErrorPayload 解码及纯错误映射，再到主线程检查当前认证状态、弹错、更新 Published 状态并交付结果。读取可变 authToken、AuthManager 和 UI 的代码不能一起搬到后台。

保留请求、错误映射和凭据交换行为。先保持通用写请求的现有执行/订阅语义；仅详情 GET 接入可取消的读取实现。CardDetailReader 继续拥有底层订阅：一个页面取消等待不取消其他等待者；卡片失效或会话失效由 reader 取消真实请求。一次 confirmed 完成后，下一次 confirmed 仍发起确认读取；cached 只服务展示。

补一个可注入 Session、关闭 reachability 的内部构造入口，供本地 URLProtocol 测试。多订阅、retry、取消和 401 的行为必须测试，不能把所有 Future 机械改为 Deferred。记录类型、字节数、耗时，不记录正文、token、完整敏感请求或响应。SSE 线程调整与其他 service 的 Combine/async 桥取消暂不扩散修改。

### 图片

单个串行编码队列，输入不可变 UIImage，输出 CardEditingImage；后台只使用图片处理 API，UIImageView/SwiftUI 状态仍在主线程。
沿用当前 JPEG 质量：资料页 0.82、身份页 0.88、相机插图 0.9；不顺带改变分辨率、格式或上传协议。取消/换图后旧结果不上传；编码开始前显示现有忙碌状态。一次选图请求只持有自己的输入与结果，结束释放。
LocalNoteThumbnail 已使用异步 byPreparingThumbnail，继续保留；仅测量其解码和内存成本，不当作尚未异步的重复改造。

### 编辑器资源

一次安装进程内、同一资源目录及协议/schema 身份共享一次校验任务和成功结果。完整 SHA 校验仍在；失败不缓存为成功、不调用 loadFileURL。首次校验在后台；后续编辑器复用成功结果。一个等待者关闭不取消其他编辑器的校验，关闭后回来的结果不能加载旧 WKWebView。测试使用独立 validator，避免跨 fixture 的缓存污染。

## 5. 编辑器：顺序、保存、关闭

完整 BlockNoteEditorBridgeSession（包含有状态的 runtime adapter）由每个编辑器的非主 actor 独占。MainActor 保留 WKWebView、控制器 continuation、事件应用、焦点回调和生命周期。
主线程按收到顺序编号，只有一个 FIFO drain 调用 worker 并将结果按序应用；不为每条消息分别启动 Task，不能依赖 actor 接收顺序替代显式排序。

WK 回调先检查 handler/main-frame，再复制已知顶层字段为 Sendable envelope；内嵌 contentJSON 保持 String，不在主线程 JSONSerialization 全文往返。worker 完成 decode、session 转换和命令 JSON/script 编码。只传纯数据，不把 Any 或 WKScriptMessage 标成 unchecked Sendable。

返回结果带 attachment generation、sequence、state 摘要、prepared commands 与 events。主线程保留“命令 → snapshot 成功/失败 → events”顺序。自然 focus 在入口更新观察版本并排队；不能用尚未应用 ready 的主线程旧状态丢弃紧随 ready 的 focus。DOM focus probe 带观察版本进入同一 FIFO，在出队和应用时复核；较新的自然 focus 使旧 probe 失效。关闭立即禁止 mutation，旧实例事件不应用到新模型。

两类屏障必须区分：

- drainAcceptedEvents()：捕获本地已接收的序号，直到这些结果已应用到 model 才完成；不代表捕获了仍在 JavaScript debounce 内的输入。
- requestSnapshot()：通过现有 JS requestID 协议取得精确快照；显式 Save、Back、Accept 保留该步骤。5 秒超时从调用时计算，包括排队；失败/取消/关闭只完成 continuation 一次。

关闭采用同步封口与异步排空两段。WKWebView 可以立即移除 handler/停止加载；controller 与关闭任务要保留已接收事件，直到旧 editor model 更新并完成本地保存。禁止因 SwiftUI dismantle 不能 await 而直接 cancel 掉队列。

普通 autosave、inactive、onDisappear 只 drain 当前 watermark 再保存，不能永久封口一个可能重新出现的编辑器。最终 dismantle 与账号切换才 beginClosing；现有 LocalNotesController 的 editor registration 持有最终保存任务，独立于 SwiftUI View 存活。关闭回调固定旧 attachment 的 completion，不能 await 后改等新 controller。drain completion 只等待事件应用，不能等待随后使用它的保存任务。页面已离开、当前 binding 已关闭且保存成功，三者满足才注销；旧 binding 的完成不能注销新 binding。

切换 library scope 前暂停旧 scope 云同步、关闭并保存旧会话。保存失败时保留旧 scope 的 dirty 会话和错误，暂不 configure 新 scope；ContentView 按当前账号与 library scope 是否一致直接隔离旧笔记界面，显示保存中或重试入口。恢复成功后按此时最新认证目标继续切换，不重放过期的账号切换请求。不改变 AuthManager 的认证结论，也不把旧正文写入新账号。

第一版不合并有状态 adapter 的全文事件，不改变 block ID 映射；每个编辑器只有一个计算在执行。测试记录积压条数和字节数，验证停止输入后队列排空、释放旧文档。持续高输入速率造成积压仍是需要测量的风险；若代表性长文压力测试无法排空，编辑器迁移不得作为完成项交付，另行设计协议背压，不能静默丢编辑事件。

Merge 转换单独由 worker 执行，owner 保留 instance/generation/local revision 与 pending 标记。转换未完成时，clean store 通知不能重载旧正文。worker 仅返回正文、manifest 和未解析媒体引用等派生值，不返回会覆盖用户最新标签的整份 store snapshot。Accept/Back 在捕获快照到完成动作期间暂时阻止新编辑，等待精确 snapshot 的转换完成，再沿用现有 flush/commit/minimize；失败解锁、保留草稿并展示现有错误。

Merge 的认证失效同样需要排空。MergeTaskCoordinator 持有当前编辑器的关闭/排空注册；换账号或退出时立即隐藏旧 presentation/rail、禁止新用户操作和网络工作，但暂不 invalidateLifetime。先同步封口，等待 bridge 已接收正文与 codec 转换应用到原 MergeSessionStore，沿用原 actor/operation 的本地同步 persistence.save，然后才 clearRuntimeState 并按最新目标 activate/deactivate。迟到网络结果失效，已尝试的 pendingSave 身份/正文保持冻结；不能为方便清理重置 attempted 标志并改写已发送操作。

普通关闭、dismantle 和 inactive 也由 coordinator 保留该 drain，不能依赖 host View 存活。转换失败时保留旧 owner 与未处理正文，隔离 UI并提供重试，不强行 clear。该确认沿用现有 persistence API 的同步保存语义，不新增磁盘 fsync 保证。只有 Merge 的生命周期测试通过，才对 mergeArtifact profile 启用后台 bridge/codec；T6 单独交付时只启用 standard profile。

## 6. 范围、兼容性与完成标准

- iOS 16.0+，iPhone；Swift package tools 5.9，保持项目现有 Swift language mode。无需升级 Swift 6、使用 @concurrent 或新增第三方框架。
- 本次性能优化不以升级语言模式或提高最低 iOS 版本为前提；同时逐步加强并发检查，为 Swift 6 迁移做好准备。
- 编辑器 protocolVersion = 3、schemaVersion = 1；不编辑生成的 JS/CSS，不调整 Web 协议。
- 不修改 NoteSync 的持久化操作、创建/重试幂等键、Merge 保存确认顺序、数据库 schema、端点或权限。
- 本次不搬迁 MergeSessionPersistence / MergeTaskPersistence 的全量 JSON 落盘，不重写 HomeCardsManager 列表更新。二者纳入测量，只有证实形成主要成本才单独立项；完成本计划不等于所有主线程计算已经清零。
- 可交付依据：线程/取消/时效/保存正确性自动测试；真实模拟器流程；同 fixture、同设备和构建配置的前后性能记录。先记录基线，不预先承诺帧率或提速百分比。
- 每个阶段独立可回退，不需要数据迁移。出现正文丢失、跨账号污染、超时被吞、旧结果覆盖新输入时，该阶段不通过。

## 7. 依据

- [Apple：Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [Apple：Embracing Swift concurrency](https://developer.apple.com/videos/play/wwdc2025/268/)（采用执行边界原则，不照搬新语言特性）
- [Apple：UIImage](https://developer.apple.com/documentation/uikit/uiimage)（不可变图片可跨线程使用；不扩大到所有 UIKit 对象）
- [Meta：How we think about threads on iOS](https://engineering.fb.com/2024/12/18/ios/how-we-think-about-threads-ios-performance/)（公开工程实践，非所有社区统一架构的证明）
- [Alamofire 5.12.2 DataRequest](https://github.com/Alamofire/Alamofire/blob/5.12.2/Source/Core/DataRequest.swift)（项目锁定版本的 responseData 队列默认值）
