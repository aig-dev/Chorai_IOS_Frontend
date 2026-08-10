# iOS Mobile Guide Callouts Design

## Outcome

Chorai's contextual iOS onboarding uses a single anchored micro-callout instead of a miniature dialog. Each guide contains one action-led sentence, never an acknowledgement button such as `Got it` or `Try Spark`. The real product control is the primary call to action: activating it completes the guide, while tapping outside the callout dismisses the guide without performing the action.

## Options considered

1. Use an anchored one-sentence micro-callout with no title and no secondary button. **Selected.** It keeps the target and instruction visually connected without creating a competing action.
2. Keep a small context title above one sentence, but remove the button. This preserves labels such as `FIRST VISIT`, but adds height without improving the immediate action.
3. Use only a spotlight and a very short label. This is visually lighter, but makes the relationship between the target and its outcome less explicit and increases accessibility risk.

## Visual and copy system

- A guide has one visual layer: a compact anchored callout with one sentence and its existing connector line.
- Remove guide titles such as `FIRST VISIT`, `SPARK FROM THIS CARD`, and `KEEP THE USEFUL ONES` from the phone UI.
- Remove acknowledgement or duplicate-action labels such as `Got it`, `Try Spark`, and `Try it`.
- Keep copy in sentence case, start with a concrete action, name the visible target when necessary, and describe only the immediate outcome.
- Copy must fit within two lines at standard iPhone widths. It must not shrink below the product's normal secondary-text size to make it fit.
- The target pulse remains the only animated emphasis. The callout does not add decorative motion.
- Approved prototype copy:
  - Home: `Tap + to capture your first note.`
  - Explore Spark entry: `Tap Spark to continue from this card.`
  - Spark result: `Favorite a result to keep it.`
  - Merge-ready state: `Merge two related notes.`

## Interaction and state

- A guide renders only when its route matches, its target is visible, and its prerequisites are satisfied.
- Only one guide may be visible at a time.
- Activating the highlighted target marks the guide complete and continues the product action.
- Tapping outside the callout and outside the highlighted target silently dismisses that guide.
- Dismissal is one-time for the current guide version; the same guide does not reappear on later visits unless its version changes.
- Changing route or removing the target hides the guide immediately.
- Guides never disappear on a timer. Users must have enough time to read, dismiss, or act.
- Tapping the callout itself has no action and must not block the highlighted target.

## Accessibility

- The highlighted product control retains its native minimum 44-point hit area and its existing VoiceOver label.
- The callout is announced once as contextual help and does not take over focus or create a modal focus trap.
- VoiceOver exposes a nonvisual `Dismiss tip` accessibility action even though no visible close button is shown.
- Outside-tap dismissal is an additional convenience, not the only accessible dismissal mechanism.
- Reduced Motion disables or simplifies the target pulse without changing guide visibility or meaning.
- No essential state change depends on an automatic timeout.

## Scope

- Update the throwaway HTML prototype first so the wording, density, connector placement, and state rules can be reviewed together.
- Production Swift implementation is a separate follow-up and must reuse the current onboarding state model and real target controls.
- This change does not alter invitation, registration, Spark navigation, tab structure, or Merge eligibility.

## Verification

- Confirm every phone guide contains exactly one sentence and no visible acknowledgement or close control.
- Confirm Home, Explore, Spark result, and Merge copy each fit within two lines at 390-point width without overlapping the target or primary content.
- Confirm the real target remains visually dominant and at least 44 points in production.
- Confirm target activation completes the guide, outside tap dismisses it, route change hides it, and no timer removes it.
- Confirm VoiceOver can hear the guide, activate the target, and invoke `Dismiss tip` without a visible button.
- Confirm Reduced Motion removes nonessential pulsing while preserving the anchored relationship.
