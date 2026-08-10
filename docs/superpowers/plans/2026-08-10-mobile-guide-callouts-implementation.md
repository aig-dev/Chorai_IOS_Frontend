# Mobile Guide Callouts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the approved minimal contextual-guide behavior work in the throwaway iOS onboarding prototype, with executable state tests and visual interaction verification.

**Architecture:** `guide-state.js` owns the versioned guide definitions, visibility decision, outcomes, and the only callout renderer. `app.js` composes the reviewed screens and delegates target/outside/Escape events; CSS preserves the existing visual hierarchy while making the callout one compact sentence.

**Tech Stack:** Static HTML, CSS, browser JavaScript, Node.js built-in `node:test`, in-app-browser visual QA.

## Global Constraints

- Scope is `prototypes/onboarding-html-prototype`; do not modify production Swift.
- Render a single anchored callout with exactly one sentence, never a title, visible close control, `Got it`, `Try Spark`, or acknowledgement action.
- Use these exact approved sentences: `Tap + to capture your first note.`, `Tap Spark to continue from this card.`, `Favorite a result to keep it.`, and `Merge two related notes.`
- A guide is visible only when its route matches, its target is visible, its prerequisites are met, and its current guide-version outcome is unset.
- Target activation records `completed`; a tap elsewhere inside that phone records `dismissed`; tapping the callout itself changes nothing.
- Prototype outcomes remain in memory and reset on reload. A later Swift implementation must persist dismissal by guide version and expose VoiceOver `Dismiss tip` as a custom accessibility action.
- Do not add a timer, overlay, focus trap, Spark tab, menu-mediated Spark entry, or onboarding screen.
- Preserve the existing Spark continuation flow and visual target hierarchy. Real targets become semantic buttons.
- The callout announces contextual help without focus takeover. Reduced Motion removes the pulse without changing visibility or meaning.
- Use red-green-refactor for behavior and finish with in-app-browser QA at a 390-point mobile viewport.

---

## File Structure

- Create `prototypes/onboarding-html-prototype/guide-state.js`: definitions, versioned outcomes, visibility rules, and callout markup.
- Create `prototypes/onboarding-html-prototype/tests/guide-state.test.mjs`: native Node behavior tests that load the actual helper through `vm`.
- Modify `prototypes/onboarding-html-prototype/index.html`: load the helper before `app.js`.
- Modify `prototypes/onboarding-html-prototype/app.js`: helper integration, semantic targets, delegated interaction, and Guide Map outcomes.
- Modify `prototypes/onboarding-html-prototype/styles.css`: compact callout, button reset, connector tuning, reduced-motion pulse.
- Modify `prototypes/onboarding-html-prototype/NOTES.md`: prototype semantics and production-native handoff.

### Task 1: Shared guide-state contract

**Files:**
- Create: `prototypes/onboarding-html-prototype/guide-state.js`
- Create: `prototypes/onboarding-html-prototype/tests/guide-state.test.mjs`

**Interfaces:**
- Produces `globalThis.ChoraiGuideState` with `guideDefinitions`, `outcomeKey(guideId)`, `shouldRenderGuide(input)`, `transitionGuide(outcomes, event)`, and `renderGuideCallout(guideId)`.
- `shouldRenderGuide({ guideId, activeRoute, targetVisible, prerequisitesMet, outcomes })` returns `boolean`.
- `transitionGuide(outcomes, { type: "target" | "outside", guideId })` returns a new outcome record; an unknown guide or event returns the original record.

- [x] **Step 1: Write the failing behavior tests**

