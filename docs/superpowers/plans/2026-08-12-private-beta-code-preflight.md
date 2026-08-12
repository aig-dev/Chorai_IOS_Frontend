# Private Beta Code Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify a Product Access Code on the Private Beta entry screen before Sign Up, without reserving or consuming it, while keeping registration as the only atomic claim authority.

**Architecture:** The Go backend adds one read-only `POST /api/auth/access-code/preflight` boundary backed by a shared eligibility evaluator. Read-only mode performs ordinary reads; final registration calls the same evaluator with row locks and then executes the existing conditional claim. CoreFlow owns bounded preflight result/error types, `NetworkAccess` maps the wire contract, and `PrivateBetaEntryView` saves and navigates only after an injected preflighter succeeds.

**Tech Stack:** Go 1.x, Gin, GORM/MySQL/SQLite tests, Redis-backed rate limiting, Swift 5.9, SwiftUI, Combine, Alamofire, CoreFlow, XCTest/XCUITest, Xcode 26 iOS Simulator.

## Global Constraints

- `POST /api/auth/access-code/preflight` is unauthenticated and accepts only `{"access_code":"CRAI-XXXX"}`.
- The local and server request bound is 9 through 64 characters after trimming.
- Preflight is read-only business logic: it creates no Actor, AccessGrant, CohortMember, Activity, ActionLog, Relation, reservation, or claim.
- The only permitted preflight write is the dedicated Redis abuse-prevention counter.
- All authoritative ineligible states return HTTP 403 with top-level `error_code: PRODUCT_ACCESS_CODE_INVALID` and `message: product access code is invalid or no longer available`.
- A successful preflight returns HTTP 200 with `{"success":true,"data":{"available":true}}` and no code metadata.
- Missing policy, codec, or storage authority fails closed with HTTP 503; malformed JSON or out-of-bound input returns HTTP 400 before eligibility storage is queried.
- The dedicated limiter is 10 preflight attempts per IP per minute, independent of registration and email verification; limiter storage failure remains fail-open.
- Registration remains the only code claim, repeats eligibility under row lock, and rolls back account creation if the code becomes unavailable.
- Never log a plaintext Product Access Code or an unredacted request/response payload that contains it.
- iOS deployment remains iOS 16+ on iPhone; do not add an iPad product target or a new dependency.
- Keep existing Sign Up, Google, and Apple payloads unchanged: they continue forwarding one complete `access_code` plus `idempotency_key` pair.
- Do not add a migration, database table, column, ontology primitive, or client-side eligibility rule.
- The Go worktree already contains unrelated user edits and a separate verified admin-policy endpoint change; stage only preflight hunks and never stage Spark/Explore changes.

## File Structure

### Go backend repository: `../Chorai_Go`

- Create `chorai-go/internal/access/code_eligibility.go`: one package-level eligibility evaluator, read/lock mode, typed reader interface, and bounded availability errors. It owns no HTTP or Action side effects.
- Create `chorai-go/internal/access/code_eligibility_test.go`: table tests for every predicate and for read-only versus lock mode.
- Modify `chorai-go/internal/ontology/actions/access_actions.go`: adapt GORM plus the campaign codec to the evaluator and keep the existing mutation/provenance sequence after a locked eligible result.
- Modify `chorai-go/internal/ontology/actions/access_actions_test.go`: prove preflight-style evaluation makes zero product writes and final claim still consumes exactly once.
- Modify `chorai-go/internal/ontology/actions/access_registration_test.go`: retain rollback and exactly-once registration guarantees after sharing the evaluator.
- Modify `chorai-go/internal/ontology/actions/action_executor.go`: expose `PreflightAccessCode(context.Context, string) error` on the existing concrete dependency boundary without creating an Action.
- Modify `chorai-go/internal/api/dto/access.go`: add the strict preflight input and bounded success result.
- Modify `chorai-go/internal/ontology/services/access_service.go`: add the read-only preflight dependency/method; do not place DB logic in the service.
- Modify `chorai-go/internal/ontology/services/access_service_test.go`: verify trimming, unavailable dependency behavior, and pass-through eligibility errors.
- Modify `chorai-go/internal/ontology/handlers/access_handler.go`: bind the public request, emit the exact flat 200/400/403/503 wire contract, and set `Cache-Control: no-store`.
- Modify `chorai-go/internal/ontology/handlers/access_handler_test.go`: cover exact public bodies, auth independence, and no service call on invalid input.
- Modify `chorai-go/internal/auth/rate_limiter.go`: delegate middleware checks to the existing `RateLimiterCore` so the limiter is testable with `cache.InMemoryClient`, while preserving fail-open behavior.
- Create `chorai-go/internal/auth/rate_limiter_test.go`: cover 10/minute isolation, integer `Retry-After`, and fail-open storage errors.
- Modify `chorai-go/internal/api/router.go`: mount the preflight handler inside `/api/auth` with limiter key `access_code_preflight`; do not attach identity or product-access middleware.
- Modify `chorai-go/tests/contract/campaign_access_contract_test.go`: prove the new route is public and independent of the access gate.
- Modify `chorai-go/tests/integration/access_claim_integration_test.go`: exercise available/invalid preflight followed by the existing atomic claim and verify zero writes before claim.

### iOS repository: current directory

