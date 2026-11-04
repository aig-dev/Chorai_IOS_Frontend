# 真实 App 截图收集

本目录由 `index.html` 展示真实 App 截图；不创建新原型。收集脚本保存在本目录 `collect.py`（工作副本 `/tmp/chorai-remediation-publish-review.py`），批次在 `batches.json` 追加。已于 2026-10-28 发布最终审阅数据：138 张原始截图，覆盖 78 个页面／状态；74 张浅色、64 张深色，其中 60 个状态有浅深色配对。`publish_ready: true`。所选截图全部来自明确通过的测试，已发现的失败画面显式排除；这不代表用户最终视觉验收或真实服务验证。

1. 每批先导出 xcresult attachments，明确填写 manifest、result、log、theme、build；主题不能根据文件名或图片猜测。
2. 执行 `python3 docs/design/2026-10-27-full-native-remediation/review/collect.py --plan /tmp/chorai-review-plan.json` 检查映射、遗漏主题及未识别命名截图。这一步不复制 PNG，不生成 `captures.js`／`evidence.json`。
3. 新命名截图可在 `capture_overrides` 添加 `id`、中文 `label`、`note`，可选 `referencePattern`（相对既有 revisions 目录，支持 `{theme}`）和 `order`。明确排除项放入 `ignore_names`。不能用忽略规则掩盖应提供的页面。
4. 最终批次确认后，将 `publish_ready` 设为 `true`，执行 `python3 docs/design/2026-10-27-full-native-remediation/review/collect.py --publish`。重复执行结果稳定；同页／状态与同主题选择 timestamp 最新的命名截图，菜单、错误、键盘、辅助字号等子状态独立保留。

脚本仅复制原始 PNG 字节，按内容 hash 命名并校验 SHA-256；不裁切、缩放或加工图片，不删除旧图片。原型仅链接既有 V6 Home／Editor／Spark／Merge、V8 Grid 与 V9 Explore／Reader 图片，并记录 reference hash。其余页面明确标为共享原生视觉体系，没有单独确认稿。

仅发布对应日志明确 `passed` 的测试中主动命名的截图。失败、被中断或结果缺失的测试截图均跳过；自动 Screenshot、标为 failure 的附件与 debug 标记也跳过。已知视觉缺陷可用每个批次的 `exclude_names` 排除，必须记录原因；不能因测试通过而掩盖已发现的画面问题。未映射的有效命名截图会阻止发布。测试状态从对应批次日志读取；缺失状态标 `unknown` 并排除。`evidence.json` 保存每张候选和最终选定图片的 result bundle、testIdentifier、testOutcome、原文件、timestamp、设备、批次与 hash，并记录跳过原因。

截图只能证明实际画面与对应离线检查，不能证明真实登录、AI 生成、消息送达或服务器保存。
