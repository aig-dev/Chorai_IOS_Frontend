# Chorai iOS 原生视觉改造计划

日期：2026-10-21。范围：原生 iPhone App。已交付独立原生可点击原型及 Explore、Home、编辑器的六张浅／深色设计图，供第一轮审阅。正式 App 的视觉迁移尚未实施；下述迁移范围与规范仍待用户审稿后确定。

## 1. 已确认的目标

- 尽可能发挥 iOS 原生组件、系统材质、手势、键盘、字体、触觉和无障碍能力。
- 用户已选择：跟随系统浅色／深色模式，保留温白、墨绿的 Chorai 品牌感。
- 保留现有产品体验：功能、页面入口、操作顺序、内容关系、权限、保存和任务状态语义不变。
- 从现有 Web 借鉴品牌与内容排版；不把 Web 的导航、桌面布局和 CSS 效果移植到 iPhone。
- 先比较真实页面的视觉方案与可点击原型，再逐个页面实施。此文不授权同时重写导航状态机、富文本引擎或后端合同。

建议的方向：**系统原生控件 + Chorai 的阅读气质 + 克制的品牌表达**。内容承载信息，玻璃承载操作，Chora 提供个性。

## 2. 现状核验

| 当前事实 | 影响 | 对应改造 |
| --- | --- | --- |
| 主壳是 PageTabViewStyle 加自绘 CoreTabBar | 使用 SwiftUI 不等于使用系统 Tab Bar；材质和隐藏逻辑由应用维护 | 比较标准 TabView 与现有选择状态、键盘、覆盖层、onboarding 合同后迁移 |
| 三个 Tab 重复铺 home_bg，多个页面固定白字 | 只换背景会造成浅色模式不可读 | 同步迁移背景、前景、分隔线和控件状态为语义颜色 |
| 真正 glassEffect 目前集中在 CardEditorGlassSurface 两处 | 大部分“玻璃”仍是手工 blur、填色和描边 | 优先采用系统组件的玻璃；必要的自绘控件再使用系统 glassEffect |
| 固定字号与系统 text styles 混用 | 大字体、中文换行和不同屏宽容易不一致 | 统一语义字体角色和 Dynamic Type |
| 富文本是 BlockNote WKWebView 文档桥 | 保存、块数据、选择范围和撤销依赖现有协议 | 先原生化外壳和输入配合；不在视觉改造中替换正文引擎 |
| 旧的 LegacyMergeView 与当前 Merge lifecycle 同时存在 | 按文件名修改可能改错页面 | 当前 Merge 入口以 CoreFlow/MergeLifecycleViews.swift 为准 |

原生项目仍以 iOS 16 为最低版本。本方案不自行提高系统门槛；iOS 26 及以上使用 Liquid Glass，旧版本使用标准 Material／不透明表面。当前本机 Xcode 27.1、iOS 26.5 Simulator 可用于验证现代外观，旧版兼容性需另行覆盖。

## 3. 三种视觉方向与建议

| 方向 | 表达 | 优点 | 取舍 |
| --- | --- | --- | --- |
| A · 系统优先 | 接近系统应用的排版、分组列表和克制配色 | 熟悉、稳定，原生组件覆盖高 | Chorai 的内容与角色辨识度较弱 |
| **B · Chorai 原生阅读（推荐）** | 系统导航和控件；温白／墨绿的浅色内容层；安静的深色内容层；局部 Chora | 同时保留品牌、阅读体验和平台感 | 需要认真维护 light/dark 语义色与卡片层级 |
| C · 沉浸玻璃 | 大范围透明表面、强背景氛围、显著动态 | 展示时有视觉冲击 | 长文、键盘输入和复杂卡片的可读性与性能风险高，不作为主方向 |

推荐 B，以 A 的原生组件体系为基础。Liquid Glass 的强度由层级和用途决定，而不是按页面铺满。

## 4. 从 Web 借什么，如何在 iOS 表达