- Modify `Packages/CoreFlow/Sources/CoreFlow/AccessModels.swift`: add preflight request/result, `AccessCodePreflightError`, `AccessCodePreflighting`, and pure response classification.
- Modify `Packages/CoreFlow/Tests/CoreFlowTests/AccessModelsTests.swift`: cover exact coding keys and complete status/error classification.
- Modify `ArcNote/APIEnvironment.swift`: add the canonical `/api/auth/access-code/preflight` route.
- Modify `ArcNote/NetworkModels.swift`: add the success envelope and a dedicated preflight response carrying optional `Retry-After` seconds.
- Modify `ArcNote/NetworkManager.swift`: send only `access_code`, suppress payload logging, decode the success envelope, parse integer `Retry-After`, and publish one bounded preflight wire result.
- Modify `ArcNote/KeychainStore.swift`: make `NetworkAccess` implement `AccessCodePreflighting` and translate all wire/network failures to CoreFlow errors.
- Modify `ArcNote/AccessGateView.swift`: inject preflight/store dependencies, implement `Checking…`, suppress duplicate calls, cancel safely, clear only a matching stale invalid code, and save/navigate only on success.
- Modify `ArcNote/ArcNoteApp.swift`: inject deterministic available/invalid/rate-limit/unavailable/delayed fixtures for the Private Beta UI route.
- Modify `Packages/CoreFlow/Tests/CoreFlowTests/IOSAccessSourceTests.swift`: assert the route, redaction, dependency injection, and unchanged registration pair contract.
- Modify `ArcNoteUITests/ArcNoteUITests.swift`: exercise success, invalid, rate-limited, service-unavailable, checking/duplicate, and cancellation behavior.

---

### Task 1: Build One Shared, Side-Effect-Free Eligibility Evaluator

**Files:**
- Create: `../Chorai_Go/chorai-go/internal/access/code_eligibility.go`
- Create: `../Chorai_Go/chorai-go/internal/access/code_eligibility_test.go`

**Interfaces:**
- Consumes: `campaign.Codec.Digest(string) string`, `campaign.Validate(string) (campaign.BetaSpec, string, error)`, `domainmodels.AccessCode`, `domainmodels.Campaign`, and `models.AccessPolicy`.
- Produces: `type CodeEligibilityMode uint8` with `CodeEligibilityReadOnly` and `CodeEligibilityForUpdate`.
- Produces: `type CodeEligibilityReader interface { CurrentProductAccessPolicy(context.Context, CodeEligibilityMode) (*models.AccessPolicy, error); AccessCodeByDigest(context.Context, string, CodeEligibilityMode) (*domainmodels.AccessCode, error); CampaignByID(context.Context, string, CodeEligibilityMode) (*domainmodels.Campaign, error) }`.
- Produces: `type CodeEligibilityResult struct { Code domainmodels.AccessCode; Campaign domainmodels.Campaign }`.
- Produces: `func EvaluateProductAccessCode(context.Context, CodeEligibilityReader, *campaign.Codec, string, time.Time, CodeEligibilityMode) (CodeEligibilityResult, error)`.
- Produces: `ErrCodeInvalid` for every authoritative ineligible state and `ErrCodeAuthorityUnavailable` for reader/codec/policy authority failures.

- [ ] **Step 1: Write the failing table test for every eligibility predicate.**

  The test reader records requested modes and returns controlled policy/code/campaign rows. Use one valid baseline and mutate one predicate per case:

  ```go
  tests := []struct {
      name   string
      mutate func(*codeEligibilityFixture)
  }{
      {"policy is not private beta", func(f *codeEligibilityFixture) { f.policy.Mode = "open" }},
      {"digest is unknown", func(f *codeEligibilityFixture) { f.code = nil }},
      {"code is claimed", func(f *codeEligibilityFixture) { f.code.ClaimantID = stringPointer("actor_other") }},
      {"code is revoked", func(f *codeEligibilityFixture) { f.code.RevokedAt = timePointer(f.now) }},
      {"code is expired", func(f *codeEligibilityFixture) { f.code.ExpiresAt = f.now }},
      {"campaign is missing", func(f *codeEligibilityFixture) { f.campaign = nil }},
      {"campaign is unpublished", func(f *codeEligibilityFixture) { f.campaign.PublishedAt = nil }},
      {"campaign spec is malformed", func(f *codeEligibilityFixture) { f.campaign.Spec = "{" }},
      {"campaign hash is stale", func(f *codeEligibilityFixture) { f.campaign.Hash = strings.Repeat("0", 64) }},
      {"campaign kind is wrong", func(f *codeEligibilityFixture) { f.campaign.Kind = "marketing" }},
      {"campaign spec version is wrong", func(f *codeEligibilityFixture) { f.campaign.SpecVersion = 2 }},
      {"campaign is paused", func(f *codeEligibilityFixture) { f.campaign.State = "paused" }},
      {"campaign has not started", func(f *codeEligibilityFixture) { f.campaign.StartsAt = f.now.Add(time.Minute) }},
      {"campaign has ended", func(f *codeEligibilityFixture) { ended := f.now; f.campaign.EndsAt = &ended }},
      {"cohort is not allowed", func(f *codeEligibilityFixture) { f.code.Cohort = "unknown" }},
  }
  ```

  Each case must assert `errors.Is(err, access.ErrCodeInvalid)` and must not expose which predicate failed. Add separate cases for missing codec, codec without a key, missing policy, and reader errors; assert `ErrCodeAuthorityUnavailable` rather than invalid.

- [ ] **Step 2: Run the new focused suite and verify RED.**

  Run:

  ```bash
  cd ../Chorai_Go/chorai-go
  go test ./internal/access -run 'TestEvaluateProductAccessCode' -count=1
  ```

  Expected: compile failure because `EvaluateProductAccessCode`, `CodeEligibilityReader`, and the typed errors do not exist.

- [ ] **Step 3: Implement the evaluator with one fixed predicate sequence.**

  `EvaluateProductAccessCode` must:

  ```go
  if reader == nil || codec == nil || !codec.Available() {
      return CodeEligibilityResult{}, ErrCodeAuthorityUnavailable
  }
  now = now.UTC()
  policy, err := reader.CurrentProductAccessPolicy(ctx, mode)
  if err != nil || policy == nil || policy.PolicyID != "pol_product_access" {
      return CodeEligibilityResult{}, ErrCodeAuthorityUnavailable
  }
  if policy.Mode != "private_beta" {
      return CodeEligibilityResult{}, ErrCodeInvalid
  }
  digest := codec.Digest(plain)
  if digest == "" {
      return CodeEligibilityResult{}, ErrCodeInvalid
  }
  ```

  Then load the code and campaign using the same `mode`; map record absence to `ErrCodeInvalid`, map storage errors to `ErrCodeAuthorityUnavailable`, validate `Campaign.Spec` and hash, and apply every predicate listed in Step 1. Return copies of the two rows only when all predicates pass. This function must not call `Create`, `Save`, `Update`, or mutate an input row.

