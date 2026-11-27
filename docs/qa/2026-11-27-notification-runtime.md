# Ordinary notification navigation on the isolated production API

The product Swift source remains at `fbc60b322e938c32ae8a9db8ab1598f190b9d9f2`; this change only corrects the UI test helper. It selects the actual sidebar Button, waits until it is hittable, and uses the normal notification button. It does not force taps, introduce an app route, seed inbox rows, or bypass authentication and authorization.

The first run received real comment, follow, and like notifications but failed on the generic sidebar element's hittability. The recording showed the toolbar button. That three-test failure remains preserved. Its two created notes were conditionally trashed and the test follow was removed before the corrected attempt.

After build-for-testing, the three existing selectors passed together on the dedicated iPhone 17 Pro / iOS 26.2 simulator, with zero failures or skips:

- `testFollowNotificationOpensSourceProfileAndPersistsRead`
- `testLikeNotificationOpensCanonicalCard`
- `testCommentNotificationOpensCanonicalCard`

Each uses task-created ordinary accounts against the actual local production-profile API. Follow opens the exact source Actor; like and comment open the exact card. Each checks the persisted read state and absence of an alert. Screenshots were exported and the notification page inspected. The compile retained Swift 6 and emitted no concurrency warnings; unchanged App and Swift package gates were not rerun or relabeled as fresh results.

All six notes from the combined HTTP, Web, failed-native and passing-native acceptance reached erasure COMPLETE and detail 404 through their original requests and normal cleanup worker. Five intended first-read transitions produced five unique completed Activities; repeated reads did not change their timestamps or add facts. The exact Go source, binary, private evidence hashes, failed attempts and remaining release conditions are recorded in the [shared evidence](../../../Chorai_Go/docs/evidence/2026-11-27-notification-runtime.md).
