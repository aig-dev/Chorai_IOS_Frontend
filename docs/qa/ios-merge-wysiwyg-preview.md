# iOS Merge WYSIWYG preview verification

Date: 2026-08-19
Result: passed

## Scope

This run closes the three-source Merge preview flow across the Go service and
the iOS app. It verifies one WYSIWYG surface for scrolling and editing, shared
Card Editor tag presentation, the shared six-tier material, durable recovery of
the same job and draft, exact revision commit, the global numeric task rail,
compact-device reachability, accessibility settings, and the approved visual
matrix. A final whole-range review also verifies that a clean HTTP 409 server
adoption reprojects the canonical document and tags into the open editor
without losing an unfinished tag or issuing a stale replacement save.

The frozen bases were Go
`047a5fbb00c5a25a54c6a748e5f69bf4fff429d2` and iOS
`2416bad7c43f029e9f12670ea14c9493801c9b6d`.

## Environment and safety boundary

- iPhone 17 Pro, iOS 26.2 build 23C54, UDID
  `43E6164C-1F4B-47E4-9B65-D154C7281A56`, 402 x 874 points and
  1206 x 2622 pixels.
- Chorai iPhone SE 3 QA, iOS 26.2 build 23C54, UDID
  `86CD9628-7C27-4799-B237-3EEC82E7E9B5`, 375 x 667 points and
  750 x 1334 pixels.
- The populated default development authority remained read-only. Its
  presentation transition was blocked by legacy state and a partial successor
  schema, so no existing default job was cancelled, rewritten, or deleted.
- The real flow ran against isolated Task 12 ontology/domain schemas. Provider
  instability was separated from product behavior by a repository-supported,
  authenticated deterministic fixture runtime on a task-owned loopback port.
  No protocol response was invented. Three task-only source Cards used by the
  sibling test were permanently deleted after the proof; no pre-existing Card
  was changed.
- Private tokens, credentials, URLs, fixture body text, and source Card IDs are
  intentionally absent from this document and the image assets.

## Real cross-platform proof

The canonical post-fix commit job was
`mjob_5834a876a5c578a3986702cc`. It reached `COMMITTED` through the
normal product flow after the app:

1. recovered the same persisted session/job;
2. displayed the server-owned `Notable` level with no numeric rate control;
3. edited body and tags on the same surface;
4. minimized, reopened, terminated, and relaunched without creating another
   job;
5. recovered the same draft and selected revision 4;
6. accepted and committed revision 4 as
   `mcmt_mgv1_zxlqe6ouvpsmfwgdrmje5hmlkvmmb5jmvtkfs6pz25ekhjkgumgq`;
7. opened the canonical committed Card.

Read-only database verification after the UI pass proved:

- one committed job and one commit row;
- selected artifact revision 4 and the exact committed document hash;
- one output Card, one current Card projection, one governed Activity, and one
  governed Action;
- projected rate `3`, the exact edited tag set, and no post-commit metadata
  endpoint;
- the same persisted session scope after relaunch.

The final same-job resume/commit bundle is
`/private/tmp/chorai-task12-postfix-resume3-live-20260819.xcresult`: 1 test,
0 failures, 73.884 seconds.

Four earlier jobs failed only at the external/deterministic-provider bring-up
boundary and were not retried again:

- `mjob_02bad88d8f60bdb8e8945cf2`
- `mjob_4176e042f30f7a7025845cb3`
- `mjob_58137ded52085fe164361476`
- `mjob_4ec01107f05cb5186daf4c58`

They were confined to the isolated authority and removed with that authority
after evidence capture. They are provider-diagnosis evidence, not product
success evidence.

## Live sibling Discard proof

A final product-boundary run created two real jobs from the same ordered set of
three task-owned source Cards. The sole global rail displayed two tasks. The
test opened one completed artifact, used the destructive `Discard`
confirmation, and proved that only that job disappeared from the rail:

- `mjob_258441c43d722cf89ae17deb` became `CANCELLED` through the visible
  WYSIWYG Discard action;
- `mjob_afce66aefa3b886c938949fe` remained `ARTIFACT_READY`, stayed as the one
  surviving rail task, and was opened successfully;
- both jobs retained exactly the same three frozen source IDs in source order;
- the surviving sibling was cancelled exactly once only during cleanup.