- [ ] **Step 4: Add mode-forwarding and success tests.**

  For both `CodeEligibilityReadOnly` and `CodeEligibilityForUpdate`, assert all three reader calls observe the same mode. On success assert the returned IDs match the fixture; assert the reader recorded no write call and the input rows remain deeply equal to their pre-call snapshots.

- [ ] **Step 5: Run the focused package and verify GREEN.**

  Run:

  ```bash
  cd ../Chorai_Go/chorai-go
  go test ./internal/access -run 'TestEvaluateProductAccessCode' -count=1
  ```

  Expected: PASS.

- [ ] **Step 6: Format and checkpoint Task 1.**

  ```bash
  cd ../Chorai_Go/chorai-go
  gofmt -w internal/access/code_eligibility.go internal/access/code_eligibility_test.go
  git diff --check -- internal/access/code_eligibility.go internal/access/code_eligibility_test.go
  git add internal/access/code_eligibility.go internal/access/code_eligibility_test.go
  git commit -m "feat(access): share private beta code eligibility"
  ```

  Before committing, `git diff --cached --name-only` must list exactly those two files.

### Task 2: Reuse Eligibility In Read-Only Preflight And Atomic Claim

**Files:**
- Modify: `../Chorai_Go/chorai-go/internal/ontology/actions/action_executor.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/actions/access_actions.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/actions/access_actions_test.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/actions/access_registration_test.go`

**Interfaces:**
- Consumes: Task 1 `access.EvaluateProductAccessCode(...)` and `access.CodeEligibilityMode`.
- Produces: `func (e *actionExecutor) PreflightAccessCode(context.Context, string) error`.
- Produces: a private `gormCodeEligibilityReader` whose read-only mode uses plain GORM reads and whose update mode adds `clause.Locking{Strength: "UPDATE"}` to AccessCode/Campaign plus `SHARE` to policy rows.
- Preserves: `actions.ErrCodeInvalid` as an alias of `access.ErrCodeInvalid` so AuthService and existing callers keep their current error mapping.
- Preserves: `ClaimAccess`, `AttachRegistration`, `claimPrivateTx`, conditional code update, grant/cohort creation, and provenance behavior.

- [ ] **Step 1: Write failing action tests for read-only preflight and post-preflight race safety.**

  Add `TestPreflightAccessCodeIsReadOnly` using `newAccessActionFixture`:

  ```go
  before := countAccessFacts(t, fixture.db)
  err := fixture.executor.PreflightAccessCode(context.Background(), plain)
  require.NoError(t, err)
  assert.Equal(t, before, countAccessFacts(t, fixture.db))
  assertCodeUnclaimed(t, fixture.db, "code_preflight")
  ```

  `countAccessFacts` must count actors, access grants, cohort members, activities, relations, and action logs. Add `TestRegistrationRechecksCodeAfterSuccessfulPreflight`: preflight succeeds, another actor claims the code, registration then returns `ErrCodeInvalid`, and the attempted registration actor/profile/credential/session do not exist.

- [ ] **Step 2: Run the focused action suites and verify RED.**

  ```bash
  cd ../Chorai_Go/chorai-go
  go test ./internal/ontology/actions -run 'Test(PreflightAccessCodeIsReadOnly|RegistrationRechecksCodeAfterSuccessfulPreflight)' -count=1
  ```

  Expected: compile failure because `PreflightAccessCode` does not exist.

- [ ] **Step 3: Add the GORM reader adapter and read-only method.**

  The adapter should hold `db *gorm.DB`; each method creates a scoped query from `db.WithContext(ctx)`. Map `gorm.ErrRecordNotFound` to `(nil, nil)` and other DB errors to `access.ErrCodeAuthorityUnavailable`. `CurrentProductAccessPolicy` must validate the base `Policy` type/enforcement row and read the latest `AccessPolicy`. Set `var ErrCodeInvalid = access.ErrCodeInvalid` in the actions package, add `PreflightAccessCode` to the public `ActionExecutor` interface, and fail with `access.ErrCodeAuthorityUnavailable` when the executor or DB is nil. `PreflightAccessCode` must use a single read-only transaction for a consistent snapshot and call:

  ```go
  _, err := access.EvaluateProductAccessCode(
      ctx,
      gormCodeEligibilityReader{db: tx},
      e.campaignCodec,
      strings.TrimSpace(plain),
      time.Now().UTC(),
      access.CodeEligibilityReadOnly,
  )
  return err
  ```

  It must not begin an Activity and must not be named or registered as an ontology Action.

- [ ] **Step 4: Replace duplicated claim predicates with locked evaluator output.**

  Keep idempotency-key validation and the existing same-actor/same-key replay path. For an unclaimed code, call Task 1 in `CodeEligibilityForUpdate` mode, use the returned code/campaign rows for provenance relations, then execute the existing guarded `UPDATE ... claimant_id IS NULL ...` and grant/cohort writes. Remove only predicate duplication; retain the transaction boundary and all `USED`/`GENERATED` relations.

  The claim path must still support actor-idempotent replay before treating an already-claimed code as invalid. Implement that as a narrow locked digest lookup before the shared fresh-eligibility call; no public preflight path receives actor or key information.

