# Chorai iOS Onboarding HTML Prototype Plan

> This is a throwaway visual prototype. It does not change the production iOS flow.

## Goal

Make the proposed private-beta onboarding easy to judge before implementation:

- keep the private-beta access code as a separate gate;
- offer Apple, Google, and email as account-entry options;
- keep email `Get Code` strictly for address-validity verification;
- require password confirmation on the email registration path;
- treat the registration screen as an element inventory; production layout follows the existing authentication system;
- defer interests until after the first useful action;
- show guidance only for the page and target currently visible.
- introduce Spark from the independent Spark icon on the current Explore card, then show the existing continuation/result pattern.

## Views

1. **Flow board** — compare the complete seven-screen journey at once.
2. **Focused walkthrough** — inspect one screen and its product rationale at a time.
3. **Guide map** — verify route, target, copy, and prerequisites as a small state system.

## Interaction and verification

- Switch views through `?variant=A|B|C`, the bottom switcher, or arrow keys.
- In the focused walkthrough, step through screens with the on-canvas controls.
- Confirm that the account screen shows Apple, Google, and the complete email path without mixing the beta code into the form.
- Confirm that the main tabs read Explore, Home, and Chat; Spark must not appear as a tab.
- Confirm that the Explore Spark guide targets the independent top-right Spark icon rather than the ellipsis menu or the whole card.
- Confirm that the Spark screen uses a chain rail, source strip, and result deck instead of a prompt composer.
- In the guide map, select a route to confirm that its copy and target change together.
- Verify at desktop and narrow mobile widths; keep all controls keyboard accessible.
