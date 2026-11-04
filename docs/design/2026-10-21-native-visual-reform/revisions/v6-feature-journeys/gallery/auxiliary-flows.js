/* Source-verified journeys illustrated with existing native prototype captures.
 * Null images intentionally mean “source behavior only; no visual captured”.
 * Every screenshot state is a design prototype, never a production screenshot.
 */
(function () {
  const repo = '/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/';
  const v5 = '../../v5-explore-grid/screenshots/';
  const early = '../screenshots/';
  const source = (label, path) => ({ label, path: repo + path });
  const onlyLight = '截图说明：此状态目前只有 V5 浅色实拍；深色模式也显示同一张浅色图，不代表深色已完成。';
  const oldVisual = '截图说明：此处为 V6 温白墨绿＋学院金原生原型的实际浅深色画面。';

  window.auxiliaryFlows = {
    reading: {
      id: 'reading', title: '阅读与收藏', kicker: '从遇见到读完',
      summary: '先扫读，再展开；收藏和回到浏览都保留清楚的路径。',
      current: '源码已核对：正文 / View 打开阅读；作者、Like、评论、收藏各有入口，收藏只对他人笔记开放。',
      design: 'V5 新主题：大卡与 Grid 共用内容；温白墨绿承载正文，玻璃用于导航，学院金用于少量强调。',
      boundary: '浏览图谱不会执行收藏或社交操作。Grid 和右滑收藏是本轮设计方向；截图是离线原型，不是正式应用截图。',
      source: [source('卡片阅读与动作', 'ArcNote/CoreFlow/FlowViews.swift:348'), source('阅读收藏权限', 'ArcNote/DetailView.swift:552'), source('评论权限', 'ArcNote/CommentPopupView.swift:269')],
      start: 'flow',
      states: {
        flow: {
          title: '01 · 先读一张', imageLight: v5 + 'flow-light.png', imageDark: v5 + 'flow-dark.png',
          explanation: '实际原生 V5 大卡截图。内容占主要空间，底部保留上一条与滑动方向提示。',
          behavior: '原生产 Flow 点击正文进入阅读，两个滑动方向都是离开当前卡片；右滑收藏 / 左滑跳过是用户选择的新原型方向。',
          status: 'design', actions: [{ label: '展开全文', to: 'reader' }, { label: '换成 Grid 浏览', to: 'grid' }], hotspots: []
        },
        grid: {
          title: '02 · 一屏扫读多条', imageLight: v5 + 'grid-light.png', imageDark: v5 + 'grid-dark.png',
          explanation: '实际 V5 Grid 截图。以图文比例和留白组织多种笔记，仍可点入同一阅读页。',
          behavior: '这是新增浏览方式；原版 grid2x2 是菜单排列，不能作为原来已有 Grid 浏览的证据。',
          status: 'design', actions: [{ label: '打开一条笔记', to: 'reader' }, { label: '回到大卡', to: 'flow' }], hotspots: []
        },
        reader: {
          title: '03 · 安静地读完', imageLight: v5 + 'reader-light.png', imageDark: v5 + 'reader-dark.png',
          explanation: '实际 V5 阅读页。作者、完整正文、收藏和更多操作各有稳定位置。',
          behavior: '当前正式阅读页还包含 Like、评论、相关笔记、Follow 和 Chat；这些能力不应被此次阅读排版删掉。',
          status: 'design', actions: [{ label: '看收藏规则', to: 'collection' }, { label: '看作者与评论分支', to: 'social' }, { label: '返回浏览', to: 'flow' }], hotspots: []
        },
        collection: {
          title: '04 · 收藏与保存各有含义', imageLight: null, imageDark: null,
          explanation: '已有行为 · 源码核对。没有新主题收藏成功截图，本节点仅说明规则。',
          behavior: '登录后可收藏 / 取消收藏他人笔记，只有接口成功才更新状态和数量；自己的笔记用 Save 保存正文。Home 收藏列表取消收藏成功后移出该项。原型样例状态不代表服务端收藏。',
          status: 'existing', actions: [{ label: '返回阅读画面', to: 'reader' }, { label: '看作者与评论分支', to: 'social' }], hotspots: []
        },
        social: {
          title: '05 · 认识作者，留下回应', imageLight: null, imageDark: null,
          explanation: '已有行为 · 源码核对。作者页、评论和失败提示的新主题原生画面尚未拍摄。',
          behavior: '头像可进入作者页，Follow 和 Chat 依赖真实服务。评论支持公开 / 私密与回复；回复私密线程锁定为私密。只有发送成功才清空输入，失败保留输入。仅他人评论显示举报 / 拉黑。',
          status: 'existing', actions: [{ label: '回到原文', to: 'reader' }, { label: '继续浏览', to: 'flow' }], hotspots: []
        }
      }
    },

    writing: {
      id: 'writing', title: '写作与保存', kicker: '让正文做主角',
      summary: '从本人笔记进入编辑，明确保存状态，再继续 Spark、Merge 或分享。',
      current: '源码已核对：新笔记为空正文、初始私密；生产编辑器是 BlockNote。Save / Saving / Retry / Back 随安全快照和提交状态切换。',
      design: '保留单一正文、系统键盘、原生导航与安静工具层级。Home / 编辑器沿用单一正文结构，已重新拍摄 V6 浅深色画面。',
      boundary: '展示图来自基础 TextEditor 原型，不代表生产富文本能力已迁移；样例保存只在当前内存会话，不是云端同步。',
      source: [source('新建与初始私密', 'ArcNote/NewNoteView.swift:63'), source('保存状态及失败', 'ArcNote/NewNoteView.swift:635'), source('后续动作先保存', 'ArcNote/NewNoteView.swift:1157')],
      start: 'home',
      states: {
        home: {
          title: '01 · 从 Home 找到自己的笔记', imageLight: early + 'home-light.png', imageDark: early + 'home-dark.png',
          explanation: oldVisual,
          behavior: '正式 Home 区分本人笔记与收藏；本人笔记进入编辑，收藏内容进入阅读。New note 创建自己的私密草稿。',
          status: 'design', actions: [{ label: '查看编辑器', to: 'editor' }, { label: '先看保存与退出规则', to: 'save-contract' }], hotspots: []
        },
        editor: {
          title: '02 · 直接写正文', imageLight: early + 'editor-light.png', imageDark: early + 'editor-dark.png',
          explanation: oldVisual + ' 这是基础文本编辑样例；不是生产 BlockNote 的全部格式工具。',
          behavior: '不另造标题栏，不把第一段自动改为标题。正式编辑器有标签、关系、公开范围、格式与图片；需要按原有能力逐项迁移。',
          status: 'design', actions: [{ label: '看保存 / 失败 / 返回分支', to: 'save-contract' }, { label: '返回 Home 画面', to: 'home' }], hotspots: []
        },
        'save-contract': {
          title: '03 · 保存后，才进入下一步', imageLight: null, imageDark: null,
          explanation: '已有行为 · 源码核对。保存中、保存失败及丢弃确认尚无新主题截图，不补造成功状态。',
          behavior: '主按钮有 Save / Saving / Retry / Back。保存失败停留并可重试；Back 会核对当前快照，无未保存变化才离开。无法取得安全快照时，可继续编辑或确认丢弃关闭。Spark / Merge / Share / Root 先确保正文保存成功，不能绕过失败继续。',
          status: 'existing', actions: [{ label: '继续编辑画面', to: 'editor' }, { label: '查看 Home 画面', to: 'home' }], hotspots: []
        }
      }
    },

    sharing: {
      id: 'sharing', title: '分享', kicker: '交给 iOS 原生面板',
      summary: '确认要分享的内容，再进入系统分享；打开面板与发送成功分开。',
      current: '源码已核对：正式流程先取分享预览与图片产物，检查分享能力并固定产物，再把 UIImage 交给系统。失败可重试，不改变笔记。',
      design: 'V5 以原生 Form 解释样例内容，随后调用真实 iOS 分享面板。沿用原入口的所有权规则，分享不改变公开范围。',
      boundary: '截图分享的是离线样例文本，不是正式图片产物。浏览图谱不会打开系统面板或发送内容；没有给任何接收人发送。',
      source: [source('预览与分享权限', 'Packages/CoreFlow/Sources/CoreFlow/ShareCardStore.swift:24'), source('系统分享图片', 'ArcNote/CoreFlow/ShareCardView.swift:191'), source('菜单所有权条件', 'ArcNote/PopupMenuView.swift:434')],
      start: 'entry',
      states: {
        entry: {
          title: '01 · 从有权限的入口分享', imageLight: early + 'editor-light.png', imageDark: early + 'editor-dark.png',
          explanation: oldVisual + ' 此画面用于说明自己笔记的入口，未展示展开后的生产菜单。',
          behavior: 'Explore 本人菜单有 Share，他人菜单对应位置是 Report；Home 收藏内容的完整菜单也有 Share。编辑器触发分享前先保存。不能据此给所有卡片无差别增加入口。',
          status: 'design', actions: [{ label: '查看样例分享说明', to: 'preview' }], hotspots: []
        },
        preview: {
          title: '02 · 先确认分享内容', imageLight: v5 + 'share-light.png', imageDark: v5 + 'share-light.png',
          explanation: '实际 V5 原生分享说明页；明确是本地虚构样例，不发布笔记、不改变隐私。' + onlyLight,
          behavior: '正式版本会加载后台产物；此离线预览只准备明确标注的样例文本。没有伪造公开链接、图片生成结果或分享成功。',
          status: 'design', actions: [{ label: '查看系统分享面板实拍', to: 'system' }, { label: '关闭，返回笔记', to: 'entry' }], hotspots: []
        },
        system: {
          title: '03 · iOS 系统分享面板', imageLight: v5 + 'system-share-light.png', imageDark: v5 + 'system-share-light.png',
          explanation: '实际 V5 系统分享面板截图；它曾在原生样例中打开。' + onlyLight,
          behavior: '用户仍需自己选择目标并确认发送，也可取消。面板打开不等于已发送，也不证明生产分享产物可用。本图谱仅切换截图，不触发发送。',
          status: 'design', actions: [{ label: '取消，回到分享预览', to: 'preview' }, { label: '结束讲解，回到笔记', to: 'entry' }], hotspots: []
        }
      }
    },

    'link-report': {
      id: 'link-report', title: '连接与举报', kicker: '动作不同，权限也不同',
      summary: '连接归属于自己的笔记；举报使用真实原因且等待真实回执。',
      current: '源码已核对：Link 按发起笔记所有权限制候选与关系方向；Report 支持五类原因、可选说明、提交中、失败重试与真实回执。',
      design: 'V5 用原生选择列表、表单和弹层承接；学院金用于连接选择及结果预览，举报保持克制且明确。',
      boundary: '这些截图只有本地预览；没有创建关系、提交举报或生成编号。关闭会清除预览。菜单与表单的深色画面尚未拍摄。',
      source: [source('Link 候选和方向', 'ArcNote/LinkPopupView.swift:68'), source('举报状态', 'Packages/CoreFlow/Sources/CoreFlow/ContentReportStore.swift:37'), source('举报成功必须有回执', 'ArcNote/CoreFlow/ContentReportView.swift:191')],
      start: 'menu',
      states: {
        menu: {
          title: '01 · 他人笔记的更多操作', imageLight: v5 + 'menu-light.png', imageDark: v5 + 'menu-light.png',
          explanation: '实际 V5 原生菜单。保留 Spark / Report / Link / View，并把样例收藏与跳过放在另一组。' + onlyLight,
          behavior: '本人笔记对应 Share / Edit；不要把自己的 Remove 与举报他人内容混用。菜单中的 Link 表示关联笔记。',
          status: 'design', actions: [{ label: '查看连接选择', to: 'link' }, { label: '查看举报表单', to: 'report' }], hotspots: []
        },
        link: {
          title: '02A · 选择自己的笔记来连接', imageLight: v5 + 'link-light.png', imageDark: v5 + 'link-light.png',
          explanation: '实际 V5 本地连接预览；金色选中状态与连接方向清楚可见。' + onlyLight,
          behavior: '他人内容只能选本人笔记作为关系来源；本人内容可选择本人或已收藏笔记。此画面只显示关系预览，明确未保存，关闭即清除。',
          status: 'design', actions: [{ label: '看正式服务的成功 / 失败条件', to: 'service-contract' }, { label: '关闭连接预览', to: 'menu' }], hotspots: []
        },
        report: {
          title: '02B · 说明举报原因', imageLight: v5 + 'report-light.png', imageDark: v5 + 'report-light.png',
          explanation: '实际 V5 本地表单，反馈为 Draft preview · not submitted。' + onlyLight,
          behavior: '原因沿用 Spam / Harassment / Misinformation / Copyright / Other，可加说明。按钮仅 Preview report，没有提交、审核或本地持久化承诺。',
          status: 'design', actions: [{ label: '看正式提交的分支', to: 'service-contract' }, { label: '关闭，清除本次预览', to: 'menu' }], hotspots: []
        },
        'service-contract': {
          title: '03 · 成功必须来自真实服务', imageLight: null, imageDark: null,
          explanation: '已有行为 · 源码核对。真实举报回执、服务错误和连接成功的新主题画面尚未拍摄，故本节点无截图。',
          behavior: '正式 Link 成功后关闭，可按入口设置跳到所选笔记；失败留在弹层，重复关系有提示。正式 Report 提交中禁用重复提交，失败保留原因和说明并可重试，只有服务回执才显示 Report submitted / Case。此图谱不执行以上服务动作。',
          status: 'existing', actions: [{ label: '回到连接预览', to: 'link' }, { label: '回到举报表单', to: 'report' }, { label: '返回菜单', to: 'menu' }], hotspots: []
        }
      }
    }
  };
}());
