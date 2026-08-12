# Private Beta Code Preflight Design

## Outcome

The Private Beta entry screen verifies a Product Access Code with the Go backend before it opens Sign Up. Verification is read-only: it neither reserves nor claims the code. Registration remains the only operation that atomically claims the code and creates the account.

This prevents an unknown, claimed, revoked, expired, or campaign-invalid code from carrying a user through email verification only to fail at final account creation.

## Current problem

`PrivateBetaEntryView` currently checks only whether the trimmed code is 9 to 64 characters, saves it to the device-only Keychain, and navigates to `SignUpView`. A syntactically plausible but unusable code therefore passes the entry screen. The backend discovers the problem only after the registration endpoint has rate-limited the IP and consumed a correct single-use email verification code.

The code must be checked at the screen where the user enters it, while final registration must still defend against the race where another registration claims the code after preflight succeeds.

## Options considered

1. **Keep local format validation only.** This is the current behavior. It cannot distinguish an available code from a claimed, revoked, expired, unknown, or inactive-campaign code, so it does not solve the user-facing problem.
2. **Add a read-only server preflight and claim only during registration. Recommended.** This rejects unusable codes at the entry screen without consuming scarce access. Registration revalidates under its existing transaction, preserving single-use correctness under concurrency.
3. **Reserve the code at the entry screen.** This reduces the interval in which another user can claim the code, but introduces reservation expiry, abandoned reservations, recovery, and cleanup. It also consumes or locks access before an account exists. That complexity is not justified for this flow.

## User interaction

`PrivateBetaEntryView` keeps its current layout and Product Access Code field.

When the user taps Continue:

1. Trim the input and enforce the existing 9-to-64-character format bound locally.
2. Enter a `Checking…` state. Disable the text field and Continue button so one screen cannot issue overlapping checks.
3. Call the read-only preflight endpoint with the captured code.
4. On success, save the verified code to `KeychainStore` and navigate to the existing `SignUpView`.
5. On authoritative rejection, stay on the entry screen and show `This Product Access Code is invalid or no longer available.`
6. On rate limiting, stay on the screen and show `Too many checks. Try again in N seconds.` when the server supplies a positive retry interval; otherwise use `Too many checks. Try again shortly.`
7. On transport or service failure, stay on the screen and show `Code verification is temporarily unavailable. Try again.`

The submitted code is never saved before a successful preflight. If an authoritative invalid response refers to the same code already stored from an older app run, clear that stale pending Keychain value. Do not clear it for rate limits, cancellation, or transient service failures.

Returning to the entry screen always requires another preflight before navigation, even when the field was populated from Keychain. Preflight success is not presented as a reservation or guarantee.

## API contract

Add an unauthenticated endpoint beside the existing auth routes:

```http
POST /api/auth/access-code/preflight
Content-Type: application/json

{"access_code":"CRAI-XXXX"}
```

An available code returns:

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"success":true,"data":{"available":true}}
```

Every authoritative unavailable condition returns the same bounded response:

```http
HTTP/1.1 403 Forbidden
Content-Type: application/json

