# Chorai iOS · V7 卡片等级

本轮补齐此前视觉旅程中遗漏的卡片六级体系，并把它与 Chora 成长清楚分开。沿用**温白墨绿，加少量学院金**：正文仍是主角，等级通过名称、细节和小型卡边形象表达。

这是独立原型与设计补充，不修改正式应用的等级规则、权限或后台合同。V1–V6 保留；[V6 功能旅程](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/design/2026-10-21-native-visual-reform/revisions/v6-feature-journeys/gallery/index.html)继续可用。

## 查看入口

- [V7 浏览器图谱](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/design/2026-10-21-native-visual-reform/revisions/v7-card-levels/gallery/index.html)：原生截图与流程讲解；浏览器按钮切换画面。
- [V7 原生原型目录](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/design/2026-10-21-native-visual-reform/revisions/v7-card-levels/prototype)：在模拟器体验实际原生控件。等级演示入口为 `--journey levels`；画面参数见下方流程说明。
- [流程与源码依据](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/design/2026-10-21-native-visual-reform/revisions/v7-card-levels/FLOW-MAP.md)：区分原生已有行为、本轮提案和演示边界。
- [离线分享文件](./Chorai-Card-Levels-V7-offline.html)：73 张实拍图片已内嵌，约 16.53 MiB，下载后可用浏览器直接打开。

## 卡片的六个等级

| 等级 | 当前原生 `rate` 阈值 | V7 视觉方向 |
| --- | --- | --- |
| I · Basic | `< 3` | 中性细节，最安静的卡边形象 |
| II · Notable | `3–8` | 绿色细节 |
| III · Valuable | `9–26` | 蓝色细节，形象放上沿 |
| IV · Significant | `27–80` | 紫色细节 |
| V · Exceptional | `81–242` | 墨绿与学院金，仅这一档使用绿金形象 |
| VI · Definitive | `≥ 243` | 朱红细节，与第五档保持可辨认的形态差别 |

阈值与英文名称来自 [原生 CardLevelStyle](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/CardLevelStyle.swift:16)。V7 复用 [Web 已批准的小尺寸卡边形象](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/docs/design/2026-10-19-chora-card-system/README.md:9>)，作为 iOS 迁移预览；不重新采用已撤回的完整站立形态，不加入持续闲置动画。Web 方案已批准，不等于本次 iOS 迁移已经完成。

卡片等级表达内容体系中的层级身份，不表示作者信誉、访问权限或个人排名。仓库 Merge 规范将结果 `rate` 定义为冻结来源数值的累积，编辑正文和标签不能修改它；本轮仅核对规范与客户端使用方式，没有在线验证后台计算，也不把等级宣传为 AI 对正确性或文笔的评分。

## 已有能力与本轮补充

| 范围 | 原生当前状态 | V7 预览 |
| --- | --- | --- |
| Home | 已使用等级材质；本人笔记支持按 rate 升降序排序 | 本章展示共享卡片样例；尚未重新设计 Home 整页 |
| Merge 结果 | 已显示等级名称及材质，rate 不可编辑 | 补齐等级在结果审核中的视觉表达 |
| Explore / Grid | Flow 有 rate 数据，但当前没有统一等级展示；Grid 是本轮新增浏览方案 | 等级标记、卡边形象与一致的查看入口属于迁移提案 |
| 等级说明 | 未找到原生统一 About level 弹层 | 新增说明弹层属于本轮提案，不提供手动升级能力 |
| 未知等级 | 当前负数及 0 映射 Basic；缺失 rate 默认 1 | 预览提议用中性“等级暂不可用”处理未知输入，未改变正式解析逻辑 |
| Chora Growth | 已有 committed stage 与六维数据展示 | 单独展示固定 Thread 样例，不与卡片等级联动 |

## Chora 成长是另一套体系

Chora 的六阶段为 **Initial → Trace → Thread → Weave → Co-Think → Second Voice**；六维为 **Curiosity、Insight、Creativity、Empathy、Judgment、Resonance**，各维有效范围为 0–12。

正式页面展示服务器返回的 `committedStage`，不是候选阶段或客户端推算阶段。V7 使用固定 **Thread** 样例；Collect、Merge、切换卡片等级都不会让该样例成长。卡片上的六种形象用于标识卡片等级，不等于 Chora 的六个成长阶段。

## 验证状态

已完成独立原型构建、54 项既有模型检查及 3 项新增原生交互检查；新增 22 张浅深色实拍。浏览器导航与离线内嵌图片已验证。详见 [VALIDATION.md](./VALIDATION.md)。所有演示使用本地样例；没有联系后台、提交评级或修改真实成长数据。
