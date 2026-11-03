# Chorai native V8 · Grid brush & detail Chora

独立 SwiftUI 原型，bundle 为 `com.chorai.nativeprototype.v8`，构建输出位于 `/tmp/chorai-native-prototype-v8/ChoraiPrototype.app`。所有内容与等级均为离线样例，不连接账户、AI、评级或成长服务。

## 启动

从本目录运行：

```bash
../Open-Prototype.command --journey levels --step grid --appearance system
```

`--appearance` 可用 `system`、`light`、`dark`；省略时跟随系统。

| `--step` | 展示内容 |
| --- | --- |
| `grid` | Grid 顶部，默认隐藏角色并保留等级笔触 |
| `grid-lower` | Grid 下方卡片，便于比较 V／VI 的笔触 |
| `reader-basic`、`reader-notable`、`reader-valuable`、`reader-significant`、`reader-exceptional`、`reader-definitive` | 从 Grid 打开对应等级的完整阅读样例，保留同一等级与 Chora；关闭回到 Grid |
| `basic`、`notable`、`valuable`、`significant`、`exceptional`、`definitive` | 原有大尺寸 Flow 单卡场景 |
| `guide`、`merge`、`growth`、`unknown` | 六级说明、Merge 位置样例、独立成长样例、未知等级场景 |

顶部菜单中的场景切换用于设计评审，不是用户编辑卡片等级的产品功能。正文与更多菜单的阅读入口携带同一笔记和等级；明确点击收藏才更新本次内存会话。重新启动应用会重置样例。

Grid 不展示小 Chora，也不为它留空。笔触、细边框和 Roman／名称仍保留；详情展示匹配的静态形象。Flow／Merge 大尺寸样例继续原有角色策略。此处 Merge 是只读位置研究，接受保存流程仍在保留的 Merge 旅程中。

## 验证入口

V8 的四项原生 UI 检查使用 `-only-testing:ChoraiPrototypeUITests/CardLevelJourneyTests`，该类绑定 V8。复制保留的其他旧测试类仍指向 V6，不应混作 V8 本轮结果。本轮构建与 54 项既有模型检查通过；四项 `CardLevelJourneyTests` 全通过，0 个失败。测试环境为 Xcode 27.1（27A9275）与 iPhone 17 Pro／iOS 26.5。构建、截图、交互及离线文件的不同验证范围，分别记录在 [VALIDATION.md](../VALIDATION.md)。
