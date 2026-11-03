(() => {
  'use strict';
  const cards = [
    ['photo', '图文'], ['essay', '长文'], ['quote', '引语'], ['checklist', '清单'],
    ['code', '代码'], ['reference', '参考链接'], ['comparison', '对照'], ['short', '短句']
  ];
  const cardKeys = cards.map(([key]) => key);
  const states = ['rest', 'skip', 'collect', 'history'];
  const readerCards = ['photo', 'essay'];
  const $ = selector => document.querySelector(selector);
  const $$ = selector => [...document.querySelectorAll(selector)];
  const image = $('#capture');
  const hotspot = $('#card-hotspot');
  const loading = $('#image-status');
  const cue = $('#gesture-cue');
  let screen = 'explore';
  let theme = 'light';
  let card = 'photo';
  let state = 'rest';
  let previousExplore = 'photo';
  let expectedSource = '';
  let drag = null;
  let ignoreClick = false;
  let toastTimer;

  const label = key => cards.find(([id]) => id === key)?.[1] || '图文';
  const themeLabel = () => theme === 'dark' ? '深色' : '浅色';
  const imagePath = () => `../screenshots/v9-${screen}-${screen === 'explore' && state !== 'rest' ? state : card}-${theme}.png`;
  const stateLabels = { rest: '静止卡面', skip: '左滑反馈', collect: '右滑反馈', history: '历史半屏页' };

  function notify(message) {
    const toast = $('#toast');
    clearTimeout(toastTimer);
    toast.textContent = message;
    toast.classList.add('visible');
    toastTimer = setTimeout(() => toast.classList.remove('visible'), 3400);
  }

  function setPressed(selector, property, current) {
    $$(selector).forEach(button => button.setAttribute('aria-pressed', String(button.dataset[property] === current)));
  }

  function render({ writeHash = true } = {}) {
    document.body.classList.toggle('dark', theme === 'dark');
    document.querySelector('meta[name="theme-color"]').content = theme === 'dark' ? '#242329' : '#faf9f6';
    setPressed('[data-screen]', 'screen', screen);
    setPressed('[data-theme]', 'theme', theme);
    setPressed('[data-card]', 'card', card);
    setPressed('[data-state]', 'state', state);
    $$('[data-card]').forEach(button => { button.hidden = screen === 'reader' && !readerCards.includes(button.dataset.card); });
    $('#sample-count').textContent = `${String((screen === 'reader' ? readerCards : cardKeys).indexOf(card) + 1).padStart(2, '0')} / ${screen === 'reader' ? '02' : '08'}`;
    $('#state-section').hidden = screen === 'reader';
    hotspot.hidden = screen !== 'explore' || state !== 'rest';
    hotspot.setAttribute('aria-label', readerCards.includes(card) ? `查看${label(card)}笔记的阅读详情设计，也可左右拖动切换卡片` : `${label(card)}固定卡面，可左右拖动切换卡片`);
    $('#back-hotspot').hidden = screen !== 'reader';
    $('#open-reader').hidden = screen === 'reader';
    $('#return-explore').hidden = screen !== 'reader';
    const source = imagePath();
    const title = `${screen === 'explore' ? 'Explore' : '阅读详情'} · ${screen === 'explore' && state !== 'rest' ? stateLabels[state] : label(card)} · ${themeLabel()}`;
    $('#capture-label').textContent = title;
    image.alt = `${title}，iOS 原生独立原型实际截图`;
    $('#full-image').href = source;
    document.title = `${title} · Chorai V9`;
    if (source !== expectedSource) {
      expectedSource = source;
      loading.hidden = false;
      loading.querySelector('span').textContent = '正在载入原生截图…';
      $('#retry-capture').hidden = true;
      $('#preview').setAttribute('aria-busy', 'true');
      image.src = source;
    }
    const notes = {
      rest: ['EXPLORE · 固定摘要卡', '内容变，卡片尺寸不变。', '图文、长文、清单都占用同一块空间。长内容在摘要处结束，点进正文再完整阅读。移除底部遮罩与常驻操作说明，等级笔触继续保留。'],
      skip: ['EXPLORE · 左滑反馈', '滑动的时候，才说 Skip。', '手指带动卡片，边缘浮出克制的 Skip 标记。松手未越过阈值就回弹；越过才进入下一张，刚看过的内容仍可从历史找回。'],
      collect: ['EXPLORE · 右滑反馈', '用墨绿表达收藏，不染整张卡。', '右滑时出现书签与 Collect，等级笔触保留自己的颜色。正式实现需等待真实收藏成功后再换卡；此处只演示离线状态，不代表已收藏。'],
      history: ['EXPLORE · 回看历史', '可以回头，也记得你读到哪。', '顶部历史图标打开系统半屏页。回看旧卡片保留未读位置，继续探索会回到原来的进度，不需要常驻在底部的 Previous。']
    };
    const note = screen === 'reader'
      ? ['READER · 全页正文', '不再把全文装进另一张卡。', '作者、等级与小 Chora 收在页首，正文直接铺在阅读底上。保留真实内容结构，长文自然滚动；阅读时隐藏底部浏览栏，返回后仍是刚才的卡片。']
      : notes[state];
    ['#note-kicker', '#note-title', '#note-body'].forEach((id, index) => { $(id).textContent = note[index]; });
    $('#preview-caption').textContent = screen === 'reader'
      ? '阅读首屏 · 点左上角返回原卡片'
      : state === 'rest' ? '图文与长文卡片可点开查看阅读设计' : `${stateLabels[state]} · 静态原生状态截图`;
    if (writeHash) {
      const hash = `#${screen}-${theme}-${card}-${state}`;
      if (location.hash !== hash) history.replaceState(null, '', hash);
    }
  }

  function openReader({ allowSample = false } = {}) {
    if (screen === 'explore') previousExplore = card;
    if (!readerCards.includes(card)) {
      if (!allowSample) {
        notify('这张展示固定卡面。切到图文或长文，可点开对应的阅读设计。');
        return;
      }
      card = 'essay';
    }
    screen = 'reader';
    state = 'rest';
    render();
  }

  function back() {
    screen = 'explore';
    card = previousExplore;
    state = 'rest';
    render();
  }

  function readHash() {
    const parts = location.hash.slice(1).split('-');
    if (['explore', 'reader'].includes(parts[0])) screen = parts[0];
    if (['light', 'dark'].includes(parts[1])) theme = parts[1];
    if (cardKeys.includes(parts[2])) card = parts[2];
    state = states.includes(parts[3]) ? parts[3] : 'rest';
    if (screen === 'reader') {
      if (!readerCards.includes(card)) card = 'photo';
      state = 'rest';
    }
    if (screen === 'explore' && state !== 'rest') card = 'photo';
    previousExplore = card;
    render();
  }

  image.addEventListener('load', () => {
    loading.hidden = true;
    $('#preview').setAttribute('aria-busy', 'false');
  });
  image.addEventListener('error', () => {
    loading.hidden = false;
    loading.querySelector('span').textContent = '这张原生截图还未载入。请确认截图文件已随设计稿保存。';
    $('#retry-capture').hidden = false;
    $('#preview').setAttribute('aria-busy', 'false');
  });
  $('#retry-capture').addEventListener('click', () => {
    loading.querySelector('span').textContent = '正在重新载入…';
    image.src = `${imagePath()}?retry=${Date.now()}`;
  });

  $$('[data-screen]').forEach(button => button.addEventListener('click', () => {
    if (button.dataset.screen === screen) return;
    if (button.dataset.screen === 'reader') openReader({ allowSample: true });
    else back();
  }));
  $$('[data-theme]').forEach(button => button.addEventListener('click', () => { theme = button.dataset.theme; render(); }));
  $$('[data-card]').forEach(button => button.addEventListener('click', () => { card = button.dataset.card; state = 'rest'; render(); }));
  $$('[data-state]').forEach(button => button.addEventListener('click', () => {
    state = button.dataset.state;
    if (state !== 'rest') card = 'photo';
    render();
  }));
  $('#open-reader').addEventListener('click', () => openReader({ allowSample: true }));
  $('#return-explore').addEventListener('click', back);
  $('#back-hotspot').addEventListener('click', back);
  hotspot.addEventListener('click', () => {
    if (ignoreClick) { ignoreClick = false; return; }
    openReader();
  });

  hotspot.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    drag = { x: event.clientX, y: event.clientY, id: event.pointerId, horizontal: false };
    ignoreClick = false;
    hotspot.setPointerCapture(event.pointerId);
  });
  hotspot.addEventListener('pointermove', event => {
    if (!drag || event.pointerId !== drag.id) return;
    const dx = event.clientX - drag.x;
    const dy = event.clientY - drag.y;
    if (Math.abs(dx) > 16 && Math.abs(dx) > Math.abs(dy) * 1.3) drag.horizontal = true;
    if (!drag.horizontal) return;
    ignoreClick = true;
    if (Math.abs(dx) < 12) {
      delete cue.dataset.direction;
      return;
    }
    cue.dataset.direction = dx > 0 ? 'collect' : 'skip';
    cue.textContent = dx > 0 ? 'COLLECT' : 'SKIP';
  });
  function endDrag(event, cancelled = false) {
    if (!drag || event.pointerId !== drag.id) return;
    const dx = event.clientX - drag.x;
    const completed = !cancelled && drag.horizontal && Math.abs(dx) >= 72;
    const moved = drag.horizontal;
    drag = null;
    delete cue.dataset.direction;
    if (hotspot.hasPointerCapture(event.pointerId)) hotspot.releasePointerCapture(event.pointerId);
    if (completed) {
      card = cardKeys[(cardKeys.indexOf(card) + 1) % cardKeys.length];
      state = 'rest';
      render();
      notify(dx > 0 ? '右滑演示 · 已切换下一张样本，没有执行真实收藏' : '左滑演示 · 下一张样本');
    } else if (moved && !cancelled) {
      notify('未越过滑动阈值，保留当前卡片');
    }
    if (moved) { ignoreClick = true; setTimeout(() => { ignoreClick = false; }, 300); }
  }
  hotspot.addEventListener('pointerup', event => endDrag(event));
  hotspot.addEventListener('pointercancel', event => endDrag(event, true));
  hotspot.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    card = cardKeys[(cardKeys.indexOf(card) + (event.key === 'ArrowRight' ? 1 : cardKeys.length - 1)) % cardKeys.length];
    render();
    notify(`${label(card)}卡面样本`);
  });
  window.addEventListener('hashchange', readHash);
  readHash();
})();
