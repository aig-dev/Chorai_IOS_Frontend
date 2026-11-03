# V8 素材来源与复用范围

本次没有重新生成角色或绘制替代笔触。素材来自已经批准的 Web 卡片系统：

`/Users/didi/Documents/ChatGPT/Jaime@Chorai 2/src/asset/chora-card-levels/`

| V8 原型素材 | 用途 | 与源文件核对 |
| --- | --- | --- |
| `prototype/Assets/rim-brush.png` | 右上角笔触，RGBA 1254 × 1254 | 字节完全一致 |
| `prototype/Assets/perches.png` | I–IV、VI 静态 Chora 的透明图集 | 字节完全一致 |
| `prototype/Assets/exceptional-green-gold.png` | 仅 V · Exceptional 绿金形象 | 字节完全一致 |

笔触依据 [Web 已批准的设计](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/docs/design/2026-10-19-chora-card-system/README.md:13>)与 [共享样式](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/src/styles/chora-card-level.css:28>)。Web 将原图缩放为 231 × 231，在 190 × 98 的区域内偏移 −18／−74，整体贴在卡片右上角 −2／−2，透明度为 0.72。原生复用透明通道作为 mask，再填入各级颜色；窄卡片可以等比缩放裁切区域，避免溢出相邻列。

六级共享笔触形状，颜色分别为 `#9BA7AE`、`#57A781`、`#5294D9`、`#A881D4`、`#B39A55`、`#D66C61`。角色裁切坐标沿用 [ChoraCardLevel.tsx](</Users/didi/Documents/ChatGPT/Jaime@Chorai 2/src/components/ChoraCardLevel.tsx>)，不重着色、不增加动画。Grid 隐藏角色时，笔触仍保留。

原型中的其余正文与花园图片沿用既有离线样例。浏览器导览明确沿用 V7 的说明／成长截图，以及 V6 的既有功能章节；这些不是 V8 新拍摄结果。新截图与验证范围由主线程交付记录补充。
