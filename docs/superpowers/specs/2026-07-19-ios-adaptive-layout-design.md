# iPhone Adaptive Layout Design

## Status

Design checkpoint for the cross-screen iPhone layout correction requested on 2026-07-19. The work starts from the actual native app rather than treating the supplied simulator image as a single-screen defect.

## Context

The iOS target supports iPhone (`TARGETED_DEVICE_FAMILY = 1`) from iOS 16. The UI is composed from independently evolved SwiftUI screens and overlays. Several visual surfaces reach both physical edges of the screen, while others use unrelated fixed values. A source audit also found direct `UIScreen.main.bounds` reads in the chat detail, comment popup, link popup, search field, and side menu. Those global measurements are incorrect whenever a view is presented inside a sheet, navigation stack, safe area, keyboard-adjusted area, or future container.

The result is inconsistent gutters, panels that look pinned to the device frame, overlay heights that do not match their presenting surface, and controls whose available width changes unpredictably across small and large iPhones. The reference image is an example of that visual-boundary problem, not a reason to crop or mask a single page.

## Goals

- Make every iPhone-facing root screen, card, list, form, editor, and overlay use the same responsive visual-boundary rules.
- Keep decorative backgrounds full-bleed while keeping readable and interactive content inside device-safe, aesthetically balanced gutters.
- Derive popup, drawer, keyboard, chat-bubble, and modal geometry from the live parent container instead of `UIScreen.main.bounds`.
- Preserve existing product flows, API behavior, navigation, and liquid-glass visual language.
- Verify representative primary, settings, profile, editor, chat, and overlay routes on compact, standard, and large iPhone simulators.

## Non-goals

- No iPad, split-view, Mac Catalyst, or landscape redesign; the current app target is iPhone-only.
- No web, Go backend, or API contract change.
- No redesign of product information architecture, copy, colors, typography hierarchy, or business interactions.
- No arbitrary global maximum content width that would create empty side bands on wide iPhones.
- No change to the already responsive action-box design unless compatibility testing exposes a concrete defect.

## Visual Direction

The app continues to use its dark, glass-forward design. The scene background may extend under the status and home-indicator regions, but user-facing surfaces should not look glued to the physical bezel.

All standard screen content uses a shared horizontal gutter calculated from the live content width:

| Available width | Horizontal gutter |
| --- | ---: |
| `<= 375 pt` | `16 pt` |
| `376 ... 402 pt` | `20 pt` |
| `>= 403 pt` | `24 pt` |

The layout layer also exposes a continuous standard surface radius of `24 pt`, compact spacing of `12 pt`, regular spacing of `16 pt`, and a minimum `44 x 44 pt` interactive hit target. A screen may deliberately use a full-bleed canvas (for example, a writing plane or immersive media), but it must name that decision locally instead of inheriting it accidentally from a missing inset.

### Screen and Surface Rule

Each primary screen has two layers:

1. a full-frame background that may ignore safe areas;
2. a content layer that receives `AdaptiveLayoutMetrics` and applies the shared gutter before presenting lists, cards, forms, headers, and bottom controls.

An `AdaptiveScreen` root owns the geometry calculation and publishes its metrics through a SwiftUI environment value. A reusable `AdaptiveSurface` owns the rounded material/stroke/shadow treatment for standard glass cards. This keeps every view from restating a slightly different padding, radius, and screen-width condition.

### Responsive Geometry Rule

`AdaptiveLayoutMetrics` is calculated from the actual `GeometryReader` size and safe-area insets. It must be usable by all native SwiftUI views without consulting `UIScreen.main.bounds`.

- A sheet or popup uses its own `GeometryReader` size for height, width, position, and offscreen animation distance.
- The side menu uses the presenting container width and a bounded fraction that remains comfortable on compact and large phones.
- Chat bubbles and attached-note rows use the chat container width after accounting for their visible avatar and control columns.
- Search, forms, profile cards, settings rows, and generated card grids use the shared gutter or the container width passed by their parent.
- Keyboard-aware overlays calculate their visible bottom edge from their own safe-area and keyboard state; they never borrow a full-device height.

### Content Families Covered

The implementation applies the rule to these families rather than only the profile page:

- app shell, authentication, onboarding, library, explore, search, chat, notifications, trash, settings, preferences, account, and profile pages;
- note detail, discovery path, flow, merge, spark, compose, and native card-editor presentations;
- invitation, follow, block, Chora profile, and API/plugin administration pages;
- side drawer, action box, popup menu, comment composer, link picker, chat composer, and navigation overlays.

