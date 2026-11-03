# Chorai · 欢迎与登录、Chat、侧栏 · 第三轮

日期：2026-10-29。此目录是独立审稿资料；`index.html` 是图片查看页，不是认证 UI 实现。

## 展示顺序与文件

| 内容 | 文件 | 证据类型 |
| --- | --- | --- |
| Chat 已选方案 3 的 Chora 调整 | `chat-chora.png` | 视觉设计图，非原生截图 |
| 欢迎页与 Sign In 方案 1 | `auth-1.png` | 配套视觉设计图，非原生截图 |
| 欢迎页与 Sign In 方案 2 | `auth-2.png` | 配套视觉设计图，非原生截图 |
| 欢迎页与 Sign In 方案 3 | `auth-3.png` | 配套视觉设计图，非原生截图 |
| 欢迎页与 Sign In 方案 4 | `auth-4.png` | 新增配套视觉设计图，非原生截图 |
| 欢迎页与 Sign In 方案 5 | `auth-5.png` | 新增配套视觉设计图，非原生截图 |
| 欢迎页与 Sign In 方案 6 | `auth-6.png` | 新增配套视觉设计图，非原生截图 |
| 侧栏修改前 / 后 | `qa/sidebar-before.png`、`qa/sidebar-after.png` | 实际原生 App 截图 |

方案 1–6 只按展示顺序编号，不附加概念名称。Chat 单独展示，延续上一轮已选方向。图片就绪后由根任务放入对应文件；查看页不生成、修改或替换图片。桌面每行并排比较三组认证图，小屏改为纵向展示；图片保持完整比例，点击打开原图。

## 方案 1 + 2 融合稿

用户选择将 1 与 2 结合。本次新增 `auth-combined-1-2.png`，原六套不变。主结构与材质沿用 1：温白纸感、衬线标题、克制金线与分组表单；加入 2 的 Almond Chora。欢迎页把 Chora 放在标题与按钮之间的留白中，登录页缩小，避免表单失焦。

本次只交付融合后的视觉稿。Email / Password、Google / Apple、Private Beta 访问码与注册流程均不变；未编辑认证生产源码。用户确认细节后再据此落地。

## 现有认证范围

“Landing”在本轮指现有 App 内欢迎页，不是营销网站。

- 欢迎页保留 `Login` 和 `Join Private Beta`。来源：`ArcNote/ContentView.swift:105`。
- Sign In 保留 Email、Password、SIGN IN，以及 Google、Apple；不新增登录方式。来源：`ArcNote/SignInView.swift:36`、`ArcNote/ContentView.swift:390`。
- Join Private Beta 先预检 Product Access Code，成功后进入现有 Sign Up。邀请访问码与注册邮件验证码保持不同语义。来源：`ArcNote/AccessGateView.swift:138`。
- 登录后继续遵循已有访问权限和兴趣选择路径；视觉方案不改变账户、权限、服务合同。来源：`ArcNote/ContentView.swift:79`。

欢迎页依据当前源代码，不声称已有本轮欢迎页原生截图。现有 Sign In 原生参考为 `../2026-10-27-full-native-remediation/review/images/sign-in-light-bfa7625616ae.png` 与 `sign-in-dark-58bf94ef6dba.png`，均为 1206×2622 px。

## Chat 与侧栏的边界

Chat 图像用于确认已选方案 3 的构图、留白及 Chora 呈现。它展示成功加载且没有会话的状态；不把加载或错误伪装为空态，不新增联系人、在线状态或 AI 对话功能。设计图本身不证明原生页面已完成。

侧栏已完成实现与自动验证：Local / Production Simulator 构建通过，CoreFlow 875/875，原生交互 7/7（4 + 3 两批）通过。`qa/sidebar-after.png` 与 Chat 两张原生截图均直接导出自成功测试结果，来源见 `qa/native-test-capture-manifest.json`。解锁后已完成浅色开合操作和录像抽样检查；深色另跑 3 项原生测试并查看实际截图。Chat 增加深色资源修正后又实际执行 1 项 CTA 检查通过。工具连接中断部分及验证边界见下方记录；录屏不用于推断设备帧率。详细结果见 [VALIDATION.md](VALIDATION.md)。

本轮查看页只新增 `index.html` 与本说明。根任务分别负责图像落盘、侧栏生产实现和最终验证；查看页没有登录、网络服务或账户写入。

## 历史与预览

- [上一轮方案](../2026-10-29-note-actions-v2/index.html) 及其原型保持原样。
- 现有本地预览入口：`http://127.0.0.1:8768/2026-10-29-entry-chat-sidebar/`。
- 审稿图、原生截图和验证结果分别标注；设计选择不自动等同于视觉验收或生产交付。

## 2026-10-30 · 灵动修订

用户反馈融合稿“没有灵动的设计感”。新增 `auth-combined-1-2-v2-curious-page.png`，页面入口 `#auth-lively`。旧六套与上一版融合图片保留原始字节。

修订把 Chora、纸页与衬线文字组合成一个有遮挡、探头和斜向节奏的主视觉；登录页延续探头姿态，仍只使用现有 Email / Password、Google、Apple。欢迎页的品牌文案 “A little room for ideas to grow.” 是本轮文案提案。

图底部是静态动效分镜：约 450ms 探出并停稳，Login 后约 320ms 缩小移位。它不是已实现或实测的动画；Reduce Motion 规划为淡入。仅用于评审，未修改原生产品或认证源码。
