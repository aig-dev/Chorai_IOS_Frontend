# 原生入口打磨验证 · 2026-11-03—04

本轮原生入口打磨与本地验证已完成。本记录区分构建、自动交互、实际截图和手动观察。常规深色完整路径、键盘、最大辅助字号、欢迎页转场及中途切换 Reduce Motion 均已核对。最新 Local 与 Production 两个配置构建通过；Production 仅构建。此前锁屏阻碍已解除，最终动效证据见下方，不将本地检查等同真实服务验收或用户视觉签收。

## 环境与范围

- 工程：`/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend`。
- Xcode 27.2，build 27B52；使用项目命令的 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
- 本轮运行设备：iPhone 17 Pro / iOS 26.5 Simulator，UDID `92DE3535-B261-49B5-844F-9BD9B8C241B4`。
- 构建产物：`/tmp/chorai-cosmos-native-build`，保留原有锁定依赖，禁用签名。
- 运行检查使用 Local 配置与 `--ui-test-auth-entry` 离线样本。未提交真实 Google / Apple 授权、邮件验证码或账户注册；未启动 Production 配置。
- 保留现有认证方式、访问码约束、注册字段和后端合同。本轮只打磨原生入口的展示、可达性与返回／恢复行为。

## 已核对的结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| ArcNote Local Simulator 构建 | `BUILD SUCCEEDED` | `/tmp/chorai-auth-polish-verified-local.log` |
| ArcNote Production Simulator 构建 | `BUILD SUCCEEDED`，仅构建 | `/tmp/chorai-auth-polish-verified-production.log` |
| CoreFlow 认证相关检查 | 27 项，0 failures | `/tmp/chorai-auth-polish-verified-core.log` |
| AuthEntryFlowUITests 完整流程 | 12 项，0 failures | `/tmp/chorai-auth-polish-final-ui.log` |
| 第四轮字号调整后的受影响流程重跑 | 2 项，0 failures | `/tmp/chorai-auth-polish-accessibility-ui.log` |
| 第五轮修正后 ArcNote Local Debug 构建 | `BUILD SUCCEEDED` | `/tmp/chorai-auth-polish-manual-local.log` |
| 第五轮修正后 ArcNote Production Debug-Production 构建 | `BUILD SUCCEEDED`，仅构建 | `/tmp/chorai-auth-polish-manual-production.log` |
| 第五轮修正后兴趣上限与欢迎返回回归 | 2 项，0 failures | `/tmp/chorai-auth-polish-manual-regression.log` |
| 第六轮文字动效修正后 Local / Production 构建 | 均 `BUILD SUCCEEDED`，Production 仅构建 | `/tmp/chorai-auth-polish-motion-local.log`、`/tmp/chorai-auth-polish-motion-production.log` |
| 第六轮文字局部修正后欢迎返回回归 | 1 项，0 failures | `/tmp/chorai-auth-polish-motion-regression.log` |
| 第六轮最终限定动效范围后 Local / Production 构建 | 均 `BUILD SUCCEEDED`，Production 仅构建 | `/tmp/chorai-auth-polish-scoped-motion-final-local.log`、`/tmp/chorai-auth-polish-scoped-motion-production.log` |
| 第六轮限定动效范围后欢迎返回回归 | 1 项，0 failures | `/tmp/chorai-auth-polish-scoped-motion-regression.log` |
| 最后 Reduce Motion 即时切换修正后的 Local / Production 构建 | 均 `BUILD SUCCEEDED`，Production 仅构建 | `/tmp/chorai-auth-polish-motion-setting-local.log`、`/tmp/chorai-auth-polish-motion-setting-production.log` |

27 项 CoreFlow 检查包括 `AuthenticationErrorsTests` 10 项、`IOSAccessSourceTests` 14 项、`RegistrationDraftTests` 3 项；不是全包重新测试。

完整 12 项流程覆盖邮箱变更后的验证码清空、发送失败后重试、密码不一致、验证码拒绝后恢复、登录校验、注册入口、返回路径与草稿保留、访问码错误清除、用户名最短长度提示、兴趣最多 9 项与跳过、最大辅助字号的深色注册。

