# 本轮验证 · 2026-10-29

本轮验证限定为本地原生页面与离线交互，不表示真实登录、消息送达、AI生成或服务器保存。

## 当前结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 相关 CoreFlow 合同 | 36 / 36 通过；覆盖导航、Home原动作、搜索、键盘和Spark入口 | `/tmp/chorai-1029-contracts-final.log` |
| 最终 UI 测试构建 | 成功 | `/tmp/chorai-1029-build-header.log` |
| 浅色 UI | 5 / 5 通过 | `/tmp/chorai-1029-approved-a-light.xcresult` |
| 深色 UI | 5 / 5 通过 | `/tmp/chorai-1029-approved-a-dark.xcresult` |
| ArcNote Local 构建 | 成功 | `/tmp/chorai-1029-approved-a-local.log` |
| ArcNote Production 构建 | 成功；没有启动Production | `/tmp/chorai-1029-approved-a-production.log` |
| 旧原型保护 | V3—V8 的402个manifest条目一致；原文件未覆盖 | `qa/preservation.json` |
| 依赖版本 | Package.resolved无变更 | `qa/preservation.json` |

设备为 iPhone 17 Pro / iOS 26.5，工具 Xcode 27.1，使用项目范围 DEVELOPER_DIR。仍在main原HEAD，所有改动留在既有本地工作树，未提交、推送或换分支。

## UI实际覆盖

1. 原有 Explore Grid → 阅读 → Home 路由、返回与页面内容。
2. 普通与辅助大字号下，聊天附件文字确实放大换行；返回及输入控件点击框至少44pt。
3. 多行输入时附件／发送底部对齐并保持在键盘上方；空输入禁用、输入启用、本地样本发送完成后再禁用。此成功为fixture内存回执。
4. Explore普通／搜索和Spark结果页不显示浏览位置数字，原浏览入口仍可用。
5. 三个真实Tab根入口均可切换，Chat标题、菜单、搜索实际可见；菜单44pt区域边缘点击可打开侧栏，无额外Back。

早期检查发现裸toolbar label的AX边界小于44pt，随后用44pt label、plain样式及contentShape修复。一次测试使用Tab label内部identifier定位不稳定，层级证据显示原生Tab正常存在；改用系统Tab的实际名称后完成最终复测。未降低44pt断言。

`native.html`图片全部来自最终通过的两次UI运行；`qa/evidence-light.json`和`qa/evidence-dark.json`记录每张原始attachment与测试路径。已人工查看浅色Home/Chat、深色聊天普通/辅助字号及审稿页。

## Spark设计提案

`spark.html`尚未接入生产UI。浏览器验证了：初始无选择，阅读返回不选择，显式单选启用继续，下一轮来源正确且清空选择，回看恢复原选择，失败保留结果和选择。深色等级字色调整、阅读层焦点和下层不可交互亦已加入。正文／图片是阅读入口；右上圆圈是下一轮来源选择。原生Grid落地仍待用户确认这一交互。

## 保全边界

相对上一轮最终源码快照，仅变更 ChatDetailView、ChatView、ExploreView、HomeView、TabBarView、SparkContinuationViews 与项目测试注册；新增两份UI测试。Home的正文／标签／分栏／排序／New note部分逐字保持。BlockNote正文引擎、网络/API/认证、CoreFlow状态机与依赖均无本轮改动。
