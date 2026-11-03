# Design QA · Cosmos entry prototype

Date: 2026-11-03. Scope: the independent browser prototype at <http://127.0.0.1:8771/>. Browser checks were performed by the coordinating agent; build and preservation checks were repeated independently. This record does not certify native implementation or live authentication.

Final result: passed for the independent prototype scope below. Native acceptance remains unperformed.

## Verified

- Sign Up: access-code gate, all account fields, complete successful flow, return navigation with values retained, email edits clearing the old code, 60-second resend countdown, password mismatch, final registration-code rejection and recovery.
- Interests: nine-item maximum, reset, selection continuation and skip.
- Sign In: email/password path, simulated offline error and access-required gate.
- Providers: Sign In → Apple preview → completion; Sign Up → access → email → Apple preview → interests. Provider sheets explicitly state that no provider is contacted.
- Appearance: light and dark; manual reduced-motion setting; no browser console errors observed during review.
- Final focus/geometry check: accessibility-based interaction through both provider paths kept `.device-screen.scrollTop` at `0` before and after transitions. Earlier Playwright clicking with a viewport override produced a tool-induced `320` offset; no runtime scrolling workaround was added. The later accessibility-based checks are the evidence for normal interaction.

## Build and preservation

| Check | Result |
|---|---|
| `npm run build` | Exit 0; TypeScript, Vite and Sites output completed |
| Protected mobile runtime | 28 / 28 SHA-256 hashes matched |
| `../native-before.json` | 415 / 415 hashes matched; 0 changed, 0 missing |
| `../previous-preview-before.json` | 61 / 61 hashes matched; 0 changed, 0 missing |

Source review found no P1 issue in the reviewed auth flow. Final registration rechecks access preflight, current-email/code association, code length and account fields. Simulated pending operations cancel on route changes, scenario changes and unmount. AuthFlow and Prototype contain no credential transmission, credential storage or credential logging calls.

## Visual comparison

The final `cosmos-comparison.jpg` was inspected against the safe source frames. The reference's centered small headings, large single-field input, keyboard-adjacent CTA, restrained rounded sign-in fields, and wrapping interest pills are preserved. Chorai keeps its warm-white / forest palette, existing Chora asset, Apple / Google entry methods and nine-interest limit. The email field sits higher to leave space for those existing providers; the interest taxonomy is illustrative and ungrouped rather than inventing the source app's taxonomy. Unselected pills use plus and selected pills use check. These are intentional adaptations, not pixel or timing parity claims.

No text/control overlap remained in the reviewed 393×852 phone canvas, the default fitted preview, light/dark provider sheets and auth screens. Dynamic Type, VoiceOver and actual hardware keyboard/safe-area behavior require native verification.

## Evidence and limits

Captures are in [../qa](../qa/): `intro.jpg`, `signin-light.jpg`, `signin-dark.jpg`, `signup-email-empty.jpg`, `signup-email.jpg`, `provider-dark.jpg`, `interests.jpg`, and `cosmos-comparison.jpg`. `interests-before.jpg` records the earlier state, not the final design.

The supplied videos inform visual sequence and motion only. Recorded durations and estimated transition timings are approximate observations, not Cosmos implementation specifications or a measured parity claim. No real account or autofill data is reproduced in the preview.

No native source implementation, native build, real account creation, real email delivery, provider authorization, backend persistence, audio or haptic validation was performed in this prototype round. Simulated keyboard behavior and browser screenshots do not establish iPhone accessibility, keyboard, performance or tactile behavior. Interests are illustrative preview data; legal sheets are labeled placeholders. No public deployment was performed.
