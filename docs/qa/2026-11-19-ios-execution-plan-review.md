# iOS 执行边界实施计划检查记录

日期：2026-11-19。
代码基线：c5f005037f2c88bdccdbc5209060a62f68d40bd0。
结论：计划层面的已发现阻塞项已修正；可以进入用户审阅和分阶段实施。不是产品验收，也不是性能测试报告。

- [设计](../superpowers/specs/2026-11-19-ios-execution-boundaries-design.md)
- [实施计划](../superpowers/plans/2026-11-19-ios-execution-boundaries.md)

## 检查方式

主代理核对现有 View、Store、reader、网络回调、资源校验、编辑器控制器和持久化调用，并按设计覆盖、任务接口、测试条件与范围做自审。编辑器专项检查核对消息顺序、焦点、snapshot 和退出保存；独立审阅者核对完整计划与源码，并对两项阻塞问题的修订做针对性复核。

当前图索引与 HEAD 不一致且不覆盖此次 Swift 细节，证据以当前源码为准。没有更新代码图，也没有据静态扫描推断实际耗时。

## 发现与处置

| 问题 | 证据/失败窗口 | 计划处置 | 状态 |
| --- | --- | --- | --- |
| 本地预览输入没有完整身份 | HomeCardsManager.localCard 丢 bodyRevision，ownerActorId 取当前用户；视图再推断 scope | T1 从 library 变更源捕获 scope/revision，UserCard 仅客户端身份贯通，不进入 wire JSON，不降级远程 | 独立复核关闭 |
| FlowTextPreview 仍主线程清洗 | Explore 与 Spark 调用 make 执行全文正则 | T1 将原语义作为 presentation.plainText 后台准备，删除独立 textCache，预算计入该字段 | 已纳入 |
| 取消订阅不等于取消 HTTP | 通用 Future 未持有 receiveCancel→DataRequest.cancel 的链路 | T2 仅先接详情 GET，真实 URLProtocol.stopLoading 验证；不扩大到写操作 | 已纳入 |
| 普通笔记关闭时可能保存旧正文 | NewNoteView.persistLocalDraft 直接读 editingStore；dismantle 原本即时 teardown | T5 drain 后检查 dirty；registration 持有最终保存，旧 binding completion 固定，避免自等待/误注销 | 专项检查关闭 |
| inactive/重现不能永久封口 | 系统弹层、切后台、暂时离场后仍可能重用编辑器 | T5 watermark flush 与最终 beginClosing 分开 | 专项检查关闭 |
| ready 后紧随 focus 可能被丢弃 | 异步化后主线程 readiness 落后 | T6 自然 focus 与 DOM probe 进入同一 FIFO，入口更新观察版本并复核 token | 已纳入 |
| Merge 转换期间可能重载旧正文/丢标签 | reconcileCanonicalProjectionAfterStoreChange 原依赖同步更新 projected identity | T7 pendingLocalRevision、generation 检查、派生 DTO，不携带旧完整 store snapshot | 专项检查关闭 |
| Back 在异步 snapshot 后仍可输入 | 当前 Back 无 Accept 同等的动作锁 | T7 final-action token，允许内部最终转换、阻止后续输入，失败解锁；Back 不新增云端等待 | 已纳入 |
| Merge 账号失效会丢排队正文 | Portal 立即 activate/deactivate→clearRuntimeState→invalidateLifetime；updateArtifactDraft 随后拒绝写入 | T7 coordinator 持有 seal→bridge drain→codec drain→旧账号本地 save，之后才失效；保留 attempted pendingSave。T6 暂只启用 standard profile | 独立复核关闭 |
| Worker 返回值遗漏引用解析结果 | 只有 Data/EditableDocument 无法承载主线程外已计算的 unresolved refs | T7 明确 PreparedProjection/PreparedDraft 与不可变 URL 输入 | 已修正 |
| 旧源码契约会阻挡正确迁移 | NewNoteViewSourceContractTests 强制原函数直接 jpegData | T3 同步更新接入断言，线程/质量由运行时测试验证 | 已纳入 |

## 范围与可实施性核对

- 每项变动有所属文件、输入/输出、owner、失败用例、验证方式和交付条件；T1–T7 对应设计要求。
- 沿用 iOS 16、现有 Swift mode、CoreFlow/BlockNoteEditor/Alamofire，不要求新框架或 Swift 6 升级。
- 新建 ArcNoteTests 解决现有项目缺少应用单元测试 target 的问题；SwiftPM 测试不替代 UIKit/实际 WK 流程。
- 资源完整性、账号隔离、snapshot deadline、幂等操作和精确保存均有验收；不能只用“已加 async”交差。
- 原始预览缓存限制、图片质量、编辑器协议保持明确；并发数 2 是初始实现配置，性能变化由基线决定。
- 旧 Merge 全量序列化、列表批量计算、其他 firstValue 和 SSE 是明确剩余范围，未冒充已解决。

## 本轮验证与限制

已完成：当前代码与路径核对；设计/计划本地 Markdown 链接与空白检查；7 个任务段及未勾选实施步骤核对；git diff --check。最终工作区核对确认本轮只新增这 3 份文档，保留此前 3 个 xcuserdata 改动。

本轮未运行：Swift/Xcode 产品测试、模拟器业务流程、Instruments、真机测量。没有业务代码、schema、生成资源、Git 分支、提交或推送变动。计划中的测试名、接口与性能记录文件属于后续实施产物，不是已经通过的结果。

执行从 T1 开始；A/B 各项可单独验证和回退。C 必须先证明普通笔记与 Merge 的关闭/保存生命周期，再全面启用异步编辑器。运行时验证失败时不能沿用本记录宣称该阶段完成。
