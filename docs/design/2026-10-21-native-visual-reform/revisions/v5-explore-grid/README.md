# Chorai V5 · 手机端 Explore 双模式

2026-10-21。独立 SwiftUI 设计原型；温白墨绿为主、少量学院金。旧 V1–V4 和离线包完整保留。

## 查看

- 画册：[gallery/index.html](gallery/index.html)，本地预览 http://127.0.0.1:8767/revisions/v5-explore-grid/gallery/
- 点击交互：双击 [Open-Prototype.command](Open-Prototype.command)，在 iPhone Simulator 中打开 `Chorai Explore V5`。
- 默认沿用滑卡；右上角矩形 / 网格图标切换浏览模式。菜单可切换跟随系统、浅色或深色。
- 原生入口参数：`--grid` 直接打开 Grid；`--appearance light` / `dark` 直接预览色彩。
- [后续完整流程设计清单](DESIGN-COVERAGE.md)。

## 本轮内容

- 原版温白 `#FAF9F6`、墨绿 `#153B37`；金 `#846838` 为少量强调。深色保留原版中性背景 `#242329`，强调金 `#D6B378`。
- 原生双列瀑布流，八类内容，窄间距、小圆角；辅助功能大字号单列。图片区域严格限制在列内。
- 滑卡 / Grid 分别保留浏览位置，详情返回原处，收藏使用共同样例状态。滑卡保留 Previous、继续探索和右滑收藏撤销。
- 他人 Explore 菜单恢复 Spark、Report、Link、View；另保留不用手势的收藏和跳过入口。长按 Grid 卡片也可打开动作。
- Home 长按本人及收藏内容可打开 Share；Report 只用于他人内容。Home 菜单仅覆盖本轮有关入口，完整 Root / Merge / Pin 等仍见后续清单。
- Report 原生原因与说明表单，按钮为 Preview report。Link 选取自己的笔记预览关系。Share 可打开 iOS 系统分享面板分享本地虚构示例文字。
- 真正 SwiftUI TabView、NavigationStack、Menu、sheet、Form、ShareLink 与系统 Liquid Glass；网页只呈现真实原生截图。

## 演示边界

所有样例编辑与收藏只在本次 App 会话内有效。举报及关联只是当前 sheet 内的预览，关闭会清除，没有真实提交或保存关系。分享不会生成生产分享卡、发布笔记或改变公开范围。Spark、Merge、评论、聊天没有接通服务；本轮没有访问生产 API。

网格是一项新增浏览模式，正式 App 目前没有这个切换。正式 Flow 原本左右滑都跳过；右滑收藏沿用用户在本轮前几版已选择的原型行为，不应表述成原版既有功能。

原型面向 iOS 26+；正式应用的最低系统要求与源码没有因此改变。本轮使用 Xcode 27.1、iPhone 17 Pro / iOS 26.5。

## 验证

- 独立原生构建成功；54 项纯模型检查通过（13 基础、24 滑卡、17 丰富内容）。
- 10 项不同的原生 UI 检查最终通过，覆盖双模式、位置、收藏、回看/撤销、短拖/纵拖保护、浅深色、菜单归属及离线表单。初轮 9 项中 2 项因测试辅助函数整页滑动来回越过目标失败；改为按目标位置慢速短拖后，这两项复验通过。没有为此改变应用行为。
- 补充实际检查网格底部的完整对照表、短想法，以及系统分享面板。系统面板异步显示，测试即时截图早于呈现；画册中的 system-share-light.png 使用面板显示后的直接模拟器截图，未发送内容。
- 15 张原生截图；画册展示其中 14 张。完整表格、文字、图片范围及所有操作表单做了视觉核对。
- V4 的 SHA256 清单 101 个文件全部匹配；旧版本未覆盖。
- 日志：/tmp/chorai-v5-build.log、/tmp/chorai-v5-ui.log、/tmp/chorai-v5-ui-scroll-fix.log、/tmp/chorai-v5-ui-bottom.log。结果包对应同名 .xcresult（build 除外）。
- 这些结果只证明本地原型表现，未验证真实账号、生成、同步、分享产物或举报服务。