```js
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

async function loadGuideState() {
  const source = await readFile(new URL("../guide-state.js", import.meta.url), "utf8");
  const context = { globalThis: {} };
  vm.runInNewContext(source, context, { filename: "guide-state.js" });
  return context.globalThis.ChoraiGuideState;
}

test("shows a guide only for its matching eligible route until an outcome exists", async () => {
  const guideState = await loadGuideState();
  assert.equal(guideState.shouldRenderGuide({ guideId: "home", activeRoute: "home", targetVisible: true, prerequisitesMet: true, outcomes: {} }), true);
  assert.equal(guideState.shouldRenderGuide({ guideId: "home", activeRoute: "explore", targetVisible: true, prerequisitesMet: true, outcomes: {} }), false);
  assert.equal(guideState.shouldRenderGuide({ guideId: "home", activeRoute: "home", targetVisible: true, prerequisitesMet: true, outcomes: { [guideState.outcomeKey("home")]: "dismissed" } }), false);
});

test("records target activation as complete and outside interaction as dismissed", async () => {
  const guideState = await loadGuideState();
  assert.deepEqual(guideState.transitionGuide({}, { type: "target", guideId: "explore" }), { [guideState.outcomeKey("explore")]: "completed" });
  assert.deepEqual(guideState.transitionGuide({}, { type: "outside", guideId: "merge" }), { [guideState.outcomeKey("merge")]: "dismissed" });
});

test("does not create an outcome for an unsupported event", async () => {
  const guideState = await loadGuideState();
  const outcomes = { [guideState.outcomeKey("home")]: "completed" };
  assert.deepEqual(guideState.transitionGuide(outcomes, { type: "timer", guideId: "home" }), outcomes);
});

test("renders a single accessible sentence without a duplicate action", async () => {
  const guideState = await loadGuideState();
  const markup = guideState.renderGuideCallout("spark");
  assert.match(markup, /role="status"/);
  assert.match(markup, /aria-live="polite"/);
  assert.match(markup, /<p>Favorite a result to keep it\.<\/p>/);
  assert.equal((markup.match(/<p>/g) || []).length, 1);
  assert.doesNotMatch(markup, /<(button|small|span)\b/);
});

test("renders every approved callout sentence", async () => {
  const guideState = await loadGuideState();
  assert.match(guideState.renderGuideCallout("home"), /Tap \+ to capture your first note\./);
  assert.match(guideState.renderGuideCallout("explore"), /Tap Spark to continue from this card\./);
  assert.match(guideState.renderGuideCallout("spark"), /Favorite a result to keep it\./);
  assert.match(guideState.renderGuideCallout("merge"), /Merge two related notes\./);
});
```

- [x] **Step 2: Run the test to verify it fails**

Run: `node --test prototypes/onboarding-html-prototype/tests/guide-state.test.mjs`

Expected: FAIL because `guide-state.js` does not yet exist.

- [x] **Step 3: Implement the smallest helper**

```js
(function attachGuideState(global) {
  const GUIDE_VERSION = "v1";
  const guideDefinitions = Object.freeze({
    home: { copy: "Tap + to capture your first note.", className: "guide-home" },
    explore: { copy: "Tap Spark to continue from this card.", className: "guide-explore-spark" },
    spark: { copy: "Favorite a result to keep it.", className: "guide-spark-result" },
    merge: { copy: "Merge two related notes.", className: "guide-merge" },
  });
  const outcomeKey = (guideId) => `${guideId}:${GUIDE_VERSION}`;
  function shouldRenderGuide({ guideId, activeRoute, targetVisible, prerequisitesMet, outcomes }) {
    return Boolean(guideDefinitions[guideId] && activeRoute === guideId && targetVisible && prerequisitesMet && !outcomes[outcomeKey(guideId)]);
  }
  function transitionGuide(outcomes, { type, guideId }) {
    if (!guideDefinitions[guideId] || !["target", "outside"].includes(type)) return outcomes;
    return { ...outcomes, [outcomeKey(guideId)]: type === "target" ? "completed" : "dismissed" };
  }
  function renderGuideCallout(guideId) {
    const guide = guideDefinitions[guideId];
    return guide ? `<div class="guide-bubble ${guide.className}" data-guide-id="${guideId}" role="status" aria-live="polite"><p>${guide.copy}</p></div>` : "";
  }
  global.ChoraiGuideState = Object.freeze({ guideDefinitions, outcomeKey, shouldRenderGuide, transitionGuide, renderGuideCallout });
})(globalThis);
```

- [x] **Step 4: Run the helper test again**

Run: `node --test prototypes/onboarding-html-prototype/tests/guide-state.test.mjs`

Expected: PASS with all named behavior tests passing.

- [x] **Step 5: Commit the independently tested helper**

```bash
git add prototypes/onboarding-html-prototype/guide-state.js prototypes/onboarding-html-prototype/tests/guide-state.test.mjs
git commit -m "feat: add onboarding guide state helper"
```

### Task 2: Render approved callouts and make real targets control them

**Files:**
- Modify: `prototypes/onboarding-html-prototype/index.html:178`
- Modify: `prototypes/onboarding-html-prototype/app.js:1-515`
- Test: `prototypes/onboarding-html-prototype/tests/guide-state.test.mjs`

**Interfaces:**
- Consumes `globalThis.ChoraiGuideState` from Task 1.
- Adds `data-guide-target="home|explore|spark|merge"` to the four actual product-control buttons.
- Extends the helper with `resolveGuideInteraction({ phoneGuideId, targetGuideId, isCallout })`, returning `{ type, guideId }` or `null`.
- Adds `recordGuideOutcome(guideId, type)` and `guideMarkup(guideId, activeRoute)` using the Task 1 names exactly.

