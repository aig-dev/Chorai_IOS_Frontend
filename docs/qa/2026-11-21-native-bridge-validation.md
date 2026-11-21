# Native Swift 6 bridge validation

The import service keeps its production bridge. A DEBUG-only read of the
termination waiters lets hosted tests observe that enqueue has reached the
drain while the transport still holds the files.

## Import completion and file access

`NetworkNoteImportBridgeTests` executes `NetworkNoteImportService.enqueue`
through `MultipartUploadPublisherBuilder`. Its controlled publisher and
transport handle independently deliver success, failure, cancellation and
terminal response. An instrumented resource accessor records both acquisitions
and reverse-order releases. Three import parts share two URLs, so each URL
must be acquired and released exactly once while all three source keys reach
the uploader.

The eight cases cover synchronous receipt, timeout, empty completion, an
undecodable accepted response, accepted value before off-main task
cancellation, off-main cancellation of an installed subscription, off-main
cancellation before subscription registration, and repeated termination with
both registered and late waiters. In the early-cancel case an off-main
canceller reaches the task before the synchronous publisher can send its
value or return its cancellable. For the accepted-value case MainActor
remains in the callback sequence until the off-main cancel returns so
the cancellation handler remains active. The losing signals cannot replace
the first outcome or resume its checked continuation again.

The tests observe the registered waiter before delivering delayed termination.
Success, failure and cancellation leave both file scopes active and the
caller suspended until that signal. Removing the production transport wait
temporarily made all three selected lifetime cases fail on early release.
The original wait was restored before Thread Sanitizer verification.

## Ownership audit

| Boundary | Owner, delivery and release |
| --- | --- |
| Import publisher await state | MainActor creates and consumes the publisher. Task cancellation can arrive off-main. One lock protects the result, continuation and cancellable. The winner claims the continuation once and resumes it after unlocking. Cancellation asks the installed subscription to cancel outside the lock, or cancels a late registration after unlocking. Completed Combine Sink has already accepted its terminal event when completion drops the cancellable. Alamofire cancellation schedules request teardown and does not synchronously deliver a second completion. |
| Multipart termination | The termination latch protects its flag and waiter list with one lock. It removes waiters under lock and resumes them after unlocking. The production handle registers a separate `UploadRequest.responseData` callback on main. That callback follows Alamofire finish and response serialization. Combine cancellation requests transport cancellation. The callback is what frees the file scope. |
| JPEG operation | CardImagePreparation owns a serial OperationQueue. JPEGOperation protects the image and checked continuation with its lock. Queued cancellation clears the image, while running encoding holds a local image reference and occupies the queue until encoding returns. Picker and session owners validate task identity before applying results. |
| NetworkManager main delivery | `onMain` checks the main thread before `assumeIsolated` and otherwise dispatches to main. Access preflight explicitly configures `responseData(queue: .main)`, preserving synchronous delivery within that callback. |
| WebView height observation | AdaptiveHTMLWebView's MainActor coordinator observes its own WebKit view's UIKit scroll-view size. KVO follows the main-owned layout mutation. Weak capture ties callback lifetime to the coordinator and view. Replacing the token ends the prior observation, and isolated destruction invalidates the last token. This was a source audit of the callback and lifetime. |
| Recent reads and keyboard layout | NotificationCenter delivers on `.main`. RecentCardReads evicts in the callback and drops its weakly captured registrations on isolated destruction. The keyboard observer keeps its existing layout scheduling and removes its registrations on isolated destruction. |
| Pending invitation code | MainActor invitation stores call the synchronous UserDefaults wrapper. Reading an invalid record includes deletion of that record. Production callers serialize that compound operation through MainActor. |
| Chat history cutoff | MainActor owns the visibility dependency and applies the revision with a synchronous write. The persistence wrapper uses one UserDefaults operation per call and local date formatter instances. |
| Import request identity | MainActor NoteImportStore retains the actor's request identity when the upload response is ambiguous. The persistence instance locks each load, save and clear, and the MainActor caller owns the ordering across those operations. This patch leaves request recovery unchanged. |

The importer DEBUG app fixtures have their own lock-protected observations.
The hosted tests use separate test doubles, and test checkout state and
credentials are unnecessary. The production owner and SDK checks above
cover the source paths that the synthetic transport does not execute.

## Simulator evidence

Xcode 27.2 and Swift 6.4.2 ran the Local hosted scheme on the dedicated
iPhone 17 Pro simulator with iOS 26.2. The normal run passed all eight
new cases with zero skips or failures. The Thread Sanitizer run passed
all 36 selected cases, including the same eight exact import selectors,
seven JPEG cases, 19 response cases and two access-policy cases. It
recorded zero skips or failures and no sanitizer reports. Both the app
debug dylib and hosted test bundle link the simulator TSan runtime and
contain TSan initialization and memory-access symbols. CoreFlow's
eight RecentCardReads cases passed separately, including synchronous
eviction on a notification posted from a background queue and isolated
observer destruction.

The result bundles are `Task6-Bridge-Normal3.xcresult`,
`Task6-Bridge-Drain-Mutation.xcresult` and
`Task6-Bridge-TSan.xcresult` under the active plan's local evidence directory
`.superpowers/sdd/2026-11-20-post-swift6-integration/`. That directory also
contains the exact commands, selector lists and binary provenance.
The tests use a synthetic transport and a scope recorder. Live document
providers, the full release gate and CI remain outside this checkpoint.
