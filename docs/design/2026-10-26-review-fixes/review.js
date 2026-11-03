(() => {
  'use strict';
  const pages = {
    'home-spacing': ['Home 排版', 'HOME · 留白与节奏', '正文与标签，回到同一条笔记里。', '收紧正文下方多余的间距，保留笔记之间的分隔与呼吸。My Notes / Collections 和已有操作含义保持不变。'],
    'home-sort-menu': ['原生排序菜单', 'HOME · 系统菜单', '排序收进一个熟悉的入口。', '移除占据正文上方的横向排序胶囊，用系统菜单呈现已有排序项与当前选择，不新增筛选能力。'],
    'editor-empty': ['空白编辑页', 'EDITOR · 整页写作', '空白页，也是一整页。', '书写区域占满可用空间，编辑时收起 Home 底部浏览栏。保留原来的单一正文，不增加独立标题输入。'],
    'editor-tools': ['编辑工具', 'EDITOR · 工具入口', '工具回到右下角。', '用清楚的工具图标承接已有编辑选项，替代正文下面突兀的加号。下面展示真实 App 中的工具状态。'],
    'editor-typed': ['输入后的正文', 'EDITOR · 内容展开', '写下去，不被小框限制。', '正文沿整页自然展开。这里展示离线样本的输入结果，用于核对排版，不代表服务器保存成功。'],
    'editor-keyboard': ['键盘展开', 'EDITOR · 系统输入', '把空间留给正在写的内容。', '真实键盘展开时检查正文、工具和底部安全区域的关系。沿用系统输入体验，不添加一层新的写作流程。'],
    'editor-existing': ['已有笔记', 'EDITOR · 真实正文结构', '已有笔记也用同一张写作页。', '保留内容本来的段落和标题层级，不把第一段自动变成标题。编辑、标签及已有保存语义继续沿用项目能力。']
  };
  const $ = selector => document.querySelector(selector);
  const $$ = selector => [...document.querySelectorAll(selector)];
  let page = 'home-spacing';
  let theme = 'light';
  let expectedSource = '';
  const image = $('#capture');
  const status = $('#image-status');
  const compare = $('#compare');

  function render({ updateHash = true } = {}) {
    const info = pages[page];
    const dark = theme === 'dark';
    const appearance = dark ? '深色' : '浅色';
    const source = `screenshots/review-${page}-${theme}.png`;
    document.body.classList.toggle('dark', dark);
    document.querySelector('meta[name="theme-color"]').content = dark ? '#242329' : '#faf9f6';
    $$('[data-theme]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.theme === theme)));
    $$('[data-page]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.page === page)));
    $('#capture-label').textContent = `${info[0]} · ${appearance}`;
    ['#note-kicker', '#note-title', '#note-body'].forEach((id, index) => { $(id).textContent = info[index + 1]; });
    image.alt = `${info[0]} · ${appearance}，本轮原生 App 离线样本实拍`;
    $('#capture-link').href = source;
    document.title = `${info[0]} · ${appearance} · Chorai iOS 本轮修正`;
    if (expectedSource !== source) {
      expectedSource = source;
      status.hidden = false;
      status.querySelector('span').textContent = '正在载入原生截图…';
      $('#retry').hidden = true;
      $('#image-wrap').setAttribute('aria-busy', 'true');
      image.src = source;
    }
    $('#compare-control').hidden = page !== 'home-spacing';
    const comparing = page === 'home-spacing' && compare.checked;
    $('#prior-figure').hidden = !comparing;
    $('#capture-area').classList.toggle('comparing', comparing);
    if (comparing) {
      const prior = `../2026-10-26-native-rollout/fidelity/screenshots/home-${theme}.png`;
      $('#prior-capture').src = prior;
      $('#prior-capture').alt = `上轮 Home · ${appearance}，保留的 fidelity 原生实拍`;
      $('#prior-link').href = prior;
    }
    if (updateHash && location.hash !== `#${page}-${theme}`) history.replaceState(null, '', `#${page}-${theme}`);
  }

  function readHash() {
    const match = location.hash.slice(1).match(/^(.*)-(light|dark)$/);
    if (match && pages[match[1]]) { page = match[1]; theme = match[2]; }
    render();
  }

  image.addEventListener('load', () => { status.hidden = true; $('#image-wrap').setAttribute('aria-busy', 'false'); });
  image.addEventListener('error', () => {
    status.hidden = false;
    status.querySelector('span').textContent = '这张 App 实拍还未载入。截图文件正在整理，暂不以旧图替代。';
    $('#retry').hidden = false;
    $('#image-wrap').setAttribute('aria-busy', 'false');
  });
  $('#retry').addEventListener('click', () => {
    status.querySelector('span').textContent = '正在重新载入…';
    image.src = `${expectedSource}?retry=${Date.now()}`;
  });
  $$('[data-theme]').forEach(button => button.addEventListener('click', () => { theme = button.dataset.theme; render(); }));
  $$('[data-page]').forEach(button => button.addEventListener('click', () => { page = button.dataset.page; render(); }));
  compare.addEventListener('change', () => render());
  window.addEventListener('hashchange', readHash);
  readHash();
})();
