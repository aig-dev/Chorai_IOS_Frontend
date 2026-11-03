# Chorai Review V9 · 原生原型

本目录的运行入口是 `ReviewV9Root`。当前 bundle 为 `com.chorai.nativeprototype.v9`，构建输出 `/tmp/chorai-native-prototype-v9/ChoraiPrototype.app`。

- 运行 `bash build.sh` 构建独立原型，并执行 54 项既有模型检查。
- `--screen explore` / `reader`：V9 固定摘要卡与全页阅读提案。
- `--screen home` / `editor`：保留的 V6–V8 Home 与编辑器；没有重新设计 Home。
- `--appearance system` / `light` / `dark`：跟随系统或指定外观。
- Home 与 Explore 使用同一个内存样本状态。重启会重置，所有操作均不连接账户或后端。
- `UITests/ReviewV9Tests.swift` 绑定 V9。目录中保留的其他历史测试可能绑定早期 bundle，不计入 V9 结果。

完整设计范围、截图、历史版本归档与验证记录分别见 [主说明](../README.md) 和 [验证记录](../VALIDATION.md)。本目录早先误保留的 V8 启动说明已随修正前 V9 一起归档，真正的 V8 目录未改动。
