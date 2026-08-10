import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

async function loadGuideState() {
  const source = await readFile(new URL("../guide-state.js", import.meta.url), "utf8").catch(
    () => "globalThis.ChoraiGuideState = {};",
  );
  const context = { globalThis: {} };
  vm.runInNewContext(source, context, { filename: "guide-state.js" });
  return context.globalThis.ChoraiGuideState;
}

function getFunction(guideState, name) {
  assert.equal(typeof guideState[name], "function", `${name} is exposed by ChoraiGuideState`);
  return guideState[name];
}

test("shows a guide only for its matching eligible route", async () => {
  const guideState = await loadGuideState();
  const shouldRenderGuide = getFunction(guideState, "shouldRenderGuide");

  assert.equal(
    shouldRenderGuide({
      guideId: "home",
      activeRoute: "home",
      targetVisible: true,
      prerequisitesMet: true,
      outcomes: {},
    }),
    true,
  );
  assert.equal(
    shouldRenderGuide({
      guideId: "home",
      activeRoute: "explore",
      targetVisible: true,
      prerequisitesMet: true,
      outcomes: {},
    }),
    false,
  );
  assert.equal(
    shouldRenderGuide({
      guideId: "home",
      activeRoute: "home",
      targetVisible: false,
      prerequisitesMet: true,
      outcomes: {},
    }),
    false,
  );
  assert.equal(
    shouldRenderGuide({
      guideId: "home",
      activeRoute: "home",
      targetVisible: true,
      prerequisitesMet: false,
      outcomes: {},
    }),
    false,
  );
});

test("hides a guide after its current guide version has an outcome", async () => {
  const guideState = await loadGuideState();
  const outcomeKey = getFunction(guideState, "outcomeKey");
  const shouldRenderGuide = getFunction(guideState, "shouldRenderGuide");

  assert.equal(
    shouldRenderGuide({
      guideId: "home",
      activeRoute: "home",
      targetVisible: true,
      prerequisitesMet: true,
      outcomes: { [outcomeKey("home")]: "dismissed" },
    }),
    false,
  );
});

test("removes target emphasis once a guide has an outcome", async () => {
  const guideState = await loadGuideState();
  const outcomeKey = getFunction(guideState, "outcomeKey");
  const targetPulseClass = getFunction(guideState, "targetPulseClass");
  const eligibleInput = {
    guideId: "home",
    activeRoute: "home",
    targetVisible: true,
    prerequisitesMet: true,
    outcomes: {},
  };

  assert.equal(targetPulseClass(eligibleInput), "target-pulse");
  assert.equal(
    targetPulseClass({
      ...eligibleInput,
      outcomes: { [outcomeKey("home")]: "completed" },
    }),
    "",
  );
});

test("records target activation as completed", async () => {
  const guideState = await loadGuideState();
  const outcomeKey = getFunction(guideState, "outcomeKey");
  const transitionGuide = getFunction(guideState, "transitionGuide");

  const outcomes = transitionGuide({}, { type: "target", guideId: "explore" });

  assert.equal(outcomes[outcomeKey("explore")], "completed");
  assert.equal(Object.keys(outcomes).length, 1);
});

test("records outside interaction as dismissed and never creates a timer outcome", async () => {
  const guideState = await loadGuideState();
  const outcomeKey = getFunction(guideState, "outcomeKey");
  const transitionGuide = getFunction(guideState, "transitionGuide");

  const dismissed = transitionGuide({}, { type: "outside", guideId: "merge" });
  assert.equal(dismissed[outcomeKey("merge")], "dismissed");

  const retained = transitionGuide(dismissed, { type: "timer", guideId: "merge" });
  assert.equal(retained, dismissed);
});

test("renders every approved sentence as one accessible callout without duplicate actions", async () => {
  const guideState = await loadGuideState();
  const renderGuideCallout = getFunction(guideState, "renderGuideCallout");
  const expectedCopy = {
    home: "Tap + to capture your first note.",
    explore: "Tap Spark to continue from this card.",
    spark: "Favorite a result to keep it.",
    merge: "Merge two related notes.",
  };

  for (const [guideId, copy] of Object.entries(expectedCopy)) {
    const markup = renderGuideCallout(guideId);
    assert.match(markup, /role="status"/);
    assert.match(markup, /aria-live="polite"/);
    assert.match(markup, new RegExp(`<p>${copy.replace(/[+.]/g, "\\$&")}<\\/p>`));
    assert.equal((markup.match(/<p>/g) || []).length, 1);
    assert.doesNotMatch(markup, /<(button|small|span)\b/);
  }
});

test("routes a target and outside tap without making the callout itself actionable", async () => {
  const guideState = await loadGuideState();
  const resolveGuideInteraction = getFunction(guideState, "resolveGuideInteraction");

  const targetAction = resolveGuideInteraction({
    phoneGuideId: "home",
    targetGuideId: "home",
    isCallout: false,
  });
  assert.equal(targetAction.type, "target");
  assert.equal(targetAction.guideId, "home");

  const outsideAction = resolveGuideInteraction({
    phoneGuideId: "explore",
    targetGuideId: null,
    isCallout: false,
  });
  assert.equal(outsideAction.type, "outside");
  assert.equal(outsideAction.guideId, "explore");
  assert.equal(
    resolveGuideInteraction({
      phoneGuideId: "spark",
      targetGuideId: null,
      isCallout: true,
    }),
    null,
  );
  assert.equal(
    resolveGuideInteraction({
      phoneGuideId: null,
      targetGuideId: null,
      isCallout: false,
    }),
    null,
  );
});
