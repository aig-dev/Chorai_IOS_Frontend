# Native entry polish · iteration 2

User request: refine the landing page and the UX/visual finish of every authentication step, with several iterations, continuing the supplied Cosmos direction. This is authorized native implementation, not a new feature or authentication architecture project.

## Design decisions

Keep the calm centered composition and small fixed-position introduction CTA. Refine the existing visual sequence instead of replacing it with an unrelated hero. Preserve the warm-white/ink-green identity, a restrained gold accent, the existing Chora assets, current fields and service contracts. All prior designs stay saved.

Three passes:

1. **Composition and interaction:** tighten the relationship between intro image, caption and note; consistent title/body hierarchy; clear pressed and focused states; remove focus-triggered field jumps; make errors visible and actionable.
2. **Full native journey:** inspect intro forward/back, sign-in, access gate, each signup field, recovery, interest selection and skip. Fix identified problems and run meaningful UI regressions.
3. **Finish and accessibility:** inspect light/dark, keyboard-visible layouts, large text and reduced effects. Rebuild both schemes and retain actual simulator captures and exact limitations.

## Completion evidence required

- Refined welcome and all entry steps run in the native app, with saved before/after evidence.
- Existing email/provider authentication contracts, Product Access gate, legal links, verification resend interval, selection limit and cancellation protections remain intact.
- Keyboard/CTA, back navigation, focused fields, pending/error/recovery states verified by meaningful native tests and manual inspection.
- Local and Production simulator builds succeed; no Production launch or real account operation.
- Multiple documented observation/change/recheck passes, with remaining physical-device or live-service limitations stated separately.
