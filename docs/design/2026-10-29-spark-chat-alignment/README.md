# Spark、Chat 与一级页头调整 · 2026-10-29

## 已确认与待讨论

用户已选择 A：Explore / Home / Chat 统一为居中小标题，给内容更多空间。Home 内容顺序、My Notes / Collections、排序、逐卡操作、New note 不变；只调整导航栏。

Spark Grid 的方案 A 仍为可点击提案，尚未替换原生结果页。卡片正文与图片进入全文；独立圆圈用于单选下一轮来源；不默认选择第一张。阅读全文与收藏均不改变来源选择。Continue 的来源必须是所选结果的 card ID，父节点仍为当前 Spark activity。用户正在确认阅读与选择的区分。

## 本轮原生变更

- 修复 Chat 根 Tab 导航栏被外层隐藏的问题，名称恢复 Chat。
- 三页使用单行 inline headline；Toolbar 单图标使用20pt图标、44pt点击区、plain样式与明确contentShape，沿用系统玻璃背景。
- Chat 输入区附件／发送按钮取消重复的样式内边距，使用44pt圆形原生glassEffect；支持实体材质回退，保留禁用语义，多行底部对齐。
- Chat 附件预览明确传入语义字号，辅助字号可换行；保留现有发送、引用、选材与清空行为。
- 移除 Explore滑卡、Explore搜索及Spark结果页的浏览位置数字；不改变分页、请求或现有服务错误处理。

## 设计材料

- [一级页头比较](index.html)：A 已确认，B 保留比较；HTML示意不是实际SwiftUI截图。
- [Spark Grid 交互提案](spark.html)：本地样例，可读全文、明确单选、继续、回看与失败恢复；没有真实AI／收藏请求。
- 原来的V3—V9及原生审查页保留，不覆盖。

验证结果在完成后写入 VALIDATION.md。本轮不修改BlockNote正文引擎、后端合同或依赖版本；不提交、推送或切换分支。