- [x] **Step 1: Write the failing interaction-routing test**

```js
test("routes target and outside taps but leaves a callout tap alone", async () => {
  const guideState = await loadGuideState();
  assert.deepEqual(guideState.resolveGuideInteraction({ phoneGuideId: "home", targetGuideId: "home", isCallout: false }), { type: "target", guideId: "home" });
  assert.deepEqual(guideState.resolveGuideInteraction({ phoneGuideId: "explore", targetGuideId: null, isCallout: false }), { type: "outside", guideId: "explore" });
  assert.equal(guideState.resolveGuideInteraction({ phoneGuideId: "spark", targetGuideId: null, isCallout: true }), null);
  assert.equal(guideState.resolveGuideInteraction({ phoneGuideId: null, targetGuideId: null, isCallout: false }), null);
});
```

- [x] **Step 2: Run the test to verify it fails**

Run: `node --test prototypes/onboarding-html-prototype/tests/guide-state.test.mjs`

Expected: FAIL because `resolveGuideInteraction` does not yet exist.

- [x] **Step 3: Integrate helper, target buttons, and interaction delegation**

Add this before `app.js` in `index.html`:

```html
<script src="guide-state.js"></script>
<script src="app.js"></script>
```

Add this layer in `app.js` after `currentRoute`:

```js
const guideState = globalThis.ChoraiGuideState;
let guideOutcomes = {};
function guideMarkup(guideId, activeRoute = guideId) {
  return guideState.shouldRenderGuide({ guideId, activeRoute, targetVisible: true, prerequisitesMet: true, outcomes: guideOutcomes })
    ? guideState.renderGuideCallout(guideId) : "";
}
function recordGuideOutcome(guideId, type) {
  guideOutcomes = guideState.transitionGuide(guideOutcomes, { guideId, type });
  document.querySelectorAll(`[data-guide-id="${guideId}"]`).forEach((callout) => callout.remove());
  document.querySelectorAll(`[data-guide-target="${guideId}"]`).forEach((target) => target.classList.remove("target-pulse"));
  if (currentRoute === guideId) setGuideRoute(currentRoute);
}
```

Replace guide blocks with `${guideMarkup("home")}`, `${guideMarkup("explore")}`, `${guideMarkup("spark")}`, and `${guideMarkup("merge")}`. Use these semantic targets:

```html
<button type="button" class="plus-target target-pulse" data-guide-target="home" aria-label="Create your first note">+</button>
<button type="button" class="spark-entry-target target-pulse" data-guide-target="explore" aria-label="Spark this card"><img src="${sparkIconPath}" alt="" /></button>
<button type="button" class="spark-favorite-target target-pulse" data-guide-target="spark" aria-label="Favorite this Spark result">♡ <b>Favorite</b></button>
<button type="button" class="faux-button dark-button merge-target target-pulse" data-guide-target="merge">Merge notes <span>→</span></button>
```

Add this helper function to `guide-state.js`:

```js
function resolveGuideInteraction({ phoneGuideId, targetGuideId, isCallout }) {
  if (targetGuideId) return { type: "target", guideId: targetGuideId };
  if (isCallout || !phoneGuideId) return null;
  return { type: "outside", guideId: phoneGuideId };
}
```

Expose it through `ChoraiGuideState`. Delegate clicks by passing the nearest phone callout id, target id, and whether the clicked element is inside a callout to `resolveGuideInteraction`; invoke `recordGuideOutcome` only when the helper returns an event. Escape uses `{ type: "outside", guideId: activeGuideId }`. Use the approved copy in `steps[*].guide` and `routeGuides[*].copy`. In `setGuideRoute`, render `guideOutcomes[guideState.outcomeKey(routeKey)] || "eligible"` as the logic status and distinguish target completion from silent dismissal in route exits.

- [x] **Step 4: Run behavior and syntax verification**

Run:

```bash
node --test prototypes/onboarding-html-prototype/tests/guide-state.test.mjs
node --check prototypes/onboarding-html-prototype/guide-state.js
node --check prototypes/onboarding-html-prototype/app.js
```

Expected: all tests pass and scripts parse without errors.

- [x] **Step 5: Commit interactive integration**

```bash
git add prototypes/onboarding-html-prototype/index.html prototypes/onboarding-html-prototype/app.js prototypes/onboarding-html-prototype/tests/guide-state.test.mjs
git commit -m "feat: make onboarding callouts interactive"
```

