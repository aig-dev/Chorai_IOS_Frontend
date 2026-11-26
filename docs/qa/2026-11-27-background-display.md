# Authenticated editor background display

This product change follows the [ordinary runtime failure](2026-11-27-ordinary-release-runtime.md). A saved background reference and successful upload did not prove rendering: bare `AsyncImage` sent an anonymous request and the current media endpoint returned 401. The new actual-app read assertion failed on the old implementation while a direct ordinary authenticated read returned the exact uploaded bytes.

## Behavior

`NewNoteView` passes the media URL, current note scope, session generation and product eligibility to the background view. It reuses `NetworkManager.noteSyncDownload(scope:url:)`; existing same-origin bearer, redirect, account and session checks remain unchanged. Image preparation runs off the main thread. A transient view-owned loader accepts an image only for its current request, account and session after download and decoding. Cancellation, replacement and retired sessions cannot publish stale results. Eligibility participates in the task identity so verification recovery in the same session can start a new load. There is no new disk cache or transport layer.

The first authenticated screenshots also exposed an oversized aspect-fill background. A hosted sizing regression reproduced a 160-by-200 proposal becoming 300-by-200. The remote renderer now uses the proposed body dimensions and clips overflow; the background remains decorative and no longer determines its own larger surface. The regression passes.

## Qualification

- Ten hosted tests passed with zero failures or skips, including delayed requests, account/session invalidation, cancellation, decoding off-main, invalid bytes, actual SwiftUI task ownership eligibility recovery without a generation change, and proposed layout bounds.
- Sixty affected CoreFlow source-contract tests passed. The two stale bare-URL assertions were updated; local staging, background decoration and accessibility checks remain.
- Persisted Swift 6 and complete concurrency settings, normally signed Debug UI build, Debug-Production and Release builds passed. The affected build/test logs passed the existing first-party concurrency diagnostic gate. Simulator Keychain XML/DER entitlements and the matching application identifier were verified.
- The final ordinary-account UI selector passed with zero failures or skips on the final signed build. New request-start boundaries independently confirmed exact authenticated media bytes after reopen and after offline-open recovery. Both final screenshots show the image inside the original rounded body panel. All four notes from the final and earlier repair attempts reached erasure COMPLETE and detail 404, including failed or incompletely qualified attempts. Cleanup used original keys and bytes and normal worker schedules.

The bounded review found an eligibility-transition omission and a cumulative-request assertion that could count an earlier request. Both are fixed; targeted follow-up found no remaining issue. Its initial prediction that the old `Group` necessarily repeated downloads was not reproduced by the hosted characterization, which passed with one load. The final stable geometry container retains that lifecycle test; the characterization is not reported as a red failure.

The strengthened ordinary UI selector keeps exact body, audience, upload/attachment and one-create checks. It records media requests before transport and uses a new request-start boundary after reopening and after offline-open recovery. Only a matching authenticated 200 response with the exact uploaded-byte digest satisfies each load assertion. Screenshots separately qualify visible output. Task-created ordinary accounts, the isolated current production API and the dedicated simulator are used; earlier Account A credentials are not reused. Private credentials, journals and result bundles are excluded from Git.

The complete fixed-document Web/iOS/Web round trip, Merge-specific entry points and remaining first-release conditions remain open. This is not a physical-device performance or distribution-archive qualification.