{
  "success":false,
  "error_code":"PRODUCT_ACCESS_CODE_INVALID",
  "message":"product access code is invalid or no longer available"
}
```

The unified response covers unknown digest, claimed, revoked, expired, invalid cohort, unpublished or malformed campaign, inactive or out-of-window campaign, and a policy state in which the code cannot currently be used. It must not reveal the code ID, suffix, claimant, campaign, cohort, expiry, or which predicate failed.

Rate limiting returns `429 Too Many Requests`, `RATE_LIMIT_EXCEEDED`, and a standards-compatible integer `Retry-After` header. Service or policy dependency failure returns `503 Service Unavailable`. Malformed JSON or a code outside the request bound returns `400 Bad Request` without querying storage.

The endpoint accepts no idempotency key because it performs no business mutation. It never returns or logs the plaintext code.

## Backend architecture

Introduce one shared availability evaluator for Private Beta codes with two execution modes:

- **read-only preflight mode** performs authoritative reads without row mutation or reservation;
- **locked claim mode** runs inside the existing registration transaction, locks the code row, repeats the same predicates, and then performs the existing single-use claim.

The availability predicates have one implementation so preflight and registration cannot drift. Locked claim mode remains authoritative if state changes after preflight.

The evaluator reads:

- the current Product Access Policy;
- the access-code row selected by one-way digest;
- the code's canonical Campaign and validated Campaign spec.

It checks all existing claim eligibility rules before returning available. The handler and service translate all authoritative ineligible outcomes to the single public invalid response.

The endpoint receives its own Redis-backed IP limiter, separate from registration and email verification. The initial policy is 10 preflight attempts per IP per minute. Limiter failure remains fail-open, matching the current auth limiter primitive, while the availability evaluator remains fail-closed when policy, codec, or storage authority is unavailable.

No schema or migration is needed.

## iOS architecture

Add a focused `AccessCodePreflighting` CoreFlow protocol and bounded result/error types. `NetworkAccess` implements it through `NetworkManager`; `PrivateBetaEntryView` receives the protocol with `NetworkAccess.shared` as the production default so unit and UI fixtures can inject deterministic behavior.

The network layer:

- sends only `access_code`;
- suppresses payload logging;
- maps the unified 403 to an authoritative invalid-code error;
- maps 429 and `Retry-After` to a typed rate-limit error;
- maps 503 and transport failures to a temporary-unavailable error.

The view owns only presentation state (`idle`, `checking`, error copy, and navigation). It does not duplicate server eligibility rules. `KeychainStore` remains the single pending-code store, but is written only after preflight succeeds.

Existing Sign Up, Google, and Apple registration paths continue forwarding the same atomic `access_code` plus `idempotency_key` pair. They do not trust the earlier preflight and require no navigation redesign.

## Security and privacy

- Product Access Codes are bearer secrets. Neither app nor server logs their plaintext value or an unredacted request body.
- The unauthenticated endpoint exposes only the minimum Boolean distinction required by this UX and is guarded by a dedicated IP limit.
- All invalid eligibility states share one status, code, and message to avoid revealing campaign or claimant state.
- Preflight never creates an actor, grant, cohort membership, Activity, ActionLog, relation, reservation, or claim.
- Registration remains deny-by-default and repeats validation under row lock before any claim is committed.

## Ontology and ResultSpec

### Summary

- **Feature:** Private Beta Product Access Code preflight.
- **User value:** users learn that a code is unusable before entering and consuming an email verification code.
- **In scope:** read-only backend contract, shared availability rules, dedicated rate limit, iOS entry-screen integration, error handling, and tests.
- **Out of scope:** code reservation, code issuance, campaign editing, registration redesign, and changing email-verification lifetime.

### Ontology mapping

- **Data class:** Domain reads (`AccessCode`, `Campaign`), Kernel-backed policy read (`AccessPolicy`), and Redis runtime rate-limit state.
- **Objects touched:** existing Product Access Policy specialization only; no new Kernel object.
- **Relations touched:** none during preflight.
- **Actions used:** none during preflight. Final registration keeps `REGISTER_ACTOR` and the existing access-claim provenance within that transaction.
- **Canonical terms:** Product Access Code, preflight, claim, available.
- **New ontology primitives:** no.

### Write and read classification

Preflight is a deny-by-default query, not a commanded fact change. Its only write is an expiring Redis abuse-prevention counter, which is runtime state and not product authority. It requires no Activity or provenance relation. The final claim remains a committed transactional write through the existing Action path and is unchanged by preflight success.

Permission filtering occurs before any detailed state is exposed: the public contract collapses every ineligible code state to one result. No projection is introduced.

### Contract impact

- **Tables/models changed:** none.
- **Migration:** none.
- **API:** add `POST /api/auth/access-code/preflight`.
- **Clients:** add one iOS read-only preflight call; existing registration payload remains unchanged.

### Rollback

Remove the new route and iOS preflight call, then restore the current local-format-only navigation. No data cleanup is required because preflight creates no durable records. The registration claim path remains operational throughout rollback.

## Failure and concurrency behavior

- A code can become unavailable after preflight. Registration returns its existing product-access error and creates neither account nor claim because the transaction rolls back.
- Two users can preflight the same available code. At most one registration can claim it; the row lock and conditional update remain the authority.
- Cancelling or leaving the entry screen during `Checking…` must not navigate or save the code when a late response arrives.
- Repeated taps cannot create overlapping preflight requests from one view instance.
- A backend dependency outage never degrades to local-only acceptance.

## Test strategy

### Backend test-first coverage

1. An available code returns 200 while the code remains unclaimed and no Actor, AccessGrant, Activity, ActionLog, relation, or cohort member is created.
2. Unknown, claimed, revoked, expired, invalid-cohort, unpublished, malformed-spec, inactive, not-yet-active, and ended-campaign codes all return the same 403 body.
3. Missing policy, codec, or storage authority returns 503 rather than available.
4. Malformed or out-of-bound input returns 400 before storage access.
5. The dedicated limiter returns 429 with `Retry-After` without consuming registration or verification-code limits.
6. Existing registration tests prove that final claim still revalidates, rolls back account creation on failure, and claims exactly once on success.

### iOS test-first coverage

1. A successful injected preflight is the only path that writes Keychain and opens Sign Up.
2. An authoritative invalid result stays on the entry screen, shows the bounded invalid message, and clears a matching stale pending value.
3. Rate-limit and temporary-unavailable errors stay on the entry screen, show the correct copy, and retain the pending value.
4. `Checking…` disables editing and duplicate submission; cancellation prevents late navigation and persistence.
5. Network contract tests prove the exact route, `access_code` key, payload redaction, response mapping, and `Retry-After` handling.
6. Existing source contracts continue proving that Sign Up and OAuth registration forward the pending code and idempotency key.

### End-to-end acceptance

- Entering the claimed code `CRAI-BR8K` does not open Sign Up and shows the bounded invalid message.
- Entering a freshly issued available code opens Sign Up, while an admin read immediately afterward still reports that code as available.
- Completing registration with that code creates the account and changes the code to claimed exactly once.
- The relevant Go package, contract, and integration tests pass.
- CoreFlow unit/source-contract tests, the Private Beta UI fixture, and both `ArcNote` and `ArcNote Production` Simulator builds pass.

## Acceptance criteria

- Continue never navigates on the basis of format alone.
- Server preflight is read-only and shares all eligibility predicates with final claim.
- Only successful preflight persists the submitted code.
- All authoritative invalid states are indistinguishable to the client.
- Preflight has an independent IP rate limit and never spends the registration or email-verification budget.
- Final registration remains the only operation that claims a code and remains safe under concurrency.
- No plaintext Product Access Code appears in logs, durable diagnostics, or responses.
- No database migration or new ontology primitive is introduced.
