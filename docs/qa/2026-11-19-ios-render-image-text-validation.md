# Home rendering, local thumbnails and HTML text

Scope: the three approved follow-up optimizations in the [plan](../superpowers/plans/2026-11-19-ios-render-image-text.md). Baseline is the uncommitted workspace captured before this iteration, not `HEAD`; prior execution/Merge/read changes and user xcuserdata remain intact. Swift 5 and iOS 16 remain the build contract. No API, storage schema, generated editor asset or production data change.

## Runtime evidence

1. **Home row:** a real `UIHostingController` mounts `NotesCard`. Changing unrelated manager loading/cards/favorite state caused one extra body evaluation before removal of its redundant observer (RED: total 2 → 3). The same run after removal adds zero evaluations; changing the card's own snapshot still updates it. This isolates that subscription, not all parent-list recomputation or total scroll cost.
2. **Images:** eight app tests use real local stores, attachment retention, file reads, integrity checks and UIKit thumbnails. They cover shared load/prepare with independent cancellation, warm identity reuse, pixel-size separation, body removal, trash, account changes during preparation, corrupted bytes, failure retry, memory warning, decoded-byte budget, LRU eviction and actual peak preparation ≤ 2 while canceled synchronous work remains blocked. A 40-request burst over a 500 KB published body cancels half its consumers and still performs one actual image read/preparation. CoreFlow tests prove that binding uses the published snapshot without another database hydration, keeps corruption checks in the bounded data stage, and computes/reuses remote reference hashes off main.
3. **Text:** golden cases preserve the existing case-sensitive tags, nested entity ordering, malformed tags, Markdown-as-text and Unicode/whitespace behavior. Five app tests exercise the real background cache, cancellation, input/session replacement, anonymous supplied snapshots, memory/byte limits and a hosted SwiftUI transition that clears previous text while new input is preparing. All nine existing renderer call sites now supply stable IDs; their fonts/colors/line limits stay unchanged.

The first focused run after all three changes passed **20 app tests** and **38 CoreFlow tests**. Final integrated results are recorded below when complete.

## Synthetic observations

Dedicated iPhone 17 Pro Simulator, iOS 26.2, Debug. Single cold run plus ten warm repetitions; generated content only, no timing threshold assertions. Values are observations, not device p95 or a performance SLA.

| Workload | Cold result | Warm mean | Actual repeated work |
| --- | ---: | ---: | --- |
| Local 4000 × 3000 image → 1024 × 768 thumbnail | 15.78 ms | 0.0325 ms | 1 verified image read and 1 preparation across 11 requests |
| Legacy HTML, 138,000 UTF-8 bytes | 42.26 ms | 0.0031 ms | 1 background parse across 11 requests |
| Unrelated Home manager state changes | — | — | 0 additional unchanged-row body evaluations |

The prepared image occupies 3,145,728 decoded bytes. This is the cached bitmap cost, not process peak memory. Thumbnail timing includes identity lookup and file verification on the cold path; warm requests still validate current scope and body. Fixture image creation, initial disk retention and HTML fixture construction occur before timing.

## Integrated verification

- Final full CoreFlow: **1056 tests, six live-API skips, zero failures**.
- Final app-hosted suite: **73/73 passed**, using `SWIFT_STRICT_CONCURRENCY=complete`. No diagnostic in the new production worker/reader/diagnostic types; existing Swift 6 migration warnings elsewhere remain.
- BlockNoteEditor: **76/76 passed**; its sources were not changed in this iteration.
- `ArcNote` and `ArcNote Production`: both simulator builds exited 0, with complete-concurrency checking. Production was built only, never launched or contacted.
- Initial simulator run: **6/7 passed** — editor related-note expansion, general onboarding, Dynamic Type chat attachments, linked-note selection, discovery path order/menu and public-profile navigation. Exported screenshots of large text and editor metadata were visually checked. The Trash case failed at the first delete-row lookup, before rendering any card: AX shows an empty local Trash. Its test and `TrashManager` are byte-identical to the baseline; generic dev-preview does not seed the current local Trash. This is an unexercised legacy fixture, not a passing deletion-flow check.
- Final image/onboarding simulator run: **2/2 passed** after review fixes. Combined with the first run, seven distinct affected flows pass; the empty-Trash fixture remains unexercised.
- Installed the final Local build, launched with no test arguments, terminated it and launched again. Both processes logged the compiled Local endpoint and expected port. Native Simulator control is unavailable (`Invalid app: Simulator`), so the literal Springboard icon tap was not verified; this is a no-argument process restart check.
- Go `make check-docs`: **22 module/history pairs, 104 Markdown files passed**. Changed iOS Markdown local links and `git diff --check` passed; the iOS repo has no `check-docs` target.

## Independent review and corrections

One fresh read-only reviewer checked the iteration diff and surrounding owners. Three Important findings were accepted and fixed in one pass:

1. Identity lookup was rehydrating a whole persisted note per caller before shared work. A runtime regression intentionally damages only the backing row; it failed at identity lookup before the fix. Binding now uses the published immutable snapshot, while the actual data stage still rejects the corrupt record.
2. Preview URL binding was hashing remote references on MainActor. The worker now owns lookup/URL assembly and a bounded lazy index. Runtime tests verify non-main hashing, reuse, server-ID replacement and no remote hash for an already-bound local attachment.
3. A tip-store dismissal left the first card's halo visible. A real hosted card reproduced `true` after dismissal. Small observed decorations now follow `true → false → true` across dismissal and a newly eligible session without changing the card.

Focused correction suites passed **25 CoreFlow and 10 app tests**, followed by the final full suites above. This was one independent review plus author fixes and regressions, not a second independent re-review. Reviewer exclusions (remote AsyncImage, persistence format, unrelated prior edits and simulator metadata) match the approved scope.

Evidence lives in `.superpowers/sdd/2026-11-19-ios-render-image-text/`, including RED/GREEN logs, xcresult summaries, diagnostics, baseline and review package. No commit or push was requested.

## Limits

- No physical-device sampling: frame rate, hitch distribution, energy, thermal behavior and process peak memory remain unmeasured.
- These changes remove demonstrated redundant work. They do not establish that all scrolling/rendering or networking bottlenecks are solved.
- Remote images retain the existing `AsyncImage` path. Cold HTML conversion is asynchronous; the view displays an empty prepared value until its current conversion finishes.
- Prior [execution](2026-11-19-ios-execution-validation.md) and [Merge/Home/read](2026-11-19-ios-merge-home-read-validation.md) limitations are unchanged unless explicitly covered here.
