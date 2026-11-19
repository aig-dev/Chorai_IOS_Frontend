# Merge、首页列表与读取复用

用户已将“处理 Merge 剩余的主线程解码，再优化首页大列表和重复请求”设为执行目标。本设计使用已选定的现有 worker/reader 方案，作为本轮实现与验收依据。

## 范围与选择

1. Merge：`makeCleanDraft` 仍在 MainActor 进行完整 codec decode。将 clean draft 准备纳入已有 MergeArtifactEditorWorker，并让 store 与 editor 共享同一个 job 内 worker。同一文档的纯 decode 结果允许有界复用；展示 URL 每次重新验证。服务器加载、无本地修改的冲突恢复、用户 reloadServer 三条路径均覆盖。
2. 首页：HomeCardsManager 在 MainActor 全量转换/排序，批量更新逐条搜索和移动数组。使用该模块的串行 projection worker；全量排序在 worker，增量更新对变化集排序后与未变集合归并。MainActor 聚合待处理变化、验证 scope/排序/页面身份后一次发布。后台结果不能复活已删除内容或跨账号覆盖。
3. 读取：复用现有 CardDetailReader；聊天引用与首页云卡片刷新使用同一入口。NoteLibraryStore 对同一 scope 下尚未下载的同一 asset 合并在途 open。公开用户卡片分页也要合并同页并发请求，并丢弃旧账号/旧 profile 的迟到结果。只合并读取；写请求和显式刷新语义保持。

采用模块内有界状态而非全局网络缓存；后者需要定义所有接口的权限、过期与写后失效规则，超出当前失败模式。保持同步持久化 API，本轮不改磁盘耐久性及写确认顺序。

## 行为约束

- 保留现有 Swift language mode、iOS 16.0+、协议/schema 与 endpoint；不新增第三方依赖。
- 本次性能优化不以升级语言模式或提高最低 iOS 版本为前提；同时逐步加强并发检查，为 Swift 6 迁移做好准备。
- Merge decode 等待期间的新正文/标签不得被 canonical 结果覆盖；关闭/换账号使远程准备结果失效。已发送的 pendingSave key/body 不变。
- 不兼容文档仍可加载到既有只读/兼容路径，不能因为 manifest 准备失败丢掉原始数据。
- Merge decode 复用最多一个文档且限制约 1 MiB 的输入/结果估算字节，超限只计算不保留。账号/任务不共享 worker；媒体展示授权不进入纯 decode 缓存。
- 列表顺序保留置顶、日期升降序和 ID tie-break；本地 identity/scope/bodyRevision 不变。临时队列合并只作用于可重建列表投影。
- 同一份读取结果可供多个等待者使用；一个取消不取消另一个。会话失效清除结果和在途任务，403/404 不能被缓存掩盖。
- 只使用 Local/合成数据验证；Production 只构建。不提交、推送或覆盖上轮工作。

## 验收

- 运行时 probe 证明 canonical decode、列表转换/排序不在主线程；MainActor 仍负责状态发布。
- 人为阻塞 decode/列表/网络，覆盖后到编辑、scope 切换、排序切换、删除、失败重试和旧结果拒绝。
- 同文档准备/编辑投影仅实际 decode 一次；同一未下载 asset 并发 open 只发一次 detail；共享卡片 reader 的并发消费者只发一次 GET；相同 profile/page 并发加载只推进一次分页。
- 1000 条笔记的全量及批量更新记录相同 fixture 下的前后耗时与主线程应用成本；测量只报告实际环境，不以模拟器数字承诺真机收益。
- CoreFlow、BlockNoteEditor、应用测试及相关 UI 流程回归；Local/Production 构建；更新执行规范、历史和验证记录。既有 UI 基线失败单独列出。
