# Chorai iOS · V5 设计覆盖与后续计划

日期：2026-10-21。本文记录本轮目标、现有流程依据与后续待设计范围；不作为功能、测试或服务已完成的证明。

## 本轮目标

沿用用户已选择的**温白墨绿，加入少量学院金**。保留原版及 V1–V4；V5 使用独立目录，不覆盖旧原型、配色比较或离线分享包。本轮只推进独立原生原型与设计交付，不修改正式应用源码、接口、默认公开范围或后台合同。

- 浅色保持温白阅读底与墨绿品牌感；深色跟随系统保持内容清楚。学院金用于少量 Spark、关键强调和细节，不承担长正文颜色。
- Explore 同时提供大卡片滑动浏览和移动端 Grid。借鉴 Cosmos 的图文节奏、不同内容比例与克制留白，具体排版服从 iPhone 阅读和触控；不是桌面画布，也不增加无限画布。
- 两种浏览模式使用同一组内容与收藏状态。切换模式、查看详情、返回列表时保留用户上下文；保留已有上一条/回看、跳过、收藏与撤销路径。
- 卡片是主体；操作用原生菜单、按钮、导航与弹层承接。Liquid Glass 重点服务导航与浮层层级，阅读正文保持稳定可读。
- 补齐 Share、Report、Link 等动作的可发现性时，区分原版入口、V5 演示入口和后续待落地流程，不把所有菜单合并成无权限差别的一套。
- 演示数据保持文字、图片、引文、链接等多种内容形态；不因视觉示意新增正文之外的独立标题字段。

本轮交付目标是浅深色可点击原型及对应设计图。构建、实际点击、截图、状态一致性与旧版本保留情况应在交付时分别核验；本文不预先宣称验证通过。

## 现有操作清单：按页面与所有权区分

“原来只有三个功能”不准确。原生 Explore 当前使用 2×2 菜单，且自己与他人的内容不同；Spark 等页面使用更完整的菜单。收藏、Like、评论、作者入口还存在于卡片/阅读层，不等同于菜单项。

| 场景 | 已有菜单动作 | 设计约束 |
| --- | --- | --- |
| Explore · 他人内容 | Spark、Report、Link、View | 此处原版菜单没有 Share；若 V5 展示 Share，标明是复用应用已有分享能力的入口补齐 |
| Explore · 自己内容 | Spark、Share、Link、Edit | Edit 与 View 按所有权区分；不显示举报自己 |
| 完整菜单 · 他人内容 | View、Spark、Share、Link、Root、Report | 现行 3×2 的末项是 Report，不是过时注释中的 Pin；Root 保持来源语义 |
| 完整菜单 · 自己内容 | Edit、Spark、Merge、Public/Private、Share、Link、Root、Remove、Pin/Unpin | 可见性与置顶项随真实状态切换；Remove 和举报不能混用 |

依据：[Explore 菜单接入](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/ExploreView.swift:641)、[菜单实际分支](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/PopupMenuView.swift:431)、[Spark 按所有权选择菜单](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/SparkContinuationViews.swift:91)。旧枚举注释不作为实际动作清单。

## 后续待设计

### 第一阶段 · Explore 双模式与阅读闭环

优先完成本轮 V5 目标，再覆盖下列状态：

- 大卡片/网格切换、滚动与回看位置、收藏/撤销、内容详情及返回、完整菜单、作者入口。
- 网格保留真实图文比例和摘要可读性；不把所有笔记强制裁成相同图片海报。
- 首次加载、继续加载、无内容、搜索无结果、加载失败/重试；长文本、纯文字、多图、缺失图片。
- 收藏他人内容和保存本人笔记使用不同文案与状态。Grid 中的多选是后续选材流程，不应因视觉样式自动改变当前滑动动作。
- 后续多选设计参照既有产品规则：单选可 Spark，2–8 个有效来源可 Merge；数量、取消/清空、不可执行原因均可见。

可借鉴 [Web Reading Trail](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/docs/design/2026-10-06-flow-reading-trail/SPEC.md>) 的完整正文、上一条/下一条与收藏后停留。索引只表达实际结果顺序，不包装为知识图谱。

### 第二阶段 · Spark 完整流程

当前正式入口是 `SparkContinuationView`，不是旧 `SparkView`。围绕“来源 → 结果 → 继续深入/收藏/阅读 → 返回”设计：

- 来源作者与内容、链节点及当前节点；结果卡片、收藏、Like、继续 Spark、阅读全文、作者页和菜单。
- 初次加载、恢复已有会话、追加结果加载、空结果、追加失败/重试、离线、额度不足、最大深度与不可恢复状态。
- 加载或失败时有已有结果就保留，不把所有情况画成清空后的转圈。
- 编辑器触发 Spark 前先保存；保存失败留在编辑器并保持可继续写作。返回时不重复生成、不丢失原文。
- Web 的“捕捉自己的想法、认识作者、继续原文”可作为闭环补齐参考；当前原生 Spark 页面未看到独立的“捕捉想法/继续写原文”控件，需核对原生现有入口后再确定落地范围。

