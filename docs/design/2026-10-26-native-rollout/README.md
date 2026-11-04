# Chorai iOS 原生前端改版

> 2026-10-26 首轮实现因偏离确认原型而被退回。最新的逐页原稿／实际 App 对照位于 [fidelity/index.html](fidelity/index.html)，验证记录位于 [fidelity/VALIDATION.md](fidelity/VALIDATION.md)。原交付截图与工程结果保留为历史记录，不代表视觉验收。

本轮将已确认的 V1–V8 方向接入原来的 iOS App。代码位于 `ArcNote/` 及本地 Swift Packages，沿用原有服务与内容模型。旧原型保留在 `2026-10-21-native-visual-reform/`，本目录保存实施记录和真实 App 截图。

## 已落地范围

| 范围 | 现在的表现 | 保留的操作关系 |
| --- | --- | --- |
| 全局导航与主题 | 系统浅深色、温白／墨绿／少量学院金；系统 TabView、SF Symbols；iOS 26+ 真实 Liquid Glass | Explore / Home / Chat 入口、返回、键盘避让与原路由 |
| Explore | 大卡左右滑、上一条、撤销收藏、Cards / Grid 切换；同卡收藏状态同步 | 左滑跳过；右滑收藏成功才前进；失败留在当前卡 |
| 等级卡片 | 六档颜色、右上笔触、细边框、罗马数字与等级名；详情显示对应 Chora | 读取真实 rate；Grid 不显示 Chora，也不预留它的空位 |
| Home | 原生 My Notes / Collections 分段切换、清晰阅读面、玻璃新建入口 | 本人笔记／收藏、搜索、排序、可见性、删除、原 Merge 入口 |
| 详情与写作 | 浅深色完整正文；统一编辑外壳、格式栏、图片选择与操作菜单 | 单正文、无额外标题输入、默认私密；原 BlockNote 文档桥、撤销、附件、保存 |
| Spark | 同主题的卡片、来源与继续探索控件，真实收藏成功后同步 | 当前链、子链、重放、返回、收藏后留在内容 |
| Merge | 选材、进度、后台任务入口、结果编辑和确认采用统一主题 | 2–8 个来源、固定来源、冲突与恢复、接受／放弃 |
| 账户与社交 | 登录注册、兴趣、个人资料、关注、屏蔽、通知、评论、分享与举报统一适配 | 原权限、加载／空／错误状态与服务调用 |
| 其他页面 | 设置、偏好、隐私、插件、邀请／积分、Chora 成长、聊天、回收站、Discovery Path | 原功能边界、成长数据和所有权语义 |

## 看真实 App

打开仓库的 `ArcNote.xcodeproj`，选择 **ArcNote** scheme 与 iPhone Simulator。正常运行保持 Local 服务配置。

离线查看本轮外观时，在 Debug Simulator 的启动参数里添加 `--dev-preview`。这是现有的显式本地预览入口：显示 `Local Preview · offline`，示例内容可打开和切换，写入与服务操作会明确提示不可用。该入口不提供真实登录或线上身份，不用于 Production。

当前后端端口没有服务监听，所以真实登录、收藏持久化、Spark 生成、Merge 生成与聊天回复尚未完成服务联调。此次验证区分真实 App 导航、独立离线 fixture 和真实服务；未启动 Production App。

## 截图与验收

请优先打开 [原稿与实际 App 逐页对照](fidelity/index.html)。当前截图位于 `fidelity/screenshots/`。

`screenshots/` 保留的是首轮偏差稿；文件名区分 light / dark，accessibility 是当时的最大辅助字号检查。历史配对：

- `explore-grid-light.png` / `explore-grid-dark.png`
- `reader-light.png` / `reader-dark.png`
- `home-light.png` / `home-dark.png`

最新构建、测试、回归修复和验证边界见 [fidelity/VALIDATION.md](fidelity/VALIDATION.md)；首轮历史结果见 [VALIDATION.md](VALIDATION.md)。实施约定见 [SPEC.md](SPEC.md)，任务与文件分工见 [PLAN.md](PLAN.md)。