| Web 已有语言 | 原生翻译 | 明确边界 |
| --- | --- | --- |
| Open Margins：温白、留白、森林墨色 | 浅色语义背景参考 #FAF9F6，品牌墨色参考 #153B37；实际文字与控件保持系统语义及对比度 | 不把所有系统 chrome 染成墨绿；不写死所有前景色 |
| Living Index：作者、正文、日期与图片的清晰秩序 | 保留当前 feed/deck/list 的结构，改善 cell 内对齐、行距、图片比例与元数据层级 | 不照搬桌面四列瀑布流，也不把 Explore 的卡片流改成另一种浏览方式 |
| Night Atelier：安静的写作空间 | 深色模式参考炭黑 #242329、暖灰正文；工具与正文分层 | 已选跟随系统，因此不强迫浅色系统下的编辑器永远变黑 |
| Review Merge：以正文卡为主角 | 在当前审核页面里突出内容、来源、等级和真实同步状态 | 保留 Accept／Discard、冲突、重试、草稿与提交时序 |
| 六档 Chora：小型栖边角色与尾色 | 在当前等级位置研究静态小尺寸角色与卡边细节，给予正文优先空间 | 六档阈值、名称和语义不变；未知等级不补造；不把等级当作成长或权限 |
| Web 展示／正文／UI 字体分工 | 系统 SF 与 text styles 用于控件；少量展示标题可比较系统 serif；中文采用系统字体回退 | 不把 Playfair／Inter 全局套进系统控件；正文中的 heading 才是标题 |

Web 当前有未提交的卡片间距／角色显示实验。参考以已确认的基础样式与六档静态卡片为主；未选择的偶尔出现、揭晓动画等提案不自动进入原生范围。

## 5. 原生能力的使用顺序

### 5.1 系统组件先行

| 区域 | 优先实现 | 保留的体验合同 |
| --- | --- | --- |
| 主导航 | 标准 TabView，继续绑定现有 CoreTab／coordinator | Explore、Home、Chat 的名称、顺序、默认项、选中状态、导航历史不变 |
| 页顶操作 | NavigationStack、toolbar、原生 Button 与 SF Symbols | 相同入口、相同回调；不能把常用按钮藏进 More |
| 次级操作 | 原生 Menu；危险动作使用原有确认语义对应的 confirmationDialog／alert | 菜单权限、动作数量、取消与错误恢复不变；呈现变化先比较 |
| 搜索 | 原生输入、焦点与键盘管理；适配后再采用 searchable | 进入／退出、提交才查询、清空、scope 和结果导航不变；不新增 Search Tab |
| Notes／Collect | 比较原生 segmented Picker 与当前布局 | 两段标签、筛选、位置和选择状态不变 |
| 弹层 | 复用系统 sheet、popover、presentation 行为 | 不把每个 overlay 机械改成 sheet；不放开未保存内容的直接关闭 |
| 分享与图片 | 复用已有系统分享／图片选择能力，UIKit 桥接仅用于所需能力 | 分享范围、权限请求时机和图片插入协议不变 |

**标准 TabView 的迁移是有状态的组件替换，不是只改一个修饰符。** 必须验证键盘出现时隐藏、Library 被覆盖时隐藏、切 Tab 关闭 popup、onboarding 回调及深层返回。若系统组件不能维持这些合同，先保留状态容器并原生化表面，不为追求组件覆盖率改变用户路径。

现有全局 UIScrollView.appearance().isScrollEnabled = false 不应复制到新架构；只在完成局部替代和滚动回归后移除，不做顺手的全局修补。

### 5.2 Liquid Glass 的层级

- 控制层：Tab Bar、导航／工具栏、浮动主动作及弹层控制使用系统玻璃。
- 内容层：笔记正文、长列表、卡片主体保持稳定的不透明或低材质表面，阅读对比优先。
- 品牌层：小型 Chora、真实等级、用户选定的内容背景；不阻挡触摸和阅读。
- 自绘交互控件优先 regular glass；clear 只在适合的图像背景上评估。
- 多个相邻自绘玻璃控件使用 GlassEffectContainer 管理合成与形变，不各自重复堆叠 blur。
- Reduced Transparency、Increased Contrast、Reduce Motion 有明确替代表达，不能靠玻璃透明度独自表达选中、错误或可用状态。

Apple 将 Liquid Glass 定位为内容之上的导航与控制层，并建议减少自定义控件中的重复使用。以上是结合 Chorai 阅读场景的方案，不是“所有内容都透明”的视觉目标。[Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)。

### 5.3 字体、输入、动作和反馈

- UI 使用系统 text styles、SF Symbols 与 Dynamic Type；字号放大后仍能完成相同操作，不能只把文字裁成省略号。
- 原生输入配合覆盖键盘避让、交互式收起、焦点保持、选择／复制／粘贴、撤销／重做。中文输入组合中不得因主题切换或 view 重建丢内容。
- 保留现有编辑器桥实例；先核验正文外观与字号配置能力。缺少接口时，通过独立的外观更新通道支持系统主题与字号，不重新加载文档，不改 document revision、选区、撤销和块结构，也不自动制造标题。
- 触觉反馈用于真实选择变化和实际成功／错误结果；不在请求发出时提前震动表示保存成功，也不在每次滚动时播放反馈。
- 系统组件已有触觉时不重复叠加。触觉手感与滚动性能最终在真机验证，Simulator 不能替代真机结论。
- 保留可中断的系统转场；不新增连续漂浮、无意义弹跳或依赖动画时间的业务状态。

