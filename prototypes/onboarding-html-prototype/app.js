const logoPath = "../../ArcNote/Assets.xcassets/logo.imageset/logo.png";
const sparkIconPath = "../../ArcNote/Assets.xcassets/pop/menu_spark.imageset/Frame (2).png";
const guideState = globalThis.ChoraiGuideState;

if (!guideState) {
  throw new Error("ChoraiGuideState must load before the onboarding prototype.");
}

const steps = [
  {
    id: "access",
    number: "01",
    phase: "ACCESS",
    title: "邀请码独立成门",
    shortTitle: "邀请码",
    caption: "保留 private beta 的资格感，但不和注册字段混在一起。",
    rationale: "邀请码回答“你是否有资格进入”，账号注册回答“你是谁”。拆开后，每一屏只做一个决定，错误状态也更清楚。",
    removed: "不再在注册表单底部重复输入 Access Code。",
    success: "输入有效邀请码后，立即进入账号创建。",
    guide: "This gate appears once, before account creation.",
    screen: () => `
      <div class="auth-scene">
        <div class="auth-photo" aria-hidden="true"></div>
        <div class="auth-shade" aria-hidden="true"></div>
        <div class="auth-content">
          <img class="screen-logo" src="${logoPath}" alt="" />
          <p class="screen-eyebrow">PRIVATE BETA ACCESS</p>
          <h3>Welcome to Chorai</h3>
          <p class="auth-intro">A quiet place for ideas to meet, grow, and become something new.</p>
          <div class="faux-field faux-field--dark">
            <span>Private beta code</span>
            <strong>••••••••</strong>
          </div>
          <div class="faux-button faux-button--signal">Enter Chorai <span>→</span></div>
          <p class="screen-footnote">Invitation required during private beta.</p>
        </div>
      </div>`,
  },
  {
    id: "signup",
    number: "02",
    phase: "ACCOUNT",
    title: "账号入口完整，Email 更可靠",
    shortTitle: "创建账号",
    caption: "Apple、Google 快速进入；Email 保留验证码与确认密码。",
    rationale: "邀请码已经完成 beta 资格判断；Email Code 只证明邮箱可达，Confirm Password 则避免密码输错。三者职责分开后，多一步也不会显得重复。",
    decisionLabel: "KEEP / CLARIFY",
    decisionTone: "keep",
    removed: "保留 Get Code 与 Confirm Password；明确它们验证的是邮箱有效性与输入准确性，而不是 beta 资格。",
    success: "Apple / Google 一步完成；Email 通过验证码且两次密码一致。",
    guide: "Choose Apple, Google, or verify your email.",
    prototypeNote: "元素清单示意；最终排版与交互沿用现有认证体系。",
    screen: () => `
      <div class="light-screen signup-screen">
        <div class="screen-nav"><span>←</span><span class="nav-wordmark">CHORAI</span><span></span></div>
        <div class="signup-copy">
          <p class="screen-eyebrow screen-eyebrow--ink">CREATE ACCOUNT</p>
          <h3>Let’s make it yours.</h3>
          <p>One quick step, then you can start capturing ideas.</p>
        </div>
        <div class="social-stack">
          <div class="faux-button apple-button"><span class="apple-mark"></span> Continue with Apple</div>
          <div class="faux-button google-button"><span class="google-mark">G</span> Continue with Google</div>
        </div>
        <div class="or-divider"><span></span><b>or use email</b><span></span></div>
        <div class="field-stack field-stack--signup">
          <div class="faux-field"><span>Name</span><strong>Maya Chen</strong></div>
          <div class="faux-field faux-field--action"><span>Email</span><strong>maya@example.com</strong><em>Get code</em></div>
          <div class="faux-field faux-field--verified"><span>Email verification code</span><strong>472901</strong><em>Verified ✓</em></div>
          <div class="faux-field"><span>Password</span><strong>••••••••••</strong></div>
          <div class="faux-field"><span>Confirm password</span><strong>••••••••••</strong></div>
        </div>
        <div class="faux-button dark-button">Create account <span>→</span></div>
        <p class="terms-copy">By continuing, you agree to the Terms and Privacy Policy.</p>
      </div>`,
  },
  {
    id: "home",
    number: "03",
    phase: "FIRST ACTION",
    title: "Home 只教创建",
    shortTitle: "Home",
    caption: "引导锚定可见的 +，用户可以立刻照着做。",
    rationale: "空 Library 的唯一主任务是创建第一条 Note。Guide 必须贴近右下角真实按钮，而不是悬浮在没有关系的位置。",
    removed: "不在 Home 解释 Explore、Spark 或 Merge。",
    success: "用户创建第一条 Note，空状态立即消失。",
    guide: "Tap + to capture your first note.",
    screen: () => `
      <div class="light-screen app-screen home-screen">
        <div class="app-topbar">
          <span class="avatar-dot">MC</span>
          <strong>Library</strong>
          <span class="more-dot">•••</span>
        </div>
        <div class="segmented-control"><span class="is-selected">Notes</span><span>Collections</span></div>
        <div class="empty-state">
          <span class="empty-glyph" aria-hidden="true">⌁</span>
          <h3>Your ideas start here.</h3>
          <p>Capture a thought, a question, or something you want to remember.</p>
        </div>
        ${guideMarkup("home")}
        <button type="button" class="plus-target ${guideTargetClass("home")}" data-guide-target="home" aria-label="Create your first note">+</button>
        <div class="app-tabbar"><span>Explore</span><span class="is-active">Home</span><span>Chat</span></div>
      </div>`,
  },
  {
    id: "explore",
    number: "04",
    phase: "DISCOVER",
    title: "Explore 从右上角进入 Spark",
    shortTitle: "Explore",
    caption: "首次 Spark 引导只高亮当前卡片右上角的独立图标。",
    rationale: "用户先在 Explore 看到一张有兴趣的卡片；当 Spark 状态可用时，Guide 必须锚定这张卡右上角的独立 Spark 图标，而不是整张卡或 ellipsis 菜单。",
    removed: "不把 Spark 画成独立 Tab，也不要求先打开 ellipsis 菜单。",
    success: "用户点击独立 Spark 图标，打开这张卡的 continuation。",
    guide: "Tap Spark to continue from this card.",
    screen: () => `
      <div class="dark-app-screen app-screen explore-flow-screen">
        <div class="flow-topbar"><span class="flow-menu">≡</span><strong>Explore</strong><span class="flow-search">⌕</span></div>
        <div class="flow-deck-label"><span>FOR YOUR CURIOSITY</span><small>01 / 12</small></div>
        <article class="flow-card-prototype">
          <div class="flow-card-glow" aria-hidden="true"></div>
          <header class="flow-card-header">
            <div class="flow-author"><span class="flow-avatar">AK</span><p><b>Alex Kim</b><small>2h · Mental models</small></p></div>
            <div class="flow-actions">
              <span class="flow-more" aria-label="More actions">•••</span>
              <button type="button" class="spark-entry-target ${guideTargetClass("explore")}" data-guide-target="explore" aria-label="Spark this card">
                <img src="${sparkIconPath}" alt="" />
              </button>
            </div>
          </header>
          <div class="flow-card-copy">
            <span>MENTAL MODELS</span>
            <h3>Ideas become more useful when they collide.</h3>
            <p>Unexpected connections turn isolated thoughts into better questions.</p>
          </div>
          <div class="flow-tags"><span>creativity</span><span>systems</span><span>thinking</span></div>
          <footer class="flow-engagement"><span>♡ 128</span><span>◌ 24</span><span>↗ Share</span></footer>
        </article>
        <div class="flow-next-peek"><span>UP NEXT</span><b>Collect first. Organize later.</b></div>
        ${guideMarkup("explore")}
        <div class="app-tabbar app-tabbar--dark"><span class="is-active">Explore</span><span>Home</span><span>Chat</span></div>
      </div>`,
  },
  {
    id: "spark",
    number: "05",
    phase: "CREATE VALUE",
    title: "Spark 延续当前卡片",
    shortTitle: "Spark",
    caption: "进入后沿用 chain rail、source strip 与结果卡片。",
    rationale: "Spark 是从当前 Explore card push 进入的 continuation journey。进入后保留来源上下文，让用户查看结果、Favorite，或继续向下 Spark。",
    removed: "移除独立 Spark Tab、输入框、prompt chips 与生成式空状态。",
    success: "用户查看结果并 Favorite，或从结果继续 Spark deeper。",
    guide: "Favorite a result to keep it.",
    screen: () => `
      <div class="dark-app-screen app-screen spark-continuation-screen">
        <header class="spark-continuation-header">
          <span class="spark-back" aria-label="Back to Explore">←</span>
          <img src="${sparkIconPath}" alt="" />
          <div class="spark-chain" aria-label="Spark chain depth">
            <span class="spark-chain-node is-source"></span><i></i><span class="spark-chain-node is-current"></span><i></i><span class="spark-chain-node"></span>
          </div>
        </header>
        <section class="spark-source-strip">
          <span>SOURCE CARD</span>
          <p>Ideas become more useful when they collide.</p>
          <b>›</b>
        </section>
        <div class="spark-deck">
          <div class="spark-backplate" aria-hidden="true"></div>
          <article class="spark-result-card">
            <header class="spark-result-header">
              <div class="flow-author"><span class="flow-avatar flow-avatar--spark">C</span><p><b>Chorai</b><small>Spark continuation</small></p></div>
              <span class="spark-depth">01</span>
            </header>
            <div class="spark-result-copy">
              <span>NEW CONNECTION</span>
              <h3>Collision works when each idea changes the question.</h3>
              <p>Instead of organizing thoughts by topic, place unlike notes side by side and ask what assumption they challenge together.</p>
            </div>
            <div class="spark-result-tags"><span>creative systems</span><span>questions</span></div>
            <footer class="spark-result-footer">
              <button type="button" class="spark-favorite-target ${guideTargetClass("spark")}" data-guide-target="spark" aria-label="Favorite this Spark result">♡ <b>Favorite</b></button>
              <span>◌ 18</span>
              <span class="spark-deeper"><img src="${sparkIconPath}" alt="" /> Spark deeper</span>
            </footer>
          </article>
        </div>
        ${guideMarkup("spark")}
      </div>`,
  },
  {
    id: "complete",
    number: "06",
    phase: "VALUE LOOP",
    title: "用价值闭环结束 onboarding",
    shortTitle: "完成",
    caption: "完成不是“看完教程”，而是已经创建、发现并保存。",
    rationale: "完成态应该复述用户刚刚获得的价值，而不是庆祝点击了几个 Next。兴趣设置作为可选链接出现在此处，不阻塞回到产品。",
    removed: "兴趣选择不再是进入产品前的强制第三步。",
    success: "回到 Library；需要时再个性化兴趣。",
    guide: "Your first idea loop is complete.",
    screen: () => `
      <div class="light-screen completion-screen">
        <div class="completion-mark"><span>✓</span></div>
        <p class="screen-eyebrow screen-eyebrow--ink">FIRST LOOP COMPLETE</p>
        <h3>Your space is taking shape.</h3>
        <p class="completion-intro">You have already made Chorai useful to you.</p>
        <div class="completion-list">
          <div><span>✓</span><p><b>Captured</b><small>Your first note</small></p></div>
          <div><span>✓</span><p><b>Discovered</b><small>An idea worth saving</small></p></div>
          <div><span>✓</span><p><b>Sparked</b><small>A new line of thought</small></p></div>
        </div>
        <div class="faux-button dark-button">Go to Library <span>→</span></div>
        <p class="optional-link">Personalize interests later</p>
      </div>`,
  },
  {
    id: "merge",
    number: "07",
    phase: "LATER",
    title: "Merge 等内容成熟后再教",
    shortTitle: "Merge",
    caption: "只有拥有两条可关联 Note 后，才出现一次性提示。",
    rationale: "Merge 是高阶能力。空 Library 时讲它既抽象又无法实践；当用户已经选中两条 Note，解释会立刻变得具体。",
    removed: "不把 Merge 塞进首次 onboarding 的前几屏。",
    success: "满足前置条件后，用户能当场完成一次 Merge。",
    guide: "Merge two related notes.",
    screen: () => `
      <div class="light-screen app-screen merge-screen">
        <div class="screen-nav"><span>×</span><strong>Merge</strong><span class="later-badge">LATER</span></div>
        <div class="merge-intro"><h3>Two notes, one new direction.</h3><p>Chorai will keep the originals and create a connected synthesis.</p></div>
        <div class="merge-notes">
          <article><span>SELECTED NOTE 01</span><b>Ideas become useful through collision.</b></article>
          <i>+</i>
          <article><span>SELECTED NOTE 02</span><b>Collect before you organize.</b></article>
        </div>
        ${guideMarkup("merge")}
        <button type="button" class="faux-button dark-button merge-target ${guideTargetClass("merge")}" data-guide-target="merge">Merge notes <span>→</span></button>
      </div>`,
  },
];

