# iOS Spark Footer Interactions Implementation Plan

**Goal:** Remove the obsolete bottom Spark/up-swipe interaction and make the Spark footer favorite behave like Flow without opening detail.

**Architecture:** Keep Spark continuation in the existing same-page session store and explicit header/menu controls. Add a dedicated in-place favorite mutation to `SparkSessionStore`, isolate the card content gesture region from the footer, and suppress success overlays while retaining inline failure feedback.

**Tech Stack:** SwiftUI, Combine, Swift Package Manager/XCTest, XCUITest, Xcode simulator.

---

### Task 1: Lock the interaction contract with failing tests

**Files:**
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/SparkContinuationSourceContractTests.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CoreSparkModelsTests.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/SparkSessionStoreInteractionTests.swift`

1. Add source-contract assertions for a dedicated footer favorite button, stable accessibility identifier/value, footer isolation from the detail tap, absence of `SparkUpwardCue`, and absence of the saved favorite overlay.
2. Change gesture resolver expectations so vertical drags cancel rather than continue Spark.
3. Add store tests proving favorite/unfavorite mutate the visible result in place, carry Spark discovery context, emit success telemetry, lock duplicates, and roll back on failure.
4. Run the focused tests and record the expected failures before production edits.

### Task 2: Implement in-place Spark favorite state

**Files:**
- Modify: `Packages/CoreFlow/Sources/CoreFlow/SparkSessionStore.swift`

1. Add `toggleFavoriteCurrent()` using the current visible result and active activity ID.
2. Optimistically replace `isFavorited` and `favoriteCount` without changing `visibleIndex`.
3. Route favorite through `CoreSparkServing.favorite(assetID:sparkActivityID:)` and unfavorite through `unfavorite(assetID:)`.
4. On failure, restore the exact prior result, unlock interaction, persist, and expose `.saveFailed`; on favorite success, invoke the supplied onboarding callback without visual notice state.

### Task 3: Remove obsolete Spark gesture UI and isolate footer controls

**Files:**
- Modify: `Packages/CoreFlow/Sources/CoreFlow/CoreSparkModels.swift`
- Modify: `ArcNote/CoreFlow/SparkContinuationViews.swift`

1. Remove `.save` and `.sparkDeeper` from card gesture decisions; make either dominant horizontal swipe advance and vertical/diagonal drags cancel.
2. Delete the bottom-center `SparkUpwardCue` rendering and type.
3. Remove the card-level Spark-deeper accessibility action and upward gesture indicator/animation branch.
4. Split the result card into a tappable content region and an engagement footer.
5. Add the bottom-left favorite button wired to `store.toggleFavoriteCurrent`, matching Flow sizing and accessibility.
6. Remove legacy save/undo state and the floating favorite overlay. Render failures as restrained inline text below the card.

### Task 4: Update end-to-end interaction coverage

**Files:**
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

1. Replace up-swipe continuation scenarios with taps on `spark.continue.<card-id>`.
2. Add a favorite-button scenario asserting server favorite state, unchanged visible card, active accessibility value/count, and no detail navigation.
3. Update right-swipe and visual-evidence scenarios to assert that both horizontal directions only browse and the floating save control is absent.

### Task 5: Verify behavior and presentation

**Files:**
- Verify: `Packages/CoreFlow/Tests/CoreFlowTests`
- Verify: `ArcNoteUITests/ArcNoteUITests.swift`

1. Run focused CoreFlow tests for the source contract, gesture resolver, and Spark store interactions.
2. Run the full CoreFlow test suite.
3. Build both `ArcNote` and `ArcNote Production` schemes for an iPhone simulator.
4. Run focused Spark UI tests on a real simulator, capture the loaded and favorited states, and inspect screenshots for overlap and Flow alignment.
5. Review the final diff for unrelated changes and request an independent code review before completion.
