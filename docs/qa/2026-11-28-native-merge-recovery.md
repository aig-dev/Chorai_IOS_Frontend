# Native Merge 普通账号恢复验收

2026-11-28。基线 Native `76e8995375be8c96d8aee7508ea9b3b336ebc2a1`，本批只修改 `ArcNoteUITests.swift` 的选择和导航夹具；App／CoreFlow／编辑器产品代码未改。后端为专用本机隔离 prod API，使用本任务创建、拥有三篇私有纯文字 NOTE 的普通账号。

## 夹具修正

- 在来源列表内滚动，要求卡片完整落在可见区域且可点击，再执行真实元素 tap；保留选中值断言。首轮原坐标点击没有选中第二来源，不把全零的几何附件当作越界证明。
- 重启后使用已有 `openOrdinaryLibrary()` 进入 Library。应用可恢复到 Home，夹具不能强制等待 Flow。最终 Explore 冒烟显式选择对应 tab。
- 保留正文、标签、任务身份、草稿重开、提交回执、Library 输出和任务浮条移除断言；没有改写持久化任务或降低断言。

## 限定结果

选择器为 `testMergeRelaunchResumesCommitsAndReturnsCanonicalCardToLibrary`。同一任务跨保留的失败尝试连续完成：第二次运行实际选择三来源、创建唯一 job、生成并保存两个编辑版本，随后因错误的重启导航假设失败；最终运行从原 UserDefaults scope／job 恢复，再保存一次并提交。最终为 1 pass／0 fail／0 skip，外层耗时 95.04 秒；这是既有 job 分支通过，不是最终源码单次完整 create-to-commit 通过。

服务端记录一项 create、三项 save（revision 2／3／4）、一项 commit 和唯一 NOTE／版本／Action／Activity。完整段落、正文、标签、评分与十字符派生标题逐项比对，九条来源与归属关系准确。两张最终截图核对了 Library 的 canonical card 和提交后 Explore。最终测试文件 SHA-256 为 `4fdee437a9a0668ffe5475f6ac5df5763d9d53507f4defb5d017755264b9c5c2`；正常签名模拟器 build-for-testing、314 件产物和签名／资源检查通过。Local `ArcNote` 与 `ArcNote Production` 两个 scheme 另行编译通过，均未启动应用或连接生产 API，日志未发现首方并发警告。没有把本次窄测试和构建当作重新执行完整 Swift 6 三配置门禁或分发签名归档。

首轮默认头像 GET 曾被测试代理拒绝；后续只开放该确切只读路径。两次 UI 失败、原持久状态、完整网络回执、截图和三次审计脚本校准失败均保留。审计校准分别处理当前产品默认 props／styles／标题与空白行为、`committable` 状态及 wire/native hash 表达，最终仍严格比较完整投影。

正式策略选择 `visual_echo` 并省略配图，输出只有文字，关联扣费账本为零；本记录不证明图片生成成功、付费结算、多图 HTTPS 媒体或正常 Library 选择入口（创建从已知 Detail 的真实 Merge 菜单开始）。清理发现后端审阅日志擦除 CHECK 阻断；修复、原请求物理清理和新旧 schema 回退边界见 [后端验收](../../../Chorai_Go/docs/evidence/2026-11-28-native-merge-erasure.md)。整轮上线资格仍由后端首发清单管理。
