# Native sidebar and Chat validation · 2026-10-29

本报告记录本轮真实源码、编译与测试边界。设计图与本地 UI 验证不代表线上服务验证或用户最终视觉签字。

## Implementation boundary

- `SideMenuView` 的导航状态继续位于当前 tab 的 `NavigationStack`。视觉层使用绑定当前 scene、不能成为 key window 的独立覆盖窗口；不隐藏根页导航栏和底栏，不改其 safe area。
- 侧栏只有一个 0.24 秒 ease-out 动画 owner；Reduce Motion 时不做位移动画。关闭过程中覆盖层继续拦截触摸，移除后恢复原窗口的 accessibility 状态。Settings / Profile 等已有目的地出现时暂时收起视觉层，返回恢复侧栏。
- 装饰性大横幅改为真实头像、用户名、Credits、following / followers 的紧凑标题区；保留所有六个菜单动作、未读提示和个人页入口。透明度降低 / 高对比度使用实色背景。
- 缓存的个人资料与 Credits 在刷新时继续可见；没有资料才显示占位。Follow count 缺字段保持原来的 0 语义。移除 300 ms 的数字显现延迟。
- My Notes / Favorites 在实际关闭完成后消费一次已选动作，不使用固定延迟。原有 scope request 和 lazy tab 路径保留。
- Home / Explore 对照 `qa/source-before.json`：只反转本轮菜单按钮动画 wrapper 与导航栏条件隐藏两项变更，即可恢复原 SHA-256。两页正文、卡片、分段控件、排序和 New note 完整保留。
- Chat 由独立实现者按用户选定的方案 3 + 两只 Chora 落地；TabBarView 仅把 `onExplore` 接入已有 Explore tab。认证界面未修改。

## First-pass evidence and corrections

- 新增 / 更新侧栏 source regressions 先在旧实现观察到 4 cases / 16 expected failures，记录 `/tmp/chorai-1029-sidebar-red.log`。
- 已有 Explore title contract 仍要求 literal `Text("Explore")`，与先前批准的 Search / Explore 条件标题不符；已更新对应断言。
- Keyboard tab-bar contract 改为断言新的 `isTabBarCovered`，继续保留 keyboard 隐藏条件；onboarding 仍使用 `isLibraryCovered`，包含侧栏覆盖状态。
- CoreFlow 完整包曾通过 875 / 875。该阶段在并行编译期间复跑得到 874 / 875：`MergeSessionStoreResumeTests/testInjectedPollDelayJitterReachesSleeper` 报 `Timed out waiting for Merge poll sleep`。保留 `/tmp/chorai-1029-sidebar-coreflow-final.log` 与 `/tmp/chorai-1029-sidebar-coreflow-loaded-timeout.log`。编译空闲后原测试独立复跑 **1 / 1 通过**，记录 `/tmp/chorai-1029-sidebar-merge-retry.log`。未修改 Merge 代码或测试。
- 初次 Local 和 Production Simulator builds 均通过，但真实 UI 测试发现直接向 SwiftUI 根 hosting view 添加 UIKit 子视图会触发运行时警告，并使 Favorites / Settings 不可点击。该实现已替换为 scene-bound non-key overlay window，没有掩盖警告或修改导航语义。
- 第一次 UI run：7 cases，3 passed / 4 failed；完整结果 `/tmp/chorai-1029-sidebar-ui.xcresult` 与 `/tmp/chorai-1029-sidebar-ui.log`。两项侧栏失败是上述 hit testing 问题；两项 Chat 失败是父 accessibility identifier 覆盖子 CTA identifier，实际返回了 0 个会话。Chat 容器已添加 `.accessibilityElement(children: .contain)`；没有增加测试 fixture 分支。

## Final automated verification

- **CoreFlow：875 / 875 通过**，最终 non-key-window + Chat 源码，编译空闲后完整复跑。日志 `/tmp/chorai-1029-sidebar-coreflow-v2.log`。先前 874 / 875 的并行负载超时与其独立重试结果均保留，未覆盖。
- **ArcNote Local Simulator build：通过**，最终命名 scheme 再次编译；日志 `/tmp/chorai-1029-sidebar-local-v2.log`。
- **ArcNote Production Simulator build：通过**；日志 `/tmp/chorai-1029-sidebar-production-v2.log`。仅编译，没有安装、启动或请求 Production。
- **build-for-testing：通过**；日志 `/tmp/chorai-1029-sidebar-uitest-build-v2.log`。
- **七项预定 UI 用例均实际通过，分为 4 + 3 两次执行**。第二轮 class selection 实际只执行了 4 项，不能记成 7 / 7；检查编译后的 runner 已包含全部新 selector，移除 simulator 的测试 runner 缓存后，改用生成的 `.xctestrun` 明确选择另外三项并实际执行。
  - `/tmp/chorai-1029-sidebar-ui-v2.xcresult`：4 / 4，通过 cold Favorites scope、Profile / Credits、Explore / Spark 无计数器、三根页标题和 Chat 控件。日志 `/tmp/chorai-1029-sidebar-ui-v2.log`。
  - `/tmp/chorai-1029-sidebar-ui-newcases.xcresult`：3 / 3，通过 normal Chat Explore CTA、Accessibility XXXL CTA、所有三根页 Sidebar → Settings → Back → close。日志 `/tmp/chorai-1029-sidebar-ui-newcases.log`。
  - 两个最终 xcresult 的 `runtimeWarnings` 均为空；此前 UIKit hosting-view 层级警告没有再出现。