第四轮依据截图修正了辅助字号输入、按钮加载占位与协议位置，随后重跑：

- `testEmailSignupRecoversFromSendFailureAndSkipsInterests`
- `testLargeTextDarkSignupKeepsActionsReachable`

这 2 项在第四轮调整后通过；不将先前完整 12 项的通过描述成后续每次调整后重新跑了全部 12 项。大字号检查使用 `UICTContentSizeCategoryAccessibilityXXXL`，断言实际输入高度、主按钮在键盘上方、Reset / Skip 可达且不重叠，并完成离线注册路径。

## 原始运行结果与截图

完整流程结果包：

`/Users/didi/Library/Developer/Xcode/DerivedData/ArcNote-bzxqkbmsvnhjmsesggijjvzcvlsy/Logs/Test/Test-ArcNoteUITests-2026.11.03_23-37-26-+0800.xcresult`

第四轮重跑结果包：

`/tmp/chorai-cosmos-native-build/Logs/Test/Test-ArcNoteUITests-2026.11.03_23-46-14-+0800.xcresult`

第五轮修正后回归结果包：

`/tmp/chorai-cosmos-native-build/Logs/Test/Test-ArcNoteUITests-2026.11.04_00-57-39-+0800.xcresult`

该次运行在 2026-11-04 00:59:13 完成，日志逐项记录 `testSignupInterestSelectionStopsAtNineAndContinues` 和 `testReturningLaunchOpensSignInAndBackReturnsToWelcome` 通过，汇总为 2 项、0 failures。

第六轮文字动效修正后结果包：

`/tmp/chorai-cosmos-native-build/Logs/Test/Test-ArcNoteUITests-2026.11.04_01-08-23-+0800.xcresult`

该次运行在 2026-11-04 01:08:52 完成，欢迎返回流程1项通过。第五轮和第四轮受影响测试的结果均分别保留，不重复计入新增测试数。

本目录的 `result-bundle.txt` 和 `accessibility-result-bundle.txt` 保留同一路径。`captures/` 保存真实原生截图，`xctest-*-manifest.json` 保存导出映射；`captures/accessibility-before/` 留存第四轮修改前的大字号截图。`index.html` 是这些截图的对照页，不是另一个认证实现，也不能代替原生交互验收。

密码输入期间，系统可能在截图中隐藏安全输入内容或键盘；不能据此判定真实输入页面完整布局。自动测试已实际操作安全输入、校验与恢复；2026-11-04 又在 Device Hub 中显示离线样本密码并展开软件键盘，完成登录与确认密码页的人工布局核对。

## 运行过程中的证据修正

最初一次流程测试只执行旧的 7 项。排查发现 Simulator 载入了旧 XCTest runner；更新测试 runner 后，日志已逐项列出并执行完整 12 项。旧 7 项结果未作为完整新套件的证明，也未与 12 项重复计数。

新增行为测试已执行通过，但没有记录修复前的失败运行，不宣称完成了红／绿循环。

## 2026-11-04 手动深色与减弱效果核对

Mac 解锁后，由主代理通过 Device Hub 实际操作。全程为普通字号、深色外观，Reduce Motion 和 Reduce Transparency 均开启；原始窗口截图保留在 `captures/manual/`，右侧设备面板可见所用设置。

- 登录：点击邮箱，输入后使用 Return 切换到密码；显示离线样本密码并切换软件键盘，确认主动作在键盘上方。截图 `signin-dark-keyboard.png`。
- 从 Sign Up 进入访问码页，输入离线访问码 `UI-TEST-BETA`，依次完成邮箱、验证码 `123456`、用户名、密码、确认密码。对应 `signup-email-dark.png`、`signup-code-dark.png`、`signup-username-dark.png`、`signup-password-dark.png`。
- 确认密码页：显示样本密码并展开软件键盘，标题、输入、Create account 与协议文案均完整可读、没有被键盘遮挡。截图 `signup-confirm-dark-keyboard.png`。
- 提交离线注册后进入兴趣页，点击 Skip 到达 `Offline fixture complete`。截图 `interests-dark.png`、`offline-complete-dark.png`。
- `welcome-dark-reduced.png` 保留减弱效果开启时的欢迎页外观。上述检查已解除先前“等待 Mac 解锁”的阻碍，不再将普通深色与安全输入布局列为未做。

