# Notes

This prototype answers one design question: **how can Chorai keep private-beta access intentional while making first use feel minimal and contextual?**

Current decision:

- The private-beta code is a one-time eligibility gate before account creation.
- Apple, Google, and email are all valid account-entry paths.
- The email path keeps `Get Code` to prove the address is reachable and keeps `Confirm password` to catch typing mistakes.
- The access code and email verification code must never appear as one combined registration concept.
- Registration layout is schematic: it inventories required elements, while implementation keeps the existing authentication-system composition.
- Spark is not a primary tab. The first Spark guide highlights the independent Spark icon at the top right of the active Explore card.
- Tapping that icon pushes the existing continuation experience: chain rail, source strip, and result deck.
- Each contextual guide is one anchored sentence. Its real product target completes the guide; tapping elsewhere in the same phone silently dismisses it. Outcomes remain in memory for this throwaway prototype and reset after reload.
- The prototype announces guide copy with a live status message and supports Escape as a review aid. Production Swift still needs durable guide-version state plus the VoiceOver custom `Dismiss tip` action; an HTML prototype cannot truthfully expose that native action.

Run locally:

```bash
python3 -m http.server 4173 --directory /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend
```

Then open `http://localhost:4173/prototypes/onboarding-html-prototype/?variant=A`.

The three variants are alternative ways to review the same recommended product flow, not three competing visual styles for the shipped app.