系统字体的动态排版与标准控件的触觉是可直接利用的平台能力。[Apple Typography](https://developer.apple.com/design/human-interface-guidelines/typography)、[Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)。

Widgets、Live Activities、App Intents、Spotlight、iCloud 同步等可以以后按真实使用场景评估，但属于新增产品能力，不混入这次保持 UX 的视觉改造。

## 6. 不变项：逐页验收的基准

1. 三 Tab、侧菜单、页面入口与返回关系不变；不自动采用 Web 的 Curator／Library／Neural AI 命名。
2. Explore 的推荐卡、搜索、收藏、dismiss、Spark、作者入口及回调顺序不变。
3. Home 的 Notes／Collect、本人编辑与他人阅读／收藏的区分、排序／分页／刷新／定位不变。
4. 笔记仍是单一正文；不新增独立标题字段。tags、链接、背景、图片和公开范围遵守现有协议。
5. 保存、保存中、失败、重试、只读和返回状态分别保留。更换图标不会把状态机简化为一个固定“完成”。
6. Merge 保留固定来源、2–8 来源约束、候选搜索、后台继续、最小化／恢复、取消确认和失败恢复。
7. Merge Accept 仍先取得正文 snapshot、flush 草稿再 commit；Discard 和冲突处理不变。
8. 等级由真实 rate 决定；Chora 成长由真实 committed_stage 决定，两个维度不合并。
9. 认证、访问权限、API、持久化、隐私默认值和生产环境不因视觉改造改变。
10. loading、empty、error、disabled 状态也要完成设计；不能只验收有数据的截图。

## 7. 实施阶段与交付

### 阶段 0 · 可探索的当前版本

- [x] 完成本地免登录预览：仅 Debug＋Local＋Simulator＋显式参数，打开真实三 Tab。
- [x] 示例读取使用离线 transport；在线保存、AI 和账户操作明确不可用。
- [x] 核验入口不写入认证凭据或改变生产配置；去掉参数后实际启动仍显示登录欢迎页。
- [x] 保存 Explore、Home、编辑器当前截图与操作检查记录，作为首批视觉对照。

本地预览使用说明与验证记录：[LOCAL-PREVIEW.md](/Users/didi/Documents/ChatGPT/Chorai-iOS-setup-2026-10-21/LOCAL-PREVIEW.md)。实际文件位于原生仓库同级的 `Chorai-iOS-setup-2026-10-21` 文件夹，快捷启动为 `Open-Chorai-Preview.command`。预览是离线示例，不具备真实保存、账户、AI 或同步能力。

### 阶段 1 · 三屏定调，先看方案

- [x] 在当前相同结构上制作 Explore、Home、编辑器三屏的浅／深色对照。
- [x] 在独立 SwiftUI 原型中检查系统 Tab／toolbar、搜索提交、键盘输入及保存／返回路径；三项原生 UI 测试通过。
- [ ] 明确正文／控件／品牌三个层级、语义颜色、字号角色、图标和 Chora 尺寸。
- [ ] 用户看过真实可点击样本后，再冻结视觉规范和逐页迁移范围。

交付：三屏六状态对照、可点击的原生样本、差异说明。原生材质与键盘效果以 Simulator／真机为准，HTML 或静态图只能辅助讨论。

第一轮交付入口：[REVIEW.md](REVIEW.md)。原型的纯文本输入仅用于验证视觉及输入手感，不能替代正式 BlockNote 富文本、存储及冲突回归。

2026-10-21 后续审稿已批准在独立 Explore 原型中试做一项交互变更：左滑略过、右滑收藏；增加 Previous 连续回看及 Continue exploring 返回未读处。回看不改变收藏，误收藏有独立撤销。该批准仅用于原型比较，未迁移正式 App；Home、编辑器及搜索路径保持上一轮方案。

### 阶段 2 · 公共原生基座与浏览路径

- [ ] 收束语义颜色与字号，移除迁移页面中的固定白字／深紫假设；旧页面仍保持可读。
- [ ] 将共享导航与控件逐个替换到原生实现，保持 coordinator 和路由合同。
- [ ] 完成 Explore 与 Home；同时检查正文详情和作者入口。
- [ ] 浅／深、中文／英文、大字体、长内容、键盘、空与失败状态均有运行验证。

主要文件：ArcNote/CoreFlow/FlowViews.swift、CoreShellViews.swift、TabBarView.swift、ExploreView.swift、HomeView.swift、AdaptiveLayout.swift。可在 ArcNote/DesignSystem 内建立薄的语义 tokens 和兼容性包装；不创建一套仿原生控件库。

### 阶段 3 · 写作与 Merge

- [ ] 原生化 CardEditorShell、FormattingBar、metadata、保存／重试与键盘配合。
- [ ] 保留 BlockNoteEditor 文档桥、选区、撤销、snapshot 和 callback 身份。
- [ ] 为正文补齐系统主题与 Dynamic Type 的外观更新能力；现有桥接口尚未提供该通道，不能只换 SwiftUI 外壳就声称正文已适配。
- [ ] 迁移当前 Merge 选材与审核的表面；真实状态机和控制器不重写。
- [ ] 覆盖 Spark continuation／Merge 的强制深色及局部弹层主题，随前景色和材质一并迁移；检查 Spark 来源条、结果卡、评论弹层和返回路径。
- [ ] 验证长文输入、失败后重试、主题切换不丢草稿，以及 Accept／Discard／冲突的既有顺序。

主要文件：ArcNote/CardEditor/*、ArcNote/NewNoteView.swift、ArcNote/CoreFlow/SparkContinuationViews.swift、MergeLifecycleViews.swift、MergeArtifactEditorSurface.swift。Packages/BlockNoteEditor 仅在确有外观接口缺口时扩展，不手改其生成资源。

### 阶段 4 · 收尾与兼容

- [ ] Chat、个人资料、设置、通知、登录等复用成熟的公共规范。
- [ ] 用已有 API 和真实数据验证保存、Spark、Merge、同步；离线预览不代替这一步。
- [ ] 验证 iOS 16 fallback 与 iOS 26+ 玻璃路径；不扩大设备支持范围。
- [ ] 真机验证输入、返回手势、触觉、滚动和内存；对比改造前后测量结果。
- [ ] 清理被迁移表面替代的重复材质与全局副作用，保留回退方案。

每个阶段以独立可用的页面完成，不做全站同时切换。任务排序按“原生感提升、使用频率、行为风险”共同决定，不以单纯替换控件数量为目标。

## 8. 验收方法

| 维度 | 通过条件 |
| --- | --- |
| 使用路径 | 相同任务能从相同入口、以相同动作顺序完成；权限、结果与取消语义一致 |
| 原生表现 | 系统控件承担导航／输入／菜单等职责；没有重复手工模仿平台的玻璃与反馈 |
| 视觉 | 选定浅／深方向完整；正文优先；品牌与等级有区分；控件可读、可点 |
| 无障碍 | 至少44pt有效触摸区；VoiceOver标签与焦点顺序正确；大字体不遮住关键动作 |
| 系统设置 | Reduce Motion／Reduce Transparency／Increased Contrast 下仍可完成任务 |
| 数据完整性 | 不改 canonical document、保存／权限合同，不因主题切换重建编辑器或清空草稿 |
| 工程 | Local与Production都能构建；相关单测／UI测试通过；既有失败独立记录，不能宣称全绿 |
| 体验测量 | 真机记录阅读滚动、键盘出现、编辑输入与页面切换；发现退化则局部回退 |

后续 UI 回归应覆盖三 Tab、菜单开关、搜索提交／清空、Notes／Collect、打开／返回笔记、编辑／取消／保存失败／重试、Merge 选材／恢复／Accept／Discard，以及键盘出现时 Tab 隐藏规则。纯材质常量不写镜像测试；重点测行为与内容完整性。

## 9. 当前代码依据

原生：TabBarView.swift:449；CoreFlow/CoreShellViews.swift:21；CoreFlow/FlowViews.swift:5；CardEditor/CardEditorGlassSurface.swift:68；CardEditor/CardEditorShell.swift:96；NewNoteView.swift:494；CoreFlow/MergeLifecycleViews.swift:23；CoreFlow/MergeArtifactDraftController.swift:211；Packages/BlockNoteEditor/Sources/BlockNoteEditor/BlockNoteEditorCoordinator.swift:154；Packages/CoreFlow/Sources/CoreFlow/CardLevelStyle.swift:16。

Web（同级 Jaime@Chorai 2）：src/styles/interface-foundation.css；typography.css；editor-experience.css；merge-artifact-review.css；src/components/ChoraCardLevel.tsx；docs/design/2026-10-19-chora-card-system/README.md。Web 的未提交实验保持原状，本轮不修改。

本计划不把“使用 SwiftUI”与“体验已原生化”等同；也不把“最大化原生优势”理解为必须改写一切。每个替换都要同时满足用户现有路径和平台质量。
