# V7 · 等级与成长流程依据

本图谱只承接卡片等级与 Chora 成长的遗漏项；[V6 功能旅程](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/design/2026-10-21-native-visual-reform/revisions/v6-feature-journeys/gallery/index.html)中的阅读、写作、Spark、Merge、分享、连接与举报保留。正式源码行为与本轮迁移提案分开记录，样例画面不作为后台成功证明。

## 本轮可查看的状态

原生演示使用 `--journey levels --step <状态>`。以下状态名用于预览定位，不是新增产品路由或后台状态。

| 状态 | 要看什么 | 交互与语义 |
| --- | --- | --- |
| `basic`、`notable`、`valuable`、`significant`、`exceptional`、`definitive` | 同一套六级标记、名称与小型卡边形象 | 切换样例比较视觉；不会给任何笔记重新评级 |
| `grid` | 多种等级放在同一个 Explore 网格时的密度与辨识度 | Explore 等级标记与说明入口属于迁移提案，不新增权限 |
| `merge` | 结果审核中的等级名称与形象 | 结果就绪、等级揭晓、Accept 保存分开；看见等级不等于已经保存结果 |
| `growth` | 固定 Thread 阶段与六维成长样例 | 只读样例；不因 Collect、Merge 或切换卡片而升级 |
| `unknown` | 缺少可靠等级时的中性表面 | 属于提案；没有把当前原生负数归 Basic、缺失默认 1 的逻辑改掉 |

卡边形象沿用 Web 已批准的小尺寸趴边、探身与抱角方向：III 放上沿，只有 V · Exceptional 使用绿金，正文区域保持干净。依据：[Web 已批准版本](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/docs/design/2026-10-19-chora-card-system/README.md:9>)。复用素材不表示 iOS 已完成生产迁移。

## 卡片等级：已有数据，展示尚未全覆盖

六级阈值固定为 **Basic <3、Notable 3–8、Valuable 9–26、Significant 27–80、Exceptional 81–242、Definitive ≥243**。[原生映射](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/CardLevelStyle.swift:16)

- **Home 已有等级材质与本人笔记排序。**等级通过卡边和局部色彩处理；本人笔记的 Rarity 高低排序传递 rate 升降序。非搜索收藏列表目前只重新加载收藏，没有传该排序，因此不能把其排序能力一并算作完成。[材质](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/HomeView.swift:1469)、[排序入口](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/HomeView.swift:561)、[分支](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/HomeView.swift:117)
- **Merge 已有等级名称与结果材质。**显示文字等级，数值不作为 UI 分数；等级胶囊本身不是升级按钮。客户端读取 draft / presentation 的 rate；保存请求没有 rate 字段。[等级展示](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeArtifactEditorSurface.swift:275)、[读取 rate](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeArtifactDraftController.swift:69)、[保存合同](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/CoreMergeModels.swift:809)
- **Explore / 阅读的统一等级展示是这次补齐。**FlowCard 虽有 rate，当前 Flow 仍用统一背景；Detail 传递 rate 到笔记模型，没有独立等级说明入口。V7 的标记与 About level 弹层属于提案。[Flow 数据](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/CoreFlowModels.swift:28)、[Flow 背景](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/FlowViews.swift:460)、[Detail 数据](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/DetailView.swift:66)
- **动作继续由所有权决定。**原生菜单没有手动改等级的能力；本人内容仍为 Edit / Share，Explore 他人内容仍为 View / Report，Link 与 Spark 保持各自意义。等级不解锁新权限。[菜单分支](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/PopupMenuView.swift:434)

## 不把数值累积说成质量打分

仓库规范描述的 Merge 规则是：冻结来源 rate；缺失或非正值按 1；溢出安全地求和；同一结果后续编辑保持 rate 不变。三个 rate=1 的来源对应结果 3，即 Notable。这是**规范中的服务端计算定义**，本轮没有检查运行中的后台或实际返回值。[规范与例子](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/superpowers/specs/2026-08-17-ios-merge-wysiwyg-preview-design.md:160)

该规范把等级描述为正向知识价值的层级，但没有据此承诺“更高等级一定更正确”，也不是作者信誉分。About level 应解释已有含义与来源，不新增 AI 评分、用户排名或自动升级承诺。[语义说明](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/superpowers/specs/2026-08-17-ios-merge-wysiwyg-preview-design.md:105)

**未知输入须单独区分现状和提案：**当前原生 `CardLevelStyle` 把负数、0 映射 Basic，卡片 DTO 缺失 rate 默认 1。V7 中性未知态是拟迁移的展示规则，不代表正式客户端或后台已修复。错误类型仍可能解析失败，不应悄悄画成有效高等级。[边界测试](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Tests/CoreFlowTests/CardLevelStyleTests.swift:13)、[缺失默认值](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/CardResponseModels.swift:154)

## Chora：独立的阶段与六维成长

| 维度 | 当前合同 | 展示要求 |
| --- | --- | --- |
| 阶段 | 0 Initial、1 Trace、2 Thread、3 Weave、4 Co-Think、5 Second Voice | 使用服务器 committedStage；不能展示候选阶段来暗示已升级 |
| 六维 | Curiosity、Insight、Creativity、Empathy、Judgment、Resonance | 各维有效值 0–12；不由卡片等级换算 |
| 无效 / 不可用 | 未知 stage 名称为空；无快照、请求失败或无效维度都有不可用处理 | 显示 Unavailable，不补成零分或伪造阶段 |
| 用户操作 | Growth 只读；获取失败可重试 | 姓名、称呼、头像编辑属于 Identity，不是成长编辑 |

依据：[阶段枚举](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/ChoraProfileModels.swift:37)、[维度与有效范围](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/ChoraProfileModels.swift:83)、[committedStage 映射](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/NetworkChoraProfileService.swift:170)、[原生成长展示与重试](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/ChoraIdentityGrowthSections.swift:109)、[不可用数值展示](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/ChoraProfileSections.swift:605)。

V7 的 Thread 与六维数值均为固定样例。卡片六种形象标记的是六级内容身份，不能直接对应 Chora 六阶段；也没有“收藏一次升一级”或“每次 Merge 自动成长”的规则。

## 本轮交付边界

浏览器图谱用于查看原生截图和解释步骤；模拟器用于体验原生控件。离线样例不查询或修改真实评级、成长与笔记。构建、交互、截图、离线文件生成与验证结果由本轮验收另行记录；本文不提前声明通过。
