/* V7: sourced behavior, fixed offline specimens, no service calls. */
(() => {
  const repo='/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/';
  const a=(label,to)=>({label,to});
  const source=(label,path)=>({label,path:repo+path});
  const state=(title,stem,explanation,behavior,actions)=>({title,imageLight:`../screenshots/levels-${stem}-light.png`,imageDark:`../screenshots/levels-${stem}-dark.png`,explanation,behavior,actions,status:'design',hotspots:[]});
  const tiers=[
    ['basic','I','Basic','银灰','0–2','保持最安静的银灰边缘，小 Chora 伏在卡边。'],
    ['notable','II','Notable','青绿','3–8','青绿色细边与直立小 Chora，不扩大装饰面积。'],
    ['valuable','III','Valuable','蓝','9–26','蓝色尾部和罗马数字形成辨识点，正文仍保持温白／深色阅读底。'],
    ['significant','IV','Significant','紫','27–80','紫色抱角姿态留在卡片边缘，避免压住作者和内容。'],
    ['exceptional','V','Exceptional','绿金','81–242','沿用你选定的绿金组合；这套专属角色材质只属于第五级。'],
    ['definitive','VI','Definitive','珊瑚红','243+','更鲜明的尾部轮廓用在小范围，保留原有层级名称。']
  ];
  const levels={id:'levels',title:'卡片等级',kicker:'六档卡片，各自可辨',summary:'补上六级卡片、Explore / Grid / Merge 的展示位置，以及可回看的等级说明。角色不挤占正文，等级不改写操作权限。',
    current:'原生已有 Basic、Notable、Valuable、Significant、Exceptional、Definitive 六档。Home 使用等级材质；本人笔记支持按 rate 排序；Merge 结果显示等级名。当前 Explore Flow 与阅读正文尚未直接展示等级，原生也没有独立的等级说明入口。',
    design:'V7 将 Web 已确认的小 Chora 趴边 / 探身 / 抱角画稿迁入独立 SwiftUI 样例，保留六级颜色和罗马数字。新增 About card levels 说明页属于设计提案。顶部场景切换只服务设计评审，不是用户修改卡片等级的功能。',
    boundary:'全部等级均为固定样例。实际卡片仍由服务端 rate 决定，收藏和阅读不会在此原型里涨级。未知值中性展示是本轮建议；旧原生将负值映射 Basic、缺失 rate 默认 1，尚未改变。',
    source:[source('六级映射与阈值','Packages/CoreFlow/Sources/CoreFlow/CardLevelStyle.swift:16'),source('原生缺失字段的默认值','Packages/CoreFlow/Sources/CoreFlow/CardResponseModels.swift:154'),source('Home 排序与等级表面','ArcNote/HomeView.swift:117'),source('Merge 等级名与操作','ArcNote/CoreFlow/MergeArtifactEditorSurface.swift:275'),{label:'已确认的小 Chora 画稿与部署记录',path:'/Users/didi/Documents/ChatGPT/Jaime@Chorai 2/docs/design/2026-10-19-chora-card-system/README.md'}],start:'guide',states:{}};
  levels.states.guide=state('六级对照 · 从形态看起','guide','六张卡共享内容层级，颜色、罗马数字与小 Chora 提供识别。打开任一档，查看实际卡片上的比例。','这是设计样例目录。这里的切换用于比较视觉，不是给笔记手动评级；正式产品没有“选择等级”操作。',tiers.map(([id,roman,name])=>a(`${roman} · ${name}`,id)).concat([a('看 Grid 密度','grid'),a('看 Merge 结果','merge')]));
  tiers.forEach(([id,roman,name,color,range,detail],i)=>{
    levels.states[id]=state(`${roman} · ${name} / ${color}`,id,detail,`本地样例固定映射 ${range}。与其他档位共用阅读、收藏和更多操作；等级不增加权限，也不代表作者能力或内容正确性。原生现有名称保留，新视觉尚未迁入正式 App。`,[a('返回六级对照','guide'),a('看下一档',tiers[(i+1)%tiers.length][0]),a('看 Grid 中的比例','grid'),a('看 Merge 中的结果','merge')]);
  });
  levels.states.grid=state('Grid · 内容先行，等级留在边缘','grid','将同一套角色与等级标记缩小到双列浏览；没有独立角色大区块，也没有增加抽卡或升级按钮。','这是原生 Grid 展示提案，点击卡片可阅读。浏览模式改变密度，不改变每张卡所属等级与阅读、收藏的语义。角色全部可见便于评审；此前“偶尔遇见”露出比例提案未在这里实施。',[a('放大看一张卡','valuable'),a('回到六级对照','guide'),a('看 Merge 结果','merge')]);
  levels.states.merge=state('Merge · 结果出现，等级随结果呈现','merge','结果表面保留等级名与静态 Chora。使用固定示例解释外观，不演示随机升级，也不把揭晓当成保存成功。','原有 Merge 结果可编辑正文 / 标签，并通过 Accept 保存。仓库规范写明 rate 来自冻结来源的累积，编辑正文不改变等级；本轮没有验证运行中的服务。这里的样例用于对照视觉，完整接受 / 冲突 / 失败流程仍在 Merge 章节。',[a('对照 Exceptional 卡片','exceptional'),a('返回六级对照','guide'),a('看看等级不可用时','unknown')]);
  levels.states.unknown=state('边界 · 等级暂不可用','unknown','有内容就继续阅读；没有有效等级信息时，使用中性边缘，不补造角色和级别。','这是数据边界建议，与旧原生默认 Basic 的逻辑有差异。目前只在独立原型中展示，尚未修改 DTO、后端或正式映射。未知不应被视觉误报为“最低等级”。',[a('回到正常卡片','basic'),a('返回六级对照','guide')]);
  const growth={id:'growth',title:'Chora 成长',kicker:'陪伴者的成长，独立于卡片',summary:'卡片的六档与 Chora 的六阶段是两套数据。成长页展示已确认阶段与六维状态，阅读 / 收藏动作不会在原型里伪造升级。',
    current:'Chora Profile 已有 Identity、Growth、Soul Sources、Chat History。Growth 使用服务端 committed_stage，并展示 Curiosity、Insight、Creativity、Empathy、Judgment、Resonance 六维；未知阶段或无效维度显示 Unavailable。',
    design:'V7 增加一张原生成长页样例。使用温白墨绿、原生信息层级与条形状态，展示 Thread 固定样例。将卡片等级入口与 Chora 成长说明分开，不把六种卡片角色直接解释成六个成长阶段。',
    boundary:'阶段与数值均为本地样例。没有获取真实用户档案、未实现新的成长算法；这里不设计“收藏一次升级”或“Merge 一次升一阶段”等规则。',
    source:[source('已确认阶段枚举','Packages/CoreFlow/Sources/CoreFlow/ChoraProfileModels.swift:37'),source('六维与有效值范围','Packages/CoreFlow/Sources/CoreFlow/ChoraProfileModels.swift:83'),source('只使用 committed_stage','ArcNote/CoreFlow/NetworkChoraProfileService.swift:170'),source('成长展示与不可用处理','ArcNote/ChoraIdentityGrowthSections.swift:109')],start:'profile',states:{}};
  growth.states.profile=state('Growth · 看已确认的成长','growth','以 Thread 固定样例展示六维状态。角色的陪伴感放在信息层级里，正文与数值保持清晰。','已知阶段依次为 Initial、Trace、Thread、Weave、Co-Think、Second Voice。维度有效范围为 0–12。阶段未知或维度缺失应标示不可用，不把计算中的阶段或缺失数值当成已确认结果。',[]);
  window.cardLevelFlows={levels,growth};
})();
