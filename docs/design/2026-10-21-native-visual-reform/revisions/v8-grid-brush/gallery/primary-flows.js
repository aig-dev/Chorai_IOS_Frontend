/* Screenshot journeys only. Navigation never triggers AI, writes, or task APIs. */
(function () {
  const repo = '/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/';
  const source = (label, path) => ({ label, path: repo + path });
  const action = (label, to) => ({ label, to });
  const state = (title, imageStem, explanation, behavior, actions) => ({
    title,
    imageLight: '../../v6-feature-journeys/screenshots/' + imageStem + '-light.png',
    imageDark: '../../v6-feature-journeys/screenshots/' + imageStem + '-dark.png',
    explanation,
    behavior,
    status: 'design', actions, hotspots: []
  });

  window.primaryFlows = {
    spark: {
      id: 'spark', title: 'Spark', kicker: '从一条笔记，继续探索',
      summary: '来源始终可回看；沿相关结果阅读、收藏或继续深入，加载与失败都保留上下文。',
      current: '源码已核对：正式入口是 SparkContinuationView。支持来源与历史节点、结果卡、阅读全文、作者、收藏、Like 和继续 Spark；已有结果在继续加载或失败时保持可见，空结果与深度限制有独立状态。',
      design: '温白墨绿承载内容，学院金标示 Spark 与当前节点。V6 用离线样例把加载、结果、深入、收藏、错误、空结果和限深画面串起来。',
      boundary: '浏览器只切换原生截图；所有“查看”按钮是流程讲解，不发起 AI 请求、消耗额度或写入收藏。截图中的结果与状态来自本地样例，不是实时推荐。',
      source: [
        source('正式加载 / 空结果 / 错误阶段', 'ArcNote/CoreFlow/SparkContinuationViews.swift:267'),
        source('结果阅读 / 作者 / 深入动作', 'ArcNote/CoreFlow/SparkContinuationViews.swift:319'),
        source('收藏权限与失败回滚', 'Packages/CoreFlow/Sources/CoreFlow/SparkSessionStore.swift:124'),
        source('追加结果与错误', 'Packages/CoreFlow/Sources/CoreFlow/SparkSessionStore.swift:852'),
        source('额度 / 深度 / 网络错误', 'Packages/CoreFlow/Sources/CoreFlow/SparkSessionStore.swift:1004')
      ],
      start: 'entry',
      states: {
        entry: {
          title: '01 · 从正在读的笔记出发',
          imageLight: '../../v5-explore-grid/screenshots/reader-light.png',
          imageDark: '../../v5-explore-grid/screenshots/reader-dark.png',
          explanation: '沿用 V5 原生阅读页实拍，说明 Spark 的来源上下文；此截图尚未展开更多菜单。',
          behavior: 'Spark 从具体笔记进入。若从编辑器触发，正式流程先确保正文保存成功；失败继续留在编辑器，不绕过保存条件。',
          status: 'design', hotspots: [],
          actions: [action('查看 Spark 加载画面', 'loading'), action('直接查看结果设计', 'results')]
        },
        loading: state('02 · 等待时仍知道从哪里来', 'spark-loading',
          'V6 本地加载状态示例，不代表正在发起真实请求。',
          '正式流程区分来源加载、触发、恢复与确认中。若已有结果，继续加载时保留结果并覆盖轻量等待状态；首次进入才用骨架。',
          [action('查看有结果的分支', 'results'), action('查看空结果分支', 'empty'), action('查看失败分支', 'error'), action('返回来源画面', 'entry')]),
        results: state('03 · 先看见一个值得展开的想法', 'spark-results',
          'V6 预置结果示例。学院金提示 Spark 与当前位置，正文保持稳定阅读底。',
          '正式结果支持阅读全文、认识作者、收藏 / 取消收藏、Like、更多操作与继续深入；这些入口各自保留权限。浏览图谱不会执行截图中的动作。',
          [action('查看全文阅读画面', 'reader'), action('查看收藏状态示例', 'collected'), action('查看继续深入的画面', 'deeper'), action('查看追加失败分支', 'error'), action('返回原文', 'entry')]),
        deeper: state('04 · 深入一个分支，仍能回到前文', 'spark-deeper',
          'V6 预置深入层级示例；新的来源与链节点属于本地演示。',
          '正式继续 Spark 使用当前结果作来源，维护链深度与历史节点；回看节点和再次发起生成是不同操作。返回旧节点不应伪装成新生成。',
          [action('回看上一层结果', 'results'), action('查看深度限制', 'limit'), action('查看追加失败', 'error'), action('返回最初原文', 'entry')]),
        reader: state('05A · 打开结果，完整阅读', 'spark-reader',
          'V6 从结果进入阅读的本地示例，不是服务端内容验证。',
          '正式结果可打开 DetailView，并可进入作者页；退出阅读应回到刚才的 Spark 上下文。阅读不等于收藏，也不触发新的 Spark。',
          [action('返回 Spark 结果', 'results'), action('查看收藏状态示例', 'collected'), action('返回最初原文', 'entry')]),
        collected: state('05B · 留下结果，继续自己的节奏', 'spark-collected',
          'V6 本地收藏状态示例，不能据此认定服务端已经收藏。',
          '正式 Spark 只允许收藏他人结果；先乐观更新并暂时锁定操作，失败时恢复原状态。成功回调与页面中的临时选中状态不能混为一谈。',
          [action('回看结果初始画面', 'results'), action('查看阅读画面', 'reader'), action('查看深入示例', 'deeper')]),
        error: state('分支 · 追加失败，不丢掉已有结果', 'spark-error',
          'V6 人工设定的错误状态示例；没有真实请求失败。',
          '正式实现有继续触发失败与追加更多失败。已有结果保持可见；重试、额度不足、不可恢复、限深要分别处理，不能所有错误都反复生成。',
          [action('回看已有结果', 'results'), action('查看重试时的加载示例', 'loading'), action('返回原文', 'entry')]),
        empty: state('分支 · 这次没有新的线索', 'spark-empty',
          'V6 空结果状态示例，不编造内容填满画面。',
          '正式空结果有独立 No new thread 状态，没有默认追加操作按钮。图谱提供回看来源与其他画面的讲解导航，不表示原应用新增自动重试。',
          [action('返回来源画面', 'entry'), action('对照有结果的设计', 'results')]),
        limit: state('分支 · 到达深度限制', 'spark-limit',
          'V6 限深提示示例；不设定或暗示服务端具体最大层数。',
          '正式 maximumDepth 返回限深提示；有现成结果时不提供继续重试该限制的按钮。仍可阅读已有内容并回到前面，不假装还能无限深入。',
          [action('回看上一层示例', 'deeper'), action('回到结果阅读', 'reader'), action('返回最初原文', 'entry')])
      }
    },

    merge: {
      id: 'merge', title: 'Merge', kicker: '选好来源，再把结果变成自己的笔记',
      summary: '选材、任务、结果草稿和接受保存是四件事；中途离开、失败与冲突都能看清下一步。',
      current: '源码已核对：固定来源与候选选择后创建任务；任务可由协调器接管并回到后台入口。结果可编辑正文和标签，具有同步与冲突状态；Accept 先同步草稿再提交，Discard 与取消任务各有确认。',
      design: 'V6 用原生选择列表、任务层与可编辑结果串起温白墨绿加少量学院金。设计按 2–8 来源规划；当前原生 canCreate 只核验至少 2 个，尚不能称已有 8 个上限。',
      boundary: '全部是本地样例截图，浏览器仅导航截图。生成、后台、冲突和 saved 都可由演示启动参数展示；saved 画面尤其不代表真正执行了 Accept、保存了笔记或联系了服务。',
      source: [
        source('现有创建条件', 'Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:56'),
        source('固定来源不可移除', 'Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:188'),
        source('任务接管后返回', 'ArcNote/CoreFlow/MergeLifecycleViews.swift:190'),
        source('任务阶段与完成状态', 'ArcNote/CoreFlow/MergeLifecycleViews.swift:665'),
        source('取消必须确认', 'ArcNote/CoreFlow/MergeLifecycleViews.swift:559'),
        source('接受前先同步', 'ArcNote/CoreFlow/MergeArtifactDraftController.swift:211'),
        source('冲突处理', 'Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:379')
      ],
      start: 'selection',
      states: {
        selection: state('01 · 围绕一篇笔记选材料', 'merge-selection',
          'V6 本地选材画面。固定来源与候选分开，数量和下一步条件保持可读。',
          '正式选材保留固定来源，候选带真实笔记与版本。固定来源不能被取消选择。设计规划 2–8 来源；原生当前代码只显式检查至少 2 个，不凭此推断后台上限。',
          [action('查看已选材料的示例', 'selected')]),
        selected: state('02 · 确认一起使用哪些来源', 'merge-selected',
          'V6 预置选中状态；选中标记、数量与来源摘要共同表达选择。',
          '正式创建前需有可用能力、至少两份来源且没有进行中操作。图谱不会创建任务，也不会因点击下一步而使用笔记内容。',
          [action('查看任务进行中的示例', 'progress'), action('回看选材画面', 'selection')]),
        progress: state('03 · 任务进行中', 'merge-progress',
          'V6 人工演示的生成状态，不代表真实 AI 正在工作。',
          '正式实现区分检查能力、创建、生成和加载产物。离开界面不是取消；只有成功交给任务协调器后才从原处返回。取消需要明确确认。',
          [action('查看后台任务入口', 'background'), action('查看结果准备好的分支', 'ready'), action('查看任务失败分支', 'failed'), action('查看确认取消后的示例', 'cancelled')]),
        background: state('04 · 可以离开，也知道从哪里回来', 'merge-background',
          'V6 本地后台入口状态示例，不意味着本次有真实后台任务运行。',
          '正式任务接管成功后回到原处，并由任务入口恢复；接管保存失败会留在当前界面重试。关闭视图、最小化与取消是不同操作。',
          [action('回看进行中任务', 'progress'), action('查看恢复后已就绪的示例', 'ready'), action('查看任务失败状态', 'failed')]),
        ready: state('05 · 结果准备好了，仍是一份草稿', 'merge-ready',
          'V6 预置结果草稿画面；没有调用生成或接受接口。',
          '正式结果允许编辑正文与标签，保留附件；生成完成不等于已经成为保存的笔记。Accept 与 Discard 是之后的选择。',
          [action('查看编辑与接受规则', 'edit'), action('查看同步失败分支', 'sync-error'), action('查看版本冲突分支', 'conflict'), action('回看后台入口', 'background')]),
        edit: state('06 · 调整后，再决定接受', 'merge-ready',
          '此节点复用 ready 的同一张真实原生截图，说明同一结果表面可阅读和编辑；不是新增编辑结果截图。',
          '正式 Accept 先读取安全正文快照、同步草稿，再提交。同步中、离线未同步或冲突时不可接受；Discard 需确认并只丢弃本次草稿，不删除来源。',
          [action('查看接受完成的状态预览', 'saved'), action('查看同步失败时如何停留', 'sync-error'), action('查看冲突选择', 'conflict'), action('返回结果概览', 'ready')]),
        'sync-error': state('分支 · 草稿没有同步成功', 'merge-sync-error',
          'V6 本地同步失败状态示例；没有真实上传或网络故障。',
          '正式逻辑保留待同步操作并允许适当重试，未同步时不放行 Accept。应保留用户刚写的内容，不能用一个成功提示覆盖失败。',
          [action('回看可编辑草稿', 'edit'), action('对照同步后可接受的状态', 'ready'), action('查看冲突分支', 'conflict')]),
        conflict: state('分支 · 你的版本与服务端不一致', 'merge-conflict',
          'V6 人工设定的冲突示例，没有与服务端产生真实冲突。',
          '正式提供 Reload server version 和 Keep my version。前者采用服务端版本；后者以最新版本为基线重提自己的内容，仍需同步成功，不能把点击保留直接当保存完成。',
          [action('查看解决后回到草稿的画面', 'edit'), action('对照仍未同步的状态', 'sync-error'), action('回看结果概览', 'ready')]),
        saved: state('07 · 接受完成的状态设计', 'merge-saved',
          '这是 saved 状态预览，可由演示启动参数直接展示；没有执行真实 Accept，也没有产生真实已保存笔记。',
          '正式逻辑只有提交完成才进入 completed，并可用返回的结果标识打开已保存内容。生成就绪、草稿已同步与最终接受保存，必须分别表达。',
          [action('回看接受前的草稿', 'edit'), action('重新浏览选材讲解', 'selection')]),
        failed: state('分支 · 任务失败，给出能做的事', 'merge-failed',
          'V6 本地失败状态示例；不表示真实任务或服务已失败。',
          '正式流程有暂停、失败、恢复与重试；可用按钮取决于任务状态。已有任务的恢复、重新生成与取消不能混作一个重试操作。',
          [action('查看恢复时的任务画面', 'progress'), action('查看后台任务入口', 'background'), action('查看确认取消后的状态', 'cancelled')]),
        cancelled: state('分支 · 确认取消任务之后', 'merge-cancelled',
          'V6 本地取消状态预览，不代表取消了任何真实任务；也不作为 Discard 草稿的独立截图。',
          '正式取消有确认步骤，离开当前视图不触发取消。取消失败与已取消需要区分；来源笔记不应被删除。图谱只展示取消后的设计方向。',
          [action('回看任务进行中的画面', 'progress'), action('重新浏览选材讲解', 'selection')])
      }
    }
  };
}());