const routeGuides = {
  home: {
    label: "Home / Library",
    stepId: "home",
    state: "first_library_visit",
    target: "visible create-note (+) button",
    copy: "Tap + to capture your first note.",
    trigger: "Library is empty and the + anchor is rendered.",
    exits: "User taps + to capture a note, or taps outside the tip to dismiss it.",
    color: "violet",
  },
  explore: {
    label: "Explore · Spark entry",
    stepId: "explore",
    state: "product_spark_intro",
    target: "independent Spark icon on the active Flow card",
    copy: "Tap Spark to continue from this card.",
    trigger: "An eligible Explore card and its Spark icon are rendered.",
    exits: "User taps the direct Spark icon to continue, or taps outside the tip to dismiss it.",
    color: "teal",
  },
  spark: {
    label: "Spark · continuation",
    stepId: "spark",
    state: "product_spark_results",
    target: "Favorite action on the visible result card",
    copy: "Favorite a result to keep it.",
    trigger: "A Spark result card is rendered and visible.",
    exits: "User Favorites the result, or taps outside the tip to dismiss it.",
    color: "violet",
  },
  merge: {
    label: "Merge · later",
    stepId: "merge",
    state: "first_merge_ready",
    target: "enabled Merge notes action",
    copy: "Merge two related notes.",
    trigger: "At least two eligible notes are selected.",
    exits: "User merges the selected notes, or taps outside the tip to dismiss it.",
    color: "teal",
  },
};

