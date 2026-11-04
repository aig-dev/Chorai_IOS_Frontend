# V6 · 阅读、写作与关系操作流程依据

日期：2026-10-21。范围是当前原生源码审阅和已存在的原型截图；没有调用后台、发布笔记、提交举报或向他人发送内容。本文中的“已有”表示源码已有对应行为，不代表本次验证过真实服务。

## 图谱怎样读

- **已有行为 · 源码核对**：说明当前正式代码的动作、分支和失败处理。没有对应新主题截图时只显示文字，不拿普通页面充当成功或错误截图。
- **视觉原型 · 新主题**：V5 Explore、阅读、菜单、分享、Link、Report 的实际原生截图。温白墨绿为主，学院金只用于少量选择、连接和重点动作。图片不是正式应用现状截图。
- **早期视觉原型 · 待统一**：Home 与基础编辑器使用设计目录原有的浅深色截图；未重新拍成 V6，且基础 TextEditor 不代表生产 BlockNote 的格式、图片和保存逻辑已经迁移。
- 菜单、分享、连接和举报目前只有浅色截图。图谱切换到深色时仍展示该浅色截图，并明确标注；不合成未拍摄的深色画面。

## 现有路径与保留条件

| 路径 | 当前原生行为 | 视觉解释与边界 |
| --- | --- | --- |
| Explore → 阅读 → 返回 | 点击正文或 View 打开阅读；阅读包含作者、正文、关联笔记、Like、评论、收藏。收藏只适用于他人笔记。菜单按所有权分支。 | 新主题用同一份内容承接大卡与 Grid，再进入稳定的阅读页。Grid 是本轮设计新增的浏览模式，原版菜单的 `grid2x2` 只是菜单排列。 |
| 收藏 / 取消收藏 | 需要登录且不能收藏自己的笔记；只在服务响应成功时更新收藏与数量。Home 的收藏列表有取消收藏入口，成功后移出列表。 | 预览收藏只改样例状态，不等于服务端收藏；保存本人正文继续叫 Save。不能把收藏包装成复制或改写原文。 |
| Home → 新建 / 编辑 | 本人笔记进入 NewNoteView；新建初始为空正文、无独立标题、私密。正式正文由 BlockNote 驱动。 | Home / 编辑器截图沿用早期原型。保留单一正文、隐私状态、标签与工具层级，不增加独立标题输入。 |
| 编辑 → 保存 / 重试 / 返回 | 主按钮随状态切换 Save、Saving、Retry、Back。保存读取安全快照；成功且版本一致才判定干净。失败留在编辑器；无待保存变化的返回仍核对当前快照。无法取安全快照时允许“Keep Editing”或确认丢弃后关闭。 | 图谱没有伪造“云端已保存”的画面。现有样例只保存到内存会话，不可声称重启后仍在或已同步。 |
| 编辑 → Spark / Merge / Share / Root | 先取得安全快照并确保笔记已保存，再执行下一个动作；保存失败则停留并提示。Link 同样要求先有已保存笔记。 | 新主题不可绕过保存条件。流程图的“下一步”是讲解导航，不是后台调用。 |
| 作者 → 个人页 / 关注 / Chat | 阅读头像打开作者页；阅读有 Follow / Unfollow 和创建会话入口。作者页有关注状态、关注/粉丝列表、作者笔记、Chat、拉黑确认及操作失败反馈。 | 当前辅助图谱只有源码说明，没有作者页新主题截图；不伪造关注数、在线状态或已创建会话。 |
| 评论 → 回复 / 发送 | 评论弹层加载列表；正文不能为空，提交中不可重复发送。可选择公开或私密；私密评论的回复保持私密。只有发送成功才清空输入，普通失败保留内容并报错，未授权进入已有认证处理。 | 评论的可见性不能因视觉简化丢失。当前没有新主题评论画面，不能把“0”样例入口称为已接通评论。 |
| 他人评论 → 举报 / 拉黑 | 仅他人评论显示更多操作；举报对象类型是 comment；拉黑是另一项动作。 | 举报笔记、举报评论、拉黑用户、删除自己的内容要区分。 |
| Share → 预览 → 系统分享 | 加载后台分享预览与图片产物；检查 `canNativeShare`；准备分享时固定该产物，再把 UIImage 交给 iOS 分享面板。加载或准备失败可重试，笔记保持不变。 | V5 截图分享的是明确标注的样例文本，尚不是正式分享图片流程。打开系统面板不等于内容已发送。Share 不等于将私密笔记改成公开，也不能凭模型中的字段宣称已有复制链接按钮。 |
| Link → 选笔记 → 连接 | 从本人笔记发起可搜索本人及已收藏笔记；从他人笔记发起仅可搜索本人笔记，并以选中的本人笔记作为关系来源。创建成功后关闭；按入口设置决定是否跳转所选笔记。失败留在弹层，重复关系有错误提示。 | V5 只展示方向与选择预览；没有创建或持久化关系。Link 的含义是关联笔记，不是复制网页地址。 |
| Report → 原因 → 可选说明 → 提交 | 原因是 Spam、Harassment、Misinformation、Copyright、Other。提交中禁用编辑和重复提交；失败保留原因与说明，可重试；只有服务返回回执才显示 Report submitted / Case。 | V5 使用 Preview report / Draft preview · not submitted，关闭清除预览。不生成假编号、审核承诺或虚假的提交成功画面。正式成功/失败状态本轮仅按源码说明。 |

