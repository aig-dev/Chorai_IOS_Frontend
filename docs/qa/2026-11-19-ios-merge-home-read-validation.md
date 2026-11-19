# Merge、首页列表与读取复用验收

本轮范围为 [设计](../superpowers/specs/2026-11-19-ios-merge-home-read-efficiency-design.md) 与 [实施计划](../superpowers/plans/2026-11-19-ios-merge-home-read-efficiency.md)。基线为上轮执行边界改动完成后的工作区副本，不是单独的 git HEAD。源码入口与新功能约束见 [执行架构](../architecture/execution.md)。

## 运行环境与证据

- macOS 27.2.1，Xcode SDK 27.2；Swift 5，最低 iOS 16 保持。
- App 测试：独立的 `Chorai Execution QA` iPhone 17 Pro / iOS 26.2 模拟器；网络使用 URLProtocol/计数 stub，未知请求不放行。Production 只构建。
- 本轮日志、原始 xcresult、前置源码副本与进度记录位于 `.superpowers/sdd/2026-11-19-ios-merge-home-read-efficiency/`；Xcode DerivedData 复用上一轮的专用目录。

## 正确性

| 边界 | 运行时验证 |
| --- | --- |
| Merge canonical 准备 | decode probe 证明非主线程；clean draft 与 editor projection 对同一文档只 decode 一次；超预算不保留；无效正文原样保留 |
| Merge 等待与所有权 | 初次准备未完成不发布 ready；退休拒绝迟到结果；clean conflict 与显式 reload 等待期间的新正文/标签保留 |
| 大列表 | 1000 行、200 行更新，与独立全量排序结果一致；置顶、升降序、同日期 ID tie-break、删除、账号与排序切换均覆盖 |
| 连续输入 | 一个 drainer 合并待处理变更，新的 reset 替代旧输入，后台结果不能复活删除的笔记或跨 scope 发布 |
| 未下载笔记 | 两个 open 只调用一次 detail、一次落库发布；一个取消不影响另一个；失败重试、scope 切换拒绝旧结果；已下载内容不再请求 |
| 同步 | 同时 synchronize 继续共用 NoteSyncCoordinator 原有在途工作，没有第二层同步缓存 |
| 聊天与详情 | publisher 创建时不发请求；聊天和 async 详情只发一次 GET；取消一个订阅不会中止其他读取者 |
| 公开主页 | 同 profile/page 重复加载一次请求、一次翻页；刷新取代下一页；切 profile/session 拒绝旧结果；失败可重试 |

## 测量

所有数字为合成数据 Debug 样本；不是设备帧率、生产延迟或峰值内存。列表数据取 `app-final-summary.json` 对应 57 项回归的 20 次样本，同一 1000 行输入，更新其中 200 行；测试保留改动前算法用于对照。

| 列表工作 | p50 ms | p95 ms | 执行位置 |
| --- | ---: | ---: | --- |
| 原全量映射/排序 | 4.75 | 4.93 | 主线程 |
| 新全量映射/排序，含 actor 往返 | 4.60 | 4.77 | 计算在 worker |
| 原批量更新 200 行 | 12.11 | 12.90 | 主线程，逐条扫描/移动数组 |
| 新批量更新 200 行，含 actor 往返 | 2.23 | 2.29 | worker，排序变更集后线性归并 |

列表主线程 `@Published` 赋值（一个空 Combine 订阅，1000 行）p50 为 0.075 ms、p95 为 0.104 ms。它不包含 SwiftUI 布局和实际滚动，不能据此声称滚动已达到某帧率。

Merge 使用 macOS CoreFlow 测试中的 1000-block / 96,832-byte 文档，25 次运行去除前五次。

| Merge 工作 | p50 ms | p95 ms |
| --- | ---: | ---: |
| 原 canonical decode，同步基线 | 38.07 | 53.20 |
| 新 canonical clean draft，冷 worker 往返 | 37.87 | 49.12 |
| 同文档后续编辑投影，复用 decode | 4.50 | 7.13 |
| 仍同步的 UserDefaults 持久化 | 3.16 | 3.97 |

canonical decode 的收益是移出主线程并避免紧接着重复 decode，不是消除首次计算。独立线程 probe 和门控测试证明执行位置与应用资格。

## 验证结果

- CoreFlow：1050 tests，6 个明确的 live-API skip，0 failures。
- BlockNoteEditor：76 tests，0 failures。
- 完整 App：58 tests，0 failures（含独立审查修复回归）。追加用例先复现未授权 profile 入口仍可发布旧 owned projection；现在该分支也立即退休旧投影与 loading owner。
- 模拟器：6 个选定流程通过（普通编辑器 ready、Merge 立即 Back 后重开、clean conflict、pending tag、延迟 Accept、无损失败下 Back 保留）。
- Local 与 Production 在修复后已分别重新构建通过；编译产物的 `ChoraiAPIEnvironment` 分别为 local / production。
- Local 安装后终止并无参数重启，进程日志仍为 `environment=local`、`127.0.0.1:8180`。未完成字面意义的 Simulator 图标点击；没有把 CLI 重启写成图标操作。
- 一次 fresh-context 独立只读审查完成。审查指出首个列表投影未完成时就清除 loading，导致非空离线库短暂显示空态；先用 gate 测试复现失败，再等待当前投影并重新验证 owner/generation。修正后的完整 App 58/58 通过；修复后的 Local 与 Production 最终重建均成功（exit 0）。

## 限制

真机滚动帧率、SwiftUI 大列表布局、峰值进程内存和能耗未测。同步持久化 API 保持原契约；完整 Swift 6 迁移不在本轮范围。原有 Combine 传输接口的并发诊断并未全部清零。新注入的 MainActor 闭包明确标记 Sendable；测试的 session 也由 MainActor fixture 持有，避免可变局部捕获。Xcode 的 complete-concurrency 编译输出含旧警告及 exit-code-0 包装诊断，构建退出码和 xcresult 均单独核对。

上轮已证明的两项既有 UI 问题仍单独保留：旧 Home menu fixture 未进入真实已授权本地笔记路径；Merge 选择后的段落上边界约 3pt 裁剪。详见 [上轮验证记录](2026-11-19-ios-execution-validation.md)。本轮不以跳过的旧用例宣称它们已修复，也不修改生成的 editor JS/CSS。DEBUG Merge fixture 仅内存持久化，不能用它证明进程重启后的草稿恢复；持久化保证来自实际 UserDefaults 测试。

## 审查裁定

独立审查只提出上述 loading 时序问题。执行者按实际行为将其从 Minor 提升为本轮必修的正确性回归，因为新异步边界不应把尚未准备完成的数据报告为空；修复只增加等待已有 drainer，没有新的状态模型。

审查未进一步评价的既有 Home fixture、Merge 裁剪、旧 Swift 6 告警与同步持久化继续保留：前两项已有基线证据；语言迁移与耐久性 API 改造不属于本轮，新增闭包跨隔离声明已改成明确 Sendable。代价是这四项仍需后续各自验证。没有需要单独延期的本轮 minor 项。未提交、推送或清理既有工作区；基线和日志继续保留供复核。

文档检查：Go 工程入口要求的 `make check-docs` 通过（22 module pairs / 104 Markdown files）；iOS 仓库没有该 Make target，因此另外核对本轮所有修改 Markdown 的本地链接，零断链。`git diff --check` 通过。
