# iOS 全前端整改：逐页范围与功能一致性审计

> **请先读 [2026-10-28 当前状态](#current-status-2026-10-28) 和 [验证记录](VALIDATION.md)。** 下文开头及 2026-10-27 各节是保留的历史审计。开工时的“Profile／IM 等仍仅换主题”“Explore／Reader 尚未落地”已被后续真实页面整改取代，不能作为当前状态。当前已完成实际结构迁移与多轮局部验证；深色模式和最终收尾仍在进行，不等于全部状态通过或用户视觉验收。

审计日期：2026-10-27。基线提交：`8fe71f81850ca32aa07773a29ca21b04f1604458`，当前工作树已有大量未提交的原生迁移改动。本文是**本轮全面整改开始时的源码与现存证据盘点**，不是整体验收。其他执行者正在并行整改；后续完成项应附新的截图、用例和构建结果更新状态。

## 结论

- Home／编辑器、Explore／Grid、Reader、Spark／Merge、卡片菜单与 Share／Link／Report 已有实质布局迁移，但仍有明确未落地的用户修正以及功能连续性待验证项。
- **Profile、聊天列表／会话、设置／隐私、Chora、邀请／积分、通知、回收站、身份验证等，不应被归为“已经全部完成重新设计”。** 大多数当前 diff 仍以主题色、语义字体、SF Symbols 和点击区替换为主，很多旧自绘头栏、容器与弹层结构仍在。
- V8 没有 Profile、IM、评论、设置、身份验证、Chora 的已确认逐屏截图；原型里的相应占位说明不是设计稿。它们应延展确认过的系统色彩、原生导航／控件与内容层级，同时保留真实现有功能，不能宣称与一个不存在的原稿逐像素一致。
- 旧 `2026-10-26-native-rollout/PLAN.md` 的全部勾选代表当时工程任务记录，不能继续作为本次“整个前端完成”的证明。其首轮实现已被用户指出不符原型，后续对照也只覆盖八个主要画面。
- 原型是视觉参考；**原有真实模型、权限、动作、请求与数据状态才是功能合同**。原型中硬编码的 Writing／Ideas 分类和卡片右下角箭头不应迁移成正式功能。

## 证据与判定规则

直接阅读了 native `AGENTS.md`、当前 `ArcNote` 源码、相对 HEAD 的差异、此前 SPEC／PLAN／FIDELITY-AUDIT、fidelity 验证记录、最近 Home／编辑器修正记录和 V9 DESIGN。未运行构建、模拟器或网络请求。本次只写本文，不修改产品源码。

状态含义：

- **实质迁移／待全面复核**：真实布局和原生控件已改变，有源码与部分历史原生截图；不等于用户已验收。
- **明确待落地**：用户最新指定的设计仍只在 V9 或文字要求中，真实 App 尚保留旧结构。
- **主题迁移／需继续整改**：颜色和字体现已接入，但主要结构与旧版一致；不能称已完成全页原生化。
- **原生宿主／保留能力**：系统选择器或网页宿主，不应另造一套功能。
- **非当前产品入口**：仅 Preview／旧实现引用，不应为了“全覆盖”重新暴露。

所有“历史验证”均有时效和范围限制；本轮真实改动后需重跑对应检查。历史离线 fixture 不证明账户、AI、消息发送、服务器保存、生产环境或真机可用。

## 必须先纠正的功能解释与风险

### Home 的 Writing／Ideas

`revisions/v9-fixed-deck-reader/prototype/Model.swift:31` 的 `NoteFilter` 把 All notes／Writing／Ideas 硬编码成原型过滤器；同文件也把 Writing／Ideas 当样例笔记标签。`ChoraiPrototype.swift:447` 的 Filter Picker 暴露了它们。这个原型行为并不来自真实 Home 合同。

真实 `HomeView.swift` 使用 `LibrarySortOption`，原有四种排序为最近编辑、最近添加、等级从高到低、等级从低到高；卡片底部标签来自真实 `card.tags`。因此：

- Writing／Ideas 可以作为离线样例的标签内容，不应成为全用户固定分类。
- 不新增分类、按标签分组、自动分类或相关 API。
- 真实排序应继续使用已有 descriptor 和服务参数，外观可以改为系统菜单。
- 原型过滤器不能作为真实排序的验收基线。

### Home 右下角更多

真实 `HomeView.swift` 的 `NotesCard` 与 `HomePostCard` 当前已经使用 `ellipsis` 和 `NativeCardActionsMenu`，而原型 `NoteRow` 仍用 `arrow.up.right`／`bookmark`，完整动作只在长按菜单中。前一轮仅恢复原型 Home，连这个样例语义差异也一并恢复了。

正式 App 应以可见的更多按钮作为动作入口，不能用纯跳转箭头替代。本人笔记的当前真实动作含 Edit、Spark、Merge、Share、Link、Root、Public／Private、Pin／Unpin、Remove；收藏内容的动作应保持当前真实权限分支（View、Spark、Share、Link、Root、Report，收藏取消仍是明确动作）。不能根据旧代码注释中“Pin”等文字推导额外权限；应核对实际分支。

### Remove 的确认宿主仍有已知缺口

`PopupMenuView.swift` 的默认删除分发沿用 `DeleteCard` 通知；Home 是既有确认接收者。此前 fidelity/VALIDATION 已明确记录：虽然通知新增显式 cardID，防止删除错误卡片，但 Detail／Spark 入口在 Home 未挂载或被覆盖时，确认可能不可达。这个问题不能被“明确目标 ID 的保护通过”掩盖。应检查每个本人卡片入口，保持确认与取消语义，修复不可达路径；不得自动删除或新增后端操作。

### Public／Private、Pin／Unpin 也依赖 Home，独立详情入口不完整

追加核查确认与删除相同的宿主耦合：

- `PopupMenuView.swift` 无显式 callback 时只发送 `ToggleCardVisibility`／`ToggleCardPin` 通知；整个 `ArcNote` 中接收者只有 `HomeView`。
- `DetailView` 的系统 Menu 和其旧 popupMenu 宿主均未传入 `onToggleVisibility`／`onTogglePin`／`onDelete`；`SparkContinuationView` 同样未传这三类 callback。
- `HomeCardsManager.toggleCardVisibility`／`toggleCardPin` 需要目标出现在当前 Home cards 或与 `currentMenuCardData` 完全同 ID 的 fallback。独立 Detail／Spark 的目标不一定存在于此列表。失败在 Home 接收路径里只有打印，不会为当前详情展示用户可理解的错误。
- 即使 Home 成功调用服务，当前 Detail／Spark 也没有接收这两类已提交状态变化；其菜单可能继续使用旧 `isPublic`／`isPinned`。不能用修改 Home 列表证明原页面动作完整。
- MyProfile 传入自己的三个 callback，自己持有确认目标；它不应被误改回全局通知。

建议独立实施任务拥有 `PopupMenuView.swift` 与共享本人卡片动作状态／宿主和相关行为测试，提供 Detail／Spark 的绑定接口；与正在编辑 Detail／Spark 的执行者协调接入，避免抢文件。不要让新宿主与旧 Home 监听同时发出重复 mutation。优先覆盖：无 Home 的入口、目标不在 Home 列表、取消删除零请求、失败可见与不假成功、成功结果同步、连续 toggle 使用服务返回状态、原权限分支不扩张。

### Explore／Reader 尚未落实最新要求

审计时真实 `FlowDeckView` 仍有 Previous、Skip／Collect 说明和内部纵向 ScrollView；真实 `DetailView.readerCard` 仍使用外层等级卡片。V9 DESIGN 已记录用户选择的固定摘要卡 → 点开全文、拖动才显示方向反馈、全页正文 Reader。本轮最新“开始落地”授权适用于这些已明确的修正；不应再以 V5 的旧下栏和 V8 的外层卡片反驳用户后续意见。

## 主要浏览、写作与 AI 路径

| 页面／状态 | 对照来源 | 审计时状态与真实实现 | 尚需完成／验证 |
| --- | --- | --- | --- |
| App 导航／Explore–Home–Chat | V6 原生 TabView + 既有 coordinator | **实质迁移／待全面复核**。`TabBarView.swift:519` 使用真实 TabView，保留各页路由；二级页隐藏 Tab 的多个路径已分别修复 | 所有子页返回、深链、冷启动侧栏、后台 Merge 的跨页状态；不能只测三个首页 |
| Home · My Notes | V6 Home 排版；真实排序／动作合同 | **实质迁移／待全面复核**。`HomeView.swift` 的开放式正文列表、系统分段／排序 Menu、New note、右下角更多已接入 | 本人动作逐项、排序刷新／编辑返回、长正文／空标签、菜单可点性；拒绝原型 Writing／Ideas 分类 |
| Home · Collections | V6 Home 视觉；真实收藏列表 | **实质迁移／待全面复核**。`AIListView`／`HomePostCard` 使用同类开放列表、取消收藏、更多 | 真实收藏读写状态、作者入口、收藏菜单权限、从其它页收藏后刷新；不得改成原型内存收藏 |
| Home 内搜索结果 | 真实已有搜索语义 | **实质迁移／待全面复核**。`LibrarySearchResultsView` 在 Home 内使用；当前取消／提交沿用原输入状态 | 无查询／无结果／错误／分页、搜索菜单与正文点击；不增加跨库搜索能力 |
| Explore · 滑卡 | V5 外观 + 用户后续固定卡要求 + V9 | **明确待落地**。`CoreFlow/FlowViews.swift` 已迁移主题和控件，但审计时仍内部纵向滚动并显示 Previous／Skip · Collect | 固定摘要高度、全文入口、无底部遮罩、仅拖动反馈、回看／恢复位置、服务收藏成功后前进与失败留卡 |
| Explore · Grid | V5 网格 + V8 六等级笔触 | **实质迁移／待全面复核**。真实 Grid 及共享收藏状态在 FlowViews；笔触与 Chora 策略已接入 | 两列长短富内容／六等级、Grid 无 Chora、点入退出恢复位置、更多权限与收藏竞态 |
| Explore 搜索／过滤入口 | 既有真实搜索／推荐合同 | **实质迁移／待全面复核**。`ExploreView.swift` 保留搜索与导航，对接真实 Flow store | 空／失败、加载与新一轮推荐、搜索清除／返回，不能硬编码原型样本顺序或类型 |
| 阅读详情／相关笔记 | V8 等级标识 + 用户全页正文要求 + V9 | **明确待落地**。`DetailView.swift:437` 仍封装 `readerCard` 并 `.choraiCardLevel(...showsChora:true)` | 去外层卡壳，正文直接成为页面；保留作者、关注、消息、收藏、更多、标签、相关卡、最后一段、返回上下文 |
| 新建／编辑笔记 | V6 Editor + 用户整页／右下工具修正 | **实质迁移／待全面复核**。`NewNoteView.swift`、`CardEditor/*`、BlockNote bridge；最近已有浅深色、整页可编辑区域与菜单验证 | 保留单正文、默认私有、草稿／保存／取消、照片／相机／链接／标签／格式／撤销；既有只读兼容保护不可移除 |
| 编辑工具／媒体选择 | V6 工具位置 + 原有能力 | **实质迁移＋原生宿主**。右下工具入口、系统菜单、照片／相机／链接流程 | 键盘打开／收起、长文、readonly、44pt目标；系统选择器取消不修改正文 |
| Spark · 来源／结果／继续深入 | V6 feature journeys | **实质迁移／待全面复核**。真实入口是 `CoreFlow/SparkContinuationViews.swift`；有结果与深入的浅深色历史截图 | 来源关系、前后结果／深度、收藏停留、捕捉想法、作者、返回原文、加载／空／错误／额度等全部状态 |
| Merge · 来源选材 | V6 selection／selected | **实质迁移／待全面复核**。真实入口 `CoreFlow/MergeLifecycleViews.swift`；固定来源和候选行已整理 | 2–8上限、固定anchor、选择保留、搜索、取消、权限及是否可执行；不迁入虚构材料 |
| Merge · 生成／后台任务 | V6 progress／background | **实质迁移／待全面复核**。`MergeTaskRail`／Coordinator 状态仍真实 | 离开页面继续、打开同一任务、取消、失败重试、多个任务；不可随机显示成功／Thinking |
| Merge · 结果编辑／接受／放弃 | V6 ready／saved／conflict等 | **实质迁移／待全面复核**。`MergeArtifactEditorSurface` 与生命周期 state 仍真实；有浅深色结果截图 | 单正文和来源、接收／放弃确认、同步失败／冲突／恢复、不会将原型Saved假成功带入正式状态 |
| 卡片等级／笔触／Chora | V7–V8 六等级 | **实质迁移／待全面复核**。`ChoraiCardLevel.swift`、`CardLevelMaterial`与资源 | 六级／未知级、Grid不出现角色、详情出现对应角色；原rate阈值和committed成长不变 |

## 其它用户可达页面与覆盖缺口

以下页面均未在 V8 获得单独的逐屏确认图。基线应是确认的温白／墨绿／学院金、系统浅深色、原生控件，以及原有产品功能。

| 页面／入口 | 审计时真实状态 | 本轮需要的处理与验收证据 |
| --- | --- | --- |
| 本人 Profile（侧栏头像） | **主题迁移／需继续整改**。`MyProfileView.swift:144` 起仍自绘头栏、头像骑在边框、大外层资料卡包含笔记列表；大部分 diff 为颜色／字重／图标 | 原生导航和清晰资料／统计／笔记层级；保留头像、关注／粉丝列表、笔记菜单、对话入口；浅深色截图与返回链路 |
| 他人 Profile（作者／通知／关注列表） | **主题迁移／需继续整改**。`UserProfileView.swift` 保留大卡容器和自绘导航；Follow、Message、Report、Block及内容仍实际连接 | 既有权限／关注状态／拉黑确认、笔记详情与更多、空／错误；不能新增社交指标或在线状态 |
| Edit Profile（Settings → Personal Data） | **主题迁移／需继续整改**。`EditProfileView.swift` 仍 `.navigationBarHidden(true)`、自绘保存条和旧字段卡片；文本／上传／保存逻辑保留 | 原生表单与保存／取消，头像／背景照片选取、裁切／上传失败、简介限制；本轮无新原生截图 |
| Followers／Following | **主题迁移／需继续整改**。`FollowListView.swift` 原来已有 NavigationStack，当前主要换主题和字体 | 搜索若无原功能不新增；保留加载／分页／重试、Follow状态、用户点击、权限与空态；逐主题验证 |
| Chat 会话列表（底部 Chat） | **主题迁移／需继续整改**。`ChatView.swift` 自绘顶部搜索栏和列表；服务与历史可见性未替换 | 原生导航／搜索／列表层级，保留原搜索、未读／时间／选中会话行为；无本轮完整浅深色审稿图 |
| Chat 会话详情／消息输入 | **主题迁移／需继续整改**。`ChatDetailView.swift` 保留自绘头像头栏、消息泡、底部手工输入行和选材弹层；仅主题／图标／字体／Reduce Motion | 真实消息顺序、文本选择、键盘、发送／流式回复／继续生成／失败、长内容、引用笔记，所有原能力保留；不要把AI会话改造成新IM功能 |
| Chat 引用笔记选择器／已选引用 | **主题迁移／需继续整改**。同文件 `SelectCardPopupView` 仍自绘遮罩弹窗 | 可改原生sheet与选择列表，但保留已有搜索／选择／移除语义及限制，不新增附件类型 |
| 侧栏／账号入口 | **主题迁移／需继续整改**。`SideMenuView.swift` 仍固定宽度滑入drawer、头像偏移、自绘背景 | 保留 My Notes／Favorites／Notification／Trash／Settings／Help & Report，核对冷打开路由／未读／关闭；不用新增账户切换 |
| Settings | **主题迁移／需继续整改**。`SettingsView.swift` 自绘header、ScrollView、手工行／分隔线，未改系统Form/List | Personal Data／Chora／Invitations & Credits／Account & Privacy／Log Out全部保持；登出确认／错误与返回 |
| Account & Privacy | **主题迁移／需继续整改**。真实实现是 `BlockedActorsView.swift:4`，自绘SettingsDestinationHeader + ChoraSectionSurface | 账户字段、会员语义、实际隐私开关与保存失败回滚、Blocked Users入口；不暴露不存在的设置 |
| Blocked Users | **主题迁移／需继续整改**。`BlockedActorsView.swift:264` 保留store与列表 | 列表／加载／分页／解除拉黑确认和失败；浅深色与长名字 |
| Chora Profile · Identity | **主题迁移／需继续整改**。`ChoraProfileView`、`ChoraIdentityGrowthSections` 主要主题替换 | 头像／Display name／Preferred address、保存/错误/权限；不增加人格编辑字段 |
| Chora · Growth | **主题迁移／需继续整改**。同上，继续渲染真实stage和维度 | 未加载／失败／未知／已提交阶段；不能展示原型固定等级为真实成长 |
| Chora · Soul & Sources / Local Notes | **主题迁移／需继续整改**。`ChoraProfileSections.swift` 自绘折叠卡；导入原状态机保留 | 文件选择、校验、进度、取消、重试、重新选择和receipt；不能增加新格式或假成功 |
| Chora · Notion 来源 | **主题迁移／需继续整改**。同文件；授权与page搜索/选择/同步仍原合同 | 原生授权宿主、连接／断开确认、搜索页／导入结果／未知状态，保留actual service能力 |
| Chora · Chat History | **主题迁移／需继续整改**。`ChoraChatHistorySection.swift` 仅主题／符号变化 | 保留“此设备隐藏历史”的含义，不能改成服务器删除；确认流程不变 |
| Invitations & Credits 总览／兑换／分享 | **主题迁移／需继续整改**。`InvitationCreditView` 自绘SettingsDestinationHeader +多个surface | 真实余额、邀请码、复制／系统分享、兑换状态与错误；不引入购买、会员等功能 |
| Invitation History | **主题迁移／需继续整改**。`InvitationCreditDetailViews.swift` | 加载／分页／错误/状态；真实receipt，不造好友或虚构奖励 |
| Invitation Rewards | **主题迁移／需继续整改**。同上 | 保持奖励来源与状态语义；无新快照 |
| Credit Ledger | **主题迁移／需继续整改**。同上 | 实际金额／时间／原因、分页与错误；无新快照 |
| Notification Inbox／过滤 | **主题迁移／需继续整改**。`NotificationView.swift` 仍自绘可展开过滤条、手工header/list；业务filter原有 | 改成系统控件可保留实际过滤项；已读状态和目标跳转、失败不误跳；历史target fixture不等于完整视觉验收 |
| Notification Detail（legacy内容） | **主题迁移／需继续整改**。`NotificationDetailView.swift` 主要颜色字体 | 区分真实目标通知和legacy正文通知；保留内容／返回，无新快照 |
| Trash／恢复／清空相关确认 | **主题迁移／需继续整改**。`TrashView.swift` 仍旧页面结构、卡片与自绘条 | 维持现有恢复和删除范围、确认／失败／加载／分页；不得自行清空用户数据，离线fixture验证 |
| Discovery Path / Root | **主题迁移／需继续复核**。`RootView.swift` 是来源关系页，不是应用Root；主要颜色字体变更 | 真实顺序／来源关系、本人编辑/他人阅读、缺失/不可见/失败、滚动；不将关系编造成知识图谱 |
| 评论列表／回复／评论举报 | **主题迁移／需继续整改**。`CommentPopupView.swift` 仍旧自绘overlay和输入区，举报用现有sheet | 原评论/回复/删除/举报权限、键盘、展开、发送错误；不要把原型本地评论框当真实能力 |
| Card More 菜单 | **实质迁移／待全面复核**。`NativeCardActionsMenu` 系统 Menu 复用既有dispatch；部分调用者仍旧 PopupMenu | 所有本人/他人/收藏/结果场景的动作矩阵，导航闭环；特别检查 Remove 的确认宿主 |
| Share | **实质迁移／待全面复核**。`CoreFlow/ShareCardView.swift` NavigationStack/Form/系统分享；V5有浅色对照 | 真实图片artifact、生成错误、只读预览、分享不改变privacy；缺深色独立审稿证据 |
| Link | **实质迁移／待全面复核**。`LinkPopupView.swift:324` NavigationStack/Form，真实动作owner | 来源/所有权/候选、加载/错误/即时动作语义；不复制原型的假preview确认流程；缺深色独立证据 |
| Report | **实质迁移／待全面复核**。`CoreFlow/ContentReportView.swift` NavigationStack/Form；原因仍真实 | 理由/上下文、提交/错误/重试/receipt、关闭；缺深色独立证据 |
| Welcome／登录入口 | **主题迁移＋根导航调整／需全面复核**。`ContentView.swift` 增加access状态分支的NavigationStack，视觉主要主题替换 | 正常／未登录／private beta／不可用路径和返回，不把本地preview绕过带入production |
| Sign In | **主题迁移／需继续整改**。`SignInView.swift` | 既有登录方式、密码、验证码/错误等真实有的控制；原生表单输入/键盘/返回，双主题 |
| Sign Up | **主题迁移／需继续整改**。`SignUpView.swift`；InputField对密码使用SecureField | 既有注册字段、邀请码、Terms/Privacy、校验／失败／导航；不新增注册方式 |
| Private Beta Entry／Access Gate | **主题迁移／需继续整改**。`AccessGateView.swift` 包含两个既有页面 | 实际access状态、重新加载与退出、注册入口；不虚构通行成功 |
| Choose Interests | **实质迁移／待全面复核**。`ChooseInterestsView.swift` 已从随机位置气泡改为可读网格，store仍唯一选择owner | 原有选项来源、选择上限、Reset／Skip／Next、加载／保存失败和大字；它是既有兴趣设置，不是Home新增分类 |
| Onboarding Guide／Contextual tips | **主题迁移／待回归**。`CoreFlow/OnboardingGuideLine.swift` | 原有guide状态、完成/跳过/延后、目标定位、不会强制打开新功能或遮挡关键入口 |
| Help & Report／Terms／Privacy 网页宿主 | **原生宿主／保留能力**。`WebView.swift` 仅loading主题调整；远端网页本轮未请求 | 保持真实目的地和返回；本地UI整改不等于远端内容已重设计 |
| Photos／Camera／文件导入／系统Share／Notion授权 | **原生宿主／保留能力**。系统picker/ShareController/OAuth协调器 | 保留系统权限与取消/成功回调，验证宿主外观和回到原页面；不额外申请权限 |

## 不应算作新待实现功能的遗留文件

代码里存在并不等于当前用户可达；本轮不能借全前端整改重新开放这些入口。

| 文件／类型 | 静态引用证据 | 处理 |
| --- | --- | --- |
| `AccountDetailsView.swift` / AccountDetailsView | 搜索构造调用只看到自身Preview；Settings真实路由是AccountPrivacyView | 保留／清理可另议，不能把Membership／Storage等注释样本变成新功能 |
| `PreferencesView.swift` | 构造调用只看到自身Preview | 不新增Preferences菜单或硬编码开关 |
| `APIAndPluginsView.swift` | 构造调用只看到自身Preview | 不新增API／Plugin服务入口，不把占位apikey能力作为项目实际功能 |
| `SparkView.swift` | 构造调用只看到Preview；真实CardNavigationDestination使用SparkContinuationView | 检验真实CoreFlow路径，不能用旧Spark截图代替 |
| `MergeView.swift` 的 private LegacyMergeView | 非真实Merge路径；NewInsightView只从此legacy实现引用 | 真实路径在CoreFlow/MergeLifecycleViews与MergeArtifactEditorSurface，不新增旧结果入口 |
| `NewInsightView.swift` | legacy Merge与自身Preview引用 | 不把旧界面可编译误算成产品路由完成 |

以上为静态引用结果，不能证明所有外部反射或构建变体绝无调用；在当前 SwiftUI 显式路由中未发现入口。

## 验收清单：不能再用“文件改过”替代完成

1. 每个上表可达页面都登记入口、原有动作矩阵、所有权/只读状态、真实数据来源和退出路径。
2. 有已确认截图的页面，比较同屏尺寸／同状态；若最新用户意见修正旧图，以最新意见为准，登记差异原因。
3. 无单独确认图的页面，在真实 App 使用相同原生设计系统整改，提供实际浅深色截图，不伪称已有原稿；用户已授权开始落地，无需重新制作独立原型。
4. 每条关键路径保留业务语义：搜索范围、排序字段、公开默认值、收藏成功条件、AI来源、Merge限制、删除确认、聊天历史隐藏、隐私设置等。
5. 菜单/表单/弹层不能仅看主态：检查loading、empty、error、readonly、长文字、大字号、键盘及返回。
6. 所有正在被修改的真实页面，以新的原生构建与定向测试验证；历史包测试通过只作基线，不覆盖此次代码。
7. 不可把本地fixture的收藏/发送/保存响应称为真实服务成功；Production只构建，不用来补演示数据。
8. 最终重新审计每一行，任何缺图、缺入口回归、功能语义待确认项保持未完成，直到明确证据补齐。

## 可复用历史证据位置（均非本轮完成证明）

- `../2026-10-26-native-rollout/FIDELITY-AUDIT.md`：V5/V6/V8逐屏参考映射及辅助页无截图的界限。
- `../2026-10-26-native-rollout/fidelity/VALIDATION.md`：八个主要画面对照、针对性11项UI历史结果；同时明确记录删除确认宿主未解决。
- `../2026-10-26-review-fixes/VALIDATION.md`：真实Home／编辑器最新修正范围与逐项浅深色测试记录；明确Explore／Reader V9尚未正式落地。
- `../2026-10-21-native-visual-reform/revisions/v9-fixed-deck-reader/DESIGN.md`：固定摘要卡与全页阅读的用户要求、动作不变和反馈方案。
- `ArcNote/PopupMenuView.swift`、`TabBarView.swift`、`SideMenuView.swift`、`SettingsView.swift`：实际路由和菜单动作范围。

## 本次共享卡片动作整改补记（2026-10-27，仍待 App 集成验收）

初始盘点发现的“默认 Remove / Public / Pin 只依赖 Home 通知”已经有独立实现，不再是未动代码的状态；这不代表已通过整条产品路径验证。

- `PopupMenuView.swift` 的共享宿主持有 `OwnedCardActionStore`，默认动作绑定确切 card ID 与 ownership，不发送旧 Home 写操作通知。明确传入的 MyProfile 等 callbacks 仍优先，新的宿主重置继承 callbacks，避免父页面处理另一页面的卡片。
- Remove 先系统确认；取消不请求；失败可重试相同目标。系统先 dismiss 再触发按钮的顺序有独立测试。Public / Pin 等待服务回执才更新状态，请求中锁定默认菜单操作；错卡 ID 的回执不报告成功。
- 网络适配器仅调用既有 NetworkManager 方法，保持无当前身份拒绝请求的边界。Local Preview 继续经既有 URLProtocol 拦截，不建立第二套线上 API 路径。
- Home 已接提交回调：按当前真实排序刷新、重新执行当前提交的 query/scope，删除后移除匹配列表／搜索／菜单目标；不更改用户当前栏目与排序。两个系统排序 Menu 打开即关闭原有引导提示。
- Detail 已接提交回调：仅匹配当前 card ID；删除成功退出；Public / Pin 直接呈现服务回执元数据。详情 GET 投影可能滞后，因此不追加读取来覆盖成功回执。
- 新增 `OwnedCardActionStoreTests`（11 项行为）和 `OwnedCardActionIntegrationSourceContractTests`（3 项跨页面源码约束）。定向 8 组共 52 项测试通过，记录 `/tmp/chorai-owned-card-final.log`；三个改动 SwiftUI 文件只做了语法解析，非全 App 类型检查／构建。此次子任务没有运行 Simulator，没有联系真实服务。
- 仍须 root 进行整 App 编译和入口回归：Home / Profile / Detail / Spark 的本人卡片菜单，取消／失败／重试／成功状态及返回，确认不存在重复请求、错误卡片目标或离线样本越界。列表重新加载仍遵守后端投影；共享菜单和 Detail 的成功状态以回执为准。

## 当前实施覆盖表（2026-10-27，本轮实施中快照）

**此节追加当前状态，前文保留为开工时的历史审计。不是全部完成，也不是视觉验收通过。** 本节重新读取了实际源码、任务开始时的 394 项 SHA-256 清单 `/tmp/chorai-remediation-start-source.json`、执行者的改动与日志；未通过运行生产 App 或请求生产服务补证。实施仍并行进行，后续源码修正与最终构建应继续更新证据。

状态：**结构已改**表示已改变实际页面结构与控件；**保留现有合格结构**表示已有真实原生或产品专用结构，不能为了文件覆盖率再重写；**待落地**表示仍存在确定的旧呈现；**正在修**表示已发现问题、修正已开始但尚未完成集成验收。表中“需 UI”均为仍须执行的运行检查，不是已通过。只有附有具体日志的项目才记为已验证。

### 主要页面与创作路径

| 可达页面／状态 | 当前真实结构与实现证据 | 功能边界／仍需工作 |
| --- | --- | --- |
| 主导航 Explore／Home／Chat | **结构已改**。`TabBarView` 使用真实 `TabView` 与原有路由协调；二级页分别隐藏 Tab，Merge 任务轨道仍独立保留 | 核心 Grid→Reader→Home、Home→Editor 已有本轮 UI 通过。需 UI：冷启动侧栏、所有二级页返回、任务跨页及浅深色；不能从三条首页路线外推全导航完成 |
| Home · My Notes | **结构已改**。开放式正文列表、系统分段、系统排序 Menu、New note 与可见 ellipsis；移除横向排序胶囊带 | 四种 `LibrarySortOption`、实际 `card.tags`、私有标识和本人动作保留。无 Writing／Ideas 固定分类。需 UI：四种排序、本人每项操作、长文本／大字、编辑返回 |
| Home · Collections | **结构已改**。同类开放列表；本轮恢复原有收藏总数，取消收藏和更多各有入口 | 原列表／作者／收藏数量语义保留，菜单传真实 `UserCard`。需 UI：收藏变化后数量／列表同步、所有者与收藏对象权限 |
| Home 内搜索 · 两个 scope | **结构已改**。`LibrarySearchResultsView` 留在 Home；Collections 搜索行传入 `menuCardData: result.card`，准备菜单不再打开第二个 overlay | 原查询范围、提交／清除、分页及真实结果保留；22 项相关约束测试通过。需 UI：搜索本人／收藏结果的菜单、失败／空态和返回 |
| Explore · 推荐滑卡 | **结构已改**。`FlowCardView` 由可用 viewport 固定高度；正文富内容摘要，点击全文；无卡内纵向滚动，无常驻 Previous／Skip／Collect 文案；拖动才显示方向反馈 | 原 `FlowDeckStore` 收藏成功后前进、失败留卡规则保留。固定摘要／拖动／历史 UI 已过；需 UI：小屏与辅助字号、长标题／长标签、图片／列表／未知等级，收藏失败位置保持 |
| Explore · History | **结构已改**。系统 sheet 展示原 store 历史，`selectHistoryEntry` 在原 history／frontier 上选择，不造服务器历史接口 | 保存原位置、请求中禁止切换；本轮固定卡历史 UI 已过。需 UI：多条历史、返回 frontier、失败中切换／退出 |
| Explore · Grid | **结构已改**。原两列富内容网格、真实卡片更多与收藏；等级笔触默认展示，小 Chora 隐藏 | Grid→Reader→Home UI 已过。需 UI：六等级、图片／链接／列表混排、长内容、浅深色及收藏状态同步 |
| Explore · 搜索结果 | **结构已改，待新 UI 验证**。结果 `PostCard` 已复用 `FlowRichPreview`；高度固定为可用 viewport 扣除原翻页控制区，正文显示摘要、点击原全文；真实 card 系统 Menu prepare 只更新目标 | 原四项权限、SearchManager／CurrentIndex、上一／下一、作者／like／favorite／comment 回调不变。手势仅在摘要区，水平超过原 100pt 阈值才翻页，右上一／左下一，不改成收藏。两条独立 `SearchSummaryUITests` 已注册，需新构建验证六类内容同高、操作可达、纵拖／标签不误翻、作者／菜单／全文路由 |
| Reader · 正文／相关卡 | **结构已改**。`DetailView` 系统导航与工具栏；正文直接成为页面，等级／笔触／Chora 为紧凑身份区；作者与互动、相关卡仍在 | 真实完整正文、标签、关注／消息／收藏／评论／更多／相关卡保留。Grid→全文阅读 UI 已过；需 UI：长文最后一段、相关卡来回、各权限与错误、辅助字号 |
| 编辑器 · 新建／编辑／只读 | **结构已改（延续已落地版本）**。`NewNoteView` 与 `CardEditor` 整页单正文、原生导航、底部／键盘工具；非一张小编辑卡 | 本轮 Home→无外壳编辑器 UI 已过。需 UI：真实既有草稿／保存／取消、长文和键盘、只读兼容、单正文不造独立标题、默认私有与回到来源页 |
| 编辑工具／标签／链接／媒体 | **结构已改＋系统宿主**。右下工具入口及原菜单、tag／link 编辑、照片／相机选择器沿用 | 不新增附件类别。需 UI：工具位置／44pt、键盘遮挡、取消选择不写入、链接失败／草稿保护；编辑保存后菜单元数据刷新仍在集成验收 |
| Spark · 来源／结果／深度 | **结构已改，菜单已补齐**。真实 `SparkContinuationView` 来源条、链深度、结果阅读／前后切换与底部 Continue Spark；顶部和结果更多均已改 `NativeCardActionsMenu`，prepare 不再打开旧 overlay | 沿用本人 3×3／他人 3×2 动作及 `store.sparkCurrentDeeper`。离线专用 Spark fixture 仍仅显示原能力提示，不构造联网菜单；需 UI：两个入口的权限／路由、返回及 Continue Spark 的既有会话 |
| Spark · 收藏／作者／评论／编辑返回 | **结构已改，状态同步正在修／验收**。保留收藏原地停留与捕捉想法；已接本人动作回执、删除后当前位置及来源移除退出；源码现已接明确 editor-return refresh | 21 项初始动作交互与后续 23 项刷新相关检查由 root 记录；需在最新源码重跑整条菜单→编辑→返回与失败。Spark sheet 上方评论打开／关闭的三个独立 UI 已过，不代表 Spark 其他动作均过 |
| Merge · 来源选材／搜索 | **保留已迁移的实际结构**。`MergeLifecycleViews` 的来源／候选行、选择状态、计数与 safe-area 操作；不是 `LegacyMergeView` | `MergeSessionStore` 与网络服务本轮哈希不变，固定 anchor、2–8、已有搜索／取消规则保留。需 UI 重跑现有选择／内容点击／数量约束 fixture，双主题与大字 |
| Merge · 进度／后台任务／取消 | **保留已迁移的专用结构**。生命周期页面与 `MergeTaskRail` 的真实任务状态／协调器 | 不新增任务类型，不假成功。需 UI：同一任务返回、多个任务、退出／恢复、确认取消／失败重试，不能以静态进度截图代替 |
| Merge · 结果编辑／接受／放弃／冲突 | **保留已迁移的实际结构**。`MergeArtifactEditorSurface` 与原状态机；正文／tag／来源和恢复状态仍真实 | 需 UI 重跑现有 draft／旋转／大字／accept 锁定／discard 确认／超时重试／冲突 fixture。旧历史通过不覆盖本轮宿主改动 |
| 等级／笔触／Chora 展示 | **结构已改（已有共享实现）**。`ChoraiCardLevel`、`CardLevelMaterial`；Grid 无角色、Reader 有角色 | 不改 rate 阈值／committed 成长定义。需 UI：六级＋未知级、两主题、图文与长内容；不能用一种等级截图代表全部 |

### 社交、聊天与辅助页面

| 可达页面／状态 | 当前真实结构与实现证据 | 保留内容／必须补的验证 |
| --- | --- | --- |
| My Profile | **结构已改**。系统导航；开放资料／统计／笔记层级，移除整页大卡；实际笔记原生菜单 | 原头像／关系名单／Chat shortcut／九个本人卡片动作保留。本轮 `testMyProfileHeaderExposesChatShortcutWhileCardsKeepHomeActions` 已过；需 UI：长资料、空态／失败、菜单实际路由和双主题 |
| 他人 Profile | **结构已改**。系统导航、开放资料与笔记列表；Follow／Message／更多按原权限 | `CommunityProfileStore` 未改；本人身份隐藏自我社交操作，Report／Block 原确认仍在。需 UI：Follow／Unfollow、拉黑确认、菜单／收藏／作者跳转、失败／长内容 |
| Edit Profile | **结构已改**。系统标题／Back／Save，分组原生输入与照片入口；开放 ScrollView 不是外层整页卡 | 所有原字段、简介限制、头像／背景上传与失败保留；Back 44pt 修正后返回 Settings UI 已过。需 UI：键盘／取消／保存错误／照片选择取消／双主题 |
| Following／Followers | **保留现有原生结构**。`FollowListView` 本来使用 `NavigationStack` 与真实列表，接统一主题／控件 | 原权限、加载／分页／重试／点击 profile 保留，不新增搜索。需 UI：空／私有名单、长名、sheet 内 Profile→Link／返回层级 |
| Chat 列表 | **结构已改**。`ChatView` 系统导航和分组内容层级，原搜索输入和会话行 | 不声称新增搜索请求或过滤能力：基线搜索输入的业务接线保持。原未读／时间／头像／会话选择、设备本地历史可见性保留。需 UI：加载／空／长会话、隐藏历史后刷新、两主题 |
| Chat 会话／输入／回复 | **结构已改**。系统会话导航、实际消息流；safe-area 多行输入器、原引用笔记与恢复动作 | 原顺序、发送／流式／继续生成／错误、文本选择保留。本轮 attachment restore UI 已过；需 UI：键盘／超长消息／发送失败／输入恢复／两主题；fixture 不证明消息送达服务器 |
| Chat 选择引用／移除引用 | **结构已改**。`SelectCardPopupView` 原生 sheet + NavigationStack／搜索与选择行 | 原 `fetchCards(searchText:)`、select／remove 回调保留，不新增附件类型。需 UI：选择／取消／移除、空态／加载与会话 sheet 层级 |
| 侧栏 | **结构已改**。可滚动紧凑资料区、实际头像背景、44pt 关闭与条目；取消头像负偏移和大空白 | My Notes／Favorites／Notification／Trash／Settings／Help & Report、profile、余额／关系数／未读与原关闭延迟保留。需 UI：冷打开路由、短屏／大字、全部入口、点击背景关闭 |
| Settings | **结构已改**。系统 `Form`、section、导航／Back；原危险操作确认 | Personal Data／Chora／Invitations & Credits／Account & Privacy／Log Out 保留；已连接模块 UI 已过。需 UI：每一目的页、退出取消与失败留当前会话；不新增旧占位模块 |
| Account & Privacy | **结构已改**。`BlockedActorsView.AccountPrivacyView` 系统 Form 与只读账户字段、原 Toggle | username／email／membership、showFollowLists／allowFollow／showEmail／showPhone／showLocation／showBirthday 六项保留；原串行保存／失败回滚／Retry。需 UI：全部字段、保存中不可重复、错误恢复 |
| Blocked Users | **结构已改**。系统 List、导航、空／加载／错误与 44pt Unblock | 原 store、分页及解除拉黑动作不变；并未新增确认步骤。需 UI：长名／分页、失败保持目标、解除后列表更新 |
| Chora · Identity | **结构已改**。系统 Chora Profile 导航、开放分节；`ChoraSectionSurface(openLayout:true)` | avatar／Display name／Preferred address、原保存／部分失败草稿与权限保留；需 UI：loaded／partial save／error／大字 fixture |
| Chora · Growth | **结构已改**。开放成长区、语义层级与原真实 stage／meters | `ChoraProfileStore` 未改，不把演示等级写成真实进展。需 UI：未加载／失败／unknown／committed、长维度内容 |
| Chora · Soul & Sources / Local Notes | **结构已改**。开放 Sources 分节和原 disclosure／导入状态区 | 原文件类型校验、选择器、进度／取消／Retry／receipt、精确 asset 路由保留。需 UI：文件选择取消、取消中／失败／重新选择等现有 fixture |
| Chora · Notion | **结构已改**。同一开放 Sources 下的连接状态／页选择／同步区域，原授权宿主 | 原 OAuth、搜索／选择、断开确认、canonical unknown／import 状态保留。需 UI：现有授权／确认／失败 fixture；不执行真实授权／导入 |
| Chora · Chat History | **结构已改**。开放 section 与原确认操作 | 仍为“此设备隐藏历史”，不是服务器删除。需 UI：确认取消、actor scope、隐藏后列表／详情、cutoff 后新消息恢复 |
| Invitations & Credits 总览 | **结构已改**。系统 Form 的余额、邀请码、兑换与历史 sections | 原余额字段、复制／系统分享／pendingIntent／Retry／discard／success refresh 保留。需 UI：loaded、partial、empty、兑换失败与恢复 fixture |
| Invitation History | **结构已改**。系统 List／标题、原状态行与分页 | 原邀请人／状态／时间／receipt 数据保留。需 UI：空、分页失败重试与长文本 |
| Invitation Rewards | **结构已改**。系统 List／标题、原奖励行 | 原奖励来源／状态／金额语义保留。需 UI：空／错误／分页／双主题 |
| Credit Ledger | **结构已改**。系统 List／标题、原流水行 | 实际金额／时间／原因字段保留。需 UI：长原因、符号／金额、分页错误 |
| Notification Inbox／过滤 | **结构已改**。系统导航／toolbar、四项 segmented（All／Unread／Activity／System）、按原时间段分组 List | read-all、分页、mark-read 后路由、失败回滚保留。需 UI：`testNotificationInboxUIContract`、四项筛选、点击通知目的地、错误不误跳 |
| Notification Detail | **结构已改**。系统导航＋正文 ScrollView，无伪 header 或外层大卡 | 仍只承接 legacy 内容 fallback；真实目标通知保持原 router。需 UI：legacy body、长文本、返回及两主题 |
| Trash／恢复／永久删除确认 | **结构已改**。系统 List／导航，保留说明、状态／分页；每项 Restore／Delete 44pt；删除原生 sheet＋Form，失败留确认 | 原 exact card target、恢复／单项永久删除范围、busy 锁／Retry／取消、30 天自动清理提示保留（与本轮编辑前备份一致）。需离线 UI：打开／取消零请求、失败重试同一 ID、恢复失败；现有 Go 测试会真的创建／删除，不能为截图擅自执行 |
| Discovery Path／Root | **结构已改**。`RootView` 系统导航＋真实来源内容顺序；不是应用根页面 | 来源顺序、本人编辑／他人阅读、不可见／缺失／错误保留。本轮 collected→origin 排序 UI 已过；需 UI：失败 Retry／无来源／长内容／两主题 |
| 评论／回复／删除／举报 | **结构已改**。唯一根部 scene-aware 系统 sheet presenter、Comments NavigationStack、原生输入／medium-large detents，覆盖 Spark 已在 sheet 的情况 | 原 manager、回复／删除／举报权限、分页／失败／count 保留。`/tmp/chorai-comment-native-ui5.log` 三项 UI 已过：根详情键盘／取消、Spark 上方关闭、交互关闭后重新打开。更早 batch3 的三项失败已被此后修正和重跑替代；需继续两主题／长列表／大字／发送失败 |
| 卡片更多／本人动作共享宿主 | **结构已改＋正在修**。默认本人动作由 OwnedCardActionStore 处理，显式 Profile callbacks 保留；Spark／Explore 搜索最后两处系统 Menu 已接线 | Remove 取消零请求、失败 Retry、服务回执后 Public／Pin 更新已测试。**编辑返回旧回执遮盖新保存**修正已落盘（UUID authoritative refresh），Home／Detail／Spark 集成待全链 UI；不能把菜单源码接线检查当成功能路由验收 |
| Share／分享图片／系统 Share | **保留已迁移的原生结构**。`ShareCardView` NavigationStack＋Form 与既有系统分享 | 原图片 artifact／错误／Retry／只读预览；`ShareCardStore` 与 NetworkCoreShareService 本轮不变。需 UI：根页及上层 sheet 来源、取消／错误、浅深色；不改变公开范围 |
| Link | **结构已改＋正在修**。真实候选 Form 保留；多个 `.sheet` 监听同一 manager 的风险已改为唯一根部 `LinkPopupPresenter`／scene-aware presenter | 原来源 ID、mode／owner、候选查询与立即提交回调不变。独立 root／sheet-origin fixture 已新增，仍须 root 检查最新运行结果；不能先认定重复呈现问题验收通过 |
| Report／评论举报 | **保留已迁移的原生结构**。`ContentReportView` NavigationStack＋Form，评论行使用原 report sheet | 原 reasons／context／target、提交／失败／Retry／receipt 保留，服务和 store 本轮不变。需 UI：card／actor／comment 各真实入口、关闭与草稿／错误；不发送真实举报 |

### 账户、引导与系统边界

| 可达页面／宿主 | 当前实施状态 | 保留边界／待验证 |
| --- | --- | --- |
| Welcome／未登录根页 | **结构已改**。滚动式主内容与真实 Sign In／Sign Up 入口，ContentView 保留 access 状态分支 | 不添加不支持的社交登录。需 UI：短屏、两主题、正常／未登录／private beta／unavailable 分支与返回 |
| Sign In | **结构已改**。系统 navigation、可滚动字段／按钮、SecureField 与键盘语义 | `AuthManager` 未改，原登录函数保留；本轮键盘与 submit 可达 UI 已过。需 UI：错误、清空／长输入、两主题；不使用真实账号登录补证 |
| Sign Up | **结构已改**。系统导航、滚动表单和原输入／校验；输入字段语义整理 | 原 username／email／password／重复密码／邀请码、Terms／Privacy、partial signup 恢复不变。需 UI：既有 blank／invalid／partial／retry fixture、键盘／大字／错误 |
| Private Beta Entry | **结构已改**。系统导航／原邀请代码输入与注册流程 | 保留 authoritative invalid code 阻止 signup 和现有入口，不新增一套注册码。需 UI：现有两个 private-beta fixture 和两主题 |
| Access Gate | **结构已改**。可滚动 access 状态内容与原 reload／退出动作 | 原拒绝／不可用／重试分支不变，preview 绕过仍仅 Local DEBUG Simulator。需 UI：全部状态、返回／重复 reload |
| Choose Interests | **保留已迁移的实际结构**。明确标题、原选项网格、计数与 safe-area Reset／Next；大字时单列 | `InterestSelectionStore` 未改，原最大值／Skip／保存／错误保留；根式 onboarding 不必强造 Back。需 UI：加载／空／失败／上限／保存锁定／大字 |
| Onboarding Guide／contextual tips | **保留现有产品专用结构**。原提示层、定位与状态机，主题与手势目标延续 | 不新增教学步骤；需 UI：Home sort／Spark 收藏时取消提示、结束／跳过／延后、当前目标无遮挡。不能把所有 overlay 都视为必须改 sheet |
| Help & Report／Terms／Privacy | **系统／网页宿主保留**。`WebView` 与真实目的地址 | 仅核验宿主 loading／返回／浅深色；远端网页未在本轮请求或重设计，不新增 Help 功能 |
| Photos／Camera／裁切／文件导入 | **系统宿主保留**。UIKit／SwiftUI picker 和现有 delegate／completion | 保留权限提示、成功与取消回调；需 UI：从 editor／profile／Chora 返回正确位置。不能为外观新增权限或改变导入格式 |
| 系统 Share／Notion OAuth | **系统宿主保留**。既有分享控制器／授权协调器 | 只核验呈现／取消层级；本轮不实际对外分享、连接账户或运行生产授权 |
| 本地 Preview／测试 fixture | **验证入口，不是产品新页**。DEBUG Simulator＋Local 限制，LocalPreviewURLProtocol 拦截；Spark 独立 fixture 仍有能力边界 | 不把样例“收藏／发送／保存”称为服务器完成。新菜单不能破坏 fixture 的导航 guard；与生产真功能分开测试 |

### 不可达旧文件与保持不增加入口

`AccountDetailsView`、`PreferencesView`、`APIAndPluginsView` 仍无真实显式入口；`SparkView` 不是正式 Spark，`LegacyMergeView`／`NewInsightView` 不是正式 Merge。沿用前文引用结论，**不将这些文件列成待补产品页，也不在 Settings 新增菜单使其可达**。它们存在或编译通过都不能证明真实功能页已验证。

### 请求、字段、权限保留的本轮对照证据

1. **服务合同未被界面迁移替换。** 对 `/tmp/chorai-remediation-start-source.json` 逐项重新 SHA-256：`NetworkManager.swift`、`NetworkModels.swift`、`APIEnvironment.swift`、`APIConfiguration.swift`、`AuthManager.swift` 与 17 个相关网络适配器保持任务开始时内容，包括 Flow／Spark／Merge／CardEditing／Share／Report／Privacy／CommunityProfile／Notification／Invitations／Chora／Notion／NoteImport／InterestSelection／Discovery。该清单只有 hash，没有源码快照；它证明本轮这些文件未改，不能证明之前未提交改动与 HEAD 完全相同。
2. **原状态机仍为数据 owner。** 当前 hash 与任务开始一致的包文件包含 `MergeSessionStore`、`ShareCardStore`、`ContentReportStore`、`PrivacySettingsStore`、`BlockedActorsStore`、`CommunityProfileStore`、`NotificationInboxStore`、全部 Invitation overview／history／reward／redemption／registration stores、`ChoraProfileStore`、`InterestSelectionStore` 及其现有服务协议／模型。本轮有意改动的 `FlowDeckStore` 是原历史选择与状态同步，`SparkSessionStore` 是本人回执／编辑返回同步，另新增 OwnedCardActionStore；不能概称“所有业务代码未动”。这些变更需独立行为测试。
3. **辅助页请求／导航集合对照。** `/tmp/chorai-auxiliary-before/` 的六份编辑前备份与当前 Settings／BlockedActors／Notification／NotificationDetail／InvitationCredit／InvitationCreditDetailViews 比较，服务调用集合未新增或删除；`/tmp/chorai-trash-sidebar-before/` 与当前 Trash／SideMenu 的请求及目的页集合相同。源码对照可证调用保留，不能替代实际错误／取消／重试的 UI 验证。
4. **Home 不复制样例产品语义。** 与 `git show HEAD:ArcNote/HomeView.swift` 和真实 LibrarySortOption 对照，四种排序、本人／收藏 scope、真实 tag、collection count 保留；Collections 搜索补回真实 card 参数而非造新操作。本人九动作与收藏 View／Spark／Share／Link／Root／Report 权限分支仍由真实 layout／ownership 决定。
5. **明确字段与保护没有被排版删掉。** Privacy 六开关及账户字段、Profile 原编辑字段、邀请码／兑换 pending intent、通知读后导航／失败回滚、Trash 单项确认／busy／失败留目标、Chat 本地历史 actor scope、Chora committed stage 与导入 receipt 均有上述源码／store证据。`AuxiliaryNativePresentationSourceContractTests`、`TrashAndSidebarPresentationSourceContractTests` 与原领域测试通过，主要防止结构和权限接线丢失，不声称验证联网持久化。
6. **菜单宿主新增能力限于补齐已有动作。** 新 NetworkOwnedCardActionService 调用现有 public／pin／remove 方法并校验 actor 与 card ID；没有新 endpoint 或新增按钮。系统确认取消零请求、失败 Retry、错 ID 回执拒绝、连续 toggle 跟随服务回执已有独立测试。编辑返回刷新与 Link 唯一 presenter 两个 review 项仍记为**正在修／集成验收中**，不能因源码已落盘就关单。

### 证据强度与真实剩余工作

- **已读到通过结果：** Home 22 项 `/tmp/chorai-home-feature-parity-green.log`；辅助页 53 项 `/tmp/chorai-aux-native-green.log`；Trash／Sidebar 6 项 `/tmp/chorai-trash-sidebar-green.log`；本轮早期 CoreFlow 851／BlockNoteEditor 57 由 `PROGRESS.md` 对应日志记录，均早于后续共享宿主修正，必须注明时效。Batch 1 三条核心 UI；Batch 2 Chat attachment、Discovery、Settings、Sign In；Batch 3 Profile／EditProfile 两项已过；评论最新三项通过 `/tmp/chorai-comment-native-ui5.log`。
- **已补齐的最后两处菜单：** Spark 顶部／结果更多与 Explore 搜索更多已改为系统 Menu；准备菜单只更新真实目标，不打开第二个 overlay。三项跨模块接线回归先失败、修正后与原 Spark／Home 相关测试共 49 项通过，日志 `/tmp/chorai-discovery-menu-red.log`、`/tmp/chorai-discovery-menu-green.log`。为实际点验两个 Spark 菜单，随后增加专用 test-only 呈现开关：仅 DEBUG 的 fidelity store＋LocalDevelopmentPreview＋`--ui-test-spark-native-menus` 同时满足时显示菜单；普通 `allowsNetworkNavigation` 不变，三参数 `--dev-preview --ui-test-spark-fidelity --ui-test-spark-native-menus` 使用原 fail-closed URLProtocol。新增边界检查先失败后与相关测试共 50 项通过，`/tmp/chorai-spark-menu-fixture-red.log`、`/tmp/chorai-discovery-menu-final-green.log`。三个改动 SwiftUI 文件通过语法解析，但最新菜单尚未经过全 App 类型检查／Simulator UI。
- **后续补齐的搜索呈现：** Explore 搜索已从 HTMLWebView／整卡拖拽改为共享富内容摘要、明确固定高度、仅正文水平拖拽；原请求／index／翻页方向／作者与互动不改。提取的真实手势决策有 3 项行为测试，先按旧水平-only 规则重现三种纵向／对角误翻失败，修正后与相关 Flow／菜单测试共 42 项通过（`/tmp/chorai-search-summary-red.log`、`/tmp/chorai-search-summary-green.log`）。新 `SearchSummaryUITests` 测量六张卡实际尺寸并点验子控件／翻页／全文，已注册但此节更新时未执行。
- **实际大字号截图暴露的布局已修、待复测：** UI8 中 Explore 的 For you 与计数／history 重叠，卡片作者／日期及 Spark 挤碎。`browseHeading` 与 `FlowCardView` 在 accessibility size 改分行；作者／日期可两行，Spark 在该尺寸改图标并保留完整 VoiceOver 名称；工具符号限定 20pt、44pt 点击区，正文继续 Dynamic Type。普通字号原布局保留，不能用修前通过的 frame/tap 断言代替新截图验收。
- **正在修：** 编辑返回后旧 owned-action receipt 遮盖新公开／pin 状态；Link 多宿主重复呈现。前者显式刷新接入已落盘，后者唯一 root presenter 已落盘；各自最新 UI／失败恢复仍需检查，不能标完成。
- **运行覆盖仍不足：** 各行所列浅深色、短屏／大字、键盘、空／失败／只读、权限与返回链路；特别是 Profile／Chora／邀请／通知／Trash／认证全状态、Share／Report 的上层 sheet 来源。缺少 fixture 的真实写操作不能以生产请求补测。
- **整体完成仍未满足：** 最新全部改动之后的 Local 和 Production Simulator 构建、定向回归与主要页面双主题原生截图、功能矩阵逐项核验。Production 只构建不启动；无真实服务、账号、AI生成、消息送达、后端持久化结论。

## 最终源码边界复核与 owned-action 修复复测（2026-10-27 15:01 后）

本节为追加复核，保留前文历史快照。**前文关于“编辑返回后旧 owned-action receipt 遮盖新状态，仍待集成验收”的未决结论，现由下面的成功复测取代。** 这只关闭该共享宿主刷新缺陷，不将其他页面、Link 或全产品的历史待验证项一并视为通过。本次只读产品／测试源码，仅追加本审查文档。

### 功能与接口边界

以 `/tmp/chorai-remediation-start-source.json`、`/tmp/chorai-remediation-start.diff` 与 HEAD 重建本轮开始时的源码，并校验 10 个目标文件 SHA-256；逐项比对当前 Home、Detail、MyProfile、UserProfile、Settings、Trash、BlockedActors、EditProfile、FollowList、PopupMenu。未发现新增产品能力、原排序类别替换、权限放宽或新增 API 契约：

- Home 继续使用 `selectedSortOption.descriptor`、原 Notes／Collections scope、搜索与真实 tags；未加入原型示例分类。
- Profile／FollowList 的 follow、block、chat、like、favorite、comment 和名单入口保留。移除的旧卡片 `onAppear` 仅打印日志，不是分页调用。MyProfile 显式 delete／visibility／pin callbacks 仍原路执行；NativeMenu 每次动作前准备确切 card。
- Settings 四个设置入口及 logout 保护、Privacy 六个布尔字段、Blocked 原分页／unblock、EditProfile 原保存字段均保留。Trash 仍使用原 restore／permanent-delete 接口、确切 ID、busy／cancel／error 路径。
- Reader 的作者、收藏、点赞、评论和关联入口仍可达。Home／Detail／Spark 默认本人 `grid3x3` 均接 committed receipt 与 editor-return authoritative refresh；MyProfile 不重复发送 Home 通知。Explore／Discovery Path 的 `grid2x2` 原本没有 Remove／Visibility／Pin，故没有遗漏这些动作的 commit 接入。

复读共享 Store／Host 后，未发现额外可确定复现的状态或接口缺陷。普通列表／详情 GET 不覆盖已确认 mutation receipt；只有明确编辑返回的成功读响应产生新 refresh token。刷新失败保持最后已确认状态并显示 Retry／Cancel，不能据此宣称编辑后的服务状态已刷新；本审查没有把潜在网络时序、未执行的服务成功路径或 GET-only fixture 写入拒绝记作已证实产品 bug。

### 从失败到成功的确切证据

1. **历史失败仍保留：** `/tmp/chorai-remediation-visual-owned-ui8-light.log` 中 `testFreshEditReceiptReplacesPreviouslyCommittedMenuStates` 在 cache 断言失败。AX `/tmp/chorai-remediation-ui8-light-attachments/65ED0409-F069-4A47-A3AE-CE35A94513A7.txt` 显示页面 `Private, Unpinned`，Host cache 却仍 `Public, Pinned`、revision `2`，因此不是仅菜单没有弹出。UI8 同批 Remove Cancel、Remove Failure Retry、连续 Visibility／Pin 三项实际通过。
2. **有效修复：** `ArcNote/PopupMenuView.swift` 的 `OwnedCardActionHostModifier` 改为监听完整 `authoritativeRefresh`，直接将 `onChange` 的新 payload 传入 `store.applyAuthoritativeRefresh(refresh)`；不再监听 UUID 后从 modifier 闭包读取可选 payload。无效的 Menu `.id(ownedActionRevision)` 重建已撤销。Store 的确切 target、ownership、并发锁和服务回执规则未放宽。
3. **同一失败用例已成功复测：** build9 后 `/tmp/chorai-owned-fresh-ui9.log` 与 `/tmp/chorai-owned-fresh-ui9.xcresult` 记录 `testFreshEditReceiptReplacesPreviouslyCommittedMenuStates` **1 test、0 failures，15:00:58 完成，TEST EXECUTE SUCCEEDED**。断言包含外部编辑后 Host cache 为 `Private, Unpinned`、revision `3`，随后重新出现 Public／Pin 且实际请求序列为 `A:public:true → A:pin:true → A:public:true → A:pin:true`，共四次。它验证的是独立内存 service＋真实 SwiftUI Menu／Host，没有挂载 Home、登录或后端请求；不是通过改变菜单文本或跳过缓存断言取得通过。
4. **最新包回归已核对：** `/tmp/chorai-remediation-coreflow-all-5.log` 记录 **871 tests、0 failures**，14:57:13 完成。该结果与 UI9 分开计数；UI8 的另外三项通过不伪写成 UI9 四项整批重跑。

这些结果支持共享动作状态与本轮源码功能边界的限定结论，不代表真实编辑保存、服务端持久化、整页视觉签核或整个产品验收完成。


<a id="current-status-2026-10-28"></a>

## 2026-10-28 当前实施与验证状态

**当前结论：真实 App 的主要页面及辅助页面已完成本轮结构整改、选定浅深色运行核对与本地截图交付。** 下方分组概括前文逐项页面／状态覆盖表；“结构已改”与“相关用例已通过”分别记录，不把一个成功用例外推为该页所有权限、数据、错误和屏幕尺寸均已验证。本节取代历史段落中仍称 Profile／IM 等仅有主题替换、Explore／Reader 仍未落地的判断，保留历史文字以追溯实际发现与修复过程。最新持续结果以 [VALIDATION.md](VALIDATION.md) 为准，实际截图入口为 [原生 App 运行画面](review/index.html)。

| 既有页面／状态组 | 当前实施与功能边界 | 当前已有证据及待核对范围 |
| --- | --- | --- |
| Home／Collections／库内搜索 | 开放正文列表、系统分段与排序菜单、可见更多；保留原四种排序、真实标签、收藏数量及本人／收藏动作。正文与标签间距、顶部和 New note 位置已回到 V6 对照值 | UI10 已检查排序菜单不挤动页面、Home 间距、新建与短笔记整页编辑。真实收藏读写、服务器排序结果不由样例证明 |
| 编辑器／工具／只读状态 | 整页单正文、右下工具和键盘工具，编辑时隐藏 Tab；保留默认私有、原保存／取消／媒体／标签／兼容只读保护 | 相关整页与返回测试、既有只读不可保存及工具菜单回归已通过；真实保存、上传仍需服务环境，不能记为本轮成功 |
| Explore 滑卡／历史／Grid／搜索 | 固定摘要卡、点击全文、拖动方向反馈，无常驻下方提示／遮罩；历史沿用原 frontier；Grid 保留等级笔触且隐藏 Chora；搜索仍按原翻页规则，不把搜索滑动改为收藏 | 六类搜索结果固定尺寸与子控件／翻页测试已在 UI9 通过；UI12 复测固定卡、历史和辅助字号动作。收藏成功后才前进的规则及 Undo 失败恢复由领域测试覆盖 |
| Reader／等级／相关内容 | 全页真实 HTML 正文，无外层卡壳；紧凑等级／笔触／Chora，保留作者、关注、消息、互动、更多与关联内容。辅助字号时作者与动作分行，正文继续随系统字号变化 | UI12 的 Explore→Reader 辅助字号用例通过，检查作者宽度及动作位于作者下方；普通正文与返回已有 UI10 证据。深色画面已复核；更多长文／权限组合按验证范围限制记录 |
| Spark／Merge／评论／Share／Link／Report／卡片更多 | 保留原结果与来源、Spark 深度／收藏停留、Merge 固定来源和 2–8 约束、后台任务及恢复；菜单改原生呈现。默认本人动作使用确切卡片宿主，Profile 显式 callbacks 保留；评论与 Link 各为唯一 scene-aware presenter | 独立本人动作的旧状态刷新缺陷已同用例复测通过；评论三项、Link 三项及相关恢复用例已有日志。不是实际 AI 生成、分享发送、举报提交或后端保存验证；选定上层 sheet／深色组合已通过最终批次核对 |
| Profile／Edit Profile／关系名单／IM／Chora | **已实质改结构**：开放资料与内容层级、系统导航和表单、会话消息流与 safe-area 输入器、原生引用选择 sheet；Chora 分区依真实 identity／committed stage／来源／历史字段展示 | UI12 再次通过 MyProfile Chat shortcut 与原九项本人菜单；他人 Profile、关系入口、编辑资料返回、聊天键盘／恢复、Chora 分区已有对应离线证据。没有为这些页面虚构“已批准逐屏原型” |
| Settings／Privacy／Blocked／通知／邀请积分／Trash／Discovery | 实际 Form／List／系统导航和确认；保留六项隐私字段、名单分页、通知四范围与原路由、邀请／兑换恢复、回收站确切删除目标、来源真实顺序 | UI10 补跑 7 项全部通过，包括隐私失败回滚／Blocked 入口、邀请三目的地、通知四范围／读状态路由。其它恢复检查按具体日志记账，不声称每个服务写状态都已验证 |
| Welcome／Sign In／Sign Up／Private Beta／引导 | 原生导航、可滚动输入、原校验与访问分支；未增加登录方式或服务能力。兴趣选择与 contextual tips 保留原产品状态机 | 已有登录键盘和 Private Beta 入口／无效码阻止注册检查；只进入注册 UI，未提交真实凭据。旧 SignupInvitation fixture 未注入真实注册依赖，不能用它作本轮离线注册成功证据 |

### 本轮复查关闭的新增问题

继续工作后发现，成功右滑收藏的 `Collected / Undo` 反馈在原实现中不会自行结束，会覆盖后续卡片顶部，并在离开 Grid 后重新出现。现已按 V9 的短时反馈恢复：10 秒后收起，进入 Grid／Reader 时收起；只清除反馈，不取消已确认收藏，也不改变当前卡和历史。计时按确切目标守卫；Undo 请求中取消旧计时，失败后保留重试并重新开始显示时长。直接 Reader 入口共用单次回调，原生菜单导航由离页清理兜底，没有重复导航。

新增三个行为检查先在最小空实现上重现两项预期失败，再修正；全部 FlowDeckStore 与既有呈现检查 **36／36** 通过，含既有 Undo 失败保持与新请求中到期／重试检查。日志：[重现失败](/tmp/chorai-undo-red.log)、[修复后通过](/tmp/chorai-undo-green.log)。该项的领域结果不替代整机画面检查。

### 已核对的最新结果

- **CoreFlow：874 项，0 失败。** 已读取 [最新完整包测试日志](/tmp/chorai-remediation-coreflow-final5.log)，不是把历史 871 项结果延用到新代码。
- **Build 14：测试构建成功。** [构建日志](/tmp/chorai-remediation-build14.log) 明确记录 `TEST BUILD SUCCEEDED`；最终 Local／Production 两 scheme 也均构建成功，Local 已重新安装启动，未启动 Production。
- **UI10 浅色：原运行已完成 3 项通过，暂停后补跑剩余 7 项全部通过。** [原中断日志](/tmp/chorai-remediation-ui10-light.log) 保留 `TEST EXECUTE INTERRUPTED`，不改写为整批成功；[恢复运行日志](/tmp/chorai-remediation-ui10-resume-light.log) 为 7／7。合计覆盖原计划 10 项。
- **UI12 浅色：3／3。** [日志](/tmp/chorai-remediation-ui12-light.log) 包含 MyProfile、固定摘要与历史、Explore／Reader 辅助字号；Reader 新检查覆盖作者和动作的相对布局。
- **深色核心 10／10、辅助 13／13、既有编辑器 1／1 均通过。** 最后 Profile 与 Sign In 对比度修正后，build14 浅色 2／2、深色 2／2 复测通过。最终 138 张实际截图已交付，人工视觉核对不等同于用户签核；并非所有页面和状态都有浅深色配对。

### 原型、接口与系统宿主边界

恢复工作时重新计算 **411 项 build10 源码哈希，无差异**；随后 Undo 与 Reader 的明确修复进入后续构建，该旧 manifest 不能作为最终构建的冻结证明。最终另核对 build14 的 411 项源码哈希无后续变动，记录见 `qa/final-preservation.json`。独立重算 V3–V8 原型 **402 项，无差异**；未覆盖旧稿。与本轮开工 baseline 对照，30 个名称匹配 Network／API／Auth 的文件（含关联测试）无差异，`Package.resolved` 无 diff。功能审查未发现额外新增产品能力或接口、原权限放宽、虚构分类；具体字段和动作仍以真实代码为准。

Photos／Camera／裁切／文件导入、系统 Share、Notion OAuth 与 Help／Terms／Privacy 网页继续使用已有系统或网页宿主，不是漏改的自绘页面，也不应为覆盖率重做外部服务。未执行真实 OAuth／对外分享或请求远端网页来补验证。Chat 列表的搜索输入在 HEAD 已没有过滤／搜索请求接线；本轮保留这个既有边界，不能把输入框可见说成新增搜索功能已完成。

本轮验证是 Local Simulator 与离线 fixture 的布局、导航、状态及失败恢复检查。它不证明真实登录、消息送达、AI 生成、服务器收藏／保存／上传、部署或真机表现。旧不可达页面及测试入口没有为“全改”而重新暴露；缺少服务验证的部分保持明确限制。
