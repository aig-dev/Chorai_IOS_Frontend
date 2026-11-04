# V9 · 固定摘要卡与全页阅读

这是独立的设计审阅版本。V1–V8 和原有 fidelity 对照页保留；新 Explore 与阅读布局尚待视觉确认，不代表已替换正式 App 页面。

## 看设计稿

- 浏览器入口：`gallery/index.html`。可从本地预览服务打开，也可双击文件离线查看。
- 原生布局及交互提案：[DESIGN.md](DESIGN.md)。
- 旧版对照：`../../../2026-10-26-native-rollout/fidelity/`。
- Home / 编辑器实际修正另见：`../../../2026-10-26-review-fixes/`。

审稿页接入 `screenshots/` 中的真实原生截图，提供 Explore / 阅读详情、浅深色、8 种内容卡面及左滑、右滑、历史状态。图文和长文卡面可以点进对应阅读截图，再点左上角返回原卡片。

浏览器的横向拖动只演示方向提示、阈值和下一张样本，不重现连续的原生拖动、系统动画或触觉。其所有状态均留在当前页面内，不调用后端，不收藏、不保存、不发布内容。真实手感需在下方原生原型体验。

## 原生原型

源码位于 `prototype/`，使用 SwiftUI、系统导航、工具栏和系统半屏页。`prototype/build.sh` 构建独立示例 App，产物为 `/tmp/chorai-native-prototype-v9/ChoraiPrototype.app`，bundle identifier 为 `com.chorai.nativeprototype.v9`。

启动参数：

| 参数 | 取值 |
| --- | --- |
| `--screen` | `explore` / `reader` / `home` / `editor` |
| `--appearance` | `light` / `dark` |
| `--card` | `photo` / `essay` / `quote` / `checklist` / `code` / `reference` / `comparison` / `short` |
| `--state` | `rest` / `skip` / `collect` / `history` |

`skip`、`collect` 是供截图审阅的冻结手势状态。`history` 用离线样本展示系统历史面板。所有状态仅保留在原型当前会话中。

Home 直接复用 V6–V8 保留的 `HomePrototype`，包括原来的 Notes / Collect、排版、筛选、搜索、新建与编辑入口，并与 V9 Explore 共用本次会话的收藏状态。Home 没有另做一套设计。初版 V9 错把这个标签接到临时 List，现已恢复原组件；修正前的完整 V9 归档为 `../archives/v9-before-home-restoration-2026-10-27.zip`。Chat 仍是说明占位，本轮没有改版。

## 截图清单

每项各有 `light` / `dark`：

- `v9-explore-{photo,essay,quote,checklist,code,reference,comparison,short}-{light,dark}.png`
- `v9-explore-{skip,collect,history}-{light,dark}.png`
- `v9-reader-{photo,essay}-{light,dark}.png`

以上 Explore / Reader 共 26 张。Home 恢复后的补充截图为 `v9-home-restored-{light,dark}.png`，另有 2 张；浏览器展示完整截图，不生成或伪造原生界面。若截图文件尚未就位，页面显示缺失提示，不以旧图替代。

## 验证边界

浏览器静态检查、原生构建和离线交互验证分别记录；任何一项都不代表生产服务、真实账户、AI、持久化或部署验证。阅读稿只展示首屏，完整滚动与返回体验在原生原型中审阅。
