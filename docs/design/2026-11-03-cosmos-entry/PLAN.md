# Cosmos-style complete authentication prototype implementation plan

**Goal:** Make both full auth journeys reviewable with Cosmos reference choreography and Chorai contracts.
**Architecture:** Isolated Product Design mobile runtime. Root owns startup, introduction and external review controls; AuthFlow owns the local state machine and form routes. No networking or native mutations.
**Stack:** React, TypeScript, Motion, protected mobile runtime, local assets.

**Status:** Complete for the independent prototype and its review evidence only. Native implementation and live service integration are outside this plan.

- [x] Inspect both videos, current native contracts and protected runtime.
- [x] Preserve previous preview and native baseline; create independent project.
- [x] Implement intro/startup and review controls in src/Prototype.tsx + src/prototype.css.
- [x] Implement full auth state machine in src/AuthFlow.tsx + src/auth.css, including back, field retention, local demo loading/error, resend cooldown and interests.
- [x] Build and run runtime integrity check. Review privacy, unsupported features and contract boundaries.
- [x] Exercise full successful signup, login, validation and retry, access gate, keyboard attach, back and reduced motion in browser. Compare visual captures with supplied source frames.
- [x] Save QA evidence, verify hashes, and prepare the running local preview and direct review links in README.md.

Verification: build passed; protected runtime 28/28, native baseline 415/415 and previous preview 61/61 hashes matched. Browser results and limits are recorded in prototype/design-qa.md. This does not claim live authentication, native sound or haptic implementation, or product acceptance.

No new auth methods, API changes, branch changes, commits or production calls.
