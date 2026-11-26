# Ordinary full-document cross-client qualification

2026-11-27. This qualifies one retained ordinary NOTE flow against the task's isolated prod protocol 3 API. It does not complete R3, retained Merge integration, performance sampling or target-environment qualification.

## Flow and assertions

The shared editor_first_release_v1.json fixture has SHA256 aa4295a05d16e57470d9a0c1f793c58d9aefd0a4982eaadc8edbc63dbd30a760. An ordinary owner creates one private note through the public API. Web edits the first paragraph and reopens it. The native Library retrieves that same asset, appends text using the actual keyboard, saves, reopens and checks the full document. Web finally reopens the native result and closes without writing. Explicit title, tags, privacy, block IDs/order/nesting, styles, links, envelope and media identity remain intact. Plaintext fallback is checked separately from structured JSON.

The new opt-in test is testOrdinaryCrossClientDocumentEditsAndReopensWithoutLoss in ArcNoteUITests.swift. CHORAI_UI_TEST_CROSS_CLIENT_FIXTURE must name an explicit private fixture bound to the current ordinary actor, local API origin, exact asset and starting sync token. Missing configuration skips the test and is not passing release evidence. The normal signed app uses existing login/sync/editor paths; no application product seam or bridge change was added. The external harness owns the same asset and cleanup across both clients.

Final native attempt 4 passed one test with zero failures/skips. Two unique conditional PUTs were checked against their exact request keys, response receipts and chained versions; final GET matched the last receipt. The image uses its actual accessible name inside the body WebView. Its complete frame must lie within the visible body viewport, be hittable and have nontrivial dimensions. Authenticated image bytes match the fixture digest. Both body and image screenshots were inspected, with the full image visible. A normal signed build-for-testing and the existing first-party concurrency diagnostics check passed; Swift 6 and complete checking remain unchanged. The generated editor resource hash remains 67008dc79f286383f91e8f87ff788f1a3b0a8cf8a65d6241614f94a8f7d47f71.

## Corrections and limits

Earlier native attempts are retained as failures: image caption was mistaken for the accessible filename; a shared proxy record list included GETs in a mutation-only assertion. Attempt 3 passed XCTest but did not qualify visually because hittability alone allowed an offscreen image. The final test asserts full viewport containment and verifies the actual screenshot. These attempts are not erased or counted as final passing evidence.

Go corrected the product representation of empty image content without rewriting immutable history. Web corrected synthetic trailing paragraphs and content-free editability updates being treated as edits; the latter now uses a removable onChange subscription and checks actual block changes. Final Web return sent zero document writes and preserved the exact native token, history version and all saved fields. Server and Web implementation details and cleanup receipts belong to Go docs/evidence/2026-11-27-cross-client-note.md and Web docs/first-release-editor.md.

The task-created fixture is erased only after the final Web qualification, using its original frozen commands. The original permanent-delete operation returned PENDING twice and COMPLETE on the third attempt; the fixture detail and authenticated image both returned 404. The owning Go evidence records the exact receipt sequence. No previous account data or unrelated notes are part of this fixture.
