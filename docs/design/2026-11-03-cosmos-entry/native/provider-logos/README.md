# Authentication provider logos

Google and Apple marks are included in the shared native `AuthProviderButtons`, used by both sign-in and sign-up. Existing button actions, labels, and accessibility identifiers are preserved. The subsequent entry-polish pass uses a 48-point minimum height.

- Google: official SVG from https://www.gstatic.com/images/branding/productlogos/googleg_gradient/v1/192px.svg, preserved in the asset catalog with original rendering. The supplied SVG uses a vector clipping contour and an embedded gradient image; it is not entirely path-only artwork.
- Apple: the SDK-provided `apple.logo` SF Symbol, using semantic primary color (black in light mode, white in dark mode).
- Both marks fit a 20-point square with 10-point spacing before the label.

## Verification on 2026-11-03

- ArcNote Local Debug simulator build: passed. Log: `/tmp/chorai-provider-logos-local.log`.
- ArcNote Production simulator build: passed. Log: `/tmp/chorai-provider-logos-production.log`.
- Device Hub, iPhone 17 Pro / iOS 26.5: manually checked sign-in in light and dark appearance, and sign-up in light appearance.
- Used only the existing offline authentication fixture. No real Google or Apple authentication was submitted.
- `git diff --check`: passed. No new automated tests were added for this presentation-only change.

`AuthEntryComponents.before.swift` preserves the component immediately before adding the logos. Screenshots in this folder are actual Device Hub captures; earlier auth design and capture folders remain intact.
