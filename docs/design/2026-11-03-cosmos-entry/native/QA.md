# 原生入口验收记录 · 2026-11-03

本轮由用户确认从 Cosmos 参考浏览器原型继续落到真实 iOS 工程。截图与下面的检查均来自原生 App，旧原型和旧设计保持独立。

## 环境

- 工程：`/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend`，既有 `main` 工作区；保留本轮前已有的未提交改动，没有切分支、提交或推送。
- Xcode 27.2（27B52）；逐命令指定 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
- iPhone 17 Pro / iOS 26.5 Simulator，设备 `92DE3535-B261-49B5-844F-9BD9B8C241B4`，通过 Device Hub 实际操作。
- 所有构建缓存和测试运行目录位于 `/tmp`。原有9个外部依赖版本与 revision 不变。

## 自动检查

| 项目 | 结果 | 证据 |
|---|---|---|
| CoreFlow 单元及源码契约 | 880通过，0失败 | `/tmp/chorai-cosmos-core-final.log` |
| 原生入口 UI 回归 | 7通过，0失败 | `/tmp/chorai-cosmos-native-final-suite.log` |
| ArcNote Local Simulator | BUILD SUCCEEDED | `/tmp/chorai-cosmos-local-final-verified.log` |
| ArcNote Production Simulator | BUILD SUCCEEDED | `/tmp/chorai-cosmos-production-final-verified.log` |
| Diff 格式检查 | 通过 | `git diff --check` |

最终 UI result bundle：`/tmp/chorai-cosmos-native-build/Logs/Test/Test-ArcNoteUITests-2026.11.03_21-58-55-+0800.xcresult`。

7项 UI 用例覆盖：修改邮箱清除旧验证码；发送失败重试、密码不一致恢复、注册后跳过兴趣；验证码拒绝后返回修改；再次进入直接登录并可返回欢迎页；登录页的注册入口仍经过访问码；登录校验和键盘上方提交；兴趣最多9项及保存。测试使用软件键盘，并检查密码显示／隐藏后的焦点与输入内容。

## 本轮实际修复的交互问题

- 密码显示／隐藏使用不同的原生焦点目标，切换后输入仍进入正确字段。
- 注册各步骤观察同一个表单模型，避免分别维护表单副本。
- 原生输入在键盘收起时可能回写相同内容；现在只在内容真正改变时清除该步骤错误。通过失败日志定位后修复，原来失败的完整注册用例已通过。
- 介绍页的小笔记调整字号，避免把 unfinished 拆成残缺的单词。
- 清理验证码发送响应中的敏感内容日志；临时诊断追踪已全部移除。

## Device Hub 手动检查

- 浅色欢迎页、介绍前进和返回、原生登录页。
- 深色模式下手动走通访问码、邮箱、验证码、用户名、密码、确认密码、兴趣选择及离线完成。
- User Agreement 原生 sheet 可打开、关闭；离线模式显示明确占位，不加载外部法律页面。
- 开启 Reduce Motion 和 Reduce Transparency 后，介绍切换、注册输入和完成流程仍可用。
- 检查结束恢复 Light、Reduce Motion off、Reduce Transparency off；欢迎页已重新打开供用户体验。声音设置未改变。
- 本轮没有进行全面 VoiceOver 遍历、全部 Dynamic Type 档位和物理 iPhone 性能测量，不作这些已验收的声明。

## 原生截图

- [Device Hub 欢迎页](captures/device-hub-welcome-light.png)
- [介绍第二页](captures/auth-returning-welcome-back.png)
- [浅色登录与软件键盘](captures/auth-signin-keyboard.png)
- [深色登录](captures/device-hub-signin-dark.png)
- [密码不一致错误](captures/auth-signup-password-mismatch.png)
- [验证码恢复](captures/auth-signup-verification-recovery.png)
- [浅色兴趣选择](captures/auth-interests-before-skip.png)
- [9项兴趣选中](captures/auth-interests-nine-selected.png)
- [深色兴趣选择](captures/device-hub-interests-dark.png)
- [减少动态及透明度检查](captures/device-hub-reduced-effects.png)

截图为原始捕获。安全输入框在系统截图中可能被隐去，密码内容通过 UI 测试检查而不是截图判断。

## 保留与边界

基线567文件中，554保持原哈希、13个预期认证／测试文件变化、0缺失；234个既有素材文件与61个旧原型文件保持原哈希。项目文件的新增成员仅为本轮入口组件、离线入口及UI测试。完整记录见 [preservation-check.json](preservation-check.json)。

默认正式入口仍调用既有认证服务，保留 Product Access 门槛、Apple／Google 和邮箱注册合同。`--ui-test-auth-entry` 仅在 DEBUG 中启用，使用内存服务，绕开真实会话持久化和全局网络入口。测试不会发送邮件、创建真实账户、调用真实 Google／Apple 授权、写入 Keychain 或访问生产 API。Production 只构建，从未启动。

真实邮件送达、第三方登录、后台持久化及真实账户进入 Explore 尚未在本轮端到端验收。兴趣的上限9项和验证码60秒重发间隔沿用现有规则，不新增字段。启动和转场按用户录像中的可观察行为实现，时长是近似参考；未新增配乐或触觉效果，也未宣称与 Cosmos 内部动画参数逐帧一致。