- [ ] **Step 5: Run action and registration suites and verify GREEN.**

  ```bash
  cd ../Chorai_Go/chorai-go
  go test ./internal/ontology/actions -run 'Test(ClaimAccess|PreflightAccessCode|Registration|AccessActionProvenance)' -count=1
  ```

  Expected: PASS, including existing single-use, paused-campaign, rollback, provenance, and idempotency cases.

- [ ] **Step 6: Format and checkpoint Task 2 without unrelated backend files.**

  ```bash
  cd ../Chorai_Go/chorai-go
  gofmt -w internal/ontology/actions/action_executor.go internal/ontology/actions/access_actions.go internal/ontology/actions/access_actions_test.go internal/ontology/actions/access_registration_test.go
  git diff --check -- internal/ontology/actions/action_executor.go internal/ontology/actions/access_actions.go internal/ontology/actions/access_actions_test.go internal/ontology/actions/access_registration_test.go
  git add -p -- internal/ontology/actions/action_executor.go internal/ontology/actions/access_actions.go internal/ontology/actions/access_actions_test.go internal/ontology/actions/access_registration_test.go
  git commit -m "refactor(access): recheck codes through shared eligibility"
  ```

  Reject any staged Spark or Explore hunk. `git diff --cached --name-only` must contain only the four Task 2 files.

### Task 3: Add The Public Go Contract And Independent Limiter

**Files:**
- Modify: `../Chorai_Go/chorai-go/internal/api/dto/access.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/services/access_service.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/services/access_service_test.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/handlers/access_handler.go`
- Modify: `../Chorai_Go/chorai-go/internal/ontology/handlers/access_handler_test.go`
- Modify: `../Chorai_Go/chorai-go/internal/auth/rate_limiter.go`
- Create: `../Chorai_Go/chorai-go/internal/auth/rate_limiter_test.go`
- Modify: `../Chorai_Go/chorai-go/internal/api/router.go`
- Modify: `../Chorai_Go/chorai-go/tests/contract/campaign_access_contract_test.go`
- Modify: `../Chorai_Go/chorai-go/tests/integration/access_claim_integration_test.go`

**Interfaces:**
- Consumes: `PreflightAccessCode(context.Context, string) error` from Task 2.
- Produces: `dto.CodePreflightInput{AccessCode string}` with `binding:"required,min=9,max=64"`.
- Produces: `dto.CodePreflightResult{Available bool}`.
- Produces: `AccessService.Preflight(context.Context, dto.CodePreflightInput) (*dto.CodePreflightResult, error)`.
- Produces: `AccessHandler.BindPreflight(*gin.Context)`, `AccessHandler.Preflight(*gin.Context)`, and `POST /api/auth/access-code/preflight`.
- Produces: `NewRateLimiterWithStore(auth.RateLimitStore) *RateLimiter` for deterministic middleware tests; production `NewRateLimiter(*cache.RedisClient)` remains source-compatible.

- [ ] **Step 1: Write failing service and handler tests for the exact boundary.**

  Extend the service stub with `preflightCalls` and `preflightErr`. Tests must assert:

  ```go
  // Success
  require.Equal(t, http.StatusOK, recorder.Code)
  assert.JSONEq(t, `{"success":true,"data":{"available":true}}`, recorder.Body.String())

  // Authoritative invalid
  require.Equal(t, http.StatusForbidden, recorder.Code)
  assert.JSONEq(t, `{"success":false,"error_code":"PRODUCT_ACCESS_CODE_INVALID","message":"product access code is invalid or no longer available"}`, recorder.Body.String())
  ```

  Add malformed JSON, unknown field, 8-character, and 65-character tests; each must assert zero service calls. Add codec/policy/storage authority errors and assert the same bounded 503 response without internal details. Assert `Cache-Control: no-store` on all outcomes.

- [ ] **Step 2: Run focused service/handler tests and verify RED.**

  ```bash
  cd ../Chorai_Go/chorai-go
  go test ./internal/ontology/services ./internal/ontology/handlers -run 'Test.*Preflight' -count=1
  ```

  Expected: compile failure because DTO, service, and handler methods do not exist.

- [ ] **Step 3: Implement the DTO and service boundary.**

  Add a dedicated read dependency rather than implying a write:

  ```go
  type AccessCodePreflighter interface {
      PreflightAccessCode(ctx context.Context, accessCode string) error
  }

  func (s *AccessService) Preflight(ctx context.Context, input dto.CodePreflightInput) (*dto.CodePreflightResult, error) {
      if s.preflighter == nil {
          return nil, access.ErrCodeAuthorityUnavailable
      }
      if err := s.preflighter.PreflightAccessCode(ctx, strings.TrimSpace(input.AccessCode)); err != nil {
          return nil, err
      }
      return &dto.CodePreflightResult{Available: true}, nil
  }
  ```

  Add the preflighter as an explicit `NewAccessService` constructor parameter and update every constructor call/stub. Do not overload `AccessActions` with a read method.

- [ ] **Step 4: Implement a flat public handler response separate from existing `/api/v1/access/claim`.**

  `BindPreflight` sets `Cache-Control: no-store`, uses `dto.BindStrict`, emits the bounded 400 response on failure, and stores the validated `dto.CodePreflightInput` in a private Gin context key. `Preflight` reads that value, calls the service, and emits `gin.H{"success": true, "data": result}` so no metadata leaks into the exact contract. On `access.ErrCodeInvalid`, emit the fixed flat 403 body. On `access.ErrCodeAuthorityUnavailable`, `access.ErrPolicyUnavailable`, `campaign.ErrCodeKey`, or a database/app service-unavailable error, emit a fixed flat 503 body such as `{"success":false,"error_code":"PRODUCT_ACCESS_CODE_UNAVAILABLE","message":"product access code verification is temporarily unavailable"}`. Keep the current authenticated claim mapping (`422 ACCESS_CODE_INVALID`) unchanged.

  Splitting bind from eligibility lets the router execute `BindPreflight`, then the limiter, then `Preflight`; malformed/out-of-bound bodies therefore return 400 without incrementing Redis or querying eligibility storage.

