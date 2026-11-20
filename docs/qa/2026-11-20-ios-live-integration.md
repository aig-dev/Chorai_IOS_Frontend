# Local Go and iOS visual integration

Date: 2026-11-20. This follow-up preserves the uncommitted Swift 6 migration at
baseline `a46f21e`. Evidence is retained under
`.superpowers/sdd/2026-11-20-ios-live-integration/`. Dedicated simulator:
`EBACA372-C94A-4A14-9947-634DF3918495`, iPhone 17 Pro / iOS 26.2, Xcode 27.2.
Production is build-only. No commit or push is part of this task.

## Original failures and resolution

All three original tests failed in `Baseline-Problems.xcresult`, without skips.

- Merge: `testMergeArtifactEditsInPlaceAndRestoresDraft` compared the accessibility
  frame of an entire multiline paragraph with the visible editor viewport.
  Paragraph top was Y=299 versus viewport Y=302.333. Temporary native/DOM probes
  showed the edited line's caret at Y=325.333–347.333, visibly inside the viewport.
  WebKit scrolled the edited second line into view while clipping the earlier
  line. The `.never` inset experiment did not help and was removed. The test now
  recognizes the actual replacement text in the screenshot and checks its bounds.
  Selection, horizontal movement, scrolling, tags, Back and relaunch assertions
  remain. Generated editor assets and runtime scrolling are unchanged.
- Home: the old `--dev-preview` setup did not populate the account/environment
  scoped `NoteLibraryStore`. A preview card could not authorize a local editor.
  The original test now authenticates against the existing loopback sync fixture,
  receives a real manifest/detail and opens the resulting `local-note:` identity.
  Menu opening, unchanged-note Close and direct navigation remain asserted.
- Trash: the old fixture had no trashed note in the scoped store. The shared
  loopback server now supplies one through manifest/detail, excludes it from the
  active-only recent page and counts permanent-delete requests. Cancel requires
  zero requests; a 503 rejection requires one request and preserves the same note.

All three original scenarios passed in `Live-Home-And-Regressions.xcresult`.
That bundle's fourth, newly added real-backend test failed and is not counted as
passing. The earlier migration checkpoint is retained as historical evidence.

The AX5 test also assumed the retired editor → tags → sync order. The current
surface places sync above the editor and tags below it in a vertical ScrollView,
with pinned actions. It now verifies that order, scrolls the tags fully into view,
and retains the 44-point/hittable action assertions. The corrected case passed in
`Merge-AX5-Current-Layout.xcresult`; no production layout change was needed.

## Real runtime and observed product defects

The original dev database was retained. Its 12 unclassified legacy Actors prevent
safe automatic reconcile; they were not guessed, rewritten or deleted. This run
uses task-owned application and Memory databases and Redis DB 13. Existing
reconcile, first-administrator bootstrap and Actor Action created the isolated
identities. The dev-only note-sync protocol 3 option is enabled in a private config
copy. Configurations and credentials remain outside tracked evidence.

Docker dependencies and the real Python Agent run locally. Docker registry access
failed, so unchanged Memory Core and Worker use the supported native runtime.
Go listens on `127.0.0.1:8180`; `/health` is 200. This does not claim every optional
`run-stack` service started. Existing user database and production config are intact.

Four product defects were reproduced:

1. Go legitimately returns `unavailable/allowed/admin_bypass` with no scope for a
   currently authorized administrator. iOS rejected it, and then separately
   required a persisted offline grant to open Home. Access validation now accepts
   only that exact exception. A verified, connected session can open its own local
   library. This response never creates an offline grant; token rejection checks
   retained offline eligibility, and no server permission is changed.
2. Explore's empty/error recovery label inherited the same ink color used by the
   prominent button background. Actual screenshots showed a blank green button.
   The label now uses the existing `onAccent` theme color. Vision failed to read
   Retry before the fix; the regression checks rendered text rather than just an
   accessibility label.

3. The native Home menu sent a `local-note:` ID to the old cloud DELETE route,
   which returned HTTP 428. The actual failure alert retained the note. Local-note
   removal now calls the existing local lifecycle owner; its coordinator supplies
   the guarded cloud operation and retries. The same native confirmation is kept.
   `Local-Removal-Red.xcresult` reproduces the failure without a live backend;
   the local-transaction regression and the complete real lifecycle then passed in
   `Live-Lifecycle-Merge.xcresult`.

