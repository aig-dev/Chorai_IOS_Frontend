# iOS Comment Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Inline execution on `main` is explicitly requested; do not create a worktree or branch.

**Goal:** Restore safe, profile-backed iOS comments with a visible private-mode control and working threaded replies.

**Architecture:** Keep `CREATE_COMMENT`, comment `Asset`, `COMMENT_ON`, and `REFERENCES` as Kernel truth. Store the comment audience (`public` or `private`) inside the immutable comment payload written by the existing Action path, enforce private reads before pagination, and hydrate product-facing username/avatar data from the Domain profile repository. Decode and assemble the flat API response in a small tested CoreFlow model, while the SwiftUI sheet owns only presentation and reply-selection state.

**Tech Stack:** Go 1.x, Gin, GORM, XCTest/Swift Package Manager, Swift 5.9, SwiftUI, Alamofire.

## Global Constraints

- Work directly on the existing `main` branches as requested.
- Preserve all pre-existing dirty-worktree changes, especially `CommentPopupView.swift`, `CoreShellViews.swift`, `ArcNoteUITests.swift`, and unrelated Go share/document files.
- Never display an internal `actor_id`; use the profile username or the neutral fallback `Chorai user`.
- A private comment is visible only to its commenter and the card author. Descendants inherit the private boundary and cannot broaden it.
- The backend keeps the real actor relation for audit, provenance, reporting, and blocking.
- No database migration: audience is an optional field in the existing immutable comment JSON payload; legacy payloads default to `public`.
- All Kernel writes continue through `CREATE_COMMENT`, with one Activity and existing provenance relations.

## ResultSpec

### 1. Summary

- feature: iOS comment identity, privacy toggle, and threaded reply repair
- user value: comments show a recognizable profile, never expose raw internal IDs, support private author-only discussion, and can be replied to
- in scope: comment create/list response contract, private read policy, profile hydration, iOS model/thread assembly, private icon, reply composer
- out of scope: comment likes, edit/delete APIs, web UI redesign, Lurbage anonymous-display policy

### 2. Ontology Mapping

- data class: Kernel comment Asset and relations; Domain actor profile; recomputable UI thread presentation
- objects touched: `Asset`, `AssetVersion`, `Activity`, `Actor`
- relations touched: `OWNS`, `COMMENT_ON`, `REFERENCES`, `EXECUTED_BY`, `ACTED_ON`, `GENERATED`
- actions used: `CREATE_COMMENT`
- canonical terms used: comment audience (`public`, `private`), parent comment, display profile
- source of truth: comment Asset payload plus ownership/reference relations; Domain actor profile for username/avatar
- why not lower layer: audience is an auditable read-policy fact and must travel through the Action write; username/avatar are fast-changing Domain display data
- write frequency: one immutable comment write per submit
- high-impact ambiguity resolved: `private` means commenter plus card author only; other actors are denied before pagination
- new ontology primitives: no

### 3. Write Path

- entry point: `POST /api/cards/:id/comments`
- policy gate: authenticated actor, readable target card, valid same-card parent, and private-parent audience check
- action execution: `ActionExecutor.CreateComment`
- committed activity: exactly one `CREATE_COMMENT` Activity
- provenance relations: existing `EXECUTED_BY`, `ACTED_ON`, `GENERATED`, `OWNS`, `COMMENT_ON`, and reply `REFERENCES`
- factual relation updates: reply keeps `REFERENCES` to the parent comment Asset

### 4. Read Path / Projection

- user-facing queries: `GET /api/cards/:id/comments`
- projection needed: no durable projection; response composition is request-scoped
- permission filtering point: comment service before sorting, pagination, profile hydration, and DTO emission
- recomputation plan: parse immutable comment payloads and relations on each request

### 5. Data / Contract Impact

- tables or models changed: no table change; comment payload and DTO gain `visibility`, response gains `username` and `avatar_url`
- migration needed: no
- api changed: yes, additive fields on `GET/POST /api/cards/:id/comments` and optional `visibility` request field

