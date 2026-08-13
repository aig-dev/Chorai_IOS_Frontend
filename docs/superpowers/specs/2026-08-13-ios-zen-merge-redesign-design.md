# iOS Zen Merge Redesign

## Objective

Restore the original iPhone Merge hierarchy shown in the approved reference while using the current Merge v2 backend contract and the Web implementation as behavioral guidance. The result must feel quiet and direct: select cards, merge once, review the exact generated artifact, then discard or save.

This change is implemented directly on `main`. It does not modify the Web app, Go backend, or unrelated iOS flows.

## Source of truth

- Visual hierarchy: the supplied original iOS Merge reference.
- Merge lifecycle and artifact semantics: current Go Merge v2 endpoints and `merge_artifact.v2` / `card_doc.v1` contracts.
- Cross-platform behavior: the current Web background job, artifact preview, and exact commit flow.
- Rate palette: the backend share-render contract and Web `LiquidCard` mapping.
- Card content rendering: the current iOS Home/Favorite library-card components.

Where these sources differ, the latest backend contract controls data semantics, the original iOS reference controls mobile composition, and Zen principles remove redundant controls.

## Interaction model

### Selection

The screen has one navigation action, a centered `Merge` title, the fixed anchor card, a subtle divider, one always-visible search field, and the candidate-card list. There is no redundant search action in the navigation bar and no non-functional filter control.

The anchor is always the first selected source and cannot be deselected. Tapping a candidate card toggles it directly. Selection is communicated with a restrained accent border and compact checkmark; there is no separate checkbox row or secondary confirmation action.

A single wide floating pill sits above the safe area and reads `Merge N cards`, where `N` includes the anchor. It is disabled while only the anchor is selected and becomes active at two total sources, matching the backend minimum. The list receives enough bottom inset that no card content is obscured. The rejected `Selected notes` action bar and oversized icon button are removed.

### Generation

One tap creates the Merge v2 job. Creation, polling, and artifact loading happen automatically. The screen shows only a quiet `Weaving` state with subdued motion; it does not expose queue names, backend statuses, capability selection, or an extra “open preview” step.

Leaving an active job uses the existing cancellation protection only when data would otherwise be abandoned. Failures show one concise message and one primary `Retry` action; navigation back remains the escape route, so no extra cancel toolbar is added.

### Artifact review

When `ARTIFACT_READY` arrives, the exact server artifact appears in a centered glass panel over a dimmed Merge surface, preserving the original reference's visual language. This is the iPhone equivalent of the Web preview drawer, not a literal copy of the desktop layout.

The panel contains:

- `Merge preview` as interface chrome, not a persisted card title.
- A quiet `N sources → 1 card` context line.
- A scrollable, titleless rendering of the returned `card_doc.v1` blocks.
- Exactly two actions: `Discard` and `Save`.

There is no editable title, tag editor, rate selector, route/surprise badge, repeated source-card list, status ribbon, close button, or legacy `New Insight` / `Uncommon` content. Those elements either contradict the current titleless artifact contract or add an unnecessary action.

`Save` commits the exact previewed artifact through the existing idempotent Merge v2 commit path. During commit, both actions are disabled and the Save control shows progress in place. Success transitions directly to the new card detail; there is no intermediate success screen. `Discard` cancels the uncommitted job in one action and returns to selection.

## Card rendering and rate contract

Merge must not maintain a separate visual card system. Anchor and candidate cards reuse the same content preview, background-media handling, metadata, tags, corner radius, spacing, and readability policy used by Home/Favorite. Social metadata appears only when the source actually has an author.

The iOS library surfaces use one shared rate style with the canonical current mapping:

| Rate | Presentation | Canonical accent |
| --- | --- | --- |
| `1` | Neutral glass; no rate accent | none |
| `2` | Green ambient glow | `#00FF66` |
| `3` | Blue ambient glow | `#0371FF` |
| `4` | Purple ambient glow | `#9627D2` |
| `5` | Amber ambient glow | `#D97800` |
| `6` | Orange-red ambient glow | `#FF5E00` |

Unknown or legacy out-of-range values render as neutral glass rather than inventing a false tier. A custom background remains the main visual, with only a subtle canonical rate glow/border reflection so content stays legible. Merge, Home, and Favorite consume the same mapping so a card never changes identity between screens.

The card-detail response model must decode the backend `rate` field and pass it to the fixed anchor card. Candidate cards continue to use their returned `rate`, `content_json`, and `background_media_ref`. No code may hard-code the anchor to rate zero.

## Visual system

- Dark, low-chroma base with restrained purple/blue ambience.
- Glass communicates hierarchy; it is not applied as decoration to every element.
- System typography, semantic foreground opacity, and native safe-area behavior.
- Card content is the protagonist; interface labels are short and secondary.
- Minimum 44-point interactive targets.
- Calm ease-out transitions with no bounce; Reduce Motion removes positional animation.
- Reduce Transparency and Increased Contrast retain readable opaque surfaces and borders.
- Layout remains usable on the smallest supported iPhone and at accessibility text sizes.

## Architecture and data flow

`MergeSessionStore` remains the lifecycle authority: selection → create → poll → artifact → commit/cancel. The redesign changes projection and presentation only; it does not create a parallel merge state machine.

The iOS network model receives all current `CardDTO` fields required by presentation, especially `rate`. A small shared rate-style value maps the backend integer to a canonical semantic tier, and a shared SwiftUI library-card surface applies that tier consistently. Merge composes those existing primitives instead of copying Home card internals.

The artifact panel reads `MergeArtifact.document` directly. Commit continues to use the stored job/artifact revision and idempotency data already owned by the lifecycle layer. UI copy never exposes these implementation details.

## Error and edge behavior

- Fewer than two total sources: merge pill remains visible but disabled.
- Empty search result: concise empty state; anchor remains visible.
- Anchor fetch failure: concise unavailable state with retry, never a rate-zero placeholder.
- Generation or artifact-load failure: one message and one Retry action.
- Commit failure: preview stays visible and Save becomes retryable; artifact content is not discarded.
- Cancel/discard failure: preview remains visible with an inline error.
- Long artifacts: body scrolls inside a size-adaptive panel while actions remain reachable.
- Duplicate source IDs: existing ordering/deduplication remains authoritative.

## Verification

Automated verification must prove:

- Card detail decoding preserves rates `1...6`.
- Canonical rate mapping returns neutral for `1`/unknown and the five specified accents for `2...6`.
- The fixed anchor receives its decoded rate and candidates retain theirs.
- Selection count includes the anchor and Merge enables at two sources.
- Artifact review has only Discard and Save, uses the titleless server document, and commits through the current lifecycle store.
- Existing Merge v2 lifecycle, persistence, retry, cancellation, and exact-commit tests remain green.

Simulator visual QA must cover selection, selected state, at least three different rate tiers, custom-background readability, artifact preview, long content, a compact supported iPhone, and the normal target iPhone. At least one Reduce Motion/Reduce Transparency or Increased Contrast check is required. Screenshots are saved under `docs/qa/assets/ios-zen-merge-redesign/`, with a short QA record under `docs/qa/`.

Production validation includes the relevant CoreFlow tests, iOS source-contract tests, focused UI automation, and both ArcNote Debug and ArcNote Production simulator builds.

## Out of scope

- Backend or Web changes.
- Editing generated content before commit.
- Choosing merge capability, route, surprise kind, title, tags, or rate.
- A second card renderer dedicated to Merge.
- iPad-specific composition.
