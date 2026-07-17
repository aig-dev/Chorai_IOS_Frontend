# Native Editor Clear Glass Refinement

## Status

Design checkpoint for review before implementation planning.

## Context

The current iOS 26 editor writing plane uses `Glass.regular` over a nearly
uniform dark-purple page background. The embedded BlockNote canvas and its
`WKWebView` are already transparent, so they are not the source of the visible
gray fill.

`Glass.regular` intentionally raises luminance and suppresses background color
to preserve foreground readability. Across a large surface with no visual
variation behind it, that system treatment reads as an opaque gray card rather
than transparent glass. For image-backed notes, the current black readability
veil is also composited above the glass, which darkens the glass highlights and
further reduces perceived transparency.

## Goal

Make the editor body feel like text written on a thin, floating pane of native
Liquid Glass. The result must visibly transmit surrounding color and light,
avoid a uniform gray slab, and preserve text readability and accessibility.

## Scope

This refinement applies to the native iOS card editor:

- the full-page editor backdrop;
- the body writing plane;
- the image-background readability stack;
- the edge treatment of the writing plane;
- the shared glass helper needed to distinguish large content glass from
  compact interactive chrome.

The embedded BlockNote document model, editor commands, tags, image acquisition,
network behavior, and desktop/web editor remain unchanged.

## Visual Direction

### Large writing plane

On iOS 26 and later, the body writing plane uses `Glass.clear` with interactive
behavior. It must not add a gray, white, or card-colored fill above the system
glass.

The writing plane receives depth from the scene behind it, not from an opaque
tint. The page backdrop therefore adds restrained, broad ambient light fields:

- a soft violet light near the upper trailing area;
- a dim indigo-blue light crossing the lower leading area;
- the existing dark-purple base remains dominant.

The ambient lights must be visible outside the pane as part of one continuous
scene. They must not look like gradients painted inside the card.

### Compact chrome

Top controls and the keyboard formatting bar continue to use
`Glass.regular.interactive`. Their smaller size benefits from the stronger
material separation and they must remain visually distinct from the clearer
writing plane.

The shared glass component exposes an explicit semantic style rather than a
boolean or call-site-specific material override:

- `writingPlane` selects clear glass and the restrained pane edge;
- `chrome` selects regular interactive glass and the stronger compact-control
  edge.

### Edge and depth

The writing plane no longer uses a uniform white outline. Its edge is a subtle
directional highlight: brighter at the top and upper-leading edge, faint at the
bottom. A low-opacity shadow separates the pane from the page without turning
it into a conventional card.

No blur, tint, highlight, or shadow may intercept input or enter the
accessibility tree.

## Background Image Composition

The image-backed body stack is reordered to:

1. background image;
2. readability veil;
3. clear system glass;
4. directional edge highlight;
5. editor content.

The standard image veil target is approximately `0.22`, with implementation
tuning allowed between `0.18` and `0.26` based on simulator evidence. The veil
must sit below the glass so it does not suppress glass highlights.

Increase Contrast may use a stronger veil and edge. Reduce Transparency remains
an intentionally opaque fallback and does not attempt to simulate translucency.

## Compatibility and Accessibility

- iOS 26+: native clear glass for the writing plane and regular glass for
  compact chrome.
- iOS 16-25: an `ultraThinMaterial` fallback with the same ambient scene and
  directional edge hierarchy.
- Reduce Transparency: an opaque dark surface with sufficient text contrast.
- Increase Contrast: stronger edge and image veil without layout changes.
- Light and dark system appearances must keep the editor text and caret
  readable.
- Dynamic Type, VoiceOver order, selection, focus, scrolling, and keyboard
  behavior remain unchanged.

## Validation Strategy

### Source and unit contracts

- Prove the glass helper distinguishes `writingPlane` from `chrome`.
- Prove iOS 26 writing planes use `Glass.clear` while controls use
  `Glass.regular.interactive`.
- Prove the image veil is below the glass in source order and the standard veil
  is lower than the current `0.42` value.
- Prove the BlockNote and `WKWebView` transparency chain remains intact.

### Native visual fixtures

Capture the same simulator/device and viewport for:

- no-background editor in normal contrast;
- image-backed editor in normal contrast;
- no-background editor with Increase Contrast;
- no-background editor with Reduce Transparency when the setting can be
  controlled reliably;
- light and dark system appearances.

The before/after comparison is authoritative for the visual goal. Passing
source contracts alone is insufficient.

### Interaction regression

Re-run the focused native editor UI suite to ensure the glass re-layering does
not change hit targets, keyboard formatting, slash behavior, tag layout, image
source selection, or accessibility reading order.

## Acceptance Criteria

- The no-background writing plane visibly transmits non-uniform ambient color
  and no longer reads as a flat gray card.
- The body remains clearly legible and visually quieter than the compact
  controls.
- Image colors remain perceptible through the writing plane while white editor
  text remains readable.
- The writing plane has a directional glass edge rather than a uniform boxed
  outline.
- Reduce Transparency and Increase Contrast remain deliberate, readable states.
- The native simulator build and focused editor UI regressions pass.
- A fresh native simulator screenshot demonstrates the requested transparency
  improvement against the supplied gray reference.

## Non-goals

- No redesign of editor layout or metadata.
- No change to BlockNote document data or bridge protocol.
- No new background image behavior.
- No simulated glass inside the embedded web editor.
- No broad application-wide replacement of existing card materials.
