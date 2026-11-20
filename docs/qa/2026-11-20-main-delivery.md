# Swift 6 main delivery verification

Date: 2026-11-20. The user explicitly requested committing and pushing the completed changes to `main`, followed by investigation of the next upgrade/integration steps.

Code commit: `9ccbeeae866abc753618c5107f234f410484d635` (`feat(ios): adopt Swift 6 and harden local integration`). Normal push to `origin/main` succeeded; `git ls-remote origin refs/heads/main` matched this exact commit after the push. The subsequent documentation-only commit adds this delivery record and the next-stage plan.

## Fresh verification before commit

The committed code and test files were staged before verification. SHA-256 comparison after the gate found no source drift. The full gate used fresh temporary products; it did not rely on previously successful build output.

```bash
CONCURRENCY_OUTPUT="$PWD/.build/2026-11-20-main-publish/gate" \
IOS_DEVICE=EBACA372-C94A-4A14-9947-634DF3918495 \
make check-concurrency
```

Environment: Xcode 27.2 (27B52), Apple Swift 6.4.2, dedicated iPhone 17 Pro simulator / iOS 26.2. First-party targets use Swift 6 and complete checking; iOS 16 remains the deployment floor. Default actor isolation and Approachable Concurrency remain unchanged.

| Check | Fresh result |
| --- | --- |
| Persisted App/test modes | All nine target/configuration pairs verified |
| Gate runner regression | 18 passed |
| CoreFlow | 1,071 total: 1,065 passed, six opt-in live API tests skipped, zero failures |
| BlockNoteEditor | 76 passed, zero failures |
| Debug / Debug-Production / Release | All three builds passed; no first-party concurrency diagnostic rejected by the gate |
| App-hosted suite | 79 passed, zero failed/skipped; exact xcresult summary checked |
| Focused editor UI | All six requested full identifiers passed, zero failed/skipped; exact xcresult summary checked |
| Overall command | Exit 0; final gate PASS |
| Source integrity | No staged-file hash drift; `git diff --cached --check` passed |

Local evidence root: `.build/2026-11-20-main-publish/`. Gate logs are under `gate/`; result bundles are `gate/app-tests-ithgxrs2/App.xcresult` and `gate/editor-ui-n4elmf9y/EditorUI.xcresult`. These ignored local artifacts are not uploaded as tracked source.

## Scope of the push

The code commit contains 112 files: the complete first-party Swift 6 migration, concurrency gate, regression updates, local integration fixes and their architecture/history/validation records. Three existing personal Xcode user-state files were excluded and retained. No Go source was changed or pushed; its pre-existing `chorai-go/server` deletion was preserved.

The earlier [migration](2026-11-20-swift6-migration-validation.md) and [live integration](2026-11-20-ios-live-integration.md) records remain historical checkpoints. Their then-uncommitted status describes those tasks, not this delivery. Their broader UI and real-backend evidence is not represented as freshly rerun by today's six-case UI gate.

This delivery does not claim ordinary-account live acceptance, in-place upgrade from the old app, a signed archive, minimum-OS runtime coverage, production sync readiness or physical-device performance measurements. The six live API skips are an explicit next-stage verification item.

## Next stage

The [upgrade and integration plan](../superpowers/plans/2026-11-20-post-swift6-integration.md) prioritizes mandatory simulator/CI checks, ordinary-account M1/M2 integration, account switching, retained-data app upgrades and Merge failure recovery. It records the production protocol restrictions confirmed in Go source. These next-stage tasks are planned, not implemented by this delivery.

The follow-up documentation change was checked against the current source and test entry points. All 31 local Markdown links in its four files resolve, and `git diff --check` passes. No executable source changed after the fresh gate above.