### Task 3: Polish, document the native boundary, and validate

**Files:**
- Modify: `prototypes/onboarding-html-prototype/styles.css:696-739,1026-1061,1478-1511,1819-1837,1853-1868,2052-2077,2949-2957`
- Modify: `prototypes/onboarding-html-prototype/NOTES.md:5-13`
- Test: `prototypes/onboarding-html-prototype/tests/guide-state.test.mjs`

**Interfaces:**
- Consumes `.guide-bubble`, `.target-pulse`, and semantic target buttons from Task 2.
- Produces compact text-only callouts, preserved connector relationships, and static targets under Reduced Motion.

- [x] **Step 1: Run the behavior suite as a CSS-change baseline**

Run: `node --test prototypes/onboarding-html-prototype/tests/guide-state.test.mjs`

Expected: PASS, proving the CSS-only change starts from the approved no-timer and interaction behavior.

- [x] **Step 2: Apply visual and documentation changes**

```css
.guide-bubble { padding: 9px 11px; border-radius: 12px; }
.guide-bubble p { margin: 0; font-size: 9px; line-height: 1.45; }
.plus-target, .spark-entry-target, .spark-favorite-target, .merge-target {
  appearance: none;
  cursor: pointer;
  font: inherit;
}
@media (prefers-reduced-motion: reduce) {
  .target-pulse::after { animation: none; }
}
```

Delete `.guide-bubble span` and `.guide-bubble small`. Tune only the four guide widths/offsets so each sentence stays within two lines and the existing connector does not overlap its target. Keep targets visually primary.

Add these Notes bullets:

```md
- Each contextual guide is one anchored sentence. Its real product target completes the guide; tapping elsewhere in the same phone silently dismisses it. Outcomes remain in memory for this throwaway prototype and reset after reload.
- The prototype announces guide copy with a live status message and supports Escape as a review aid. Production Swift still needs durable guide-version state plus the VoiceOver custom `Dismiss tip` action; an HTML prototype cannot truthfully expose that native action.
```

- [x] **Step 3: Run code and server verification**

Run:

```bash
node --test prototypes/onboarding-html-prototype/tests/guide-state.test.mjs
node --check prototypes/onboarding-html-prototype/guide-state.js
node --check prototypes/onboarding-html-prototype/app.js
curl --fail --silent --show-error http://127.0.0.1:4173/prototypes/onboarding-html-prototype/?variant=C > /dev/null
curl --fail --silent --show-error http://127.0.0.1:4173/prototypes/onboarding-html-prototype/guide-state.js > /dev/null
```

Expected: all tests pass, scripts parse, and both resources return HTTP 200.

- [x] **Step 4: Perform in-app-browser interaction and visual QA at 390-point width**

Use a fresh DOM snapshot before each action:

1. Home: click `Create your first note`; guide disappears and Guide Map status reads `completed`.
2. Explore: click a neutral phone area, not the callout or icon; guide disappears and status reads `dismissed`.
3. Spark: click Favorite; guide disappears without covering result content.
4. Merge: press Escape in the active Guide Map phone; guide disappears and no timer-driven outcome appears.
5. Enable Reduced Motion when available; pulse is absent but placement and copy stay unchanged.
6. Capture Home, Explore, Spark, and Merge screenshots. Confirm direct top-right Spark entry, no Spark tab, two-line maximum copy, connectors point to targets, and no visible acknowledgement control.

- [x] **Step 5: Commit visual handoff**

```bash
git add prototypes/onboarding-html-prototype/styles.css prototypes/onboarding-html-prototype/NOTES.md prototypes/onboarding-html-prototype/tests/guide-state.test.mjs
git commit -m "style: simplify mobile guide callouts"
```

## Plan Self-Review

- Spec coverage: Tasks 1–2 cover route/target/prerequisite gating, one-time outcomes, no timer, target completion, outside dismissal, callout no-op, approved copy, and direct product targets. Task 3 covers density, connector QA, Reduced Motion, contextual announcement, and the native VoiceOver boundary.
- Test quality: native tests run the actual helper and assert its observable state and rendered callout output; no test greps source or asserts mock behavior.
- Type consistency: `guideId`, `activeRoute`, `guideOutcomes`, `outcomeKey`, `shouldRenderGuide`, `transitionGuide`, and `renderGuideCallout` keep their Task 1 signatures throughout.
- Placeholder scan: no deferred implementation placeholders are present.