let currentVariant = "A";
let currentStep = 0;
let currentRoute = "home";
let journeyObserver;
let guideOutcomes = {};

function guideRenderInput(guideId, activeRoute = guideId) {
  return {
    guideId,
    activeRoute,
    targetVisible: true,
    prerequisitesMet: true,
    outcomes: guideOutcomes,
  };
}

function guideMarkup(guideId, activeRoute = guideId) {
  return guideState.shouldRenderGuide(guideRenderInput(guideId, activeRoute))
    ? guideState.renderGuideCallout(guideId)
    : "";
}

function guideTargetClass(guideId, activeRoute = guideId) {
  return guideState.targetPulseClass(guideRenderInput(guideId, activeRoute));
}

function recordGuideOutcome(guideId, type) {
  const nextOutcomes = guideState.transitionGuide(guideOutcomes, { guideId, type });
  if (nextOutcomes === guideOutcomes) return;

  guideOutcomes = nextOutcomes;
  document.querySelectorAll(`[data-guide-id="${guideId}"]`).forEach((callout) => callout.remove());
  document.querySelectorAll(`[data-guide-target="${guideId}"]`).forEach((target) => {
    target.classList.remove("target-pulse");
  });

  if (currentRoute === guideId) setGuideRoute(currentRoute);
}

