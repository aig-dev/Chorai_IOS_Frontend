# iOS Keyboard Layout Stability Design

## Status

Implemented and verified. The user asked for an autonomous audit of every iOS
keyboard/editing surface and correction of screen-squeezing regressions.

## Problem

Before this change, the app mixed three incompatible keyboard strategies:

1. normal SwiftUI safe-area avoidance;
2. roots that ignore every safe-area region;
3. overlays that manually subtract a keyboard height from an absolute position.

The supplied Library screenshot is the visible consequence. Focusing the inline
search field causes UIKit to translate the SwiftUI hosting root upward to reveal
the first responder. The translation is outside SwiftUI's own global-coordinate
space, so an ordinary `GeometryReader` does not observe it. The whole Library
stack therefore moves until the search field intersects the status area. The
deterministic Library UI test confirmed the failure before any change:
`home.search.input` existed after focus but was no longer hittable.

This is not safely fixed with a hard-coded offset. Different input positions need
different policies.

## Design Choice

### Considered approaches

- Add a compensating offset to each failing field. This only matches one keyboard,
  device, and text size, and creates a second source of layout truth.
- Ignore the keyboard safe area at the application root. This stabilizes top
  searches but leaves chat composers, forms, and editor controls behind the
  keyboard.
- Apply a policy based on input role. This is selected: fixed top chrome is
  corrected against the measured hosting-root displacement, scrollable bodies
  absorb reduced height, bottom composers use native keyboard avoidance, and
  custom overlays use one avoidance mechanism only.

### Shared rules

- Decorative backgrounds may ignore the container safe area. Interactive roots
  do not inherit that behavior accidentally.
- Top-search roots use a shared stable viewport while search is focused. A tiny
  UIKit bridge measures the root's real screen-space top before and after keyboard
  presentation, then cancels only that measured upward translation. Their result
  list remains scrollable and dismisses the keyboard interactively; submitting
  search explicitly releases focus.
- Form screens use a fixed navigation header plus a scrollable body. No fixed
  full-screen `VStack` may depend on `Spacer` to remain usable while the keyboard
  is visible.
- Bottom composers rely on SwiftUI's keyboard safe area. The custom product tab
  bar is absent while a software keyboard is visible so it cannot consume the
  reduced viewport or appear above the keyboard.
- Keyboard-aware overlays either respect the keyboard-adjusted geometry or ignore
  it and apply measured overlap, never both. Screen-space keyboard frames are
  intersected with the live container; raw `keyboardFrame.height` and unexplained
  constants are forbidden.
- All vertical content scroll views use interactive keyboard dismissal where that
  does not conflict with the native rich-text editor's own gesture handling.

## Audited Input Inventory

| Family | Inputs | Policy |
| --- | --- | --- |
| Library | `HomeView` inline search | Stabilize the measured root origin; keep header pinned; submit clears focus. |
| Flow and Chat lists | `ExploreView`, `ChatView` search | Stabilize the measured root origin; explicit focus; submit/dismiss behavior; results scroll. |
| Chat detail | message composer and selected-card search | Native bottom avoidance; scroll dismissal; card picker stays within adjusted geometry. |
| Authentication | `SignInView`, `SignUpView` fields and verification code | Fixed header plus scrollable form; focused field and submit remain reachable. |
| Profile and sources | `EditProfileView`, `InvitationCreditView`, `ChoraProfileSections` fields | Retain existing scroll containers; add missing interactive dismissal only. |
| Reports | `ContentReportView` context editor | Fixed header plus scrollable form and submit action. |
| Merge | candidate search, artifact title, legacy insight editor/tag | Scrollable editing body; fixed chrome never shifts under status area. |
| Card editor | body WebView, tag input, inline-link sheet | Retain existing native editor safe-area inset and UI regression suite. |
| Comment overlay | comment composer | Remove raw keyboard-height positioning; anchor inside keyboard-adjusted container. |
| Link overlay | card search | Remove contradictory focus-then-end-editing behavior; size and position inside adjusted container. |
| Native sheets | inline URL/link fields | Retain native `Form` and sheet avoidance. |

## Shared Presentation State

`AdaptiveLayout.swift` owns a presentation-only keyboard observer because it
already owns live container and safe-area presentation rules. The observer exposes
only the current end frame, window intersection, and visibility. It contains no
form data and does not enter CoreFlow.

`KeyboardStableViewport` combines that state with a `UIViewRepresentable` probe.
The probe reads `convert(bounds, to: nil).minY`, which sees the hosting-root
translation that SwiftUI geometry misses. It records the resting top (clamped to
the window's top edge for compact-device launch quirks) and offsets content by the
exact measured displacement while an input is focused or a keyboard is present.
There are no device checks or keyboard-height constants.

`TabBarView` observes keyboard visibility to omit `CoreTabBar` while the keyboard
is present. Overlays lay out once inside keyboard-adjusted geometry rather than
subtracting a raw keyboard height or applying recursive UIKit inset mutations.

## Accessibility and Interaction

- Existing identifiers remain stable.
- Focused controls remain hittable and inside the application frame.
- Headers remain below the top safe region on Dynamic Island devices.
- Keyboard Search/Return releases focus when it commits an operation.
- Scroll gestures dismiss ordinary form/search keyboards interactively.
- No redundant keyboard-dismiss toolbar is added to the native editor.
- Existing 44-point hit targets and Dynamic Type behavior are preserved.

## Verification

The regression suite must prove behavior, not merely source shape:

- Library search header keeps the same top coordinate before and after focus and
  remains hittable while the keyboard is visible.
- Sign-in fields and submit action remain reachable on a short iPhone.
- Link and comment surfaces have source contracts forbidding double avoidance and
  compile in both application schemes; their live-data routes are not deterministic
  UI-test fixtures.
- Existing card-editor keyboard tests continue to pass.
- Focused UI tests run on iPhone 17 Pro and the short iPhone SE fixture.
- The 507-test CoreFlow suite, focused source contracts, Local and Production
  simulator builds, and `git diff --check` pass with fresh output.

## Acceptance Criteria

- No keyboard or editing interaction moves a top search/header into the status
  region or outside the screen.
- No custom tab bar floats above the keyboard.
- Every ordinary form can scroll its focused control and primary action into view.
- Chat/comment composers sit immediately above a docked keyboard without double
  spacing or double animation.
- Link/comment/card-selection overlays remain usable on compact and Dynamic Island
  iPhones and restore their original position after dismissal.
- No raw keyboard height, global screen bound, or per-device compensating offset is
  introduced.
