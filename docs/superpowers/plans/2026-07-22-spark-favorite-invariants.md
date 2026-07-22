# Spark And Favorite Invariants Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Spark chains free of repeated source/ancestor cards and make favoriting an owned card impossible across backend, iOS, and Web.

**Architecture:** Go owns the canonical invariants: Spark candidates and readbacks are unique by asset and exclude the current/ancestor sources; FAVORITE rejects an `OWNS` match before any transaction side effect. iOS and Web mirror those rules for immediate UX while still treating the backend as authoritative. Runtime schema reconciliation ends legacy active self-favorites and then reuses the existing engagement-count reconciliation.

**Tech Stack:** Go, Gin, GORM, Testify, Swift/Combine/SwiftUI/XCTest, React/TypeScript/Vitest.

## Global Constraints

- Users may Spark cards they own.
- A Spark page must not contain its current source card and must be unique by `asset_id`.
- A chained Spark must not return any ancestor source card.
- An actor must never create or retain an active favorite on an asset they own.
- Ownership is defined by the backend `OWNS` relation / `is_owner`, not by display author identity.
- Existing provenance rows are retained; legacy active self-favorites are ended, not deleted.
- Do not change self-like behavior in this task.

---

### Task 1: Canonical Spark filtering

**Files:**
- Modify: `Chorai_Go/chorai-go/internal/ontology/actions/spark_actions.go`
- Modify: `Chorai_Go/chorai-go/internal/ontology/services/spark_service.go`
- Test: `Chorai_Go/chorai-go/tests/integration/spark_integration_test.go`

**Interfaces:**
- Produces: candidate filtering keyed by `targetAssetID` and service payload filtering keyed by `TargetAssetID`.
- Consumes: Spark chain `ParentActivityID`, `USED` relations, and asset-version lookup.

- [x] Add integration tests that return duplicate versions of one asset, the current source, and an ancestor source; assert only one non-excluded asset remains in POST and activity readback.
- [x] Run `go test ./tests/integration -run 'TestSpark.*(Source|Ancestor|Duplicate)' -count=1` and confirm the new assertions fail for the missing behavior.
- [x] Add an ancestor-source collector that walks parent metadata and `USED` relations, then filter fused candidates by excluded asset IDs.
- [x] Make `buildSparkPayload` exclude supplied asset IDs and deduplicate all rows by asset ID so persisted legacy rows cannot leak through readback.
- [x] Run the targeted integration tests and existing Spark integration suite until green.

### Task 2: Self-favorite rejection and legacy reconciliation

**Files:**
- Modify: `Chorai_Go/chorai-go/internal/ontology/actions/spark_actions.go`
- Modify: `Chorai_Go/chorai-go/internal/database/runtime_schema.go`
- Test: `Chorai_Go/chorai-go/internal/ontology/actions/engagement_counts_test.go`
- Test: `Chorai_Go/chorai-go/internal/database/runtime_schema_test.go`

**Interfaces:**
- Produces: `CONFLICT` from `FavoriteAsset` when `(actor, asset)` has an active `OWNS` relation.
- Produces: idempotent startup reconciliation changing legacy active self-favorites to `ENDED` before count reconciliation.

- [x] Add an action test asserting an owner receives `CONFLICT` and no Favorite, Activity, count, credit, or signal side effect is created.
- [x] Run `go test ./internal/ontology/actions -run TestFavoriteAssetRejectsOwnedAsset -count=1` and observe failure.
- [x] Add the ownership guard before the favorite transaction and verify the action test passes.
- [x] Add a runtime-schema test with one self-favorite and one external favorite; assert only the self-favorite is ended and `favorite_count` becomes one.
- [x] Run the schema test red, implement idempotent reconciliation without deleting rows, then rerun green.

### Task 3: iOS ownership and Spark deck defenses

**Files:**
- Modify: `Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/CoreFlowModels.swift`
- Modify: `Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/FlowDeckStore.swift`
- Modify: `Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/SparkSessionStore.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/Models/RelatedCardsModels.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/NetworkModels.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/CoreFlow/NetworkCoreFlowService.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/CoreFlow/NetworkCoreSparkService.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/CoreFlow/FlowViews.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/CoreFlow/SparkContinuationViews.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/Models/CardDetailModels.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/Models/SearchModels.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/Models/UserAllCardsModels.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/DetailView.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/RecommendedCardsManager.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/HomeCardsManager.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/TabBarView.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/UserProfileView.swift`
- Modify: `Chorai_IOS_Frontend/ArcNote/SparkView.swift`
- Test: `Chorai_IOS_Frontend/Packages/CoreFlow/Tests/CoreFlowTests/SparkSessionStoreInteractionTests.swift`
- Test: `Chorai_IOS_Frontend/Packages/CoreFlow/Tests/CoreFlowTests/FlowDeckStoreTests.swift`

**Interfaces:**
- Produces: `FlowCard.isOwner: Bool` with a default of `false` and preservation through copy helpers.
- Consumes: backend `is_owner` and `owner_actor_id` fields.

- [x] Add failing Store tests proving source results are removed and owned cards never call favorite/unfavorite services.
- [x] Add `isOwner` to decoded card models and propagate it into `FlowCard`.
- [x] Filter initial/replayed Spark pages by `sourceAssetID`, guard Store mutations, and omit favorite controls for owned cards.
- [x] Run targeted CoreFlow tests and the complete CoreFlow package suite.

### Task 4: Web ownership defenses

**Files:**
- Modify: `chorai_web_frontend/src/components/SparkView.tsx`
- Modify: `chorai_web_frontend/src/components/CollectionCard.tsx`
- Modify: `chorai_web_frontend/src/components/ExploreView.tsx`
- Modify: `chorai_web_frontend/src/components/NoteDetailView.tsx`
- Modify: `chorai_web_frontend/src/components/ProfileView.tsx`
- Modify: `chorai_web_frontend/src/components/HomeView.tsx`
- Test: `chorai_web_frontend/src/components/SparkView.guideAnchors.test.tsx`
- Test: `chorai_web_frontend/src/components/CollectionCard.test.tsx`
- Test: `chorai_web_frontend/src/components/NoteDetailView.test.tsx`

**Interfaces:**
- Consumes: canonical `Note.isMine` populated from backend `is_owner`.
- Produces: no save/favorite control and no mutation call for owned notes.

- [x] Add failing component tests for owned notes across Spark, collection cards, and detail view.
- [x] Guard mutation handlers and conditionally omit favorite controls when `note.isMine` is true.
- [x] Run the targeted Vitest files and production build.

### Task 5: Cross-stack verification

**Files:**
- Verify only; no new production interfaces.

- [x] Run focused Go action, runtime schema, integration, and compliance tests.
- [x] Run all CoreFlow tests and relevant iOS source-contract tests.
- [x] Run targeted Web tests and `npm run build`.
- [x] Inspect all three diffs and confirm no self-like behavior, generated API, or unrelated files changed.
