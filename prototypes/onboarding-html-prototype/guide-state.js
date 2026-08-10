(function attachGuideState(global) {
  const GUIDE_VERSION = "v1";

  const guideDefinitions = Object.freeze({
    home: Object.freeze({
      copy: "Tap + to capture your first note.",
      className: "guide-home",
    }),
    explore: Object.freeze({
      copy: "Tap Spark to continue from this card.",
      className: "guide-explore-spark",
    }),
    spark: Object.freeze({
      copy: "Favorite a result to keep it.",
      className: "guide-spark-result",
    }),
    merge: Object.freeze({
      copy: "Merge two related notes.",
      className: "guide-merge",
    }),
  });

  const outcomeKey = (guideId) => `${guideId}:${GUIDE_VERSION}`;

  function shouldRenderGuide({ guideId, activeRoute, targetVisible, prerequisitesMet, outcomes }) {
    return Boolean(
      guideDefinitions[guideId] &&
        activeRoute === guideId &&
        targetVisible &&
        prerequisitesMet &&
        !outcomes[outcomeKey(guideId)],
    );
  }

  function transitionGuide(outcomes, { type, guideId }) {
    if (!guideDefinitions[guideId] || !["target", "outside"].includes(type)) return outcomes;

    return {
      ...outcomes,
      [outcomeKey(guideId)]: type === "target" ? "completed" : "dismissed",
    };
  }

  function renderGuideCallout(guideId) {
    const guide = guideDefinitions[guideId];
    if (!guide) return "";

    return `<div class="guide-bubble ${guide.className}" data-guide-id="${guideId}" role="status" aria-live="polite"><p>${guide.copy}</p></div>`;
  }

  global.ChoraiGuideState = Object.freeze({
    guideDefinitions,
    outcomeKey,
    shouldRenderGuide,
    transitionGuide,
    renderGuideCallout,
  });
})(globalThis);
