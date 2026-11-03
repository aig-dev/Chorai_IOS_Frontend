# Chorai entry · Cosmos reference

Date: 2026-11-03. Latest user direction: imitate both supplied Cosmos recordings for the entire Sign In and Sign Up process, including animation and keyboard behavior. The former three-beat welcome is abandoned and preserved separately.

## References
Clip A is 81.65s: content introduction, account creation, interest selection, arrival. Clip B is 40.36s: short brand startup, sign-in entry and existing-account login. Frame extraction is local read-only; real autofill and account data are not copied into the prototype or shared review assets.

## Scope
Independent full interactive prototype, including success and failure branches. Existing native contracts determine fields and gates. No live authentication, account creation, production requests, or native code modification in this design round.

## Flow
- Short startup: small Chora appears centrally once, wordmark stays at bottom. About1s then task. No kinetic wordmark or unobserved sound/haptic claim.
- First entry: 3 content-led intro screens; Next keeps bottom position while artwork moves vertically, text crossfades. Explore, notes, Spark use existing product content. Log In is always reachable.
- Sign In: centered small title, two quiet outlined fields, Email/Password, Apple/Google, CTA anchored above keyboard. Loading, rejection, connectivity failure, access-required branch.
- Sign Up: access-code preflight -> email/send code -> 6character code -> username -> password -> confirmation/create -> interest selection or Skip -> review completion checkpoint. Preserve field values on back. Edited email invalidates previous code. No separate verification-success claim before registration.
- Existing validators: access code9–64 chars; username>=2; email regex; code exactly6chars; password>=8 withletter+number; confirmationmatch. Interest1–9 forNext, Skip allowed, Reset available. No phone, gender, birthday or password-reset function added.
- Google/Apple signup preserve the access gate. Legal links remain accessible as explicitly labeled preview sheets.

## Motion
One task per screen; slim progress header; native simulated keyboard and bottom CTA move together. Text and body use short fade/translation, loading lives in CTA. Navigation can reverse without wiping input. Reduced motion removes app-level displacement; protected keyboard remains runtime-owned. Reference motion timings are estimates from recorded frames, not Cosmos internal specs.

## Review controls
Outside the phone: replay intro/returning startup, jump Sign In/Sign Up, light/dark, reduce motion, success/rejected/offline/access-required scenarios. All values are dummy local inputs; outcomes visibly marked simulated. External labels never become product features.
