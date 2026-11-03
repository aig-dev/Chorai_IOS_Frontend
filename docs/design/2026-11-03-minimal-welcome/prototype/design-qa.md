# Minimal welcome review · 2026-11-03

## Target and boundaries
The latest user brief is the target: a simple title reveal followed by Chora. The earlier curious-paper composition is rejected for this version, so it is not a pixel-fidelity target. This is an independent browser motion study, not native authentication implementation. The generated transparent mascot uses the existing Almond identity as reference and remains review art.

## Result
- Main visual contains only the chorai wordmark and one complete Chora; quiet existing Login / Join Private Beta footer.
- Three fixed-position wordmark segments, then Chora, ending at 1.66 seconds. No loop or floating ornaments.
- Warm white / forest ink and charcoal / pale green both inspected in the browser. Character loaded at 1254 × 1254, displayed in a 144-point frame.
- Local fonts and original three-beat audio; no external service request from the prototype.
- Native production source and prior review images remain unchanged.

## Validation performed
- TypeScript + Vite build passed. Protected mobile runtime integrity: 28/28.
- Browser: title, mascot, and both footer actions visible; no broken image.
- Sound replay observed in playing state. Navigating to Login during replay switched audio state to silent.
- Login, email field interaction, non-submitting preview notice, Back, and Private Beta route checked.
- Returning from Login leaves one review-control owner, count = 1.
- Reduced-motion mode displays the settled image and disables sound replay; navigation remains usable. This controls opening and route transitions, not the shared simulated keyboard.
- Light and dark settled screenshots saved in ../qa/.
- Browser console: no error reported in final check. Motion's informational reduced-motion warning was expected while exercising that mode.
- A code-reviewed fix settles the initial frame when the page starts hidden; that initial-background edge was not separately exercised in the browser.
- SHA-256 preservation: 415/415 native baseline entries and 8/8 historical auth PNGs exactly matched, with zero missing/changed files.

## Evidence and limits
See ../qa/welcome-light.jpg and ../qa/welcome-dark.jpg. Browser audio decoding / playing / cancellation was checked; subjective loudness and physical audio output were not measured. Browser preview provides no real iPhone haptics. Native timing, sound policy, Dynamic Type / VoiceOver and physical haptics require a later device implementation and review. No login, access-code verification, account creation or backend readiness is claimed.

Live preview: http://127.0.0.1:8770/
Restart: run npm run dev -- --host 127.0.0.1 --port 8770 --strictPort from this directory.
