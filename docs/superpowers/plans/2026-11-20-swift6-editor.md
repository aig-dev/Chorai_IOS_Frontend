# Swift concurrency checks and editor pilot

Approved scope: persist complete concurrency checking and pilot Swift 6 in the
editor, using compiler checks and existing regression suites without waiting for
physical-device sampling.

## Constraints

- App and CoreFlow stay in Swift 5 language mode; iOS stays at 16.
- BlockNoteEditor production and test targets adopt Swift 6 together.
- Keep current actor/executor, event ordering, cancellation and final-save semantics.
- Do not opt into default MainActor isolation or Approachable Concurrency.
- Do not silence diagnostics with blanket unchecked Sendable or preconcurrency.
- Production is build-only; runtime tests use existing isolated fixtures.
- Preserve the current checkout and unrelated xcuserdata changes.

## Steps

1. Prove persisted checking is absent using resolved Xcode settings and package
   manifests. Enable complete checking in all three project configurations and
   both CoreFlow targets. Keep their Swift 5 language mode explicit.
2. Set the editor package to Swift 6. Compile its existing suite first, repair
   concrete compiler failures at their owning boundary, then run the full suite.
3. Add `make check-concurrency`: verify effective settings, run both package
   suites, and build Local, Production and Release without command-line language
   or strict-concurrency overrides. An explicit `IOS_DEVICE` adds app-hosted tests
   and the focused ordinary/Merge editor UI regressions on that simulator.
4. Run the complete check, record diagnostics still owned by the Swift 5 modules,
   update execution architecture/history and validation evidence, and obtain one
   independent final review.

## Acceptance

- Effective App/test settings: Swift 5, complete checking, iOS 16 in Debug,
  Debug-Production and Release. Both CoreFlow targets keep complete checking.
- Editor and editor tests compile as Swift 6 on macOS; the actual iOS editor
  source also compiles as Swift 6 in App integration.
- Full package and app-hosted regressions pass; focused editor UI cases pass.
- Each requested UI identifier must have a passing `.xcresult` record; a
  successful `xcodebuild` exit alone does not prove all selected cases ran.
- Existing Swift 5 warnings remain visible migration debt. This phase does not
  claim a warning-free App, whole-App Swift 6 safety, or measured device speedup.

## Review focus

Check package mode versus command-line overrides; Xcode configuration inheritance;
test-target isolation and XCTest callbacks; ordinary/Merge accepted-event drain;
compiler enforcement without hiding existing diagnostics; validation command
failure propagation and explicit simulator selection; iOS 16 compatibility.