依据：[正式路由](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/PopupMenuView.swift:102)、[Spark 阶段](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/SparkContinuationViews.swift:266)、[结果动作](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/SparkContinuationViews.swift:319)、[编辑器先保存](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/NewNoteView.swift:1157)、[Web 写作闭环](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/docs/design/2026-10-06-writing-spark-loop/SPEC.md>)。

### 第三阶段 · Merge 选材、后台任务与结果编辑

当前正式实现位于 `CoreFlow/MergeLifecycleViews.swift`；旧 `private LegacyMergeView` 不作为流程依据。

- 选材：固定来源、候选搜索、多选数量、来源版本、不可用来源、空列表/搜索无结果/加载失败。固定来源不能被普通清空操作误删。
- 进行中：检查能力、创建、生成、打开结果；任务被后台接管后可以回到原处，再从任务入口找回。
- 离开与取消：关闭/最小化只离开当前视图；取消需明确确认，不能混成一个按钮。
- 可恢复状态：暂停、失败、重试、取消失败、恢复任务；根据真实可用操作展示按钮。
- 结果：可编辑正文与标签、附件保留、同步中/未同步/离线/失败；冲突提供“重新载入服务端版本”和“保留我的版本”。
- 接受与丢弃：Accept 先同步草稿再提交；生成结果不等于已经保存为笔记。Discard 丢弃本次任务草稿，不删除来源；完成后可打开已保存结果并返回。

**2–8 的差异必须在落地前核实：**Web 产品规范与实现要求 2–8 个有当前版本的已保存来源；原生当前 `canCreate` 仅检查 `selectedSources.count >= 2`，已审阅的 `toggleSelection` 没有 8 个上限。设计按产品的 2–8 规划，但不能宣称原生客户端已限制到 8，更不能凭此推断服务端接受任意数量。

依据：[候选及版本](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeLifecycleViews.swift:297)、[后台接管](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeLifecycleViews.swift:175)、[任务阶段](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeLifecycleViews.swift:665)、[结果编辑/同步](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeArtifactEditorSurface.swift:302)、[冲突与提交](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeArtifactEditorSurface.swift:452)、[原生创建条件](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:56)、[原生选择逻辑](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:188)、[Web 选材规范](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/docs/design/2026-10-06-full-frontend-redesign/ROADMAP.md>)。

### 第四阶段 · 其余页面、权限与原生状态

- Home 与本人笔记：搜索、收藏内容、置顶、公开/私密、移除确认、加载/空/错误状态。
- 完整编辑器：单一正文、已有格式和附件、标签、键盘/选区/撤销、保存失败、离开时的未保存处理；不把基础 TextEditor 演示当成生产 BlockNote 编辑器已迁移。
- 阅读与关系：完整内容、评论、作者/个人页、Link、Root 与真实来源关系；所有权决定可执行动作。
- 分享与举报：真实分享产物、权限变化、系统分享、取消/失败；举报原因、提交中/失败/完成。用现有服务能力，不编造分享链接或举报回执。
- Chat、Chora、设置、隐私与通知：逐项核对现有能力再设计。Chora 的进度和表情对应真实任务状态或直接互动，不随机展示“正在思考”。
- 通用验收：浅深色、动态字体、44pt 触控区、VoiceOver、Reduce Motion、Reduce Transparency、安全区与键盘避让。用户切换显示方式不改变主要路径。

补充参考：[Web 完成矩阵](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/docs/design/2026-10-06-complete-redesign/completion-matrix.md>)、[Companion Atelier](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/docs/design/2026-10-06-companion-atelier/SPEC.md>)。这些用于查漏和语义对齐，不要求把桌面布局搬到手机，也不代表原生已完成同等覆盖。

## 原型与真实服务的边界

- V4 的 Spark、评论和 Chat 是说明性入口；基础编辑器是本地单一正文样例，Merge 尚无完整原型。它们是后续待设计范围，不是已接通能力。
- V5 的样例操作只能证明本地交互表现。若分享页、举报页、Spark 或 Merge 状态使用离线示例，必须明确标注；不能显示真实分享产物已生成、举报已提交、AI 已生成或服务已成功的假结果。
- 系统分享面板能够打开也不等于生产分享链接或卡片产物可用；举报表单能够选择原因也不等于服务端收到举报。
- 构建成功、模拟器启动、离线操作通过、数据本地持久化与服务联通是分别核验的状态。未核验的状态不写“完成”。

V4 依据：[Spark 占位](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/design/2026-10-21-native-visual-reform/revisions/v4-rich-cards/prototype/ChoraiPrototype.swift:241)、[评论占位](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/design/2026-10-21-native-visual-reform/revisions/v4-rich-cards/prototype/ChoraiPrototype.swift:279)、[基础编辑器说明](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/design/2026-10-21-native-visual-reform/revisions/v4-rich-cards/prototype/ChoraiPrototype.swift:561)。
