# Merge/Home Read Efficiency Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for inline implementation and one final independent review. Preserve the current checkout and all prior uncommitted work.

**Goal:** 处理 Merge 剩余的主线程解码，再优化首页大列表和重复请求。

**Architecture:** 复用 MergeArtifactEditorWorker、CardDetailReader 与 NoteLibraryStore；HomeCardsManager 拥有独立列表投影 worker。后台准备不可变结果，状态 owner 校验身份后发布。

**Tech Stack:** Swift 5、SwiftUI/Combine、CoreFlow、BlockNoteEditor、XCTest。

**Spec:** [设计与验收](../specs/2026-11-19-ios-merge-home-read-efficiency-design.md)。用户已选择此范围并要求持续执行，无需再次确认方案或执行方式。

## Global Constraints

- iOS 16.0+；本次性能优化不以升级语言模式或提高最低 iOS 版本为前提；同时逐步加强并发检查，为 Swift 6 迁移做好准备。
- 不改 API/存储/schema/权限，不改生成 JS/CSS，不引入全局缓存；只测 Local，Production 只构建。
- 保留现有工作区、上轮 T1–T7 和用户 xcuserdata。基线为本轮 scratch 的 baseline 副本，而非仅 git HEAD。

## Review Focus

1. canonical decode 等待时输入新正文、标签或执行 reload/retirement：原 owner 的最新编辑保留。
2. 不兼容或超大 Merge 文档：兼容行为不变，复用内存有界，展示授权独立验证。
3. 多次列表 reset/update 与 scope/排序切换交错：最终完整列表正确，旧结果不发布。
4. 相同读取取消一个等待者、失败后重试、注销后返回：共享和失效行为符合原权限。
5. 刷新撞上分页或切 profile：分页只推进一次，旧用户内容不能写回。

## Task 1 — canonical Merge preparation

Files: 修改 Packages/CoreFlow/Sources/CoreFlow/MergeArtifactEditorWorker.swift、MergeSessionStore.swift、ArcNote/CoreFlow/MergeArtifactDraftController.swift；测试 MergeArtifactEditorWorkerTests.swift、MergeSessionStoreArtifactTests.swift 与 app Merge suites。

Interface: worker.cleanDraft(from: MergeArtifact) async throws -> MergeArtifactDraftSnapshot；store.editorWorker 为同一 job 的 worker，controller 默认复用它，测试允许注入。

- [x] RED：worker cleanDraft/projection 共用 decode、线程与预算；store 初始准备阻塞时未 ready、退休拒绝迟到结果；clean conflict/reloadServer 等待时新编辑不被覆盖。
- [x] GREEN：已有 actor 实现纯准备、有界单文档复用；每条新 await 后校验 lifetime、job、draft/冲突身份，再原子应用到 store。
- [x] 验证：`swift test --package-path Packages/CoreFlow --filter 'Merge'`，app Merge suites；零失败。

## Task 2 — large local lists

Files: 新增 ArcNote/CoreFlow/HomeCardProjectionWorker.swift 与 ArcNoteTests/HomeCardProjectionTests.swift；修改 HomeCardsManager.swift、NetworkModels.swift、项目 target membership 与受影响 source contracts。

Interface: worker.reset(notes:scope:sortBy:sortOrder:) / update(changed:removed:) async -> [UserCard]；MainActor manager 合并待处理增量，按 generation 接受结果，暴露测试用 drain 等待真实投影结束。

- [x] RED/基线：1000 条笔记及批量更新；排序/置顶/tie-break，与当前等价；gate 中 scope/sort 切换、连续更新与删除不丢失。
- [x] GREEN：worker 内日期格式化/映射/排序；增量变更集合排序后线性归并；最多一个 drainer，按最新 reset 和每个 ID 的最后变更聚合。
- [x] 验证：完整 app tests、相关 CoreFlow source contracts；记录前后 fixture 测量。

## Task 3 — repeated reads

Files: 修改 Packages/CoreFlow/Sources/CoreFlow/NoteLibraryStore.swift、ArcNote/CoreFlow/CardDetailReader.swift、ArcNote/Models/ChatModels.swift、HomeView.swift、HomeCardsManager.swift；测试 NoteLibraryStoreTests.swift、CardDetailReaderTests.swift、新增 HomeCardsLoadingTests.swift。

- [x] RED：两个同时打开未下载 asset 的调用只有一次 detail；一个取消另一个成功；scope 失效、失败重试；聊天与详情共享同次 GET；同 profile/page 并发加载只请求一次并只推进一页，切 profile 拒绝旧结果。
- [x] GREEN：NoteLibraryStore 原 scope 拥有下载任务及落库，先检查现有本地数据；CardDetailReader 提供可取消 publisher 适配；调用者使用现有确认/强制刷新策略。公开列表按 session/profile/page 拥有在途请求及结果资格。
- [x] 保留 NoteSyncCoordinator 已有 synchronize single-flight；测试确认，不新增另一层同步缓存。
- [x] 验证：完整 CoreFlow 和 app tests；网络使用计数 stub/隔离 Session，未知请求拒绝。

## Task 4 — integration and evidence

- [x] 更新 docs/architecture/execution.md、execution.history.md，新建 docs/qa/2026-11-19-ios-merge-home-read-validation.md，记录性能、正确性和未验证项。
- [x] 完整 CoreFlow、BlockNoteEditor、app tests；相关 Merge/Home/读取 UI 回归；Local/Production build。
- [x] 单次独立审查本轮相对 scratch baseline 的改动；重要问题 RED→GREEN 修复。保留既有未完成项，不将其写成已通过。
- [x] 审计目标的三部分均有代码与运行时证据后，更新 goal complete；无提交/推送。