### 6. Validation

- ontology compliance: focused Action tests verify the existing write path and payload
- policy / deny-by-default: service tests verify commenter/card-author access and denial for other viewers
- provenance completeness: existing Action tests plus focused package suite remain green
- permission-filter-first: tests assert filtering occurs before `total` and pagination
- projection recomputability: CoreFlow tests rebuild nested replies from flat parent IDs
- package tests / smoke tests: Go focused packages, CoreFlow `swift test`, iOS Debug build, and targeted endpoint/UI smoke when the local stack is available

### 7. Semantic Freeze

- term: private comment
- means: a comment/reply readable only by its commenter and the target card author
- not means: unauthenticated comment, identity-erased audit record, public anonymous alias, or a private card
- owner: comment Action payload and comment read policy
- outward contract: lowercase `visibility` value `public` or `private`
- forbidden conflations: Lurbage anonymous-display aliases and card-level visibility
- affected docs/rules/index entries: this plan only; no global semantic rule changes

### 8. Rollback

- rollback method: revert additive DTO/action/iOS changes; legacy comments remain readable because missing audience defaults to public
- data cleanup needed: no
- risk notes: reverting after private comments exist would make their payload field ignored, so backend rollback must retain private filtering until those records are migrated or removed

---

### Task 1: Backend comment contract and policy tests

**Files:**
- Create: `../Chorai_Go/chorai-go/internal/ontology/actions/comment_actions_visibility_test.go`
- Create: `../Chorai_Go/chorai-go/internal/ontology/services/comment_service_test.go`

**Interfaces:**
- Consumes: existing `ActionExecutor.CreateComment` and `CommentService.ListComments/CreateComment`
- Produces: executable expectations for `visibility`, profile hydration, private filtering, and reply parent preservation

- [ ] **Step 1: Write failing tests**

```go
func TestCreateCommentPersistsPrivateAudience(t *testing.T) { /* assert payload visibility */ }
func TestListCommentsFiltersPrivateThreadsBeforePagination(t *testing.T) { /* assert viewer-specific items and total */ }
func TestCreateCommentReturnsProfileDisplayFieldsAndParent(t *testing.T) { /* assert username, avatar_url, parent_comment_id */ }
```

- [ ] **Step 2: Verify RED**

Run: `go test ./internal/ontology/actions ./internal/ontology/services -run 'Comment' -count=1`

Expected: FAIL because comment request/result/DTO do not expose audience or profile fields and private comments are not filtered.

### Task 2: Backend minimal implementation

**Files:**
- Modify: `../Chorai_Go/chorai-go/internal/api/dto/comment.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/actions/parity_action_stubs.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/actions/comment_actions.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/services/comment_service.go`
- Modify: `../Chorai_Go/chorai-go/internal/api/openapi.go`
- Modify: `../Chorai_Go/chorai-go/cmd/server/main.go`

**Interfaces:**
- Consumes: `ActorProfileRepository.GetByActorID/ListByActorIDs`, existing comment ownership and parent relations
- Produces: optional request `visibility`; response `visibility`, `username`, `avatar_url`; filtered viewer-specific list totals

- [ ] **Step 1: Add normalized audience to the Action payload**

```go
type CreateCommentRequest struct { /* existing fields */ Visibility string }
type commentContentPayload struct { /* existing fields */ Visibility string `json:"visibility,omitempty"` }
```

- [ ] **Step 2: Enforce private parent policy and persist the normalized audience**

Use `public` when omitted, reject unknown values, deny actors outside the commenter/card-author audience, and force replies to private parents to remain private.

- [ ] **Step 3: Hydrate and filter service DTOs**

Inject `ActorProfileRepository`, filter private comments and descendants before pagination, batch-load profiles, and emit `Chorai user` rather than an actor ID when a profile is absent.

- [ ] **Step 4: Update the OpenAPI request schema and composition root**

Add the `visibility` enum to `CreateCommentRequest` and pass `profileRepo` into `NewCommentService`.