The fresh result bundle is
`/private/tmp/chorai-task12-live-sibling-discard-20260819-v3.xcresult`: 1 test,
0 failures, 48.530 seconds. Read-only database verification independently
confirmed the `CANCELLED`/`ARTIFACT_READY` split before cleanup.

## Final iOS behavior gates

Fresh, non-parallel UI batches were run from the final built test runner.

| Device | Result bundle | Result | Coverage |
| --- | --- | ---: | --- |
| iPhone 17 Pro | `/private/tmp/chorai-task12-post-sibling-pro-v1.xcresult` | 18/18 passed | selection, Working cancel, rail count/fifth/cold/measured/rotation, WYSIWYG edit/reopen, focused and unfocused rotation, tag-focus width-slot race, default tags, busy Accept, Discard confirmation, timeout Retry, and both clean-409 controller cases |
| iPhone SE 3 | `/private/tmp/chorai-task12-post-sibling-se-v1.xcresult` | 14/14 passed | WYSIWYG edit/reopen, focused and unfocused rotation, tag-focus width-slot race, default tags, accessibility Dynamic Type, busy Accept, Discard confirmation, timeout Retry, fifth/cold/measured rail, and both clean-409 controller cases |

The post-matrix whole-range review found and fixed one controller/store
reconciliation gap. In the controlled case, revision 1 content was edited and
returned exactly to its acknowledged value while its PUT was in flight; the
PUT received 409 and the server supplied canonical revision 2. The final
controller now reprojects only when the Store is clean, has no pending save,
and the canonical document/tag identity differs from the currently projected
identity. Ordinary local writes and save acknowledgements do not rebuild the
editor. Automatic adoption preserves an unfinished tag input, while an
explicit Reload Server action retains its documented discard semantics.

The final controller bundles prove canonical revision 2 becomes visible on
both phones, an unfinished tag is appended to the adopted server tags and
saved against revision 2, Accept performs no stale replacement PUT, and commit
is invoked exactly once:

- `/private/tmp/chorai-task12-clean409-controller-green-20260819-v1.xcresult`
- `/private/tmp/chorai-task12-clean409-controller-se-green-20260819-v1.xcresult`
- `/private/tmp/chorai-task12-clean409-pending-tag-green-20260819-v2.xcresult`
- `/private/tmp/chorai-task12-clean409-pending-tag-se-green-20260819-v1.xcresult`

The compact keyboard regression was tested explicitly. Portrait focus preserves
the editor frame after settling. Landscape focus reveals at least one readable
body line above the keyboard without intercepting horizontal text selection.
Dismissal returns to Preview, preserves content and a valid reading position,
and keeps the editor and mutation actions inside the window. A tag keyboard
held through rotation cannot poison the cached resting viewport for later body
focus.

The final rail contract keeps the collapsed control exactly 12 points above the
measured, cached, or deterministic New Note slot. Expanded capacity adapts to
the available height while retaining 44-point rows; portrait shows tasks 1...4
and scrolls to task 5, while Pro and SE landscape keep a viable row in-window
and make the remaining tasks reachable by scrolling.

## Package and build gates

| Gate | Result |
| --- | --- |
| CoreFlow full package | 748 passed, 0 failed |
| BlockNoteEditor full package | 45 passed, 0 failed |
| Independent affected source contracts | 25 passed, 0 failed |
| ArcNoteUITests build-for-testing | exit 0, resolved packages only |
| ArcNote Debug generic Simulator build | exit 0 |
| ArcNote Debug-Production generic Simulator build | exit 0 |
| `git diff --check` and exact cached-path audits | passed |

The final builds used isolated DerivedData at
`/private/tmp/chorai-task12-post-sibling-debug-build-20260819` and
`/private/tmp/chorai-task12-post-sibling-production-build-20260819` with
automatic package resolution and updates disabled.

Go unit, affected integration, full test, build, vet, contract, isolated
presentation-transition, and repository cutover gates passed. The fresh
`make verify-merge-vnext-cutover` run completed every hermetic proof and ended
with `MERGE_VNEXT_HARD_CUTOVER_QUALIFIED`.

## Accessibility settings