Some screens already have a component-specific adaptive layout, such as `ActionBoxView`. Those screens retain that local behavior and consume shared metrics only where it resolves a real surrounding boundary inconsistency.

## Accessibility and Dynamic Type

- Preserve Dynamic Type; never solve overflow by applying a global text scale transform.
- Header and action rows that can exceed their horizontal budget use flexible layout or `ViewThatFits`, with labels allowed to wrap where that is more legible than clipping.
- All tappable controls keep an effective hit target of at least `44 x 44 pt`.
- Decorative full-bleed layers remain hidden from the accessibility tree.
- Existing accessibility identifiers and VoiceOver labels remain stable. New identifiers are added only to root surfaces and fixture routes needed for deterministic layout tests.

## Architecture

### New App-Level Primitives

- `AdaptiveLayoutMetrics`: a small value type initialized from a container size and safe-area insets. It exposes `horizontalGutter`, `contentWidth`, standard spacing, surface radius, and a bounded drawer width.
- `AdaptiveLayoutReader`: a view wrapper that creates metrics from `GeometryReader` and publishes them in the SwiftUI environment.
- `AdaptiveScreen`: a root helper that places a full-frame background beneath a safe content layer without forcing the background padding onto the screen body.
- `AdaptiveSurface`: a visual modifier/view that standardizes the outer material, continuous corner radius, stroke, and content inset for ordinary glass cards.

These primitives remain in the ArcNote application target because they are presentation rules. CoreFlow remains focused on product state and API orchestration.

### Migration Strategy

Migrate roots in coherent families so each change is independently testable:

1. introduce metrics and validate their breakpoint behavior;
2. establish the app shell, reusable glass surface, and deterministic layout test route;
3. migrate navigation, library/discovery, profile, settings/account, and auxiliary data pages;
4. migrate editor, detail, flow, merge, spark, and creation flows;
5. replace all `UIScreen.main.bounds` calls in chat, side menu, search, comment, and link overlays with live geometry;
6. execute cross-device screenshot and UI-test regression coverage.

No screen should receive a blanket `.padding(.horizontal, 20)` if it is already inside an `AdaptiveScreen`; use a semantic `adaptiveContentGutter()` modifier or an explicitly passed metrics value so nested surfaces do not double-inset.

## Test Strategy

### Unit and Source Contracts

- Add pure unit coverage for the three gutter breakpoints, content width, safe-area preservation, and bounded side-drawer width.
- Add source contracts that require `AdaptiveScreen`/`AdaptiveLayoutReader` on migrated root screens and reject `UIScreen.main.bounds` from all native app sources.
- Verify `AdaptiveSurface` preserves its `24 pt` continuous radius and accepts the metrics-derived gutter instead of a hard-coded edge value.

### UI Tests

Use deterministic DEBUG fixture routes for layout states that do not require a live backend. At minimum, launch compact and large fixtures for the app shell, profile/settings card surface, card editor, side menu, comment popup, and link popup. Assert that each root surface exists, is hittable where appropriate, and its frame stays inside the window’s safe visual boundary rather than touching both horizontal edges.

### Simulator Matrix

Run focused checks on these booted simulator classes:

| Device class | Purpose |
| --- | --- |
| iPhone SE (3rd generation) | compact width and short vertical budget |
| iPhone 16e | current standard width baseline |
| iPhone 17 Pro | modern standard device and Dynamic Island safe area |
| iPhone 17 Pro Max | largest supported iPhone width and bottom safe area |

Take before/after screenshots for representative main, profile/settings, editor, chat/drawer, and modal states. Inspect them for full-frame backgrounds, balanced gutters, non-clipped controls, contained glass cards, and safe bottom controls.

## Acceptance Criteria

- Every root screen family uses the shared responsive boundary system or documents its intentional full-bleed canvas behavior.
- Standard cards, lists, profile panels, settings forms, and modal surfaces are visually inset by `16`, `20`, or `24 pt` according to the current container width and never unintentionally touch both physical edges.
- Decorative backgrounds can still cover the entire screen under the status and home-indicator areas.
- No production source in `ArcNote/` reads `UIScreen.main.bounds` for layout.
- Side menus, comment popups, link popups, chat bubbles, and search geometry remain inside their parent container at compact and large widths.
- Dynamic Type keeps controls readable and at least `44 x 44 pt` tappable without horizontal clipping in the covered header/action rows.
- The app builds successfully and focused CoreFlow/source-contract/UI tests pass.
- Simulator screenshots on SE, 16e, 17 Pro, and 17 Pro Max show consistent visual gutters, rounded surfaces, safe-area alignment, and no new overlap or clipping in representative screens.
