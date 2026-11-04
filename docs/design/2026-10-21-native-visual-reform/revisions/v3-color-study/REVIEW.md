# Chorai 原生视觉原型 · V3 配色与大卡片

2026-10-21。本轮提供四套候选配色，并把 Explore 卡片放大、移除常驻 Skip／Collect 双按钮。原来的 V1／V2 保留，可随时对照；本版是独立 App **Chorai Colors V3**。

## 怎么看

1. 双击本目录 `Open-Prototype.command` 打开 V3。它使用独立 bundle `com.chorai.nativeprototype.v3`，与 V2 共存。
2. 默认是学院绿金，跟随系统浅／深模式。在各 Tab 左上角菜单的 **Color study → Palette** 切换四套配色，在 **Prototype appearance → Appearance** 切换浅／深。
3. 配色画册入口：[四套配色对照](http://127.0.0.1:8767/revisions/v3-color-study/gallery/color.html)。画册按 Explore、Home、编辑器与浅／深模式比较实际原型截图；手势、键盘和动态玻璃请在 Simulator 内体验。
4. 旧版入口与归档见 [VERSIONS.md](../../VERSIONS.md)。

## 四套方向

| 配色 | 本轮想验证什么 |
| --- | --- |
| 学院绿金 | 母校 William & Mary 带来的个人联系，能否形成适合 Chorai 的温暖、克制品牌感 |
| 暮色紫 | 墨紫与柔和薰衣草色能否更适合表达、创作与夜间阅读 |
| 深海蓝 | 冷静、清透的原生感是否更耐看 |
| 陶土暖灰 | 纸张与手记的温度是否让知识探索更亲近 |

学院绿金只是默认演示，尚未确定最终方案。每套都覆盖浅／深，使用同样的内容和布局。准确令牌、取舍与母校色板来源见 [PALETTES.md](PALETTES.md)。

## Explore 现在的操作

- 卡片两侧外边距从 24 pt 收到 14 pt，紧凑页头释放高度，正文从七行预览扩为最多十二行；点正文仍打开完整内容。
- 左滑略过，右滑收藏并继续；已收藏内容再次右滑仍保持收藏。拖动时出现对应方向提示。
- 常驻大号双按钮已移除。更多菜单保留 **Skip note** 和 **Collect sample / Remove from collection**；菜单收藏停留原卡，延续原有菜单行为。VoiceOver 自定义动作保留。
- **Previous** 连续回看，不改变收藏；**Continue exploring** 直接返回未读位置。
- 新增收藏后的独立 **Undo** 只撤销该次收藏，浏览位置保持不变；回看不等于撤销。
- 正文返回、作者、Spark、独立点赞和评论入口保留。搜索、Home 与编辑路径不因配色而改变。

## 验证记录

V3 独立构建与 37 项模型行为检查通过。九项原生 UI 行为均获得通过结果，验证方式与限制如下：

- 首轮 9 项中 8 项通过，轻拖误翻页失败；确认快速拖动阈值过低，将最短实际位移从 30 pt 调整为 44 pt，长拖阈值保持不变。
- 修正后复测 4 个受影响手势用例：轻拖／纵拖、收藏撤销、已收藏内容再次右滑通过；菜单略过用例出现一次菜单未展开。
- 同一最终 App 上，菜单略过／回看／继续探索的诊断复测通过；随后增加点前可交互信息，连续重复 3 次均通过。该间歇现象保留为待观察项，不声称已定位或修复。
- 其余 5 项（创建、编辑保存、搜索、菜单收藏、配色／明暗切换保持浏览状态）在首轮通过，手势阈值修正后未重复执行。

证据：`/tmp/chorai-v3-build.log`、`/tmp/chorai-v3-palette-ui.log`、`/tmp/chorai-v3-gesture-verified.log`、`/tmp/chorai-v3-menu-diagnostic.log`、`/tmp/chorai-v3-menu-repeat.log`，以及对应 `.xcresult`。运行环境为 iPhone 17 Pro / iOS 26.5。

Theme.swift 独立 iOS Simulator SDK 类型检查通过。四套浅／深中的 ink、accent 对页面底／内容面，以及 onTint 对 ink 共 40 组不透明色值计算均 ≥4.5:1；最低 4.78:1。这不等同于玻璃合成后或整页的无障碍认证。

已导出并目检 24 张 1206 × 2622 原生截图：四套配色 × Explore／Home／编辑器 × 浅／深。浏览器逐页确认图片加载、页面切换、配色切换和大图浅／深切换。三页总览图、原始 PNG 与 V3 实际滑卡录像均保存在此目录。

## 边界

这是内存样本原型，重启后恢复初始数据，没有真实账户、联网、AI、发布、云端保存或同步。原生纯文本编辑器仅用于视觉与输入手感，不替换正式 BlockNote 富文本、文档版本和冲突处理。

V3 使用真实 TabView、NavigationStack、Menu、sheet、Picker、TextEditor、SF Symbols 和 Liquid Glass，要求 iOS 26+；正式 App 的 iOS 16 最低版本保持原样。本轮未迁移正式界面，也不提交或推送代码。