- [ ] **Step 5: Write failing limiter tests using `cache.InMemoryClient`.**

  Build a Gin route with `NewRateLimiterWithStore(cache.NewInMemoryClient()).Middleware("access_code_preflight", RateLimitConfig{Max: 10, Window: time.Minute})`. Assert requests 1–10 return 204, request 11 returns 429, `Retry-After` parses as a positive base-10 integer, and a route under key `register` is still allowed. A store stub whose `Incr` returns an error must allow the request through.

- [ ] **Step 6: Run the limiter test and verify RED.**

  ```bash
  cd ../Chorai_Go/chorai-go
  go test ./internal/auth -run 'TestRateLimiterMiddleware' -count=1
  ```

  Expected: compile failure because `NewRateLimiterWithStore` does not exist.

- [ ] **Step 7: Refactor middleware onto `RateLimiterCore` and make `Retry-After` standards-compatible.**

  `RateLimiter` stores `core *RateLimiterCore`. `NewRateLimiter(redis)` delegates to `NewRateLimiterWithStore(redis)`. Middleware calls `core.Check`; on error it calls `c.Next()`; on rejection it sets `Retry-After` to `max(1, ceil(seconds))`, emits the existing flat `RATE_LIMIT_EXCEEDED` response, aborts, and returns. This preserves production behavior and makes the dedicated key testable without a real Redis server.

- [ ] **Step 8: Mount the public route and add route/integration tests.**

  Under the existing `/api/auth` group:

  ```go
  preflightHandlers := []gin.HandlerFunc{r.accessHandler.BindPreflight}
  if r.rateLimiter != nil {
      preflightHandlers = append(preflightHandlers, r.rateLimiter.Middleware(
          "access_code_preflight",
          authlib.RateLimitConfig{Max: 10, Window: time.Minute},
      ))
  }
  preflightHandlers = append(preflightHandlers, r.accessHandler.Preflight)
  auth.POST("/access-code/preflight", preflightHandlers...)
  ```

  Register it only when `r.accessHandler != nil`. Contract tests must invoke it without `actor_id`, assert 200, and assert the product access gate call count stays zero. Integration tests must verify an available code returns 200 and remains unclaimed with zero new product facts, a claimed code returns the exact 403, then a fresh code registers and claims exactly once.

- [ ] **Step 9: Run the complete focused Go boundary suite and verify GREEN.**

  ```bash
  cd ../Chorai_Go/chorai-go
  go test ./internal/access ./internal/auth ./internal/ontology/actions ./internal/ontology/services ./internal/ontology/handlers -count=1
  go test ./tests/contract -run 'CampaignAccess|AccessCodePreflight' -count=1
  go test ./tests/integration -run 'PrivateBetaAccess(Claim|CodePreflight)' -count=1
  ```

  Expected: PASS.

- [ ] **Step 10: Format and checkpoint Task 3 using patch staging.**

  ```bash
  cd ../Chorai_Go/chorai-go
  gofmt -w internal/api/dto/access.go internal/ontology/services/access_service.go internal/ontology/services/access_service_test.go internal/ontology/handlers/access_handler.go internal/ontology/handlers/access_handler_test.go internal/auth/rate_limiter.go internal/auth/rate_limiter_test.go internal/api/router.go tests/contract/campaign_access_contract_test.go tests/integration/access_claim_integration_test.go
  git diff --check
  git add -p -- internal/api/dto/access.go internal/ontology/services/access_service.go internal/ontology/services/access_service_test.go internal/ontology/handlers/access_handler.go internal/ontology/handlers/access_handler_test.go internal/auth/rate_limiter.go internal/auth/rate_limiter_test.go internal/api/router.go tests/contract/campaign_access_contract_test.go tests/integration/access_claim_integration_test.go
  git diff --cached --check
  git commit -m "feat(auth): add private beta code preflight"
  ```

  Because `router.go`, access handler/service files, and the contract test contain a separate uncommitted admin-policy change, inspect every staged hunk. Do not stage that pre-existing change in this commit and do not stage any Spark/Explore file.

### Task 4: Define The CoreFlow Preflight Contract And Network Mapping

**Files:**
- Modify: `Packages/CoreFlow/Sources/CoreFlow/AccessModels.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/AccessModelsTests.swift`
- Modify: `ArcNote/APIEnvironment.swift`
- Modify: `ArcNote/NetworkModels.swift`
- Modify: `ArcNote/NetworkManager.swift`
- Modify: `ArcNote/KeychainStore.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/IOSAccessSourceTests.swift`

**Interfaces:**
- Produces: `AccessCodePreflightInput(accessCode: String)` encoded as `access_code` only.
- Produces: `AccessCodePreflightResult(available: Bool)`.
- Produces: `enum AccessCodePreflightError: Error, Equatable, Sendable { case invalid; case rateLimited(retryAfterSeconds: Int?); case temporarilyUnavailable }`.
- Produces: `protocol AccessCodePreflighting: Sendable { func preflight(accessCode: String) async throws -> AccessCodePreflightResult }`.
- Produces: `AccessCodePreflightError.classify(statusCode:errorCode:retryAfterSeconds:)` as the one pure mapping function.
- Produces: `APIEnvironment.AccessRoute.preflight = "/api/auth/access-code/preflight"`.
- Produces: `NetworkManager.preflightAccessCode(_:) -> AnyPublisher<AccessCodePreflightWireResult, Never>`.
- Produces: `NetworkAccess.preflight(accessCode:) async throws -> AccessCodePreflightResult`.