- 新侧栏用例在 Explore / Home / Chat 分别断言覆盖层 minY、maxY、width 与 app frame 相同；Settings 可点击且目的地不被覆盖；Back 恢复同一侧栏；close 至少 44×44；关闭后侧栏控件不再留在 accessibility tree，导航栏 / 底栏 frame 与打开前一致。
- 导出的测试截图：`/tmp/chorai-1029-sidebar-ui-newcases-attachments/manifest.json`，包含三根页各一张 open / closed 与两个 Chat 截图。另有 `/tmp/chorai-1029-sidebar-ui-v2-attachments/manifest.json`。已只读查看 Explore open 截图，确认紧凑头像 / Credits / follows、全部菜单、顶部与底部覆盖范围存在。
- `git diff --check` 通过。再次对照 source snapshot，变化只落在 Sidebar、TabBar、三根页和五个相关测试文件；认证源码、API 配置及共享网络模型未变化。Home / Explore 精确逆变更 hash 检查仍通过。

## Follow-up: motion, dark appearance and combined design

用户解锁后，已通过 Device Hub 在浅色下操作展开、关闭、遮罩关闭与关闭过程中的快速重复点击。保存 `qa/sidebar-manual-light.mov`。AVFoundation 导出开、关各 8 张连续原始视频帧；根任务查看了 `qa/motion-audit/open-contact.png` 与 `close-contact.png`。在暴露的卡片右缘 x=990…1110 区间，16 帧的顶边都在 y=540，没有观察到该抽样期间的纵向跳动。录屏是可变帧率，这不是原生 FPS 性能测量，也不代表全部时刻的逐帧覆盖。

切换深色后，Device Hub 的 CUA 坐标操作出现 `noWindowsAvailable` 工具连接错误，重连与重启窗口后仍间歇出现，因此没有把后续深色检查称为手动点击验收。通过已有原生 UI 测试完成同一模拟器的深色 3 项检查，实际 **3/3 通过**，并逐张检查真实截图。结果 `/tmp/chorai-1029-sidebar-ui-dark.xcresult`、日志同名 `.log`，截图清单 `qa/dark-native-check/manifest.json`。

深色截图发现 Chat 对话气泡过暗，新增 `chat-chora-pair-dark.png`，在 asset catalog 的 luminosity dark 中启用。原浅色图保持不变，两图均为 1522×1033、带 alpha；没有 Swift / 测试 / API / 认证代码改动。最终深色气泡与身体边缘可读性已用实际 App 截图复核，`qa/chat-native-dark.png`。

- 资源修正后 Local / Production 构建均通过：`/tmp/chorai-1029-chat-dark-asset-local.log`、`/tmp/chorai-1029-chat-dark-asset-production.log`。Production 仍仅编译。
- `build-for-testing` 通过：`/tmp/chorai-1029-chat-dark-asset-uitest-build.log`。
- 资源修正后正常 Chat CTA 在 Dark 下实际 **1/1 通过**：`/tmp/chorai-1029-chat-dark-final.xcresult`，日志同名 `.log`；runtimeWarnings 为空。最终截图清单 `qa/dark-native-final/manifest.json`。
- 模拟器已恢复 Light，Local `--dev-preview` 已重新启动。Reduce Motion / Reduce Transparency 保持原状态；其分支做了源码复核，未扩大声称运行时全覆盖。

用户另选方案 1＋2 融合；本次新增 `auth-combined-1-2.png`，旧六图保留。新欢迎与登录图仍为审稿设计，没有修改原生认证页面。所有来源映射见 `qa/design-image-order.json`。

## Reproduction configuration

- Native repo: `/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend`
- Toolchain: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- Simulator: `92DE3535-B261-49B5-844F-9BD9B8C241B4` (the existing iPhone 17 Pro).
- External CoreFlow scratch: `/Users/didi/Library/Caches/ChoraiReview/coreflow`.
- External Local DerivedData: `/Users/didi/Library/Caches/ChoraiReview/app-derived`.
- External Production DerivedData: `/Users/didi/Library/Caches/ChoraiReview/production-derived`.
- Existing pinned package checkout cache: `/Users/didi/Library/Developer/Xcode/DerivedData/ArcNote-aybvwriajptjnqfsotseyzwxdivu/SourcePackages`.
- Local app: `/Users/didi/Library/Caches/ChoraiReview/app-derived/Build/Products/Debug-iphonesimulator/ArcNote.app`.
- 没有分支、提交、推送、后端变更或生产服务请求；没有在源码目录新增 `.build` / package cache。
