# 原生前端整改验证 · 2026-10-28

本轮本地实施、浅深色复核、最终构建与截图交付已完成。本文件记录真实 App 的本地验证，不表示服务端联调或用户视觉验收。确认原稿保持不变；[逐页源码与功能审计](PAGE-AUDIT.md)保留了从发现到修复的历史。

## 工程与边界

- 工程：`/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend`，`main` / `8fe71f81850ca32aa07773a29ca21b04f1604458`。改动留在本地工作树，未提交、推送或切换分支。
- 工具：Xcode 27.1（27A9275）；iPhone 17 Pro / iOS 26.5 Simulator。命令通过项目范围的 `DEVELOPER_DIR` 选择 Xcode，未更改全局选择。
- Local 为唯一启动环境。Production 只做无签名模拟器构建，没有启动或请求生产服务。
- 当前离线样本使用实际 View / Store / 原生导航。通用预览的写操作和未知请求会在本机拒绝；专用行为样本使用内存 service。成功截图、内存回执和构建均不证明真实登录、AI 生成、消息送达、上传或服务器保存。

## 用户指定的整改

| 范围 | 实际实现与验证范围 |
| --- | --- |
| Home | 保留 V6 布局与正文到标签 13pt 间隔；原四种排序收进系统菜单；真实标签与右下更多，不加入示例分类。My Notes / Collections 与编辑返回保持。 |
| 编辑器 | 单一正文铺满可用页面，右下工具，键盘格式栏；关闭键盘不缩成卡片，编辑时隐藏底部导航；只读兼容内容不能保存。 |
| Explore | 更大的固定摘要卡；点击全文；左右拖动时反馈；历史与返回探索保留；Grid 保留等级笔触并隐藏 Chora。收藏确认后前进，失败不假成功。 |
| Reader | 全页正文、原始 HTML 与实际标题；等级/笔触/Chora 在页头，作者/关注/消息/互动保持。辅助字号下作者独立一行、动作移到下方，正文大小不封顶。 |
| Spark / Merge | 保留真实来源、深入、选择 2–8、结果编辑、接受/放弃、后台任务与失败恢复；使用原生菜单和现有状态机。 |
| Profile / IM / Chora | 实际资料、关系、消息列表与会话、引用选择、Chora 四部分已做结构迁移；没有引入新社交指标、附件类别或服务能力。 |
| 辅助页面 | 设置、账户隐私、屏蔽名单、通知、邀请积分、回收站、认证入口、评论/Link/Share/Report 沿用原权限和接口，统一原生导航与控件。系统媒体/分享/网页宿主保留。 |

辅助页面没有逐屏批准的旧原型，按已确认色彩、材质与原生布局延展；不能声称与不存在的原稿逐像素一致。

## 已确认的检查

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| CoreFlow 完整测试 | 874 / 874 通过 | `/tmp/chorai-remediation-coreflow-final5.log` |
| BlockNoteEditor | 57 / 57 通过；之后编辑器包没有修改 | `/tmp/chorai-remediation-blocknote-all.log` |
| 最新 UI 测试构建 | build14 成功 | `/tmp/chorai-remediation-build14.log` |
| UI10 浅色恢复 | 暂停前 3 项完成；另外 7 项恢复运行全部通过 | `/tmp/chorai-remediation-ui10-light.xcresult`、`/tmp/chorai-remediation-ui10-resume-light.xcresult` |
| UI12 浅色 | 3 / 3 通过：MyProfile、固定卡/历史、Explore→Reader 辅助字号 | `/tmp/chorai-remediation-ui12-light.xcresult` |
| 深色核心 | 10 / 10 通过：Home、Grid/Reader、Spark、Merge、菜单、资料、评论、Link 与 Private Beta 导航 | `/tmp/chorai-remediation-core-ui12-dark.xcresult` |
| 深色辅助 | 13 / 13 通过：Profile、设置/隐私、Chora、邀请、通知、回收站、来源、登录等选定状态 | `/tmp/chorai-remediation-aux-ui12-dark.xcresult` |
| 深色既有编辑器 | 1 / 1 通过：本人笔记由更多进入整页编辑 | `/tmp/chorai-remediation-editor-ui12-dark.xcresult` |
| 最后按钮对比度复测 | build14 浅色 2 / 2，深色 2 / 2；Profile/Followers 与 Sign In。人工复看最新图片 | `/tmp/chorai-remediation-contrast-ui14-light.xcresult`、`/tmp/chorai-remediation-contrast-ui14-dark.xcresult` |
| 最终 ArcNote Local 构建 | 成功，exit 0；已安装并在 Device Hub 启动离线 Explore | `/tmp/chorai-remediation-local-final.log` |
| 最终 ArcNote Production 构建 | 成功，exit 0；未启动 Production | `/tmp/chorai-remediation-production-final4.log` |
| 独立动作状态 | UI8 取消/失败重试/连续切换 3 项通过；UI9 编辑后状态刷新单项重测通过 | `/tmp/chorai-remediation-visual-owned-ui8-light.xcresult`、`/tmp/chorai-owned-fresh-ui9.xcresult` |
| 搜索摘要 | 2 / 2 通过：六种富内容同高、纵向和标签不误翻、原路由 | `/tmp/chorai-remediation-visual-ui9-light.xcresult` |
| 离线恢复/权限 | UI9 恢复批次 11 项通过；通知失败点随后 UI10 已修正并通过 | `/tmp/chorai-remediation-recovery-ui9.xcresult` |