这些可见密码与访问码均来自固定离线样本，不是实际账户凭证。未提交真实注册或第三方认证请求。

最终限定动效范围后的回归结果包：

`/tmp/chorai-cosmos-native-build/Logs/Test/Test-ArcNoteUITests-2026.11.04_01-13-20-+0800.xcresult`

01:13:49 完成；`testReturningLaunchOpensSignInAndBackReturnsToWelcome` 1项通过。该次运行在最后一行 Reduce Motion 插画身份修正之前；最后的装饰性身份变化通过两个配置构建及下方原生录屏直接检查，没有声称重跑全部认证测试。

## 最终原生动效核对与交接

- 欢迎页录屏发现的标题／Next 与 Get started 短暂叠字和换色低对比已修正。动画仅作用于插画与分页标记，文字和底色同步更新，按钮按压反馈保留。
- `captures/manual/welcome-motion-scoped-reviewed.mp4` 的密集采样确认正常前进、返回、快速连续点击、文字单一显示及前景／背景换色同步。该段录屏还发现中途打开 Reduce Motion 后，第一次返回的旧插画仍带有位移；因此未在此处提前结束验证。
- 最后仅让插画身份同时跟随页面和 Reduce Motion 偏好，刷新已挂载的过渡类型。`captures/manual/welcome-motion-setting-verified.mp4` 记录该最终版本。按导出采样时间，17.60–17.75 秒的第一次返回、22.20–22.40 秒的继续前进均原地淡入淡出；4.00–4.35 秒的正常前进仍保留垂直转场，标题／按钮无重影或低对比复现。
- 最终录屏和逐帧证据详见 `captures/manual/welcome-motion-review.md`。带历史 `final` 文件名的早期录屏仍明确标为中间版本，旧证据没有覆盖。
- Device Hub 已恢复浅色、普通字号，Reduce Motion、Reduce Transparency、Slow Animations 和 Capture Keyboard 关闭，停留在最新离线欢迎首屏。交接截图为 `captures/manual/handoff-setting-welcome.png`。
- `git diff --check` 通过；7份本轮修改前源文件的哈希均与留档一致。仓库包含此前前端改版的未提交变更，没有将工作树描述为干净，也没有提交或推送。

本轮授权范围内的本地实现和检查完成。自动测试、静态截图和 Simulator 手动操作不证明真实设备触感、动画帧率、真实 OAuth、邮件送达或服务可用性。旧设计、修改前源文件和旧截图继续保留；视觉选择仍由用户评审。

## GitHub pre-submission verification - 2026-11-04

Normal welcome page motion was changed from 0.42 to 0.58 seconds at the user's
request; Reduce Motion remains 0.16 seconds. The fresh Local app was installed and
recorded in Device Hub. Forward, back and rapid double-Next settle correctly; a
bounded frame review found no heading/CTA ghosting or persistent clipping. The
new clip and sampling manifest are documented in `captures/manual/welcome-motion-review.md`.

| Fresh check | Result | Local log |
| --- | --- | --- |
| CoreFlow full package | 880 tests, 0 failures | `/tmp/chorai-github-prepush-coreflow.log` |
| BlockNoteEditor full package | 57 tests, 0 failures | `/tmp/chorai-github-prepush-blocknote.log` |
| ArcNote / Debug | BUILD SUCCEEDED | `/tmp/chorai-github-prepush-local.log` |
| ArcNote Production / Debug-Production | BUILD SUCCEEDED, build only | `/tmp/chorai-github-prepush-production.log` |

Both builds contain the 0.58-second change. The UI suite was not rerun in full
for this submission; its earlier 12-flow result and subsequent targeted reruns
retain their original evidence boundaries. The new manual run used the offline
fixture. Staged application-source whitespace checks pass; historical logs and
snapshots preserve their original formatting rather than being bulk rewritten.