function continuePrototypeAction(guideId) {
  if (currentVariant === "C" && currentRoute === "explore" && guideId === "explore") {
    setGuideRoute("spark");
  }
}

const phoneTemplate = (step, mode = "standard") => `
  <article class="phone phone--${step.id} phone--${mode}" aria-label="${step.shortTitle} screen">
    <div class="phone-rim">
      <div class="status-bar"><span>9:41</span><span class="status-icons">● ᯤ 100%</span></div>
      <div class="dynamic-island" aria-hidden="true"></div>
      <div class="phone-screen">${step.screen()}</div>
      <div class="home-indicator" aria-hidden="true"></div>
    </div>
  </article>`;

function renderFlowBoard() {
  const track = document.querySelector("#journeyTrack");
  const index = document.querySelector("#journeyIndex");

  track.innerHTML = steps
    .map(
      (step, position) => `
        <article class="journey-step" data-journey-step="${position}" style="--delay:${position * 70}ms">
          <div class="step-meta">
            <span>${step.number}</span>
            <p>${step.phase}</p>
          </div>
          ${phoneTemplate(step)}
          <div class="step-caption">
            <h3>${step.title}</h3>
            <p>${step.caption}</p>
          </div>
        </article>`,
    )
    .join("");

  index.innerHTML = steps
    .map(
      (step, position) => `
        <button type="button" data-index-step="${position}" class="${position === 0 ? "is-active" : ""}">
          <span>${step.number}</span>${step.shortTitle}
        </button>`,
    )
    .join("");

  index.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => {
      const position = Number(button.dataset.indexStep);
      track.querySelector(`[data-journey-step="${position}"]`).scrollIntoView({
        behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
        block: "nearest",
        inline: "center",
      });
      setActiveJourneyStep(position);
    });
  });

  if ("IntersectionObserver" in window) {
    journeyObserver = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (visible) setActiveJourneyStep(Number(visible.target.dataset.journeyStep));
      },
      { root: document.querySelector(".journey-viewport"), threshold: [0.45, 0.7] },
    );
    track.querySelectorAll(".journey-step").forEach((step) => journeyObserver.observe(step));
  }
}