- [ ] **Step 1: Write failing CoreFlow model and classifier tests.**

  Add tests that encode `AccessCodePreflightInput(accessCode: "CRAI-7KQ9")` and assert the JSON object equals exactly `["access_code": "CRAI-7KQ9"]`. Decode `{"available":true}`. Test classification:

  ```swift
  XCTAssertEqual(
      AccessCodePreflightError.classify(
          statusCode: 403,
          errorCode: "PRODUCT_ACCESS_CODE_INVALID",
          retryAfterSeconds: nil
      ),
      .invalid
  )
  XCTAssertEqual(
      AccessCodePreflightError.classify(
          statusCode: 429,
          errorCode: "RATE_LIMIT_EXCEEDED",
          retryAfterSeconds: 37
      ),
      .rateLimited(retryAfterSeconds: 37)
  )
  XCTAssertEqual(
      AccessCodePreflightError.classify(statusCode: 503, errorCode: nil, retryAfterSeconds: nil),
      .temporarilyUnavailable
  )
  ```

  Unexpected 2xx/4xx/5xx combinations must map to `.temporarilyUnavailable`; never infer eligibility from copy text.

- [ ] **Step 2: Run the CoreFlow tests and verify RED.**

  ```bash
  swift test --package-path Packages/CoreFlow --filter AccessModelsTests
  ```

  Expected: compile failure because the preflight types do not exist.

- [ ] **Step 3: Implement the bounded CoreFlow types and pure classifier.**

  Keep the new protocol independent of Alamofire, Combine, `NetworkError`, and SwiftUI. Normalize non-positive retry values to `nil`. The success result is valid only when `available == true`; a decoded false result is treated as `.invalid` by the adapter.

- [ ] **Step 4: Add a dedicated preflight wire result that owns status and header metadata.**

  Add app-internal types:

  ```swift
  struct AccessCodePreflightResponse: Codable {
      let success: Bool
      let data: AccessCodePreflightResult
  }

  enum AccessCodePreflightWireResult {
      case success(AccessCodePreflightResult)
      case failure(
          statusCode: Int?,
          errorCode: String?,
          retryAfterSeconds: Int?
      )
  }
  ```

  Implement the preflight request as its own small Alamofire publisher so it can inspect `HTTPURLResponse` when 403/429/503 is returned. Parse `value(forHTTPHeaderField: "Retry-After")` as a positive integer and decode only `error_code` from the flat failure body. Do not change shared `NetworkError` associated values or unrelated network calls.

- [ ] **Step 5: Write failing source-contract assertions for the wire call.**

  `IOSAccessSourceTests` must require:

  ```swift
  XCTAssertTrue(environment.contains("/api/auth/access-code/preflight"))
  XCTAssertTrue(network.contains("func preflightAccessCode"))
  XCTAssertTrue(network.contains("请求参数: <redacted>"))
  XCTAssertTrue(network.contains("\"access_code\": input.accessCode"))
  XCTAssertFalse(network.contains("\"idempotency_key\": input.idempotencyKey"))
  XCTAssertTrue(store.contains("AccessCodePreflighting"))
  ```

  Scope the last negative assertion to the preflight method substring so the existing claim method remains allowed to contain `idempotency_key`.

- [ ] **Step 6: Add the exact route, response envelope, request publisher, and adapter.**

  `NetworkManager.preflightAccessCode` sends only `AccessCodePreflightInput.accessCode`, uses `.post` and `JSONEncoding.default`, and prints only redacted request/response markers. `NetworkAccess.preflight` awaits the non-failing publisher; on `.success` require `available == true`. Classify `.failure(403, PRODUCT_ACCESS_CODE_INVALID, nil)` as `.invalid`, `.failure(429, RATE_LIMIT_EXCEEDED, retry)` as `.rateLimited`, and every missing-status, 503, decoding, or transport failure as `.temporarilyUnavailable`. Do not print the code or server payload.

- [ ] **Step 7: Run CoreFlow and source-contract suites and verify GREEN.**

  ```bash
  swift test --package-path Packages/CoreFlow --filter AccessModelsTests
  swift test --package-path Packages/CoreFlow --filter IOSAccessSourceTests
  ```

  Expected: PASS.

- [ ] **Step 8: Checkpoint Task 4.**

  ```bash
  git diff --check
  git add Packages/CoreFlow/Sources/CoreFlow/AccessModels.swift Packages/CoreFlow/Tests/CoreFlowTests/AccessModelsTests.swift ArcNote/APIEnvironment.swift ArcNote/NetworkModels.swift ArcNote/NetworkManager.swift ArcNote/KeychainStore.swift Packages/CoreFlow/Tests/CoreFlowTests/IOSAccessSourceTests.swift
  git diff --cached --check
  git commit -m "feat(ios): add access code preflight client"
  ```

### Task 5: Gate Sign Up On A Successful Preflight

