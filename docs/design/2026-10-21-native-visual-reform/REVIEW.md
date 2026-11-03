# Chorai 原生视觉原型 · Explore 滑卡 V2

2026-10-21。Explore、Home、编辑器，共六个浅／深色画面。V2 在独立原型中加入 Explore 左滑略过、右滑收藏及可回看的卡片浏览。

## 怎么看

Explore V2 专页：[浅深对照与操作实录](http://127.0.0.1:8767/gallery/swipe.html)。展开页面下方的实录即可观看约 20 秒的右滑收藏、撤销和回看过程。

1. 在 Finder 中双击同目录的 `Open-Prototype.command`，打开独立的 **Chorai Prototype** iOS App。
2. 默认跟随系统主题。各 Tab 左上角菜单里的 Appearance 可临时切换 Follow System、Light、Dark，方便审稿。
3. 浏览 `gallery/index.html`，可以放大单屏并在相同页面之间切换浅／深色。画册是实际原型截图；点击、键盘和系统玻璃的动态表现请在 Simulator 里体验。

本机画册地址：[设计画册](http://127.0.0.1:8767/gallery/)。本地服务停止后仍可直接打开 HTML 查看相邻 screenshots 文件夹里的图片。

## 当前设计

- **Explore V2**：原生跟手滑卡，左滑略过、右滑收藏并继续；下一张在后方显露。保留作者入口、卡片右上 Spark／更多、独立点赞／评论；正文使用七行预览，点击后阅读完整内容。以温白纸面与墨绿操作表达 Chorai 的阅读气质。
- **Home**：保留 Notes／Collect、搜索、筛选与右下新建入口；用日期、统一正文预览和标签建立秩序。没有把第一段转换成独立标题。
- **编辑器**：单一正文，原生输入、选择、复制粘贴与键盘；操作栏放在正文之外。内容修改后，左上保存更新本地样本并留在编辑器，随后切换为返回。
- **浅深适配**：浅色温白／墨绿；深色炭黑／暖灰／柔和绿。系统控件使用原生 TabView、NavigationStack、toolbar、Menu、sheet、Picker、SF Symbols 和 Liquid Glass。

这轮没有展示 Chora 成长或等级；角色形象与六档状态将在完成的角色资源及真实语义基础上单独评审。

## 可以体验的路径

- Explore 左滑略过、右滑收藏，也可点 Skip／Collect 按钮。已收藏的内容再次右滑仍保持收藏。
- 点 Previous 连续回看旧卡，收藏状态保持不变；点 Continue exploring 直接返回尚未浏览的位置。全部浏览结束后，仍可回看最后一张。
- 新增收藏后有独立的 10 秒 Undo 提示：只撤销刚才新增的收藏，当前浏览位置保持不变。回看不会撤销收藏，已收藏的旧内容也不会产生删除旧收藏的撤销动作。
- 点开正文阅读再返回仍停在原卡；作者、Spark 和独立点赞入口保留。
- 搜索输入后提交，浏览结果，再取消回到原页面。
- Home 切换 Notes／Collect、筛选、打开自己的笔记或他人只读内容。
- 新建私密样本、输入文字、保存留在编辑器、返回 Home 再打开；放弃未保存内容有确认。

本轮提供六张他人内容样本，首张 Mira 尚未收藏，Leo 已收藏，便于比较首次收藏和重复右滑的状态。所有浏览历史和收藏变更都仅保存在本次原型运行中。

## 边界

这是独立的原生视觉与输入原型，使用内存中的示例数据；重启后恢复初始样本。没有真实账户、AI、发布、网络请求或云端同步。

编辑器使用原生纯文本输入，供视觉和操作手感审阅。正式 App 的 BlockNote 富文本、块结构、格式工具、链接／图片、草稿版本与冲突处理均未替换；这些需要在正式迁移阶段逐项保持原有合同。标签编辑、真实评论和 AI 结果不在此轮可执行范围。

原型要求 iOS 26+ 以展示系统 Liquid Glass；正式 App 的 iOS 16 最低版本保持原样。本轮正式界面未迁移，也没有提交或推送代码。

## 本轮验证

V2 的 37 项模型行为检查已通过，包括原有 13 项和新增 24 项滑卡／回看检查。新增检查先观察到“略过应前进到下一条未读内容”的失败，再在实现后通过；覆盖收藏幂等、回看不取消收藏、继续探索返回未读位置、独立撤销及空列表／末尾边界。

本轮已在 iPhone 17 Pro／iOS 26.5 Simulator 上重新构建并运行，七项原生 UI 测试全部通过：左滑／右滑、连续回看与继续探索、重复收藏幂等、撤销不导航、全文返回原位置、小幅拖动回弹／纵向滚动不误开正文，以及原有搜索、新建、编辑和保存流程。

V2 原生验证记录：`/tmp/chorai-swipe-build.log`、`/tmp/chorai-swipe-ui-verified.log`、`/tmp/chorai-swipe-ui-verified.xcresult`。

V2 模型验证记录：`/tmp/chorai-swipe-model-red.log`、`/tmp/chorai-swipe-model-green.log`。第一轮记录：`/tmp/chorai-native-prototype-build.log`、`/tmp/chorai-native-prototype-ui-run1.log`、`/tmp/chorai-native-prototype-ui-run1.xcresult`。以上只覆盖独立原型，不代表正式 App 的全量回归、真机触觉或联网功能已经通过。

## 文件与交付

- `screenshots/`：六张 1206 × 2622 原生截图。
- `gallery/index.html`：支持放大与浅深对照的设计画册。
- `gallery/swipe.html`：Explore V2 专页，含约 20 秒操作实录。
- `explore-swipe-demo.mp4`：原生模拟器录屏，展示收藏、独立撤销与回看。
- `prototype/`：可重建的 SwiftUI 原型与验证代码。
- `PLAN.md`：正式迁移的分阶段计划及保持不变的产品语义。