function setActiveJourneyStep(position) {
  document.querySelectorAll("[data-index-step]").forEach((button) => {
    button.classList.toggle("is-active", Number(button.dataset.indexStep) === position);
  });
  document.querySelectorAll("[data-journey-step]").forEach((step) => {
    step.classList.toggle("is-active", Number(step.dataset.journeyStep) === position);
  });
}

function renderWalkthrough() {
  const list = document.querySelector("#stepList");
  list.innerHTML = steps
    .map(
      (step, position) => `
        <button type="button" data-walkthrough-step="${position}" class="${position === 0 ? "is-active" : ""}">
          <span>${step.number}</span>
          <span><b>${step.shortTitle}</b><small>${step.phase}</small></span>
        </button>`,
    )
    .join("");

  list.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => setFocusedStep(Number(button.dataset.walkthroughStep)));
  });

  document.querySelector("#previousStep").addEventListener("click", () => {
    setFocusedStep((currentStep - 1 + steps.length) % steps.length);
  });
  document.querySelector("#nextStep").addEventListener("click", () => {
    setFocusedStep((currentStep + 1) % steps.length);
  });

  setFocusedStep(0);
}

function setFocusedStep(position) {
  currentStep = position;
  const step = steps[position];
  document.querySelector("#focusedPhone").innerHTML = phoneTemplate(step, "focused");
  document.querySelector("#stepCounter").textContent = `${step.number} / ${String(steps.length).padStart(2, "0")}`;
  document.querySelectorAll("[data-walkthrough-step]").forEach((button) => {
    button.classList.toggle("is-active", Number(button.dataset.walkthroughStep) === position);
  });
  document.querySelector("#rationalePanel").innerHTML = `
    <p class="mini-label">${step.phase} · ${step.number}</p>
    <h3>${step.title}</h3>
    <p class="rationale-lead">${step.rationale}</p>
    ${step.prototypeNote ? `<div class="prototype-boundary"><span>PROTOTYPE BOUNDARY</span><p>${step.prototypeNote}</p></div>` : ""}
    <dl>
      <div><dt>GUIDE COPY</dt><dd>“${step.guide}”</dd></div>
      <div class="${step.decisionTone === "keep" ? "kept-row" : "removed-row"}"><dt>${step.decisionLabel || "REMOVE"}</dt><dd>${step.removed}</dd></div>
      <div><dt>SUCCESS</dt><dd>${step.success}</dd></div>
    </dl>`;
}

function renderGuideMap() {
  const picker = document.querySelector("#routePicker");
  picker.innerHTML = Object.entries(routeGuides)
    .map(
      ([key, route]) => `
        <button type="button" data-route="${key}" aria-pressed="${key === currentRoute}">
          <span class="route-light route-light--${route.color}"></span>
          <span><b>${route.label}</b><small>${route.state}</small></span>
        </button>`,
    )
    .join("");
  picker.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => setGuideRoute(button.dataset.route));
  });
  setGuideRoute(currentRoute);
}