The matrix covered default Dynamic Type, accessibility Dynamic Type, Reduce
Motion, Reduce Transparency, and Increased Contrast. Every altered setting was
restored after capture. Final readback on both devices was:

- content size: `large`;
- Reduce Motion: `0`;
- Reduce Transparency: key absent;
- Increased Contrast: key absent;
- portrait orientation confirmed by final 1206 x 2622 and 750 x 1334
  screenshots.

The final UI batches prove full `Discard` and `Accept` labels, 52-point mutation
targets, 44-point rail rows, keyboard dismissal, and no accessibility-only
symbol crowding on the SE.

## Visual evidence

The durable evidence directory contains 23 original-resolution PNGs and three
contact sheets:

`docs/qa/assets/ios-merge-wysiwyg-preview/`

- `contact-sheet-card-tiers.png` — Basic, Notable, Valuable, Significant,
  Exceptional, and Definitive.
- `contact-sheet-artifact-states.png` — focused/unfocused Notable, 0/3/10
  tags, long body, Reduce Transparency, and Increased Contrast.
- `contact-sheet-rail-and-devices.png` — Pro/SE rail states, Dynamic Type,
  Preview suppression, and Complete restoration.

All originals and all three sheets were opened and inspected against
`2026-08-17-ios-merge-wysiwyg-preview-approved-v2.png`. Final verdict:

- P0: none;
- P1: none;
- P2: none.

The Notable card retains the approved green glass quality and consistent edge.
There is no numeric rate, colored tag dot, Preview/Edit tab pair, isolated
purple/blue right edge, duplicate rail, New Note overlap, or clipped mutation
label. With three tags, a partially visible Add Tag capsule is the intentional
horizontal-overflow cue; one swipe makes it fully visible and hittable with its
trailing inset. Ten tags remain horizontally scrollable.

## Cleanup proof

Cleanup was exact and completed only after the final read-only evidence pass:

- the task backend and deterministic fixture runtime were identity-checked,
  stopped, and their two task-only ports were verified closed;
- all three temporary source bridge pointers were restored with a three-row
  compare-and-set transaction, while the original source rows and three
  protection digests remained unchanged;
- the committed output Card was permanently deleted through the canonical API,
  and the three task-only note-history projection rows left by the mixed-schema
  fixture seam were removed by exact IDs in the same guarded cleanup
  transaction;
- all three sibling-test source Cards were soft-deleted and permanently deleted
  through the canonical API; a guarded transaction then removed exactly three
  default bridge assets, three versions, three ownership relations, three note
  documents, three document versions, and three block-index rows;
- the surviving sibling was cancelled exactly once after the UI isolation
  proof; both sibling jobs were terminal before authority removal;
- both Task 12 schemas, the task-only canonical MySQL container, and its sole
  anonymous volume were removed;
- the default runtime, default MySQL container, `domain` and `ontology`
  schemas, and the pre-existing set of 22 `ARTIFACT_READY` jobs remained
  present and unchanged.

The first cleanup guard observed exact mutation counts of 3 bridge rows, 2
block-index rows, and 1 note-document row. The sibling cleanup guard added eight
independent precondition/row-count/postcondition checks around its exact
3/3/3 ontology and 3/3/3 domain deletes. Final verification found zero Task 12
schemas, zero task projection rows, and no task backend/runtime listener. The
pre-existing default set remained 22 `ARTIFACT_READY` jobs with the identical
sorted-ID SHA-256
`56f38dacfa0ef019ea99303deba5de1b84ae64f9e31e5b2833a3ce3ee65cfb22`.

## Operational limitations

- The populated default development transition remains blocked and is not
  reported as passed.
- Simulator evidence cannot independently prove physical OLED/P3 rendering;
  this is a non-blocking hardware-only caveat.

## Commits

- Go product fix: `dd8370762ac0e25bc2ab8ddbdc724e6ddd0ff028`
- Go Task 12 QA: `32aeb60c4b904aa26809b09a2f30b521077fd549`
- iOS reachability/layout fix: `c855fc8052dd4629b8186df6f9485ee140efe852`
- iOS Task 12 QA: `5995cc2ad133524d022962e117d8fad0cad99496`
- iOS canonical-draft reconciliation fix:
  `cdf003bc2172aa8a379effac6a604e10738e473e`