不同批次不会重复合并为一个看似全量的测试总数。失败和中断记录保留；最新通过结果只替代对应失败项。

## 本轮最后修正

- 收藏后撤销提示缺少关闭条件：新增只清除提示的确切目标检查，10 秒后收起，进入全文或 Grid 时收起；请求进行中不丢失失败后的撤销重试。3 个行为回归与原测试一起通过，`/tmp/chorai-undo-red.log`记录修复前失败，`/tmp/chorai-undo-green.log`记录 36 项通过。
- Reader 辅助字号作者被压成省略号：新增真实布局回归先失败（作者宽 155.33pt，期望至少 301.5pt），再将作者与动作分行；UI12 同一回归通过。正常字号与完整正文排版不变。
- 旧源文件约束要求固定 44pt 的动作被更新为可增长的最小点击区；最初完整测试的该单一失败保留在`/tmp/chorai-remediation-coreflow-final3.log`，最新 874 项全部通过。

- 深色 Follow 与 SIGN IN 的浅绿底原用白字，人工截图检查发现对比不足；改用已有 `onAccent` 语义颜色，并让 Follow 加载指示同色。原点击与状态逻辑不变。build14 浅深色两项分别复测通过。

## 服务和设备验证范围

没有运行需要真实服务的全量 UI 套件。独立后端未安装，真实账户、服务端收藏/编辑/上传、AI 生成和消息送达未联调。Chat 基线搜索输入没有过滤或请求接线，本轮保留原范围，没有补造搜索功能。旧 SignupInvitation 测试的服务注入未连接到真实 SignUp，故未用于声称注册验证；PrivateBeta 仅测试安全的预检查/导航。

未运行真机测试；系统照片/相机/分享/浏览器实际外部结果仍由系统及服务决定。编辑器保留已有 BlockNote 富文本内核，页面容器、导航与工具交互使用原生能力；没有把网页编辑内核称为完全 SwiftUI 重写。主要页面的浅深色与选定最大辅助字号检查不等于每个机型、权限组合、数据长度和在线错误状态的穷尽验证。

## 收尾

- [真实 App 逐页审阅](review/index.html#home-light)：138 张原始截图，78 个页面/状态，浅色 74 张、深色 64 张，其中 60 个状态成对。它是实际运行截图浏览器，不是新增原型。截图来源、测试批次、时间、源码快照与哈希见 [evidence.json](review/evidence.json)。已知不合格画面和失败/中断测试的画面不进入交付。
- 最终源码保全核对：build14 的 411 个文件无后续变更；V3–V8 保存清单中的 402 项无差异；与本轮开始相比，30 个 Network/API/Auth 名称文件无差异；依赖锁文件无修改；`git diff --check` 通过。见 [final-preservation.json](qa/final-preservation.json)。
- 工作树包含本次及此前保留的前端改动，不是干净工作树；仍在原 main/HEAD，未提交或推送。旧原型与旧 fidelity 页面保留。
- 最新 Local App 已重新安装并用 `--dev-preview` 启动；实际 Device Hub 画面显示 Explore / LOCAL PREVIEW。本地截图服务监听 127.0.0.1:8768。没有启动生产配置。

- 审阅入口已实际打开并检查：Home 浅深色和深色编辑器对照图片正常加载，页面切换有效，浏览器未记录脚本错误；已将页面保留在 Home 浅色对照。
