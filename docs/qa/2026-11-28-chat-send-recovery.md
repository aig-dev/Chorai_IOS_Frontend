# Native Chat send recovery — 2026-11-28

This qualifies requested-send recovery on the ordinary local prod API (Go
`0d4bc2ef`) with native source based on `76bc9a4c`. It does not complete the
whole release or qualify a signed device distribution.

The manager persists the original body, one reference and UUID before sending;
unknown outcomes retain that identity through restart. Exact receipts retire
only their send, and an initially rejected request remains editable. Account,
conversation and concurrent-view guards prevent stale replacement or clearing.
No attachment preview is persisted. Multiple selections are explicitly rejected
without dropping any choice; the existing API supports one reference per message.

## Regressions and final local checks

| Check | Result |
| --- | --- |
| Original composer drops text before acknowledgement | One red UI case; corrected case passes |
| Another view acknowledges before a late failure | Red fresh-UUID regression; corrected original-key retry passes |
| API-valid Chinese text with trailing spaces | Red local rejection; corrected storage preserves full original text |
| U+200B in a valid Go receipt | Red unmatched receipt; corrected backend normalization passes |
| Dedicated persistence cases | 9 passed, included in CoreFlow totals below |
| Complete CoreFlow suite | 1,141 passed, 0 failed; 6 opt-in live API tests skipped and not counted as passing |
| BlockNoteEditor suite | 76 passed, 0 failed/skip |
| Gate runner suite | 26 passed |
| Hosted App suite | 182 passed, 0 failed/skip |
| Fixed UI gate | All 13 selected cases passed; includes two new Chat cases |
| Swift settings and builds | Swift 6/complete/iOS 16 persisted; Local, Production and Release simulator builds pass; no first-party concurrency diagnostics |
| Ordinary recovery UI | One case passed, plus 11 private wire/state assertions |
| Ordinary read-only viewport UI | One case passed, covering two launches; history, ledger and balance unchanged |

The final production files match the three-configuration/hosted/fixed-UI source
snapshots. A separate opt-in read-only viewport test was subsequently appended:
removing only that method restores the exact qualified UI-test file hash. It was
compiled with Swift 6, passed separately, and did not alter any App code or
existing fixed-gate case. No extra full-suite run is implied.

## Actual receipt-loss recovery and retained evidence

The first local UI run sent one synthetic message to the ordinary account's own
Agent. The server committed it; the loopback proxy dropped the actual receipt.
After restart, two same-key retries were incorrectly blocked by the proxy because
JSON field order differed. Parsed payloads and keys were equal. That failed run
remains in the private journal; only the original POST reached the API.

The final candidate resumed the same origin, actor, conversation, stored UUID and
body. Its first replay returned the original message, but the proxy delivered
malformed JSON. Another app restart and same-key replay then returned the exact
successful receipt. The composer cleared only after confirmation and stayed
clear on reopening. No replacement message was created to obtain a green test.

Actual history contains one added human message and one real Agent reply. The
ordinary account ledger contains one settled debit; a separate repeatable-read,
read-only PostgreSQL audit found exactly one transaction with user −1/system +1.
Two final read-only launches could scroll the full original message and response
inside the viewport. Both screenshots were visually checked, with no history,
ledger or balance changes. Earlier screenshots opened above the newest message;
automatic positioning at the newest message is not claimed as fixed here.

The synthetic message/reply and their original audit/charge records remain in the
isolated RC database; Chat has no deletion endpoint, so no direct database cleanup
was invented. Temporary forwarders are stopped. Credentials, payloads and raw
journals stay private; hashes and bounded cross-repository status are published in
`Chorai_Go/docs/evidence/2026-11-28-native-chat-recovery.json`.

## Remaining boundaries

This is recovery for an already requested send, not general draft autosave or a
background chat queue. Unsent edits before pressing Send are outside this contract.
Web Chat recovery, failure injection for the full service combination, final
release artifacts/signing and target deployment remain separate work. HTTPS
multi-image Merge is deferred until its public test endpoint is configured;
production media restrictions are unchanged. Independent source review closed its
length finding and reported no remaining P0/P1/P2 in this bounded change.
