# Chorai V6 · 功能旅程

这一版把 Spark、Merge、阅读收藏、写作保存、分享、连接举报放进同一个可点击导览。每一步同时说明当前源码行为和新视觉的呈现方式。V1–V5 保留，生产页面未迁移。

## 怎样看

- 浏览器导览：`http://127.0.0.1:8767/revisions/v6-feature-journeys/gallery/`
- `gallery/index.html` 是分文件版本；需要已有的本地 8767 预览服务。
- `Chorai-Feature-Journeys-V6-offline.html` 是可直接发送的离线单文件，包含图片、样式和流程。用电脑浏览器打开，无须 Xcode 或网络。
- 点左边的旅程，点画面编号或右侧动作继续；“全部链路”可跳到任意节点。浅深色切换保留当前节点，“上一步”回到刚才的画面。
- 浏览器导览展示原生截图，不能在截图中打字。要实际操作原生组件，双击本目录 `Open-Prototype.command`，或使用下方命令。

## 原生交互原型

独立 SwiftUI 应用 `Chorai Journeys V6`，bundle `com.chorai.nativeprototype.v6`。不替换 ArcNote 或 V5。

```bash
./Open-Prototype.command
./Open-Prototype.command --journey spark --step results --appearance dark
./Open-Prototype.command --journey merge --step selection --appearance light
./Open-Prototype.command --screen explore --appearance light
```

默认进入 Feature journeys。Spark / Merge 可以从这里打开；Explore、Home、阅读页、编辑器也保留入口。编辑器在样例保存后才进入 Spark、Merge 和 Share。

- Spark：阅读来源与结果、收藏、点赞、深入、回看前一节点、加载、追加失败重试、空结果、限深。
- Merge：固定来源与候选搜索、多选、至少两份来源的创建条件、任务界面、关闭后恢复、单一正文与标签编辑、Accept、Discard 确认、同步失败和版本冲突。
- Accept 在本次进程里插入一篇私密笔记，可去 Home 查看。同一任务不重复插入。关闭未接受草稿保留本地会话；Discard 不改原始笔记。
- 再次启动会重置样例。后台、AI 生成、同步与冲突都是人工准备的状态；没有真实后台任务或持久化。
- 工具栏 Preview state(s) 是审阅工具，直接展示对应状态。CLI `saved` 为明确的状态预览，不会偷偷保存笔记。

构建：`bash prototype/build.sh`。产物在 `/tmp/chorai-native-prototype-v6/ChoraiPrototype.app`。使用项目命令内的 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

## 覆盖范围

导览有 **6 条旅程、35 个状态节点、91 条跳转、23 个画面点击区**。共引用 **51 张原生截图**：40 张为 V6 新拍（Spark 8 状态 × 浅深色，Merge 10 状态 × 浅深色，Home / 编辑器 × 浅深色），其余沿用 V5。

- Spark、Merge、Home、编辑器具备本版浅深色画面。
- 阅读、Grid 和卡片沿用 V5。
- Share、Link、Report 和菜单目前只有 V5 浅色实拍，选择深色时明确标注仍为浅色图，读屏描述也一致。
- 收藏服务、作者与评论、正式保存失败、连接/举报真实服务回执只呈现源码规则，尚无新的完整视觉；导览用文字节点保留这些缺口。
- 编辑器是基础 TextEditor 样例。生产 BlockNote 的富文本、图片和附件能力尚未迁移。
- 原生当前 Merge 创建条件显式要求至少 2 份来源。V6 的 2–8 规则是本轮设计约束，不能称原生原来已有 8 份上限。

源码依据和交互说明在 `SPARK-FLOW.md`、`MERGE-FLOW.md`、`FLOW-MAP.md`。本次新图延续已选温白墨绿＋少量学院金；文字和卡片保持稳定阅读底，Liquid Glass 用于原生导航、操作按钮和浮层。

## 验证

最终结果见 `VALIDATION.md` 与 `design-qa.md`。截图来自 iPhone 17 Pro / iOS 26.5，原始尺寸 1206×2622。开发工具为 Xcode 27.1 / iPhoneSimulator 27.1 SDK。

未连接真实 AI、账号、后台、分享产物或举报服务。打开系统分享面板和真实发送是不同的事；本轮没有向任何人发送内容。
