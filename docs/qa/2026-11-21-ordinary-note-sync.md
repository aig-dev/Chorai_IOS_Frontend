# Ordinary-account note sync checkpoint

2026-11-21, Swift 6.4.2, CoreFlow at `1530f29` plus this test-only change. The isolated Go runtime uses protocol 3 and qualified, separate history/staging storage. Its production enablement remains open.

Two ordinary accounts were created through canonical Campaign admission and phone registration, with `allowed/product_full` and no administrator scope. This does not validate native email signup or external OAuth. Tokens remain in the task-owned private directory.

The M2 persisted-transient test now creates its own interruption: image upload succeeds, the test transport fails before the first body transmission, SQLite closes and reopens, and recovery sends the same operation ID and frozen request. It verifies one upload and exact downloaded bytes. This removes the dependency on an externally prepared recovery directory, which caused the first run to skip. It does not claim a backend crash test.

All three M2 API cases passed. The three existing text-oriented API cases also passed against protocol 3: response loss, concurrent conflict/save-copy and stale baseline after delete/restore. With both session variables and the image fixture supplied, full CoreFlow passed **1071 tests, zero skipped, zero failures**. Ordinary default runs still opt out when no local API credentials are supplied.

The same image note exposed a server share-rendering omission. Go now preserves canonical media references, authorizes the actual viewer before and after the exact media read, and rejects unavailable images before rendering. Real before/after PNGs and owner/non-owner/anonymous access were checked; after returning the task note to private, cached images were denied to B and anonymous callers. [Server evidence](../../../Chorai_Go/docs/evidence/ios-offline-note-sync/2026-11-21-ordinary-and-sharing.md).

No App production code changed in this checkpoint. App builds and UI results remain the preceding import checkpoint's evidence, rather than a claimed rerun. Task 2's final production composition, all-writer lifecycle and permanent erasure acceptance are still incomplete.