- [ ] **Step 5: Verify GREEN**

Run: `go test ./internal/ontology/actions ./internal/ontology/services ./internal/ontology/handlers ./tests/contract -run 'Comment|OpenAPI' -count=1`

Expected: PASS.

### Task 3: CoreFlow comment decoding and thread assembly

**Files:**
- Create: `Packages/CoreFlow/Sources/CoreFlow/CommentModels.swift`
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/CommentModelsTests.swift`
- Modify: `ArcNote/Models/CommentModels.swift`

**Interfaces:**
- Consumes: flat Go comment DTO fields `comment_id`, `comment_asset_id`, `card_id`, `actor_id`, `username`, `avatar_url`, `parent_comment_id`, `visibility`, `body`, and timestamps
- Produces: `CommentModel.assembleThreads(_:)`, safe `displayName`, nested `replies`, and a manager that sends parent/audience values

- [ ] **Step 1: Write failing CoreFlow tests**

```swift
func testDecodesProfileWithoutUsingActorIDAsDisplayName() throws { /* JSON decode assertions */ }
func testMissingProfileUsesNeutralDisplayName() throws { /* never act_... */ }
func testAssembleThreadsNestsRepliesInStableOrder() throws { /* root, reply, nested reply */ }
```

- [ ] **Step 2: Verify RED**

Run: `swift test --package-path Packages/CoreFlow --filter CommentModelsTests`

Expected: FAIL because the CoreFlow comment model does not exist.

- [ ] **Step 3: Implement the tested model and adapt the app manager**

Decode additive profile/audience fields, default legacy audience to public, deduplicate flat pages, assemble parent IDs recursively, and insert new replies under their parent.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --package-path Packages/CoreFlow --filter CommentModelsTests`

Expected: PASS.

### Task 4: SwiftUI identity, avatar, private toggle, and reply flow

**Files:**
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/CommentUISourceContractTests.swift`
- Modify: `ArcNote/CommentPopupView.swift`
- Modify: `ArcNote/NetworkManager.swift`

**Interfaces:**
- Consumes: safe display name, resource-relative avatar URL, comment visibility, parent comment ID
- Produces: visible `secret`/`secret_active` toggle, reply selection/cancel UI, and POST body containing `parent_comment_id` plus `visibility`

- [ ] **Step 1: Write and run failing source-contract tests**

Run: `swift test --package-path Packages/CoreFlow --filter CommentUISourceContractTests`

Expected: FAIL because the current sheet lacks the private toggle/reply control and still falls back to the actor ID.

- [ ] **Step 2: Implement the minimal SwiftUI behavior**

Render the provided assets in a 44-point button, use `APIConfiguration.resourceURLString` for avatars, render `displayName`, expose a Reply button, focus the composer with a safe nickname, and submit the parent/audience fields.

- [ ] **Step 3: Verify GREEN**

Run: `swift test --package-path Packages/CoreFlow --filter 'CommentModelsTests|CommentUISourceContractTests'`

Expected: PASS.

### Task 5: Full focused verification

**Files:**
- Verify only; no new production files expected

**Interfaces:**
- Consumes: completed backend/iOS changes
- Produces: fresh build/test evidence and a requirement-by-requirement audit

- [ ] **Step 1: Format and test Go**

Run: `gofmt -w <changed-go-files>` then `go test ./internal/ontology/actions ./internal/ontology/services ./internal/ontology/handlers ./tests/contract -count=1`

- [ ] **Step 2: Test CoreFlow**

Run: `swift test --package-path Packages/CoreFlow`

- [ ] **Step 3: Build iOS**

Run: `xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 4: Inspect changes and privacy invariants**

Run: `git diff --check` in both repositories, inspect focused diffs, and scan the comment UI for any actor-ID display fallback.

- [ ] **Step 5: Optional live smoke when the local stack is healthy**

Create public/private root comments and a reply through the local API or existing authenticated UI smoke route; verify public viewer filtering, author visibility, nickname/avatar response fields, and normalized parent ID.
