# Native fidelity correction · 2026-10-26

The first rollout was rejected for diverging from the approved prototypes. This is the separate correction record; initial implementation screenshots and logs remain in the parent directory as historical evidence.

## Visual references and scope

Open [original / actual App comparison](index.html). The eight paired surfaces are Home, editor, Explore cards, rated Grid, reader, Spark results, Merge selection and Merge result. Each uses the actual native App on iPhone 17 Pro / iOS 26.5 at 1206 × 2622 pixels. The references are V5 Explore, V6 Home/editor/feature journeys, and V8 grade treatment; see [the reference map](../FIDELITY-AUDIT.md).

Corrections restore the open serif Home rows, labeled New note, full-page writing, grouped native Explore controls, restrained Spark and compact grade Grid, card-contained reader author controls, and the real Merge selection/result structures. Native menus and grouped Share/Link/Report sheets preserve their real action owners. UIKit's pre-presentation menu event dismisses the editor keyboard before presenting UIMenu.

The comparison is not a claim of pixel identity. Real data, ownership actions, available service fields and existing navigation remain authoritative. The original rated Grid/reader references were shown in design sheets; actual Explore navigation remains in the App. The offline reader uses the same text without a remote sample photo. My Notes / Collections and actual date/privacy state retain their production meaning. Spark/Merge captures use actual production views and stores with explicitly injected memory services.

## Final engineering checks

- Xcode 27.1 (27A9275), selected per command with DEVELOPER_DIR. Original iOS 16 deployment target retained.
- CoreFlow complete suite: **816 passed, 0 failures**.
- BlockNoteEditor complete suite: **53 passed, 0 failures**.
- Local ArcNote test build: succeeded, signing disabled; rebuilt after the long-card containment fix.
- ArcNote Production Simulator build: succeeded, signing disabled; rebuilt after the long-card containment fix. Production was never launched.
- Existing V3–V8 manifests: **402 recorded files unchanged**.
- Six protected baseline hashes unchanged: API environment/configuration, NetworkManager, network models, grade domain thresholds and Package.resolved. Vendored BlockNote Resources untouched.
- Branch remains main. Working changes are local; no commit or push.

**11 distinct offline UI cases have passing latest results** (16 light/dark case results). Their exact logs, superseded failures and corrected reruns are recorded in `qa/ui-results.json`. The selected checks cover Grid→reader→same Grid, tab/mode preservation, full final paragraph without WebView clipping, Home→editor→Home without an unwanted save prompt, cold sidebar→Collections, system Share/Report/Link entry, editor menu with keyboard dismissal, menu order and short viewport, Spark next/previous/deeper, actual Merge source selection→editable result, and discard confirmation. This is a targeted integration suite, not the full backend-dependent UI suite.

The final Explore change also reran all 10 Flow presentation contract tests successfully. Both themes now exercise long-card scrolling, reachable footer controls, Previous navigation, and an empty rendered gutter below the scroll viewport. Before the fix, the new regression test detected 2,167 text-colored pixels spilling into that gutter and failed; its latest light/dark runs pass. Four additional long-card top/bottom screenshots are retained.

## Regressions corrected during verification

- Disabling ScrollView clipping to preserve shadows also let long paragraphs paint over Previous and the tab bar. Default viewport clipping is restored, with horizontal padding retaining the card width and shadow room; vertical scrolling and swipe callbacks remain intact.
- Hidden Grid stacking could intercept the active card's menu. The active browsing surface now owns the top hit-testing layer.
- A forced root tab-bar visibility preference overrode the reader. Roots now use automatic visibility unless covered; reader visibility and return are checked at runtime.
- Reader HTML margins could extend outside the measured body and clip the final line. The body contains its margins and height includes its measured box; UI checks reach the complete final paragraph.
- Canonical offline BlockNote paragraph properties avoid treating an unchanged sample as edited.
- Cold sidebar Collections requests are consumed after Home mounts instead of being lost during the first tab switch.
- Notes search no longer presents both native and legacy menus.
- Explore restored its original owner action scope. Global deletion fallback now carries an explicit card ID and refuses missing or mismatched targets; it cannot reuse an unrelated Home selection. Existing confirmation and custom onDelete callbacks are retained.
- A test-only fixed-yield wait could expire before its fixture actor was scheduled under build load. It now waits for the same condition with a bounded deadline; production polling was not changed.

## Remaining boundaries

Port 8180 has no backend listener. Live sign-in, real AI generation, persistent collection/save, chat responses and server recovery were not validated. Unsupported Local Preview writes fail locally rather than reporting fake success. No production API calls were made.

Detail/Spark's historical owned-card Delete confirmation is still owned by Home. The explicit-target safety fix prevents wrong-card deletion, but does not claim that confirmation is reachable from every nested entry when Home is absent or covered. That route remains a separate functional follow-up.

Profile, settings, auth, Chora and chat have no approved V8 screen capture to match exactly; they inherit the shared native theme and preserve existing features. They are not labeled screenshot-identical. Physical-device and older-iOS runtime validation were not performed. Initial rollout accessibility captures remain historical evidence, not substitutes for new visual approval.

## Reproduce

Use ArcNote.xcodeproj, the ArcNote / ArcNote Production schemes, pinned dependencies and external build directories. Launch Local Debug with `--dev-preview` for read-only native browsing, `--ui-test-spark-fidelity` for the isolated Spark sequence, or `--ui-test-merge-fidelity` for actual Merge selection and an in-memory result. Keep CHORAI_UI_TEST_MERGE_BACKGROUND_URL unset.