**Files:**
- Modify: `ArcNote/AccessGateView.swift`
- Modify: `ArcNote/ArcNoteApp.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/IOSAccessSourceTests.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: `AccessCodePreflighting`, `AccessCodePreflightResult`, `AccessCodePreflightError`, and existing `CodeStoring`.
- Produces: `PrivateBetaEntryView(preflighter: any AccessCodePreflighting = NetworkAccess.shared, codeStore: any CodeStoring = KeychainStore.shared)`.
- Produces: fixture modes selected by `CHORAI_PRIVATE_BETA_PREFLIGHT_FIXTURE`: `available`, `invalid`, `rate_limited`, `unavailable`, and `delayed_available`.
- Preserves: `SignUpView`, pending-code/idempotency-key generation, and existing Sign In navigation.

- [ ] **Step 1: Change the UI tests first to require server preflight behavior.**

  Update the existing success test to launch with `CHORAI_PRIVATE_BETA_PREFLIGHT_FIXTURE=available`, tap Continue, observe `private-beta.checking`, then reach Sign Up. Add these tests:

  ```swift
  func testPrivateBetaEntryRejectsAuthoritativelyInvalidCodeBeforeSignup()
  func testPrivateBetaEntryShowsRateLimitWithoutClearingPendingCode()
  func testPrivateBetaEntryShowsTemporaryFailureWithoutClearingPendingCode()
  func testPrivateBetaEntryDisablesDuplicateSubmissionWhileChecking()
  func testPrivateBetaEntryCancellationDoesNotPersistOrNavigateAfterLateSuccess()
  ```

  The invalid test enters `CRAI-BR8K`, expects `This Product Access Code is invalid or no longer available.`, and asserts Sign Up is absent. The 37-second rate fixture expects `Too many checks. Try again in 37 seconds.`; a nil retry fixture expects `Too many checks. Try again shortly.`. Unavailable expects `Code verification is temporarily unavailable. Try again.`.

- [ ] **Step 2: Run the focused UI tests and verify RED.**

  ```bash
  xcodebuild test \
    -project ArcNote.xcodeproj \
    -scheme ArcNoteUITests \
    -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryUsesTheCurrentSignupSystemWithoutDuplicateCode \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryRejectsAuthoritativelyInvalidCodeBeforeSignup
  ```

  Expected: FAIL because Continue still navigates on format alone and no checking state exists.

- [ ] **Step 3: Inject dependencies and implement the captured-request state machine.**

  Add:

  ```swift
  private let preflighter: any AccessCodePreflighting
  private let codeStore: any CodeStoring
  @State private var isChecking = false
  @State private var requestID: UUID?
  @State private var checkTask: Task<Void, Never>?
  ```

  `continueToAccountEntry` trims and validates locally, captures `candidate` plus a new UUID, sets `isChecking = true`, clears old copy, and launches one task. The completion path first checks `!Task.isCancelled && requestID == id`; only then may it save or mutate navigation. Set `requestID = nil` and `isChecking = false` in the accepted completion path. Ignore stale completions completely.

- [ ] **Step 4: Implement exact success and error effects.**

  On success with `available == true`: `codeStore.save(candidate)`, clear message, and set `showSignUp = true`. On `.invalid`: if `codeStore.load()` trimmed equals `candidate`, call `clear()`; show the fixed invalid copy. On `.rateLimited(let seconds)`: retain storage and choose the exact numeric/shortly copy. On `.temporarilyUnavailable` or any other error: retain storage and show the fixed temporary copy. Never navigate after an error.

- [ ] **Step 5: Make checking visibly and mechanically exclusive.**

  Disable the TextField, Continue button, Back button, and Sign In link while checking. Render `ProgressView()` plus `Text("Checking…")` in the Continue label and apply `.accessibilityIdentifier("private-beta.checking")`. Add `.disabled(isChecking)` and prevent the handler from starting if `isChecking` is already true. On disappear, cancel the task, clear `requestID`, and set `isChecking = false`; a late result therefore cannot save or navigate.

- [ ] **Step 6: Add deterministic app fixtures without a live backend.**

  Under `#if DEBUG`, add a sendable fixture preflighter that reads `CHORAI_PRIVATE_BETA_PREFLIGHT_FIXTURE`. `available` returns immediately; `invalid`, `rate_limited`, and `unavailable` throw typed CoreFlow errors; `delayed_available` awaits two seconds with cancellation checking before returning. Inject it only into the `--ui-test-private-beta-entry` route. Use an in-memory `CodeStoring` fixture so tests can seed and inspect pending values without touching a developer Keychain.

- [ ] **Step 7: Extend source contracts for persistence and unchanged registration.**

  Require that `AccessGateView.swift` contains injected `preflighter`/`codeStore`, `Task.isCancelled`, request identity checking, `codeStore.save(candidate)` after the awaited preflight, matching stale-value comparison before `clear()`, and `.disabled(isChecking)`. Retain all current assertions proving `SignUpView` has no duplicate access field and sends `accessCode` plus `idempotencyKey` to email, Google, and Apple registration.

- [ ] **Step 8: Run CoreFlow and the complete Private Beta UI fixture and verify GREEN.**

  ```bash
  swift test --package-path Packages/CoreFlow --filter 'AccessModelsTests|IOSAccessSourceTests'
  xcodebuild test \
    -project ArcNote.xcodeproj \
    -scheme ArcNoteUITests \
    -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryUsesTheCurrentSignupSystemWithoutDuplicateCode \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryRejectsMalformedCodeBeforeRegistration \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryRejectsAuthoritativelyInvalidCodeBeforeSignup \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryShowsRateLimitWithoutClearingPendingCode \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryShowsTemporaryFailureWithoutClearingPendingCode \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryDisablesDuplicateSubmissionWhileChecking \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryCancellationDoesNotPersistOrNavigateAfterLateSuccess
  ```

  Expected: PASS.

- [ ] **Step 9: Checkpoint Task 5.**

  ```bash
  git diff --check
  git add ArcNote/AccessGateView.swift ArcNote/ArcNoteApp.swift Packages/CoreFlow/Tests/CoreFlowTests/IOSAccessSourceTests.swift ArcNoteUITests/ArcNoteUITests.swift
  git diff --cached --check
  git commit -m "feat(ios): validate private beta code before signup"
  ```

### Task 6: Prove The Live Flow, Privacy, And Build Matrix

**Files:**
- Modify test code only if a verification below exposes a reproducible contract defect.

**Interfaces:**
- Consumes: all Tasks 1–5.
- Produces: evidence that preflight is read-only, claimed `CRAI-BR8K` is rejected at entry, a fresh code stays available until registration, registration claims it once, and both application schemes build.

- [ ] **Step 1: Run format, focused Go suites, and ontology compliance.**

  ```bash
  cd ../Chorai_Go/chorai-go
  make fmt
  go test ./internal/access ./internal/auth ./internal/ontology/actions ./internal/ontology/services ./internal/ontology/handlers -count=1
  go test ./tests/contract -run 'CampaignAccess|AccessCodePreflight' -count=1
  go test ./tests/integration -run 'PrivateBetaAccess(Claim|CodePreflight)' -count=1
  make test-compliance
  git diff --check
  ```

  Expected: every command exits 0. If `make fmt` changes unrelated user files, restore only formatter-induced unrelated hunks with an inverse patch; never discard user edits.

