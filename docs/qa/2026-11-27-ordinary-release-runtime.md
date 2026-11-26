# Ordinary-account acceptance on the current isolated production API

The app source is `99f0aae0d73e0fee60606f1deb513a3ca6643e8c`, the shared editor bundle SHA256 is `67008dc79f286383f91e8f87ff788f1a3b0a8cf8a65d6241614f94a8f7d47f71`, and the Go API source is `b6fc75883724a3ea817b801242f2a1dc799b9d83`. The only new Swift change is the UI test fixture below. Task-created ordinary accounts use the task-owned isolated prod API and PostgreSQL database; earlier Account A credentials are not reused. Private account files and xcresults are not committed.

## Accepted paths

- The six opt-in live API tests ran separately against this runtime: six passed, zero skipped. They retain exact checks for lost acknowledgements and persisted retries, concurrent-writer conflict and save-as, lifecycle baselines, uploaded images, and offline delete/restore. All seven owned notes reached erasure COMPLETE and detail 404.
- `testLibraryOwnedCardVisibilityAndPinMutateGoState` passed with the normally signed current product. The second selector in that attempt failed on the old append gesture and is excluded; that attempt's two notes are fully erased.
- After correcting the fixture, `testNewCardStagesBackgroundAndPrivacyBeforeFirstSave` passed alone, with zero skipped tests. It verifies offline draft creation and relaunch, one acknowledged create after recovery, private-to-public transition, pending background preservation, exact appended body, explicit background upload and attachment, and reopen. Its owned note reached erasure COMPLETE and detail 404.
- The focused wrapped-paragraph regression and the affected held-background flow both passed: two tests, zero failures or skips. The existing gate-runner unit test module passed all 23 tests. The first-release UI selector file now includes the wrapped-paragraph test, bringing that explicit list to eleven existing methods. The earlier full gate's ten-selector result remains historical evidence; it is not relabeled as a single eleven-test run.

The two ordinary UI paths passed in separate bounded runs on unchanged product source. Failed suite attempts remain failed and are not presented as one clean two-test suite. The latest simulator application executable remained unchanged across the fixture builds.

## Fixture correction and excluded attempts

The original append helper assumed a hardware shortcut would move to the end of a wrapped paragraph. Actual recordings showed text inserted in the middle. Alternative shortcuts did not reliably move the insertion point in this software-keyboard session. The final helper locates the exact existing rendered text, requires the keyboard to be hidden, then taps once below the text before typing. A second tap after focus can hit the native formatting bar covering the lower WebView accessibility frame; it is deliberately absent. The regression retains both exact rendered text and saved whole-body checks, including a long wrapped paragraph. No editor serialization, synchronization, account behavior, or production UI is changed.

The earliest ordinary offline-relaunch attempt used unsigned synthetic-gate products with no embedded Keychain application entitlement and returned to signed-out state. It is excluded. Ordinary acceptance uses normal simulator signing, verified Mach-O XML/DER entitlements and matching application identifier. `codesign -d --entitlements` alone did not expose the simulator's embedded entitlement, so it is not the qualification check. The original unsigned run's only created note was erased; its offline-failed case never created a server note.

All earlier failed attempts' and the latest passing background flow's owned notes reached erasure COMPLETE and detail 404. Cleanup always replays the original request identity and body; it does not accelerate database retry clocks.

## Rendering blocker in the qualified historical version

The final ordinary-flow screenshot shows no remote background image, and its media request returned HTTP 401. `NewNoteView.editorBackground` projects the accepted media reference to a remote URL; `CardEditorBackground` passes that URL to bare `AsyncImage`, while the current media-content endpoint requires an authenticated actor. The passing UI assertions verify saved content, visibility, media identity, upload and attachment; they do not qualify successful background rendering. This is a retained-feature release blocker. Repair must reuse the existing account/environment-scoped authenticated download, preserve media authorization, and verify actual loading plus stale-account/result rejection. The next product change is separate from this fixture-only commit.

The follow-up [authenticated display repair](2026-11-27-background-display.md) now qualifies actual background loading, recovery and layout bounds. This historical record keeps the original 401 and blank screenshot failure; saved-reference assertions are not relabeled as a rendering pass.

This qualifies the listed local paths only. The same complete document still needs a real Web-to-iOS-to-Web round trip; retained Merge integration and the remaining first-release deployment conditions remain open. No physical-device performance or distribution archive qualification is claimed.
