# Chorai 原生视觉原型 · 第一轮

2026-10-21。Explore、Home、编辑器，共六个浅／深色画面。

## 怎么看

1. 在 Finder 中双击同目录的 `Open-Prototype.command`，打开独立的 **Chorai Prototype** iOS App。
2. 默认跟随系统主题。各 Tab 左上角菜单里的 Appearance 可临时切换 Follow System、Light、Dark，方便审稿。
3. 浏览 `gallery/index.html`，可以放大单屏并在相同页面之间切换浅／深色。画册是实际原型截图；点击、键盘和系统玻璃的动态表现请在 Simulator 里体验。

本机画册地址：[设计画册](http://127.0.0.1:8767/gallery/)。本地服务停止后仍可直接打开 HTML 查看相邻 screenshots 文件夹里的图片。

## 第一轮设计

- **Explore**：保留单卡浏览、作者入口、卡片右上 Spark／更多、下方点赞／评论；正文使用七行预览，点击后阅读完整内容。以温白纸面与墨绿操作表达 Chorai 的阅读气质。
- **Home**：保留 Notes／Collect、搜索、筛选与右下新建入口；用日期、统一正文预览和标签建立秩序。没有把第一段转换成独立标题。
- **编辑器**：单一正文，原生输入、选择、复制粘贴与键盘；操作栏放在正文之外。内容修改后，左上保存更新本地样本并留在编辑器，随后切换为返回。
- **浅深适配**：浅色温白／墨绿；深色炭黑／暖灰／柔和绿。系统控件使用原生 TabView、NavigationStack、toolbar、Menu、sheet、Picker、SF Symbols 和 Liquid Glass。

这轮没有展示 Chora 成长或等级；角色形象与六档状态将在完成的角色资源及真实语义基础上单独评审。

## 可以体验的路径

- Explore 左右滑动卡片、打开正文／作者、Spark 入口、点赞与收藏本地样本。
- 搜索输入后提交，浏览结果，再取消回到原页面。
- Home 切换 Notes／Collect、筛选、打开自己的笔记或他人只读内容。
- 新建私密样本、输入文字、保存留在编辑器、返回 Home 再打开；放弃未保存内容有确认。

## 边界

这是独立的原生视觉与输入原型，使用内存中的示例数据；重启后恢复初始样本。没有真实账户、AI、发布、网络请求或云端同步。

编辑器使用原生纯文本输入，供视觉和操作手感审阅。正式 App 的 BlockNote 富文本、块结构、格式工具、链接／图片、草稿版本与冲突处理均未替换；这些需要在正式迁移阶段逐项保持原有合同。标签编辑、真实评论和 AI 结果不在此轮可执行范围。

原型要求 iOS 26+ 以展示系统 Liquid Glass；正式 App 的 iOS 16 最低版本保持原样。本轮正式界面未迁移，也没有提交或推送代码。

## 本轮验证

独立原型在 iPhone 17 Pro／iOS 26.5 Simulator 上构建并运行。13 项模型行为检查及 3 项原生 UI 测试全部通过：新建并保存后返回、搜索仅提交时查询并可取消、切换页面并编辑后保存留在编辑器及返回重开。六张截图均来自实际运行的原型。最后的按钮文字对比度调整经过重新构建和截图检查。

验证记录：`/tmp/chorai-native-prototype-build.log`、`/tmp/chorai-native-prototype-ui-run1.log`、`/tmp/chorai-native-prototype-ui-run1.xcresult`。以上只覆盖独立原型，不代表正式 App 的全量回归、真机触觉或联网功能已经通过。

## 文件与交付

- `screenshots/`：六张 1206 × 2622 原生截图。
- `gallery/index.html`：支持放大与浅深对照的设计画册。
- `prototype/`：可重建的 SwiftUI 原型与验证代码。
- `PLAN.md`：正式迁移的分阶段计划及保持不变的产品语义。