4. AX5 runtime diagnostics contained a SwiftUI publication-during-update warning.
   Symbolicated frames traced it to authentication restoration notifying an idle
   comment store during view creation. Closing an unopened/already closed store
   now does nothing. The regression first failed with three redundant publications;
   it also checks that active-session invalidation still publishes, closes the read
   and rejects a late response. All 19 comment/cache cases passed; the final AX5
   rerun reported no runtime warnings. No asynchronous delay was added to revocation.

Smoke-test note creation now supplies the existing protocol's idempotency key and
structured document. Cleanup reads the sync token and submits a guarded operation.
Native tab-bar queries use their exposed system labels; locally synchronized cards
are selected by local identity and unique content, while API assertions retain the
canonical server IDs.

## Verification

| Check | Result / evidence |
| --- | --- |
| Canonical admin access, offline boundary and owned actions | CoreFlow selected suites 60 passed; Go `internal/access` passed |
| Online administrator local library and hosted regression | Hosted regression failed at both online checks before fix; final `Hosted-All-Final.xcresult` passed all 79 hosted cases, no skips |
| Comment session invalidation | New regression failed on redundant publications; all 19 comment/cache cases passed and AX5 startup no longer reports the SwiftUI warning |
| Retry text visible | `Contrast-OCR-Red.xcresult` failed on actual text recognition; the same case passed in `Live-Home-Profile-Contrast.xcresult` |
| Local build | Current UI build-for-testing passed |
| Production build | Updated `Debug-Production` build passed; not launched |
| Persisted concurrency settings | All nine target/configuration pairs remain Swift 6 + complete checking |
| Real Home / Trash lifecycle | Complete edit, API-body agreement, relaunch, delete, cancel, restore, second delete, purge and final API 404 passed in `Live-Lifecycle-Merge.xcresult` |
| Real profile / settings | Passed in `Live-Full-Paths.xcresult`, including actor ID and return navigation |
| Real Merge / search / detail | Typed search → canonical detail passed in `Live-Full-Paths.xcresult`; `Live-Merge-Final.xcresult` passed complete creation, relaunch, body/tag revision, structured-document-preserving commit, Home return and post-commit Explore relaunch; no skips/runtime warnings |
| Deterministic UI regression matrix | 16/17 passed in `Final-Regression-Matrix.xcresult`; corrected AX5 passed separately and again in `Final-Merge-Live-And-AX5.xcresult` |
| Fresh-context review | No Critical/Important findings; reviewed only this task delta against the recorded baseline; final runtime acceptance completed afterward |

Physical-device timing, a signed archive, production service availability and an
exhaustive acceptance of every app feature are outside this local integration run.

No preexisting test method was removed; this follow-up adds nine. Baseline hash
comparison found no changes outside the declared follow-up file list, including
unchanged editor coordinator and user Xcode state files.

An early real Merge returned `TEXT_PROVIDER_FAILED`. The failure bundle remains
recorded. Real Python, gRPC and Go adapter probes then succeeded, and an unchanged
source-content run reached `COMMITTED`. Subsequent UI failures were traced to old
cloud-ID list selectors and a fixed coordinate that missed short generated text;
selectors now use local identity and the actual editable TextView. Unique body
markers exclude presentation-trimmed leading whitespace; the inserted separator and
server structured-document comparison are preserved. `Live-Merge-Final.xcresult` then passed the whole scenario. That success
does not identify the cause of the initial Provider failure or establish provider
availability guarantees.

The hosted run includes one QoS runtime warning. Symbolicated frames point to the
existing semaphore wait in
`LocalNoteThumbnailReaderTests.testCancelledRunningWorkRetainsItsConcurrencySlot`
(line 95), deliberately holding the decoder to test slot retention; this is not a
new production main-thread computation finding. The three UI-runner linker warnings
come from Xcode XCTest libraries built for iOS 17 while the app retains iOS 16.
Final Local/Production compilation contains no first-party concurrency warning.

## Repeat the checks

From the iOS repository, use a dedicated simulator for App/UI checks:

```sh
swift test --package-path Packages/CoreFlow --filter 'Access|OwnedCardAction|CommentReadStoreTests|RecentCardReadsTests'
python3 scripts/check-concurrency.py --settings-only
xcodebuild -project ArcNote.xcodeproj -scheme ArcNoteTests -configuration Debug \
  -destination "platform=iOS Simulator,id=$IOS_DEVICE" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

The UI matrix is listed in the task evidence `regression-selectors.txt`. Build the
`ArcNoteUITests` scheme for testing, then run those selectors on the same simulator.
Real-flow runs use the private authenticated `.xctestrun` under the runtime location
recorded by `runtime-path.txt`; no credentials belong in tracked files. Their result
bundles and logs distinguish real backend acceptance from loopback fault injection.