function setGuideRoute(routeKey) {
  currentRoute = routeKey;
  const route = routeGuides[routeKey];
  const step = steps.find((item) => item.id === route.stepId);
  const guideOutcome = guideOutcomes[guideState.outcomeKey(routeKey)] || "eligible";
  const blockedCopy =
    routeKey === "home"
      ? "Explore instructions"
      : routeKey === "explore"
        ? "Open the ellipsis menu or switch to a Spark tab"
        : routeKey === "spark"
          ? "Ask something in a standalone Spark prompt"
          : "Tap + to create your first note";
  document.querySelector("#guidePhone").innerHTML = phoneTemplate(step, "map");
  document.querySelectorAll("[data-route]").forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.route === routeKey));
  });
  document.querySelector("#logicPanel").innerHTML = `
    <div class="logic-header">
      <p class="mini-label">ACTIVE GUIDE</p>
      <span class="logic-status logic-status--${guideOutcome}"><i></i> ${guideOutcome}</span>
    </div>
    <h3>${route.label}</h3>
    <p class="logic-copy">“${route.copy}”</p>
    <dl>
      <div><dt>STATE</dt><dd>${route.state}</dd></div>
      <div><dt>TARGET</dt><dd>${route.target}</dd></div>
      <div><dt>SHOW WHEN</dt><dd>${route.trigger}</dd></div>
      <div><dt>EXIT WHEN</dt><dd>${route.exits}</dd></div>
    </dl>
    <div class="blocked-copy">
      <span>BLOCKED COPY</span>
      <p>${blockedCopy} must never render here.</p>
    </div>`;
}

function setVariant(variant, updateUrl = true) {
  const normalized = ["A", "B", "C"].includes(variant) ? variant : "A";
  currentVariant = normalized;
  document.querySelectorAll(".variant-view").forEach((view) => {
    const active = view.dataset.variant === normalized;
    view.hidden = !active;
    view.classList.toggle("is-active", active);
  });
  document.querySelectorAll("[data-switch-variant]").forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.switchVariant === normalized));
  });
  document.title = `Chorai Onboarding · View ${normalized}`;
  if (updateUrl) {
    const url = new URL(window.location.href);
    url.searchParams.set("variant", normalized);
    window.history.replaceState({}, "", url);
  }
  window.scrollTo({ top: 0, behavior: "auto" });
}

function bindVariantSwitcher() {
  document.querySelectorAll("[data-switch-variant]").forEach((button) => {
    button.addEventListener("click", () => setVariant(button.dataset.switchVariant));
  });

  document.addEventListener("keydown", (event) => {
    if (event.target.matches("input, textarea, [contenteditable='true']")) return;
    if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
    event.preventDefault();
    const variants = ["A", "B", "C"];
    const direction = event.key === "ArrowRight" ? 1 : -1;
    const nextIndex = (variants.indexOf(currentVariant) + direction + variants.length) % variants.length;
    setVariant(variants[nextIndex]);
  });
}

function bindGuideInteractions() {
  document.addEventListener("click", (event) => {
    const element = event.target instanceof Element ? event.target : null;
    if (!element) return;

    const phone = element.closest(".phone");
    if (!phone) return;

    const callout = phone.querySelector("[data-guide-id]");
    const target = element.closest("[data-guide-target]");
    const interaction = guideState.resolveGuideInteraction({
      phoneGuideId: callout?.dataset.guideId || null,
      targetGuideId: target?.dataset.guideTarget || null,
      isCallout: Boolean(element.closest("[data-guide-id]")),
    });

    if (!interaction || !callout || interaction.guideId !== callout.dataset.guideId) return;

    recordGuideOutcome(interaction.guideId, interaction.type);
    if (interaction.type === "target") continuePrototypeAction(interaction.guideId);
  });

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || currentVariant !== "C") return;

    const callout = document.querySelector("#guidePhone [data-guide-id]");
    if (callout) recordGuideOutcome(callout.dataset.guideId, "outside");
  });
}

renderFlowBoard();
renderWalkthrough();
renderGuideMap();
bindVariantSwitcher();
bindGuideInteractions();
setVariant(new URLSearchParams(window.location.search).get("variant") || "A", false);
