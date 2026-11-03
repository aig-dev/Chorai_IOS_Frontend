# Chorai 原生设计原型 · 版本入口

各版独立保留。V5 根据用户选定的温白墨绿＋少量学院金推进；所有旧配色探索及离线包仍保留。设计原型不是正式应用迁移完成。

| 版本 | 内容 | 查看 / 打开 |
| --- | --- | --- |
| V1 | 初版 Explore、Home、编辑器浅／深原生设计 | [V1 原画册](revisions/v1-original/gallery/index.html) · [V1 归档](Chorai-iOS-design-v1.zip) |
| V2 | Explore 滑卡、回看、继续探索与撤销；常驻 Skip／Collect 双按钮 | [V2 原画册](gallery/index.html) · [V2 滑卡页](gallery/swipe.html) · [原生启动器](Open-Prototype.command) · [V2 设计归档](Chorai-iOS-design-v2.zip) · [V2 完整原型归档](Chorai-iOS-prototype-v2-preserved.zip) |
| V3 | 更大的 Explore 卡片，移除大号双按钮，四套浅／深配色比较 | [V3 配色画册](revisions/v3-color-study/gallery/color.html) · [V3 原生启动器](revisions/v3-color-study/Open-Prototype.command) · [V3 说明](revisions/v3-color-study/REVIEW.md) |
| V4 | 八种内容卡片，原版加四套候选配色，原版与绿金同内容比较 | [V4 丰富卡片画册](revisions/v4-rich-cards/gallery/index.html) · [V4 原生启动器](revisions/v4-rich-cards/Open-Prototype.command) · [V4 说明](revisions/v4-rich-cards/README.md) |
| V5 | 温白墨绿＋少量学院金；手机端 Explore 滑卡 / 双列 Grid，补充原有动作 | [V5 画册](revisions/v5-explore-grid/gallery/index.html) · [V5 原生启动器](revisions/v5-explore-grid/Open-Prototype.command) · [V5 说明](revisions/v5-explore-grid/README.md) · [设计覆盖计划](revisions/v5-explore-grid/DESIGN-COVERAGE.md) |

V2 安装为 `Chorai Prototype`（`com.chorai.nativeprototype`）；V3 安装为 `Chorai Colors V3`（`com.chorai.nativeprototype.v3`），可同时保留在 Simulator 中。它们都使用各自运行中的临时样本，不连接真实账户、AI 或同步服务。

V4 单独安装为 `Chorai Cards V4`（`com.chorai.nativeprototype.v4`），加入图文、长文、摘句、清单、代码、文献、对照与短想法，使用相同的滑卡、回看、收藏和阅读流程。五套配色包含原版温白墨绿，方便排除内容差异后比较颜色。

浏览器画册展示原生截图；完整手势、键盘和动态玻璃在对应 Simulator App 中体验。


V5 单独安装为 `Chorai Explore V5`（`com.chorai.nativeprototype.v5`）。两种浏览模式共享收藏，分别保留位置；原生交互与画册截图分开验证。


## V6 · 功能旅程 · 2026-10-21

独立保存在 `revisions/v6-feature-journeys/`，不覆盖 V1–V5。

- Spark / Merge 的原生可点击离线旅程，浅深色与关键分支。
- 浏览器功能导览：6 条旅程，35 状态，说明当前行为、新视觉与未完成范围。
- 独立单文件离线分享版及真实原生截图，验证记录见该版 `VALIDATION.md`。


## V7 · Card levels & Chora · 2026-10-21

- Preserved independent revision: `revisions/v7-card-levels/`.
- Added six card-tier specimens, native guide, Explore/Grid/Merge placements, neutral unknown-rating proposal, and a separate Chora growth fixture.
- App theme remains forest/cream with modest gold; only V Exceptional uses the approved green-and-gold character. Uses original transparent atlas crops, static small characters, and native components.
- Gallery starts at `revisions/v7-card-levels/gallery/?flow=levels`; includes all earlier V6 chapters. Offline export: `Chorai-Card-Levels-V7-offline.html`.
- V1–V6 remain; verification details and exact limits in V7 `VALIDATION.md`.


## V8 · Grid 笔触与详情 Chora · 2026-10-26

- 独立保存在 `revisions/v8-grid-brush/`，V1–V7 原稿保留。
- 按本次用户选择：Grid 默认隐藏小 Chora，并移除角色留白；右上角各级笔触、细边框、Roman／名称保留。详情显示原卡对应的 Chora，返回仍回到同一 Grid 卡片。
- 复用已批准的原始透明笔触与角色图集，六档保留各自颜色，仅 V · Exceptional 使用绿金角色。Flow／Merge 大尺寸角色展示策略保持。
- [V8 Grid 导览](revisions/v8-grid-brush/gallery/index.html?flow=levels&state=grid&theme=light) · [V8 离线文件](revisions/v8-grid-brush/Chorai-Grid-Brush-V8-offline.html) · [原生启动器](revisions/v8-grid-brush/Open-Prototype.command)。独立 bundle：`com.chorai.nativeprototype.v8`。
- 新增 30 张原生截图；V7 的说明／成长截图与 V6 功能章节按原版本保留。离线文件约 19.79 MiB，内嵌 87 张图片；导览为 8 条旅程、53 状态、149 条跳转，图片引用检查无缺失。
- 原型构建、54 项模型检查及四项原生 UI 检查通过；离线文件完成静态自包含验证，未实测 `file:` 运行。本地 HTTP 导览已实测，详细范围见 V8 `VALIDATION.md`。本版仍为独立预览，不表示正式 App／Web 迁移或后台验证完成。
