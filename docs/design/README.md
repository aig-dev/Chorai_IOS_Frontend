# Chorai iOS frontend redesign archive

This directory preserves the design studies, clickable prototypes, native rollout
records, screenshots, and verification media created during the October–November
2026 frontend redesign. Historical alternatives are retained as alternatives;
their presence does not mean every proposal was adopted.

The current app implementation is in `ArcNote/`, `Packages/CoreFlow/`, and
`Packages/BlockNoteEditor/`. The body editor still uses BlockNote; its native
presentation changes preserve the existing content model and Web compatibility.

## Browse the work

| Archive | Contents |
| --- | --- |
| [Native visual reform](2026-10-21-native-visual-reform/) | Original warm-white/forest direction, color studies, offline share packages, Explore swipe/grid, card levels and brush revisions |
| [Native rollout](2026-10-26-native-rollout/) | Implementation plan, fidelity comparisons, native screenshots and validation |
| [Review fixes](2026-10-26-review-fixes/) | Follow-up visual review and interaction corrections |
| [Full native remediation](2026-10-27-full-native-remediation/) | Page audit, reader/editor surfaces, auxiliary pages and validation |
| [Spark and Chat alignment](2026-10-29-spark-chat-alignment/) | Root headers, Spark continuation/grid and Chat sizing |
| [Note actions](2026-10-29-note-actions-v2/) | Note details, contextual actions and gesture studies |
| [Entry, Chat and sidebar](2026-10-29-entry-chat-sidebar/) | Welcome/login alternatives, paired Chora empty state and sidebar refinement |
| [Minimal welcome study](2026-11-03-minimal-welcome/) | Preserved earlier direction and source snapshots |
| [Cosmos-inspired entry](2026-11-03-cosmos-entry/) | Welcome, sign-in and sign-up flow; native implementation and polish |

The [latest native entry comparison](2026-11-03-cosmos-entry/native/polish-v2/index.html)
shows actual simulator screenshots and recordings. It is a review page, not an
alternative authentication implementation. HTML previews can be served locally
from this repository; GitHub's file viewer does not execute their interactions.

## Submission verification · 2026-11-04

- CoreFlow: 880 tests passed, zero failures.
- BlockNoteEditor: 57 tests passed, zero failures.
- ArcNote / Debug: iOS Simulator build passed.
- ArcNote Production / Debug-Production: iOS Simulator build passed; not launched.
- Xcode 27.2 / 27B52; iPhone 17 Pro / iOS 26.5 Simulator destination.
- Package versions remain pinned; builds use external derived-data/scratch paths.
- The final requested welcome timing adjustment changes the normal transition
  from 0.42 to 0.58 seconds. Reduce Motion remains a 0.16-second opacity transition.

These are fresh package/build results for this submission. Earlier native UI
checks and manual flow evidence remain individually documented in the dated
validation files, including [entry QA](2026-11-03-cosmos-entry/native/polish-v2/QA.md).
They are not described as a new full UI-suite run for this submission. Offline
fixtures do not verify real OAuth, email delivery, backend availability or physical
device haptics.