- [ ] **Step 2: Restart the local backend through the project target and smoke the exact route.**

  ```bash
  cd ../Chorai_Go/chorai-go
  make restart-backend
  curl -fsS http://127.0.0.1:8180/health
  curl -i -sS -X POST http://127.0.0.1:8180/api/auth/access-code/preflight \
    -H 'Content-Type: application/json' \
    --data '{"access_code":"CRAI-BR8K"}'
  ```

  Expected: health 200; the claimed code returns 403 with the exact bounded invalid code/message and no plaintext code in backend logs.

- [ ] **Step 3: Issue one fresh code through the existing authenticated admin API and prove preflight is non-consuming.**

  Use the existing `chorai_admin` local account to obtain a bearer token, list campaigns, select the active `private_beta` campaign, and issue one code with cohort `invited_beta` and a future `expires_at`. Capture the returned plaintext code only in the shell session, never in a file or log. Then:

  ```bash
  curl -i -sS -X POST http://127.0.0.1:8180/api/auth/access-code/preflight \
    -H 'Content-Type: application/json' \
    --data "{\"access_code\":\"$CHORAI_PREFLIGHT_CODE\"}"
  curl -fsS http://127.0.0.1:8180/api/v1/admin/campaigns/$CHORAI_CAMPAIGN_ID/codes \
    -H "Authorization: Bearer $CHORAI_ADMIN_TOKEN"
  ```

  Expected: preflight 200/available true; admin code read still reports `claim_count: 0`, with no Actor, grant, cohort member, Activity, ActionLog, or Relation added by preflight.

- [ ] **Step 4: Exercise the live Simulator entry boundary.**

  Launch the Debug app against `http://127.0.0.1:8180`. Enter `CRAI-BR8K`: Sign Up must not open and the invalid copy must appear. Enter `$CHORAI_PREFLIGHT_CODE`: `Checking…` appears, then Sign Up opens. Immediately re-read the admin code row and require `claim_count: 0`.

- [ ] **Step 5: Complete one registration and prove exactly-once claim.**

  Use a fresh email/username and current verification code through the normal UI. Registration must succeed. Admin read must then report `claim_count: 1`. Replaying registration or preflight with the same code must not create another account/grant/cohort membership; preflight now returns the same bounded 403.

- [ ] **Step 6: Run CoreFlow, UI fixture, and both Simulator builds.**

  ```bash
  swift test --package-path Packages/CoreFlow
  xcodebuild test \
    -project ArcNote.xcodeproj \
    -scheme ArcNoteUITests \
    -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryUsesTheCurrentSignupSystemWithoutDuplicateCode \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryRejectsMalformedCodeBeforeRegistration \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryRejectsAuthoritativelyInvalidCodeBeforeSignup \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryShowsRateLimitWithoutClearingPendingCode \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryShowsTemporaryFailureWithoutClearingPendingCode \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryDisablesDuplicateSubmissionWhileChecking \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testPrivateBetaEntryCancellationDoesNotPersistOrNavigateAfterLateSuccess
  xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote \
    -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56'
  xcodebuild build -project ArcNote.xcodeproj -scheme 'ArcNote Production' \
    -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56'
  git diff --check
  ```

  Expected: CoreFlow and all focused UI tests pass; both builds exit 0.

- [ ] **Step 7: Review graph impact and audit secrets.**

  Update both code-review graphs, run `detect_changes_tool`, `get_affected_flows_tool`, and `query_graph_tool(pattern="tests_for")` for the eligibility evaluator and `PrivateBetaEntryView`. Then run:

  ```bash
  rg -n 'print\(.*access|print\(.*code|请求参数' ArcNote/NetworkManager.swift ArcNote/KeychainStore.swift ArcNote/AccessGateView.swift
  rg -n 'AccessCode|access_code' ../Chorai_Go/chorai-go/internal/access ../Chorai_Go/chorai-go/internal/ontology/handlers ../Chorai_Go/chorai-go/internal/ontology/actions
  ```

  Inspect every match: no statement may interpolate the plaintext code, and `NetworkManager.preflightAccessCode` must emit only redacted request/response markers.

- [ ] **Step 8: Final worktree audit.**

  In both repositories, run `git status --short`, `git diff --check`, and `git log --oneline -6`. Confirm all new feature commits contain only intended files, the existing admin-policy and Spark/Explore user changes remain preserved, and no temporary token/code file exists.

## Plan Self-Review

- **Spec coverage:** Tasks 1–3 cover the read-only contract, one shared eligibility implementation, every invalid predicate, independent 10/minute limiter, fail-open limiter/fail-closed authority behavior, exact flat responses, and final locked revalidation. Tasks 4–5 cover typed iOS mapping, payload redaction, checking/cancellation/duplicate behavior, exact copy, Keychain rules, and unchanged registration payloads. Task 6 covers claimed/fresh live acceptance, exactly-once registration, compliance, UI, privacy, and both build schemes.
- **Type consistency:** `AccessCodePreflighting.preflight(accessCode:)` returns `AccessCodePreflightResult` everywhere; `AccessCodePreflightError` has the same three cases in CoreFlow, adapter, fixtures, and view. Backend service consumes the Task 2 method through a separate read interface and uses the exact DTO/handler names declared in Task 3.
- **Boundary consistency:** The shared evaluator lives outside ontology Actions and has no write capability. Only the locked adapter plus existing claim path mutate canonical facts and emit provenance. Redis remains runtime-only state.
- **Worktree safety:** Every backend commit step names only preflight files and requires staged-diff inspection because overlapping admin-policy edits already exist; unrelated Spark/Explore files are explicitly excluded.
- **No placeholders:** Every route, type, error, message, limiter key, test case, command, build scheme, and live acceptance transition is named.
