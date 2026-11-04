# Home / 编辑器实际修正验证 · 2026-10-27

本目录对应真实 App 的 Home 与编辑器改动，使用 `--dev-preview` 及已有编辑器离线 fixture。Explore 固定卡片与全页 Reader 是另一个 [V9 独立设计提案](../2026-10-21-native-visual-reform/revisions/v9-fixed-deck-reader/gallery/)，本轮没有将 V9 布局替换到真实 App。

## 构建与包测试

| 检查 | 已检查的结果 | 归档日志 |
| --- | --- | --- |
| Local App / UI test build | `TEST BUILD SUCCEEDED`，包含本地 App 与 UI test runner 构建 | `qa/chorai-review-final-local-build.log` |
| Production / iOS Simulator | `BUILD SUCCEEDED`；只构建，没有启动 Production App | `qa/chorai-review-production-final-verified.log` |
| CoreFlow 本次所选测试 | 114 项通过，0 失败 | `qa/chorai-review-coreflow-verified.log` |
| BlockNoteEditor 包测试 | 57 项通过，0 失败 | `qa/chorai-editor-package-verified.log` |

环境为 Xcode 27.1、iPhone 17 Pro / iOS 26.5。构建采用 Simulator 目标，关闭代码签名；这些结果不证明真机签名、发布或线上服务可用。

## 原生界面回归

以下按具体测试的最终已见结果记录。完整日志保留原始批次状态，未把部分通过的批次写成全部成功。

| 覆盖行为 | 测试 | 已检查结果 / 证据 |
| --- | --- | --- |
| Home 正文到标签约13pt，菜单44pt点击区；新笔记键盘与整页高度；低处空白能聚焦；关闭恢复Home；Format入口、输入后高度、添加与删除标签 | `testNativeReviewHomeSpacingAndFullPageDraft` | 浅色最终通过，`qa/chorai-review-editor-light-ready.log`；深色通过，`qa/chorai-review-dark-final.log` |
| 从 Home 菜单或正文进入真实编辑页；未修改时直接关闭；编辑期间隐藏Tab，退出恢复 | `testNativeFidelityHomeMenuOpensRealUnboxedEditor` | 浅色通过，`qa/chorai-review-light-complete.log`；深色通过，`qa/chorai-review-dark-final.log` |
| 已有短笔记占满写作空间，页面下部可聚焦，输入后不缩回小框 | `testNativeReviewExistingShortNoteUsesFullWritingPage` | 浅色通过，`qa/chorai-review-light-complete.log` |
| 四个已有排序项使用系统菜单；切换不撑开额外控件行；进出编辑器保留选中排序 | `testNativeReviewSortUsesSystemMenuWithoutExpandingThePage` | 浅色通过，`qa/chorai-review-light-complete.log`；深色通过，`qa/chorai-review-dark-final.log` |
| 系统菜单打开前收起键盘 | `testCardEditorNativeMenuDismissesKeyboardBeforePresentation` | 浅色通过，`qa/chorai-review-light-complete.log` |
| 格式条的图片 / 标签入口位置、工具可见性，以及关闭键盘后的工具菜单 | `testCardEditorFormattingBarPinsPhotoAndTagAndReflectsSelection` | 后续复测通过，`qa/chorai-review-tools-regression.log` |
| 标签用Return提交，不误出正文格式条 | `testInlineTagEntryCommitsOnReturnWithoutBodyFormattingBar` | 通过，`qa/chorai-review-tools-regression.log` |
| 标签从空白区提交，拒绝空白或仅井号的输入 | `testInlineTagEntryCommitsFromShellGutterAndRejectsBlankOrHashOnlyInput` | 通过，`qa/chorai-review-tools-regression.log` |
| 不兼容内容保持只读；禁止正文、工具、标签和保存修改，保留既有只读关系展示 | `testCardEditorShellCompatibilityBlockIsReadOnlyAndCannotSave` | 修正后深色通过，`qa/chorai-review-dark-final.log` |

最终深色所选批次4项全部通过、0失败，日志以 `TEST EXECUTE SUCCEEDED` 结束。这4项是只读保护、Home进入编辑器、整页新建写作和原生排序；没有据此声称整个项目所有UI测试均已执行。

## 真实正文高度与文档不变性

`BlockNoteWritingExtentRuntimeTests/testWritingFloorFillsEditableDOMAndCanShrinkWithoutEditingTheDocument` 在真实 WKWebView 中检查正文 DOM：

- 520pt 显示下限传递到根容器与 `contenteditable`，页面下部命中可编辑区域。
- WKWebView 自身仍保持520pt时，显示下限可降为280pt，再归零，不被旧视口高度锁住。
- 编辑器 `ready` 后仍有初始React渲染及延迟变更通知：本次日志中最初revision为0，稳定后为2。测试在任何CSS高度更新前等待稳定基线。
- 改变高度后，JSON正文、Markdown及revision均与该稳定基线相同。该结论是“外观更新没有改文档”，并非“初始化从未发生任何文档事件”。

## 保留的诊断失败与后续结果

- `chorai-review-light-complete.log`：6项中4项通过、2项失败，整批结尾仍是 `TEST EXECUTE FAILED`。格式条检查和整页编辑器检查已分别在工具回归、最终浅色整页测试中通过。此批次只将已通过测试产生的已有笔记 / 排序截图用于交付，来源记录含单项通过状态。
- `chorai-review-tools-regression.log`：4项中3项通过、1项只读保护失败，整批仍是失败。只读状态修正后已在最终深色批次中通过；不删除旧失败记录。
- 早期格式条测试仍预期旧的标签按钮结构，随后按新的工具入口核对；整页流程对原生控件就绪和键盘状态使用实际等待条件。保留13pt间距、44pt点击区、整页可写区域和Tab可达性的行为断言。

## 截图与验证边界

网页提供7个状态 × 浅深色共14张主要截图，另保留收起键盘与已有短笔记等补充状态。每张图的 `.xcresult`、具体测试和设备来源保存在 `qa/*-screenshots.json`；旧批次来源记录继续保留，后续重新采集的同名截图以最新映射为准。

本轮没有测试真实账户登录、网络推荐、真实收藏、AI生成、服务器保存、持久化或部署；未启动Production App、未调用生产后端。系统菜单与页面交互仍沿用已有权限、数据格式和功能语义。浏览器审阅图可用于比较视觉，不能证明原生行为或服务成功。
