# V6 · Spark 可点击流程

本页对应 `prototype/SparkJourney.swift`。它是依据现有原生流程制作的离线交互样例，不连接 AI、账号或网络服务；不修改正式应用。

## 接入

```swift
SparkJourney(state: $state, source: note, initialStep: "results")
```

- 自带 `NavigationStack`、Close 和大尺寸 sheet 配置；在现有入口中作为 sheet 展示。
- 仅依赖原型现有 `PrototypeState`、`SampleNote` 和 `Palette`；新增文件需要加入原型构建输入。
- 颜色继承 `prototypeTheme`，默认 `forestGold`；浅深色继承系统/原型设置。正文使用系统 serif，UI 使用系统字体。
- 结果来自现有样例笔记，沿用其 UUID、作者、正文与所有权；收藏更新共享 `PrototypeState.collected`，因此可以在本次运行的 Home 收藏列表中查看。
- Like 只存在于本次 Spark 旅程。收藏和 Like 均不声称服务端保存；没有定时器、自动完成或网络请求。

## 可走通的路径

1. 进入 Spark，查看来源、当前节点和第一条相关想法。
2. 读全文再返回；点击来源条可以读来源；顶部原文按钮始终保留最初来源。
3. 收藏/取消收藏、Like/取消 Like；收藏后停留在当前结果，不自动翻到下一条。本人样例显示 `Your note`，不提供收藏自己。
4. Previous / Next idea 浏览同一节点的结果；每个节点保留自己的结果位置。
5. Continue Spark 进入明确标记的加载示例；点击 `Show sample result` 才会展示新的样例节点。可以保留当前结果，或完成示例后返回旧节点。
6. Preview state 可切换追加失败、空结果、上限等状态。失败保留已有卡片；Retry sample → 加载示例 → Show sample result 增加样例结果，不替换正在读的卡片。
7. 作者入口打开本地作者示例；没有真实关注、私信或个人主页请求。

## 确定初始状态

根入口可将 `--journey spark --step <value>` 的值直接传入 `initialStep`。具体 CLI 接入与 UI 验证由主流程完成；本文件不宣称其已通过。

| 值 | 初始画面与操作 |
| --- | --- |
| `results` | 第一节点、第一条结果、来源和可点击动作 |
| `loading` | 首次加载样例、静态骨架、手动 Show sample result；无运行中的真实请求 |
| `deeper` | 已有两个节点，当前展示第二节点；可回第一节点 |
| `error` | 已有结果上方出现 More results paused；Retry sample 不清空卡片 |
| `empty` | No new thread；可以返回来源 |
| `limit` | 保留结果、禁用 Continue Spark；仍可阅读/收藏；不虚构服务端具体深度上限 |
| `reader` | 直接进入第一条结果的全文阅读页；系统返回回到同一结果 |
| `collected` | 第一条他人结果已加入本次原型收藏；显示 Collected，可取消 |

Preview state 菜单在当前会话上切换状态，保留已有本地交互；重复选择 Deeper Spark 会新增示例节点。它是明确的设计审阅工具，不是正式产品的用户设置。

## 现有原生流程依据

- 正式入口：[PopupMenuView.swift](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/PopupMenuView.swift:102) 路由至 `SparkContinuationView`。
- 来源条、历史链、阅读和作者跳转：[SparkContinuationViews.swift](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/SparkContinuationViews.swift:174)。
- 触发/恢复中保留已有结果；错误在已有结果上展示；空态为 No new thread：[阶段渲染](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/SparkContinuationViews.swift:266)。
- 现有结果可收藏、Like、继续深入、打开正文和作者：[结果动作](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/SparkContinuationViews.swift:319)。
- 收藏不推进结果；本人不能收藏自己；深入以当前结果和当前 activity 为来源，选择旧节点会恢复该节点：[SparkSessionStore.swift](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/SparkSessionStore.swift:124)。
- 正式结果分 related / angles / keywords，追加失败有独立 moreFailed 提示：[CoreSparkModels.swift](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/CoreSparkModels.swift:3)。样例只示意分组，不声称这些笔记经过检索或相关性计算。

本轮对现有语义做可点击的视觉表达。Previous 结果按钮、显式 Show sample result 和 Preview state 是审阅原型的操作；手动的追加重试也不代表后台新增能力。原生网络恢复、幂等、登录/额度/权限检查和服务端持久化未在该样例中执行。

## 验证和定位

此独立文件已用 iOS Simulator SDK 做类型检查；不等于整个原型构建、模拟器运行或 UI 测试通过。主流程需要补实际截图、浅深色点击、跨页面收藏一致性及返回位置验证。

主要可访问性标识：

- `journey.spark.results`、`.card`、`.reader`、`.reader.screen`、`.source`、`.original`。
- `journey.spark.collect`、`.like`、`.deepen`、`.previous`、`.next`。
- `journey.spark.state`、`.loading`、`.show-result`、`.keep-results`、`.error`、`.retry`、`.empty`、`.limit`。
- `journey.spark.chain`、`.node.1`、`.node.2` 等；`.close` 关闭旅程。

预计 iPhone 竖屏的操作位置：Close 在导航左侧，Preview state 在右侧；链节点在顶部第一行，来源条在其下；Continue Spark 固定于底部安全区上方。Read full note、Collect、Like 位于结果卡片下部；较大字体或长内容时允许自然滚动。准确触控范围以主流程实际模拟器截图和可访问性树为准。
