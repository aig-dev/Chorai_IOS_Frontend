# V9 验证记录 · 2026-10-27

独立原生设计提案；没有替换真实 App 的 Explore / Reader。真实 App 的 Home / 编辑器修正见 [本轮修正](../../../2026-10-26-review-fixes/)。

- Xcode27.1 / iPhone17Pro / iOS26.5。
- 独立原型构建通过，54个既有模型检查通过。
- 4项界面测试最终均通过：浅深色8类固定卡片尺寸与26张截图；最后一张后切换Grid与历史；短拖取消、左右滑、全文结尾、历史回看/恢复未读位置、搜索返回；系统边缘返回。
- 首轮发现2pt笔触越界和拖动取消后误进详情，已修复。后续一项测试在换卡动画结束前读取页码，失败附件已显示正确的2/8，改成等待可见状态后复测通过；没有放宽卡片尺寸断言。
- 前景卡片固定为当前视口计算的尺寸。当前iPhone17Pro样本宽378pt、高615pt；所有8种类型浅深色一致。
- 收藏、点赞和评论点击区域至少44×44pt，最终连续交互测试已核对。
- 浏览器实际检查过点卡/返回、拖动换卡、浅深色切换与右滑状态。页面展示原生截图，浏览器动效仅用于说明；原生触感应在安装的 `Chorai Review V9` 中体验。

`qa/chorai-v9-review-fixed.log` 保存3项通过与1项等待修正前的记录；该项最终通过记录在 `qa/chorai-v9-interaction-final.log`。26张截图的来源、测试名称与设备见qa里的screenshots.json。

## Reader 页首笔触恢复后的补充验证

- 恢复紧凑页首右侧的等级笔触，位于小 Chora 后方；沿用原来的页首高度，没有恢复外层阅读卡片，也没有改动 deck 或导航交互。
- 最终原型重新构建通过；13项原始模型检查、24项滑卡检查、17项富内容检查仍通过，共54项。记录为 `qa/chorai-v9-reader-final-build.log`。
- 新增的 `ReviewV9Tests/testReaderDesignCapturesInBothThemes()` 单独运行通过，1项测试、0失败。它分别启动图文与长文的浅深色阅读首屏，等待原生 Reader 出现后采集4张截图；这项测试用于确认启动与截图，不代替此前4项完整交互测试。
- 当前 `screenshots/v9-reader-{photo,essay}-{light,dark}.png` 均已用本次结果替换。来源为 `/tmp/chorai-v9-reader-captures.xcresult`，原生日志保存在 `qa/chorai-v9-reader-captures.log`；每张图片的测试、结果包与设备映射见 `qa/chorai-v9-reader-captures-screenshots.json`。其余22张 Explore 截图沿用原来的采集来源。
- 补充采集后已人工检查浅色图文首屏，笔触可见，页首仍紧凑。早先4项交互测试及其通过记录完整保留，没有把这次4张截图说成重新执行了全部交互回归。

## 离线交付完整性

审稿页引用的26张原生截图均在 `screenshots/` 内，文件名和 PNG 尺寸检查记录为 `qa/gallery-asset-check.json`。`SHA256SUMS.txt` 对当前 V9 文档、gallery、原型源码和资产、26张原生截图及归档日志 / 来源记录生成 SHA-256 清单。清单不包含自身、可继续更新的 `qa/browser-*.png` 浏览器取证图，以及 `.DS_Store` 系统元数据；不包含 V1–V8 或真实 App 的交付目录。

不涵盖真实账户、联网推荐、服务器收藏、AI生成、持久化或发布。原型中的反馈使用本地样本。V1–V8保留；V3–V8的402个原校验文件一致。

## Home 原型连续性修复 · 2026-10-27

原因是 V9 的根导航把 Home 标签连接到临时系统 List，绕过了仍完整保留的 HomePrototype。此次直接复用 V6–V8 的 Home 组件及同一份会话状态；Home/NoteRow/Editor 实现未重画，仅调整组件可见性。增加 `--screen home/editor` 便于定位同一页面。V9 Explore、Reader 和所有辅助类型与修复前逐字一致。

- 修复前，新增的 Home 回归用例在 Notes 分段缺失处失败，证明会检测本次占位页错误：`qa/chorai-v9-home-before.log`。
- 修复后独立原型重新构建成功，54 项既有模型检查通过：`qa/chorai-v9-home-build.log`。
- 两项定向 UI 测试均通过，0 失败：`qa/chorai-v9-home-restored.log`。第一项覆盖浅深色 Home、分段/筛选/搜索/新建入口、已有笔记编辑返回、新建空笔记返回及编辑页隐藏 Tab；第二项覆盖 Explore 右滑收藏后 Home Collect 可见同一条内容，并可打开阅读。
- 两张新的原生 Home 截图为 `screenshots/v9-home-restored-{light,dark}.png`，已逐张检查，来源见 `qa/home-restoration-screenshots.json`。它们是补充截图，不替换既有 26 张 Explore/Reader 设计图。
- 修复前的完整 V9 保存为 `../archives/v9-before-home-restoration-2026-10-27.zip`（SHA-256 `00885753b557732de0c4aad347c1d0858dfef951aa36167fa36b3a6b481176f3`），其中原清单的 67 个文件全部核验匹配。V1–V8 未编辑。

本次仅修改独立原型和验证资料，没有改动真实 App 或后端；没有重复声称完成全 App 或在线服务验证。