## 权限与入口不能合并

| 页面 / 所有权 | 当前菜单 |
| --- | --- |
| Explore / 他人笔记 | Spark、Report、Link、View |
| Explore / 本人笔记 | Spark、Share、Link、Edit |
| 完整本人菜单 | Edit、Spark、Merge、Public 或 Private、Share、Link、Root、Remove、Pin 或 Unpin |
| Home 收藏内容的完整菜单 | View、Spark、Share、Link、Root、Report |

所以“Share 和 Report 都存在”正确，但不等于每个页面、每篇笔记都同时展示。正文中的作者 / Like / 评论 / 收藏也不属于菜单项数量。右滑收藏、左滑跳过是用户选定的原型方向；原生产 Flow 的两个滑动方向都是离开当前卡片，不能写成原来就已右滑收藏。

## 源码依据

- 阅读与收藏：[正文卡片与动作](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/FlowViews.swift:348)、[阅读底部动作](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/DetailView.swift:343)、[收藏权限与成功更新](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/DetailView.swift:552)、[Home 取消收藏](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/HomeView.swift:1366)、[原 Flow 滑动](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/FlowViews.swift:546)。
- 入口与菜单：[Explore 菜单布局](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/ExploreView.swift:641)、[本人 / 他人菜单](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/PopupMenuView.swift:434)、[完整本人菜单](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/PopupMenuView.swift:483)、[收藏菜单](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/PopupMenuView.swift:561)。
- 写作：[Home 阅读 / 编辑路由](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/HomeView.swift:1008)、[新建路由](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/HomeView.swift:1232)、[新笔记初始私密](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/NewNoteView.swift:63)、[正式 BlockNote 正文](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CardEditor/CardEditorShell.swift:102)、[保存状态](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/NewNoteView.swift:494)、[安全快照与失败](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/NewNoteView.swift:635)、[返回核对](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/NewNoteView.swift:730)、[先保存再执行动作](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/NewNoteView.swift:1157)。
- 作者：[阅读作者 / Chat / Follow](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/DetailView.swift:139)、[会话成功后跳转](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/DetailView.swift:603)、[作者页关注与失败反馈](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/UserProfileView.swift:138)、[关注 / 粉丝列表](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/UserProfileView.swift:198)、[拉黑确认](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/UserProfileView.swift:397)。
- 评论：[加载与提交](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CommentPopupView.swift:58)、[公开 / 私密语义](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CommentPopupView.swift:269)、[成功后清空与私密回复](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CommentPopupView.swift:397)、[仅他人评论显示动作](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CommentPopupView.swift:486)、[举报 / 拉黑分开](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CommentPopupView.swift:542)。
- 分享：[获取真实产物](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/ShareCardStore.swift:24)、[权限与产物固定](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/ShareCardStore.swift:53)、[失败 / 重试](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/ShareCardView.swift:159)、[系统分享 UIImage](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/ShareCardView.swift:191)。
- 连接：[候选范围](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/LinkPopupView.swift:68)、[关系来源](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/LinkPopupView.swift:134)、[失败处理](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/LinkPopupView.swift:163)、[成功后导航](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/LinkPopupView.swift:194)。
- 举报：[原因](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/ContentReportModels.swift:3)、[提交 / 回执状态](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/ContentReportStore.swift:37)、[表单 / 保留输入 / 重试](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/ContentReportView.swift:93)、[真实回执画面](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/ContentReportView.swift:191)。

## 本轮辅助图谱覆盖

`gallery/auxiliary-flows.js` 提供四条讲解路径：阅读与收藏、写作与保存、分享、连接与举报。所有按钮只是切换图谱节点，不会执行截图中的发布、分享、举报、收藏或保存动作。真实系统分享面板截图仅证明该面板曾打开；并未发送给任何接收人。

作者、评论、保存失败、分享失败、真实举报回执仍缺少新主题原生画面，图谱以明确的源码说明补齐上下文，不标为视觉完成。浅深色与截图版本在节点内逐项注明。Spark / Merge 的 V6 原生演示由本轮独立页面承接，需同样保留“离线示例”和“真实结果”边界。
