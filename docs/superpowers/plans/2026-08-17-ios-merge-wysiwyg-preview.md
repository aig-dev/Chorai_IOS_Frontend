# iOS Merge WYSIWYG Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved iPhone Merge experience: one durable task rail above New Note, one in-place WYSIWYG artifact editor, Card Editor-compatible tags, and an atomic Accept that commits the exact body, tags, and server-owned semantic level.

**Architecture:** Go Merge vNext owns an immutable presentation companion beside each card document revision. The companion freezes normalized tags and the overflow-safe sum of source rates; artifact edits may replace tags but never rate. The revision chain, NOTE history, current projection, and replay path bind document and presentation together. On iOS, MergeSessionStore remains the lifecycle authority and persists a per-job draft plus one replayable save operation. A lossless codec bridges card_doc.v1 and the existing BlockNote editor, while shared CardLevelStyle and Card Editor metadata components own visual semantics.

**Tech Stack:** Go 1.25 module with go1.26.4 toolchain, Gin, MySQL, exactstore, canonical JSON, Swift 5.9, SwiftUI, Combine, WebKit-backed BlockNoteEditor, Swift Package Manager, XCTest/XCUITest, Xcode 26.2 simulator tooling.

## Global Constraints

- Work directly on each existing main branch as explicitly approved. Do not create a branch or worktree.
- Run Go build/test commands from /Users/luffylu/Documents/Chorai/Chorai_Go/chorai-go; its Git root is /Users/luffylu/Documents/Chorai/Chorai_Go. Run iOS commands from /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend. Do not stage the unrelated Chorai_Agent changes or the outer /Users/luffylu/Documents/Chorai gitlinks.
- Preserve every unrelated dirty or untracked file. Stage only the paths named by the active task and inspect the cached diff before every commit.
- Support iOS 16+ and iPhone only. Add no third-party dependency.
- MergeSessionStore remains the sole Merge lifecycle authority. UI types emit intents and present projections; they do not create a second job state machine.
- Preserve multiple concurrent jobs, actor isolation, durable job identity, relaunch recovery, canonical retry/cancel policy, one global task rail, and stale-response generation gates.
- Preserve the titleless card_doc.v1 contract. New Insight is presentation copy, not an editable or persisted title.
- The numeric rate is server-owned, never editable, and never rendered. The result rate is the saturating signed-32-bit sum of frozen source rates after each missing or non-positive value normalizes to 1.
- Initial tags are the stable source-selection/source-tag-order union after trim, leading-hash removal, empty removal, exact de-duplication, and the existing ten-tag limit.
- One artifact revision binds document bytes and merge_artifact_presentation.v1 bytes. A tag-only edit creates a revision even when docHash is unchanged.
- PUT artifact remains additive and Web-compatible: omitted tags preserve the base presentation tags; present [] clears tags; any client rate field is rejected by strict decoding.
- Accept flushes the current durable draft, then commits that exact returned revision. It never performs a second Card metadata update.
- The authoritative Merge commit remains one Kernel Action and one Activity. No new ontology primitive is introduced.
- Existing Merge v1 schema/cutover evidence remains immutable. Add a separately journaled, additive presentation transition with a deployment drain fence; do not rewrite the historical cutover registry in place.
- A rollout may wait for non-terminal legacy Merge jobs to drain, but may not delete or replace them. Legacy terminal receipts remain replay-compatible.
- Every behavior change begins with a focused failing test, a witnessed expected RED, the minimum production change, and a fresh GREEN run.
- Final verification includes Go unit/contract/integration gates, full CoreFlow, BlockNoteEditor, both iOS schemes, iPhone 17 Pro, the smallest supported iPhone, accessibility settings, and visual comparison against the approved asset.

---

### Task 1: Define the Server-Owned Presentation Companion

**Repository:** Chorai_Go/chorai-go

**Files:**

- Create: internal/merge/vnext/domain/artifact_presentation.go
- Create: internal/merge/vnext/domain/artifact_presentation_test.go
- Modify: internal/merge/vnext/domain/contracts.go
- Modify: internal/merge/vnext/domain/contracts_test.go
- Modify: ../specs/068-merge-vnext/result-spec.md

**Interfaces:**

~~~go
const ArtifactPresentationSchemaV1 = "merge_artifact_presentation.v1"

type SourcePresentationInput struct {
    Tags []string
    Rate int64
}

type ArtifactPresentation struct {
    state *artifactPresentationState
}

func NewInitialArtifactPresentation(
    sources []SourcePresentationInput,
) (ArtifactPresentation, error)

func DecodeArtifactPresentation(raw []byte) (ArtifactPresentation, error)
func (value ArtifactPresentation) ReplacingTags(tags []string) (ArtifactPresentation, error)
func (value ArtifactPresentation) Tags() ([]string, error)
func (value ArtifactPresentation) Rate() (int32, error)
func (value ArtifactPresentation) CanonicalBytes() ([]byte, error)
func (value ArtifactPresentation) Hash() (integrity.IntegritySHA256, error)
~~~

- Tags use one domain normalization function: trim whitespace, repeatedly strip leading # plus adjacent whitespace, reject empty values, preserve first exact occurrence, and stop at ten.
- Rate uses an int64 accumulator and saturates to math.MaxInt32 before conversion.
- ReplacingTags preserves the original rate byte-for-byte.
- ResultSpec records the companion as Domain-owned immutable revision metadata, not a Kernel fact or a field inside card_doc.v1.

- [ ] **Step 1: Write the failing domain table tests**

Add tests covering:

~~~go
func TestInitialArtifactPresentationNormalizesTagsAndSumsRates(t *testing.T) {
    value, err := NewInitialArtifactPresentation([]SourcePresentationInput{
        {Tags: []string{" Design ", "#Inspiration"}, Rate: 1},
        {Tags: []string{"Design", " Nature "}, Rate: 0},
        {Tags: []string{"#Nature", "Systems"}, Rate: -7},
    })
    require.NoError(t, err)
    assert.Equal(t, []string{"Design", "Inspiration", "Nature", "Systems"}, mustTags(t, value))
    assert.Equal(t, int32(3), mustRate(t, value))
}

func TestInitialArtifactPresentationSaturatesAtSignedIntMaximum(t *testing.T) {
    value, err := NewInitialArtifactPresentation([]SourcePresentationInput{
        {Rate: math.MaxInt32},
        {Rate: math.MaxInt32},
    })
    require.NoError(t, err)
    assert.Equal(t, int32(math.MaxInt32), mustRate(t, value))
}

func TestReplacingTagsCannotChangeRate(t *testing.T) {
    base := mustPresentation(t, []SourcePresentationInput{{Rate: 9}})
    edited, err := base.ReplacingTags([]string{"#Edited"})
    require.NoError(t, err)
    assert.Equal(t, int32(9), mustRate(t, edited))
    assert.Equal(t, []string{"Edited"}, mustTags(t, edited))
}
~~~

Also pin canonical field order/schema, byte-for-byte decode/re-encode, ten-tag truncation, malformed schema rejection, overlong tag rejection, and canonical hash stability.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

~~~bash
go test ./internal/merge/vnext/domain -run 'ArtifactPresentation|ResultSpec'
~~~

Expected: compilation fails because ArtifactPresentation and SourcePresentationInput do not exist.

- [ ] **Step 3: Implement the immutable value**

Use canonicaljson.CanonicalizeV1 and integrity.IntegritySHA256FromBytes. Keep state private, clone slices on every boundary, and validate canonical bytes again from validatedState. Do not export mutable wire structs.

- [ ] **Step 4: Update ResultSpec and contract ownership**

Document these exact boundaries:

- card_doc.v1 remains the visible titleless document.
- merge_artifact_presentation.v1 contains tags and rate.
- artifact revision identity commits both hashes.
- only tags are editor-controlled; rate is source-derived and immutable.
- the NOTE current model is a retryable projection of immutable history.

- [ ] **Step 5: Verify GREEN**

Run:

~~~bash
go test ./internal/merge/vnext/domain -run 'ArtifactPresentation|Contracts'
~~~

Expected: all focused tests PASS.

- [ ] **Step 6: Commit Task 1**

~~~bash
git add internal/merge/vnext/domain/artifact_presentation.go internal/merge/vnext/domain/artifact_presentation_test.go internal/merge/vnext/domain/contracts.go internal/merge/vnext/domain/contracts_test.go ../specs/068-merge-vnext/result-spec.md
git diff --cached --check
git commit -m "feat(merge): define artifact presentation contract"
~~~

### Task 2: Expand card_doc.v1 for Lossless BlockNote Editing

**Repository:** Chorai_Go/chorai-go

**Files:**

- Modify: internal/merge/vnext/domain/vision_composition.go
- Modify: internal/merge/vnext/domain/artifact_revision.go
- Modify: internal/merge/vnext/domain/artifact_revision_test.go
- Modify: internal/merge/vnext/domain/artifact_validation.go
- Modify: internal/merge/vnext/domain/artifact_validation_test.go
- Modify: internal/merge/vnext/domain/note_projection.go
- Modify: internal/merge/vnext/domain/note_projection_test.go
- Modify: internal/merge/vnext/domain/text_composition.go
- Modify: internal/merge/vnext/domain/surprise_regeneration.go
- Modify: internal/merge/vnext/domain/surprise_regeneration_test.go

**Interfaces:**

~~~go
type CardInlineStyles struct {
    Bold      bool
    Italic    bool
    Underline bool
    Strike    bool
}

type CardInlineContent struct {
    Type    string
    Text    string
    Styles  CardInlineStyles
    Href    string
    Content []CardInlineContent
}

type CardTextProps struct {
    HeadingLevel int
    Checked      *bool
}

type CardBlock struct {
    ID       string
    Type     CardBlockType
    Content  []CardInlineContent
    Props    ImageBlockProps
    TextProps CardTextProps
    Children []CardBlock
}
~~~

- Preserve the existing wire bytes for old blocks when new fields are absent.
- Add checklist as a closed CardBlockType.
- Permit heading levels 2 and 3, text styles bold/italic/underline/strike, the governed NOTE contract's http/https links, and recursive children up to depth 8 while retaining the existing total 96-block and 24,000-rune limits.
- Continue to reconstruct trusted image origin server-side. A client cannot forge source/fused provenance.
- Unsupported server-owned image, quote, code, and divider blocks remain round-trippable. Unknown block types remain rejected rather than silently discarded.

- [ ] **Step 1: Add a failing rich editor round-trip test**

Use one literal canonical card_doc.v1 fixture containing:

- a level-2 heading with bold text;
- a paragraph with plain, italic, and https link content;
- a bullet item with one child paragraph;
- a checked checklist item;
- an existing trusted image block.

Assert DecodeEditorDocument accepts the client candidate, the server rebuilds trusted image origin, CanonicalBytes preserves IDs/hierarchy/styles/link target, and ProjectCardDocumentToBlockNoteV1 retains the same visible semantics.

- [ ] **Step 2: Add failing rejection tests**

Pin rejection for javascript links, depth 9, more than 96 recursive blocks, unknown style keys, forged image origin, heading level 1, and a malformed link with no text child.

- [ ] **Step 3: Run the focused tests and verify RED**

~~~bash
go test ./internal/merge/vnext/domain -run 'EditorDocument|RichInline|Nested|NoteProjection'
go test ./internal/notecontract -run 'DocumentV1'
~~~

Expected: rich fixture decoding fails because the current decoder permits one plain text item and flat blocks only.

- [ ] **Step 4: Implement recursive strict decode and canonical encode**

Keep one closed decoder per union member. Count runes and blocks across the complete tree, not per parent. Clone nested slices and inline content at every value boundary. Reuse the same validators for client candidates, trusted documents, note projection, and surprise regeneration so accepted editor data cannot later fail commit or use a flat provenance index against a recursive document.

- [ ] **Step 5: Verify compatibility and GREEN**

Run:

~~~bash
go test ./internal/merge/vnext/domain
go test ./internal/notecontract
~~~

Expected: old canonical fixtures and new rich fixtures all PASS.

- [ ] **Step 6: Commit Task 2**

~~~bash
git add internal/merge/vnext/domain/vision_composition.go internal/merge/vnext/domain/artifact_revision.go internal/merge/vnext/domain/artifact_revision_test.go internal/merge/vnext/domain/artifact_validation.go internal/merge/vnext/domain/artifact_validation_test.go internal/merge/vnext/domain/note_projection.go internal/merge/vnext/domain/note_projection_test.go internal/merge/vnext/domain/text_composition.go internal/merge/vnext/domain/surprise_regeneration.go internal/merge/vnext/domain/surprise_regeneration_test.go
git diff --cached --check
git commit -m "feat(merge): accept rich artifact document edits"
~~~

### Task 3: Add the Governed Presentation Schema Transition

**Repository:** Chorai_Go/chorai-go

**Files:**

- Create: internal/database/merge_vnext_presentation_transition_v1.go
- Create: internal/database/merge_vnext_presentation_transition_v1_test.go
- Create: internal/database/merge_vnext_presentation_transition_mysql_v1.go
- Create: internal/database/merge_vnext_presentation_transition_runner_v1.go
- Create: internal/database/merge_vnext_presentation_transition_runner_v1_test.go
- Create: cmd/merge_vnext_presentation_cutover/main.go
- Modify: internal/database/merge_vnext_runtime_schemas_v1.go
- Modify: internal/database/merge_vnext_runtime_schemas_v1_test.go
- Modify: internal/database/runtime_schema.go
- Modify: internal/merge/vnext/runtime/startup_proof.go
- Modify: internal/merge/vnext/runtime/startup_proof_test.go
- Modify: Makefile

**Schema delta:**

- merge_sources: nullable legacy columns source_tags_canonical_bytes VARBINARY(4096) and source_rate INT.
- merge_artifact_revisions: nullable legacy columns presentation_ref VARBINARY(1024) and presentation_hash CHAR(64) ASCII binary.
- merge_commits: nullable legacy column presentation_hash CHAR(64) ASCII binary.
- note_document_versions: nullable legacy columns presentation_contract VARBINARY(64), presentation_canonical_bytes VARBINARY(4096), and presentation_hash CHAR(64) ASCII binary.
- Checks require each companion tuple to be entirely NULL or entirely populated, valid hashes, and source_rate >= 1 when present.

**Rollout fence:**

- The transition preflight fails while any legacy job is CREATED, PREPARING, PLANNED, GENERATING, ARTIFACT_READY, or COMMITTING.
- Operators wait for those jobs to finish or users cancel them through normal product behavior; the transition never deletes a task.
- Legacy terminal rows remain nullable and replay through the pre-presentation compatibility path.
- After the transition journal entry exists, every new source, artifact revision, and Merge commit must carry a companion; startup proof rejects mixed new rows.

- [ ] **Step 1: Write failing registry and drain-fence tests**

Assert the transition:

- is a new journal identity, not a mutation of MergeVNextCutoverV1;
- adds exactly the named columns/checks;
- is idempotent after a recorded success;
- rejects a fixture with one ARTIFACT_READY job;
- accepts a fixture containing only COMMITTED, CANCELLED, and FAILED legacy jobs;
- leaves legacy rows untouched.

- [ ] **Step 2: Run tests and verify RED**

~~~bash
go test ./internal/database -run 'MergeVNextPresentation'
go test ./internal/merge/vnext/runtime -run 'Presentation|StartupProof'
~~~

Expected: compilation fails because the transition registry and runner do not exist.

- [ ] **Step 3: Implement the additive runner**

Use the existing migration journal/session/lock conventions. The runner order is:

1. acquire the governed transition lock;
2. verify the original Merge v1 cutover proof;
3. execute the non-terminal-job drain probe;
4. add columns;
5. add all-or-none/hash/rate checks;
6. record the presentation transition observation;
7. release the lock.

Expose:

~~~bash
make verify-merge-vnext-presentation-transition
make apply-merge-vnext-presentation-transition
~~~

- [ ] **Step 4: Make runtime proof consume the composed schema**

Fresh databases run Merge v1 cutover followed by the presentation transition. Existing databases require both journal proofs. Do not alter historical expected SQL bytes or hashes for Merge v1.

- [ ] **Step 5: Verify GREEN**

~~~bash
go test ./internal/database -run 'MergeVNextPresentation|MergeVNextRuntimeSchemas'
go test ./internal/merge/vnext/runtime -run 'Presentation|StartupProof'
make verify-merge-vnext-presentation-transition
~~~

- [ ] **Step 6: Commit Task 3**

~~~bash
git add internal/database/merge_vnext_presentation_transition_v1.go internal/database/merge_vnext_presentation_transition_v1_test.go internal/database/merge_vnext_presentation_transition_mysql_v1.go internal/database/merge_vnext_presentation_transition_runner_v1.go internal/database/merge_vnext_presentation_transition_runner_v1_test.go cmd/merge_vnext_presentation_cutover/main.go internal/database/merge_vnext_runtime_schemas_v1.go internal/database/merge_vnext_runtime_schemas_v1_test.go internal/database/runtime_schema.go internal/merge/vnext/runtime/startup_proof.go internal/merge/vnext/runtime/startup_proof_test.go Makefile
git diff --cached --check
git commit -m "feat(merge): add presentation schema transition"
~~~

### Task 4: Freeze Source Tags and Rate, Then Publish the Initial Companion

**Repository:** Chorai_Go/chorai-go

**Files:**

- Modify: internal/merge/vnext/persistence/types.go
- Modify: internal/merge/vnext/persistence/repository.go
- Modify: internal/merge/vnext/persistence/source_materialization_v1.go
- Modify: internal/merge/vnext/persistence/source_materialization_v1_test.go
- Modify: internal/merge/vnext/persistence/source_canonical_v1.go
- Modify: internal/merge/vnext/persistence/source_canonical_v1_test.go
- Modify: internal/merge/vnext/domain/source_canonical_v1.go
- Modify: internal/merge/vnext/domain/source_canonical_v1_test.go
- Modify: internal/merge/vnext/persistence/workflow.go
- Modify: internal/merge/vnext/persistence/artifact_read.go
- Modify: internal/merge/vnext/app/objects.go
- Modify: internal/merge/vnext/app/service.go
- Modify: internal/merge/vnext/app/service_test.go
- Modify: internal/merge/vnext/app/types.go
- Modify: internal/merge/vnext/api/http_routes_test.go
- Modify: tests/contract/merge_vnext_contract_test.go

**Data contract:**

~~~go
type PinnedSource struct {
    // existing immutable NOTE history fields
    Tags []string
    Rate int32
}

type ArtifactPublication struct {
    // existing exact objects
    Presentation PublishedObject
}

type ArtifactRecord struct {
    // existing fields
    Presentation exactstore.ObservedObjectV1
    PresentationHash integrity.IntegritySHA256
}

type ArtifactResult struct {
    // existing fields
    Presentation json.RawMessage
}
~~~

- The create transaction reads current asset_note_data tags/rate beside the selected immutable NOTE version, normalizes them once, and writes the frozen values to merge_sources.
- The authenticated source snapshot/envelope includes tags/rate, so a later source Card edit cannot change the in-flight result.
- Initial artifact publication has a five-object exact set: Document, SourceTray, Alignment, Provenance, Presentation.

- [ ] **Step 1: Write a failing frozen-source test**

Create three source fixtures with rates 1, 1, and 0 and overlapping tags. Create the job, mutate asset_note_data after source freeze, then load PinnedSource. Assert the frozen values remain the originals.

- [ ] **Step 2: Write a failing initial-artifact HTTP contract test**

Drive initial publication and assert:

~~~json
{
  "schemaVersion": "merge_artifact.v2",
  "latestRevision": 1,
  "presentation": {
    "schemaVersion": "merge_artifact_presentation.v1",
    "tags": ["Design", "Inspiration", "Nature"],
    "rate": 3
  }
}
~~~

Also assert the exact write-set count is five and the returned document/revision/hash fields are unchanged.

- [ ] **Step 3: Run focused tests and verify RED**

~~~bash
go test ./internal/merge/vnext/persistence -run 'SourceMaterialization|SourceCanonical|InitialPresentation'
go test ./internal/merge/vnext/app -run 'ArtifactPresentation'
go test ./internal/merge/vnext/api -run 'ArtifactPresentation'
go test ./tests/contract -run 'MergeVNextArtifact'
~~~

Expected: PinnedSource lacks tags/rate and GET artifact lacks presentation.

- [ ] **Step 4: Implement source freeze and initial publication**

Read metadata in the same database transaction that resolves source history. Store canonical tag JSON, not a display string. Feed ordered PinnedSource values into NewInitialArtifactPresentation. Publish the companion through exactstore and bind ref/hash on revision 1.

- [ ] **Step 5: Verify source immutability and Web compatibility**

Run:

~~~bash
go test ./internal/merge/vnext/domain ./internal/merge/vnext/persistence ./internal/merge/vnext/app ./internal/merge/vnext/api
go test ./tests/contract -run 'Merge'
~~~

Existing response consumers must still decode merge_artifact.v2 because presentation is additive.

- [ ] **Step 6: Commit Task 4**

~~~bash
git add internal/merge/vnext/persistence/types.go internal/merge/vnext/persistence/repository.go internal/merge/vnext/persistence/source_materialization_v1.go internal/merge/vnext/persistence/source_materialization_v1_test.go internal/merge/vnext/persistence/source_canonical_v1.go internal/merge/vnext/persistence/source_canonical_v1_test.go internal/merge/vnext/domain/source_canonical_v1.go internal/merge/vnext/domain/source_canonical_v1_test.go internal/merge/vnext/persistence/workflow.go internal/merge/vnext/persistence/artifact_read.go internal/merge/vnext/app/objects.go internal/merge/vnext/app/service.go internal/merge/vnext/app/service_test.go internal/merge/vnext/app/types.go internal/merge/vnext/api/http_routes_test.go tests/contract/merge_vnext_contract_test.go
git diff --cached --check
git commit -m "feat(merge): publish source-derived presentation"
~~~

### Task 5: Save Document and Tags as One Artifact Revision

**Repository:** Chorai_Go/chorai-go

**Files:**

- Modify: internal/merge/vnext/app/types.go
- Modify: internal/merge/vnext/app/artifact_edit.go
- Modify: internal/merge/vnext/app/service_test.go
- Modify: internal/merge/vnext/persistence/types.go
- Modify: internal/merge/vnext/persistence/artifact_edit.go
- Modify: internal/merge/vnext/persistence/artifact_operation_owner_v1_test.go
- Modify: internal/merge/vnext/persistence/revision_chain_commitment_v1.go
- Modify: internal/merge/vnext/persistence/revision_chain_commitment_v1_test.go
- Modify: internal/merge/vnext/api/http.go
- Modify: internal/merge/vnext/api/http_routes_test.go
- Modify: tests/integration/merge_vnext/artifact_edit_e2e_test.go
- Modify: tests/integration/merge_vnext/artifact_edit_integrity_e2e_test.go
- Modify: tests/contract/merge_vnext_contract_test.go

**Interfaces:**

~~~go
type SaveArtifactInput struct {
    BaseRevision int
    BaseHash     string
    IdemKey      string
    Document     json.RawMessage
    Tags         *[]string
}

type SaveArtifactResult struct {
    SchemaVersion    string
    ArtifactID       string
    Revision         int
    DocHash          string
    PresentationHash string
    Presentation     json.RawMessage
    ValidationStatus string
    ValidationErrors []string
}

type ArtifactSavePublication struct {
    // existing fields
    Presentation PublishedObject
}
~~~

- Tags nil means preserve the base revision's tags for current Web clients.
- Tags pointing to [] means replace with no tags.
- Rate is absent from the request type. Strict JSON rejects rate as an unknown key.
- RequestHash includes canonical document candidate bytes plus canonical resolved presentation bytes.
- A tag-only mutation creates revision N+1 even when DocHash equals the base DocHash.
- Revision-chain commitment includes presentation_ref and presentation_hash.

- [ ] **Step 1: Add failing API behavior tests**

Cover these exact cases:

1. document-only request with omitted tags preserves base tags;
2. tags-only semantic change creates one next revision with the same docHash;
3. combined document/tags edit creates one next revision;
4. client rate field returns 400 and writes nothing;
5. same idemKey/same normalized request returns the same revision;
6. same idemKey/different tags returns MERGE_IDEMPOTENCY_REUSED;
7. stale baseRevision returns MERGE_REVISION_CONFLICT and writes nothing.

- [ ] **Step 2: Run focused tests and verify RED**

~~~bash
go test ./internal/merge/vnext/app -run 'SaveArtifact.*Tags|SaveArtifact.*Rate'
go test ./internal/merge/vnext/persistence -run 'ArtifactEdit|RevisionChain'
go test ./internal/merge/vnext/api -run 'PutArtifact'
go test ./tests/integration/merge_vnext -run 'ArtifactEdit'
~~~

Expected: tags are ignored/rejected because the request and exact write set contain only document/provenance.

- [ ] **Step 3: Implement one three-object editor write set**

Each editor revision publishes Document, Provenance, and Presentation under one operation owner and one database transaction. Build the presentation by replacing base tags; never accept a new rate. Persist the next revision only after all exact objects are authenticated.

- [ ] **Step 4: Bind the presentation in the revision chain**

Update revision_chain_commitment_v1 to include presentation ref/hash for every post-transition revision. Preserve legacy terminal replay by recognizing the pre-presentation chain shape only for rows whose transition-era companion tuple is NULL.

- [ ] **Step 5: Verify GREEN and Web omission compatibility**

~~~bash
go test ./internal/merge/vnext/app ./internal/merge/vnext/persistence ./internal/merge/vnext/api
go test ./tests/contract -run 'Merge'
go test ./tests/integration/merge_vnext -run 'ArtifactEdit'
~~~

- [ ] **Step 6: Commit Task 5**

~~~bash
git add internal/merge/vnext/app/types.go internal/merge/vnext/app/artifact_edit.go internal/merge/vnext/app/service_test.go internal/merge/vnext/persistence/types.go internal/merge/vnext/persistence/artifact_edit.go internal/merge/vnext/persistence/artifact_operation_owner_v1_test.go internal/merge/vnext/persistence/revision_chain_commitment_v1.go internal/merge/vnext/persistence/revision_chain_commitment_v1_test.go internal/merge/vnext/api/http.go internal/merge/vnext/api/http_routes_test.go tests/integration/merge_vnext/artifact_edit_e2e_test.go tests/integration/merge_vnext/artifact_edit_integrity_e2e_test.go tests/contract/merge_vnext_contract_test.go
git diff --cached --check
git commit -m "feat(merge): save artifact tags atomically"
~~~

### Task 6: Commit Presentation into Immutable History and Current Card Projection

**Repository:** Chorai_Go/chorai-go

**Files:**

- Modify: internal/merge/vnext/persistence/types.go
- Modify: internal/merge/vnext/persistence/commit_base_proof.go
- Modify: internal/merge/vnext/persistence/commit_base_proof_validation.go
- Modify: internal/merge/vnext/persistence/commit_fresh.go
- Modify: internal/merge/vnext/persistence/commit_replay.go
- Modify: internal/merge/vnext/persistence/commit_receipt.go
- Modify: internal/merge/vnext/persistence/completed_note_history.go
- Modify: internal/merge/vnext/persistence/commit_final_history_test.go
- Modify: internal/merge/vnext/persistence/commit_replay_authority_test.go
- Modify: internal/merge/vnext/app/commit.go
- Modify: internal/merge/vnext/app/commit_history.go
- Modify: internal/merge/vnext/app/commit_history_test.go
- Modify: internal/domain/repositories/merge_note_current_projection_repository.go
- Modify: internal/domain/repositories/merge_note_current_projection_repository_test.go
- Modify: tests/integration/merge_vnext/merge_note_commit_e2e_test.go
- Modify: tests/integration/merge_vnext/merge_note_commit_transaction_e2e_test.go
- Modify: tests/contract/merge_card_contract_test.go

**Interfaces:**

~~~go
type MergeCommitReceipt struct {
    // existing fields
    PresentationHash integrity.IntegritySHA256
}

type MergeCommitPublication struct {
    // existing fields
    ArtifactPresentation domain.ArtifactPresentation
    PresentationBytes    []byte
}
~~~

- note_document_versions stores presentation contract, canonical bytes, and hash beside the projected document.
- merge_commits stores the selected presentation hash.
- asset_note_data current projection uses companion tags/rate instead of parsing tags from the document and hard-coding rate 1.
- Existing old committed receipts with all presentation fields NULL replay without mutation under the legacy compatibility path.
- New commits require a non-null companion and cannot downgrade to the legacy path.

- [ ] **Step 1: Write a failing atomic commit integration test**

Create three rate-1 sources, edit body and tags, commit revision 2, then assert:

- one note_document_versions row has the exact body and presentation bytes;
- asset_note_data contains edited tags and rate 3;
- one Merge Action and one Activity exist;
- receipt presentation_hash matches the selected revision;
- commit replay returns the same asset/version/history/activity IDs;
- the UI-facing Card DTO reports the edited tags and rate 3.

- [ ] **Step 2: Write a failing rollback/reconcile test**

Inject:

1. exact presentation object failure before the authoritative transaction: no history, receipt, Activity, or current projection may exist;
2. current projection failure after authoritative commit: one immutable history/receipt/Activity exists, current projection is absent or stale, replay repairs it without another Card or Activity.

- [ ] **Step 3: Run focused tests and verify RED**

~~~bash
go test ./internal/merge/vnext/persistence -run 'Commit.*Presentation|CommitReplay'
go test ./internal/merge/vnext/app -run 'CommitHistory'
go test ./internal/domain/repositories -run 'MergeNoteCurrentProjection'
go test ./tests/integration/merge_vnext -run 'MergeNoteCommit'
go test ./tests/contract -run 'MergeCard'
~~~

Expected: committed current projection still has empty tags/rate 1 and history has no presentation proof.

- [ ] **Step 4: Implement exact commit loading and proof**

Load and authenticate the selected revision's presentation object in CommitBaseProof. Add its hash to the revision-chain/receipt proof and history tuple. The client still sends only revision, artifactHash, and idemKey.

- [ ] **Step 5: Update retryable projection and replay**

Verify the history companion hash before deriving tags/rate. Project both in the same current-model transaction. Preserve the existing receipt-first replay identity and one-Activity invariant.

- [ ] **Step 6: Verify GREEN**

~~~bash
go test ./internal/merge/vnext/persistence ./internal/merge/vnext/app ./internal/domain/repositories
go test ./tests/contract -run 'Merge'
go test ./tests/integration/merge_vnext -run 'MergeNoteCommit|ArtifactEdit'
~~~

- [ ] **Step 7: Commit Task 6**

~~~bash
git add internal/merge/vnext/persistence/types.go internal/merge/vnext/persistence/commit_base_proof.go internal/merge/vnext/persistence/commit_base_proof_validation.go internal/merge/vnext/persistence/commit_fresh.go internal/merge/vnext/persistence/commit_replay.go internal/merge/vnext/persistence/commit_receipt.go internal/merge/vnext/persistence/completed_note_history.go internal/merge/vnext/persistence/commit_final_history_test.go internal/merge/vnext/persistence/commit_replay_authority_test.go internal/merge/vnext/app/commit.go internal/merge/vnext/app/commit_history.go internal/merge/vnext/app/commit_history_test.go internal/domain/repositories/merge_note_current_projection_repository.go internal/domain/repositories/merge_note_current_projection_repository_test.go tests/integration/merge_vnext/merge_note_commit_e2e_test.go tests/integration/merge_vnext/merge_note_commit_transaction_e2e_test.go tests/contract/merge_card_contract_test.go
git diff --cached --check
git commit -m "feat(merge): commit artifact presentation atomically"
~~~

### Task 7: Add the iOS Wire Contract and Lossless Editor Codec

**Repository:** Chorai_IOS_Frontend

**Files:**

- Create: Packages/CoreFlow/Sources/CoreFlow/MergeArtifactEditorCodec.swift
- Create: Packages/CoreFlow/Tests/CoreFlowTests/MergeArtifactEditorCodecTests.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/CoreMergeModels.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/CoreMergeService.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/CoreMergeModelsTests.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MockCoreMergeService.swift
- Modify: ArcNote/Models/MergeModels.swift
- Modify: ArcNote/NetworkManager.swift
- Modify: ArcNote/CoreFlow/NetworkCoreMergeService.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/NetworkCoreMergeSourceContractTests.swift

**Interfaces:**

~~~swift
public struct MergeArtifactPresentation: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let tags: [String]
    public let rate: Int
}

public struct MergeArtifactSaveRequest: Equatable, Sendable {
    public let baseRevision: Int
    public let baseHash: String
    public let idempotencyKey: String
    public let documentJSON: Data
    public let tags: [String]
}

public struct MergeArtifactSaveResult: Equatable, Sendable {
    public let artifactID: String
    public let revision: Int
    public let documentHash: String
    public let presentationHash: String
    public let presentation: MergeArtifactPresentation
}

public protocol CoreMergeServing: Sendable {
    // existing methods
    func saveArtifact(
        jobID: String,
        request: MergeArtifactSaveRequest
    ) async throws -> MergeArtifactSaveResult
}
~~~

MergeArtifact gains typed latestRevision, latestHash, raw documentJSON, and presentation. MergeArtifactEditorCodec exposes:

~~~swift
public struct MergeArtifactEditableDocument: Equatable, Sendable {
    public let blockNoteJSON: String
    public let fallbackMarkdown: String
    public let preservationManifest: Data
}

public enum MergeArtifactEditorCodec {
    public static func decode(
        cardDocumentJSON: Data
    ) throws -> MergeArtifactEditableDocument

    public static func encode(
        blockNoteJSON: String,
        preserving manifest: Data
    ) throws -> Data
}
~~~

- [ ] **Step 1: Write failing model and codec tests**

Decode a real merge_artifact.v2 response containing presentation rate 3. Round-trip the rich Task 2 fixture through card_doc -> BlockNote JSON -> card_doc and assert:

- stable block IDs/order/hierarchy;
- heading levels, list/check state, styles, links, image props/mediaRef;
- server meta/schema;
- unsupported known blocks survive unchanged;
- deleting or mutating a passthrough block returns losslessRoundTripFailed rather than partial JSON.

- [ ] **Step 2: Run focused tests and verify RED**

~~~bash
swift test --package-path Packages/CoreFlow --filter 'CoreMergeModelsTests|MergeArtifactEditorCodecTests|NetworkCoreMergeSourceContractTests'
~~~

Expected: MergeArtifact lacks presentation/raw JSON and no save/codec interface exists.

- [ ] **Step 3: Implement JSON values and codec**

Decode the document as a lossless JSON value instead of flattening it through MergeDocumentDTO. Map the supported BlockNote forms explicitly. Store a preservation manifest keyed by server block ID; encode fails if every original non-editable block cannot be recovered exactly.

- [ ] **Step 4: Implement PUT networking**

Add:

~~~swift
func saveMergeArtifact(
    jobID: String,
    request: MergeArtifactSaveRequestDTO
) async throws -> MergeArtifactSaveResponse
~~~

to NetworkManager and adapt it through NetworkCoreMergeService. Send tags and never send rate.

- [ ] **Step 5: Verify GREEN**

~~~bash
swift test --package-path Packages/CoreFlow --filter 'CoreMergeModelsTests|MergeArtifactEditorCodecTests|NetworkCoreMergeSourceContractTests'
swift test --package-path Packages/BlockNoteEditor
~~~

- [ ] **Step 6: Commit Task 7**

~~~bash
git add Packages/CoreFlow/Sources/CoreFlow/MergeArtifactEditorCodec.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeArtifactEditorCodecTests.swift Packages/CoreFlow/Sources/CoreFlow/CoreMergeModels.swift Packages/CoreFlow/Sources/CoreFlow/CoreMergeService.swift Packages/CoreFlow/Tests/CoreFlowTests/CoreMergeModelsTests.swift Packages/CoreFlow/Tests/CoreFlowTests/MockCoreMergeService.swift ArcNote/Models/MergeModels.swift ArcNote/NetworkManager.swift ArcNote/CoreFlow/NetworkCoreMergeService.swift Packages/CoreFlow/Tests/CoreFlowTests/NetworkCoreMergeSourceContractTests.swift
git diff --cached --check
git commit -m "feat(ios): add merge artifact edit contract"
~~~

### Task 8: Persist and Synchronize Per-Job Artifact Drafts

**Repository:** Chorai_IOS_Frontend

**Files:**

- Create: Packages/CoreFlow/Sources/CoreFlow/MergeArtifactDraft.swift
- Create: Packages/CoreFlow/Tests/CoreFlowTests/MergeArtifactDraftTests.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/MergeSessionPersistence.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/MergeTaskSessionPersistence.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/MergeTaskCoordinator.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionPersistenceTests.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreArtifactTests.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreCommitTests.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreResumeTests.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MergeTaskCoordinatorTests.swift

**Interfaces:**

~~~swift
public struct MergeArtifactDraftSnapshot: Codable, Equatable, Sendable {
    public let baseRevision: Int
    public let baseDocumentHash: String
    public let documentJSON: Data
    public let tags: [String]
    public let rate: Int
    public let preservationManifest: Data
    public let pendingSave: MergePendingArtifactSave?
}

public struct MergePendingArtifactSave: Codable, Equatable, Sendable {
    public let idempotencyKey: String
    public let baseRevision: Int
    public let baseDocumentHash: String
    public let documentJSON: Data
    public let tags: [String]
}

public enum MergeDraftSyncState: Equatable, Sendable {
    case clean
    case dirty
    case saving
    case unsynced(MergeDraftFailure)
    case conflict(MergeArtifactConflict)
}
~~~

Store entry points:

~~~swift
func updateArtifactDraft(documentJSON: Data, preservationManifest: Data)
func updateArtifactTags(_ tags: [String])
func flushArtifactDraft() async throws -> MergeArtifact
func resolveArtifactConflict(_ resolution: MergeArtifactConflictResolution) async
~~~

- Use the existing injected MergeSleeping for a deterministic 600 ms debounce.
- Persist the exact pending request and key before the first network call.
- Back/minimize persists synchronously and allows online flush to continue.
- Accept calls flushArtifactDraft and commits only the returned revision/hash.
- Lifecycle phase remains artifact-ready/Complete while draft sync has a separate state.

- [ ] **Step 1: Write failing debounce and replay tests**

Using ControlledMergeSleeper and MockCoreMergeService, assert:

- three rapid document/tag mutations yield one save containing the latest pair;
- a mutation during an in-flight save schedules a second request based on the first returned revision;
- timeout and relaunch replay the same bytes and idempotency key;
- tag-only save updates revision;
- Back leaves the task Complete and durable;
- Accept waits for save acknowledgement and commits its exact revision/hash.

- [ ] **Step 2: Write failing conflict/actor/sibling tests**

Assert:

- clean 409 fetches and adopts latest;
- dirty 409 retains local content and offers reloadServer/keepMine;
- keepMine creates a new explicit rebase operation key;
- actor change revokes the old draft and ignores late responses;
- Discard removes only the target draft/task;
- sibling jobs continue polling/saving unchanged.

- [ ] **Step 3: Run focused tests and verify RED**

~~~bash
swift test --package-path Packages/CoreFlow --filter 'MergeArtifactDraftTests|MergeSessionStoreArtifactTests|MergeSessionStoreCommitTests|MergeSessionStoreResumeTests|MergeTaskCoordinatorTests'
~~~

Expected: draft persistence/save APIs do not exist and Accept commits the loaded artifact without flushing edits.

- [ ] **Step 4: Implement the durable draft reducer**

Normalize tags with CardEditingTag rules before persistence. Increment MergeSessionSnapshot and collection schema versions with backward decoding that treats missing draft fields as nil. Never persist a draft outside its actor-scoped task record.

- [ ] **Step 5: Implement debounce, replay, and conflict resolution**

Only one save operation may be in flight per job. Late results must pass job ID, actor generation, store lifetime, and pending-operation identity checks before applying. Offline edits remain durable and Accept remains disabled until flush succeeds.

- [ ] **Step 6: Verify GREEN and the full CoreFlow suite**

~~~bash
swift test --package-path Packages/CoreFlow --filter 'MergeArtifactDraftTests|MergeSessionStoreArtifactTests|MergeSessionStoreCommitTests|MergeSessionStoreResumeTests|MergeTaskCoordinatorTests'
swift test --package-path Packages/CoreFlow
~~~

- [ ] **Step 7: Commit Task 8**

~~~bash
git add Packages/CoreFlow/Sources/CoreFlow/MergeArtifactDraft.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeArtifactDraftTests.swift Packages/CoreFlow/Sources/CoreFlow/MergeSessionPersistence.swift Packages/CoreFlow/Sources/CoreFlow/MergeTaskSessionPersistence.swift Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift Packages/CoreFlow/Sources/CoreFlow/MergeTaskCoordinator.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionPersistenceTests.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreArtifactTests.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreCommitTests.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreResumeTests.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeTaskCoordinatorTests.swift
git diff --cached --check
git commit -m "feat(ios): persist merge artifact drafts"
~~~

### Task 9: Share the Six Semantic Level Materials

**Repository:** Chorai_IOS_Frontend

**Files:**

- Create: Packages/CoreFlow/Sources/CoreFlow/CardLevelStyle.swift
- Create: Packages/CoreFlow/Tests/CoreFlowTests/CardLevelStyleTests.swift
- Delete: Packages/CoreFlow/Sources/CoreFlow/LibraryCardRateStyle.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardRateStyleTests.swift
- Create: ArcNote/CardEditor/CardLevelMaterial.swift
- Modify: ArcNote/HomeView.swift
- Modify: ArcNote/NewInsightView.swift
- Modify: ArcNote/CoreFlow/MergeLifecycleViews.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardPreviewSourceContractTests.swift

**Interfaces:**

~~~swift
public struct CardLevelStyle: Equatable, Sendable {
    public enum Tier: String, Codable, Sendable {
        case basic, notable, valuable, significant, exceptional, definitive
    }

    public let tier: Tier
    public let label: String
    public let accentHex: String?
    public let materialAssetName: String

    public init(rate: Int)
}
~~~

Exact table:

| Rate | Label | Asset | Accent |
| --- | --- | --- | --- |
| < 3 | Basic | merge_bg_basic | neutral |
| 3...8 | Notable | merge_bg_green | #00FF66 |
| 9...26 | Valuable | merge_bg_blue | #0371FF |
| 27...80 | Significant | merge_bg_purple | #9627D2 |
| 81...242 | Exceptional | merge_bg_yellow | #D97800 |
| >= 243 | Definitive | merge_bg_red | #FF5E00 |

- [ ] **Step 1: Write a failing boundary table test**

Test rates -1, 0, 1, 2, 3, 8, 9, 26, 27, 80, 81, 242, 243, and Int.max. Assert labels/assets/hex values and explicitly assert 3 is Notable and 81 is Exceptional, never Critical.

- [ ] **Step 2: Write a failing source contract**

Require Home, NewInsight, and Merge to consume CardLevelStyle and reject local numeric threshold strings. Require the numeric rate not to appear in Merge accessibility labels.

- [ ] **Step 3: Run tests and verify RED**

~~~bash
swift test --package-path Packages/CoreFlow --filter 'CardLevelStyleTests|LibraryCardRateStyleTests|LibraryCardPreviewSourceContractTests'
~~~

Expected: CardLevelStyle does not exist and NewInsight still owns a divergent label mapping.

- [ ] **Step 4: Implement the shared value and SwiftUI material**

CardLevelMaterial uses the approved asset as the base, a continuous tier-colored one-pixel edge, restrained matching corner ambience, and no unrelated purple/blue right stroke. Reduce Transparency swaps to an opaque high-contrast tier surface; Increased Contrast strengthens text/edge only.

- [ ] **Step 5: Migrate every existing rate surface**

Replace the old LibraryCardRateStyle mapping and NewInsight literals. The visible UI shows style.label only; never interpolate rate.

- [ ] **Step 6: Verify GREEN**

~~~bash
swift test --package-path Packages/CoreFlow --filter 'CardLevelStyleTests|LibraryCardRateStyleTests|LibraryCardPreviewSourceContractTests'
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
~~~

- [ ] **Step 7: Commit Task 9**

~~~bash
git add Packages/CoreFlow/Sources/CoreFlow/CardLevelStyle.swift Packages/CoreFlow/Tests/CoreFlowTests/CardLevelStyleTests.swift Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardRateStyleTests.swift ArcNote/CardEditor/CardLevelMaterial.swift ArcNote/HomeView.swift ArcNote/NewInsightView.swift ArcNote/CoreFlow/MergeLifecycleViews.swift Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardPreviewSourceContractTests.swift
git rm Packages/CoreFlow/Sources/CoreFlow/LibraryCardRateStyle.swift
git diff --cached --check
git commit -m "feat(ios): share semantic card level materials"
~~~

### Task 10: Build the In-Place WYSIWYG Merge Surface

**Repository:** Chorai_IOS_Frontend

**Files:**

- Create: ArcNote/CoreFlow/MergeArtifactEditorSurface.swift
- Create: ArcNote/CoreFlow/MergeArtifactDraftController.swift
- Modify: ArcNote/CoreFlow/MergeLifecycleViews.swift
- Modify: ArcNote/CardEditor/BlockNoteCardEditor.swift
- Modify: ArcNote/CardEditor/CardEditorMetadataRows.swift
- Modify: ArcNote/CardEditor/CardMetadataPresentation.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MergeArtifactPresentationSourceContractTests.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/CardEditorTagFocusSourceContractTests.swift
- Modify: ArcNoteUITests/ArcNoteUITests.swift

**Presentation contract:**

- Fixed heading New Insight.
- Semantic level pill from CardLevelStyle; no numeric rate.
- One BlockNote body. Unfocused scrolling is preview; tapping the body edits in place with unchanged frame/typography/material.
- Shared CardEditorTagRow and CardMetadataTagCapsule, no colored dots, ten-tag limit, horizontal overflow.
- Top-leading Back minimizes only.
- Bottom mutation row has exactly Discard and Accept.
- Accept disabled for lossy codec state, unsynced/offline state, save in flight, or commit in flight.
- Discard clears local state only after canonical cancel succeeds.

**Accessibility identifiers:**

- screen.merge.artifact
- merge.artifact.back
- merge.artifact.level
- merge.artifact.editor
- merge.artifact.tags
- merge.artifact.add-tag
- merge.artifact.sync-state
- merge.artifact.discard
- merge.artifact.accept

- [ ] **Step 1: Write a failing structural source contract**

Require MergeArtifactEditorSurface to own BlockNoteCardEditor, CardEditorTagRow, CardLevelMaterial, Back, Discard, and Accept. Reject Preview/Edit segmented controls, local tag capsule copies, colored tag dots, a third mutation action, and Text rendering of artifact blocks as the primary body.

- [ ] **Step 2: Write a failing deterministic UI fixture**

Launch a completed rate-3 artifact with long rich content and three tags. Assert:

- level label is Notable and no element label/value contains standalone 3;
- no Preview or Edit tab exists;
- editor is vertically scrollable;
- tapping body focuses without changing its frame by more than 1.5 points;
- editing text and adding/removing a tag changes visible WYSIWYG state;
- Back closes the surface and one Complete rail remains;
- reopening the same job restores the edits.

- [ ] **Step 3: Run tests and verify RED**

~~~bash
swift test --package-path Packages/CoreFlow --filter 'MergeArtifactPresentationSourceContractTests|CardEditorTagFocusSourceContractTests'
xcodebuild build-for-testing -quiet -project ArcNote.xcodeproj -scheme ArcNoteUITests -derivedDataPath /tmp/chorai-merge-wysiwyg-deriveddata -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -quiet -project ArcNote.xcodeproj -scheme ArcNoteUITests -derivedDataPath /tmp/chorai-merge-wysiwyg-deriveddata -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:ArcNoteUITests/ArcNoteUITests/testMergeArtifactEditsInPlaceAndRestoresDraft
~~~

Expected: source contract finds the read-only review panel and UI cannot focus/edit tags/body.

- [ ] **Step 4: Extract only genuinely shared Card Editor primitives**

Make CardEditorTagRow/CardMetadataTagCapsule configurable through semantic inputs, not Merge-specific conditionals. Keep minimum 44-point targets and one VoiceOver removal action per tag.

- [ ] **Step 5: Implement the surface/controller**

MergeArtifactDraftController adapts the CoreFlow draft projection and user intents; it owns no job identity. Request a BlockNote snapshot before Back/Accept. Back persists locally and dismisses immediately; Accept awaits flushArtifactDraft then invokes the existing commit path.

- [ ] **Step 6: Add error and conflict presentation**

Render concise inline states for saving, saved, offline unsynced, validation failure, and conflict. Conflict exposes exactly Reload server version and Keep my version. A failed save/commit leaves body/tags visible and retryable.

- [ ] **Step 7: Verify GREEN on both phone sizes**

Run the focused source tests and the fixture on iPhone 17 Pro and the smallest supported iPhone. Add a Dynamic Type accessibility-size fixture and confirm body/tags/actions remain reachable.

- [ ] **Step 8: Commit Task 10**

~~~bash
git add ArcNote/CoreFlow/MergeArtifactEditorSurface.swift ArcNote/CoreFlow/MergeArtifactDraftController.swift ArcNote/CoreFlow/MergeLifecycleViews.swift ArcNote/CardEditor/BlockNoteCardEditor.swift ArcNote/CardEditor/CardEditorMetadataRows.swift ArcNote/CardEditor/CardMetadataPresentation.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeArtifactPresentationSourceContractTests.swift Packages/CoreFlow/Tests/CoreFlowTests/CardEditorTagFocusSourceContractTests.swift ArcNoteUITests/ArcNoteUITests.swift
git diff --cached --check
git commit -m "feat(ios): add wysiwyg merge artifact editor"
~~~

### Task 11: Anchor the Single Rail Above New Note and Expand Upward

**Repository:** Chorai_IOS_Frontend

**Files:**

- Create: ArcNote/CoreFlow/MergeTaskRailAnchor.swift
- Modify: ArcNote/ArcNoteApp.swift
- Modify: ArcNote/HomeView.swift
- Modify: ArcNote/CoreFlow/MergeTaskRail.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MergeTaskRailSourceContractTests.swift
- Modify: ArcNoteUITests/ArcNoteUITests.swift

**Interfaces:**

~~~swift
@MainActor
final class MergeTaskRailAnchorStore: ObservableObject {
    @Published private(set) var newNoteFrame: CGRect?
    func update(newNoteFrame: CGRect)
}

struct MergeTaskRailAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(
        value: inout Anchor<CGRect>?,
        nextValue: () -> Anchor<CGRect>?
    )
}
~~~

- Home reports the real note.create frame through an anchor preference.
- The app-shell portal caches that frame for pushed routes so the rail does not jump.
- Collapsed rail centerX equals New Note centerX.
- Collapsed rail bottom is 12 points above New Note top.
- Expansion list is above the collapsed control, max four visible, vertical scrolling for tasks 5+.

- [ ] **Step 1: Write a failing frame-level UI test**

On Home with one task:

~~~swift
XCTAssertEqual(rail.frame.midX, newNote.frame.midX, accuracy: 1.5)
XCTAssertEqual(newNote.frame.minY - rail.frame.maxY, 12, accuracy: 2)
~~~

With five tasks, expand and assert controls 1...4 are visible above the collapsed button, task 5 becomes hittable after upward scroll, every target is at least 44 points, and no task frame intersects note.create.

- [ ] **Step 2: Run on iPhone 17 Pro and verify RED**

Use the existing deterministic rail fixture. Expected: current top padding places the rail near the upper-right rather than above New Note, and the list expands downward.

- [ ] **Step 3: Implement the real anchor and upward shell**

Remove the hard-coded .padding(.top, 112) ownership. Keep one global portal in ArcNoteApp. Arrange expanded controls before the collapsed button in the vertical stack and anchor the stack by its bottom-trailing corner.

- [ ] **Step 4: Verify pushed-route stability**

Open Home Detail and Explore Detail while a task exists. Assert exactly one hittable rail and the same screen-relative center/bottom slot as Home. The cached anchor survives the New Note button leaving the visible hierarchy.

- [ ] **Step 5: Verify GREEN on both phones**

Run the rail source contract and UI cases on iPhone 17 Pro and the smallest supported iPhone, including five tasks, Reduce Motion, and Dynamic Type.

- [ ] **Step 6: Commit Task 11**

~~~bash
git add ArcNote/CoreFlow/MergeTaskRailAnchor.swift ArcNote/ArcNoteApp.swift ArcNote/HomeView.swift ArcNote/CoreFlow/MergeTaskRail.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeTaskRailSourceContractTests.swift ArcNoteUITests/ArcNoteUITests.swift
git diff --cached --check
git commit -m "fix(ios): anchor merge rail above new note"
~~~

### Task 12: Prove the Cross-Platform Flow and Complete Visual QA

**Repositories:** Chorai_Go/chorai-go and Chorai_IOS_Frontend

**Files:**

- Modify: Chorai_Go/chorai-go/tests/integration/merge_vnext/merge_note_commit_e2e_test.go
- Modify: Chorai_Go/chorai-go/tests/integration/merge_vnext/durable_http_e2e_test.go
- Modify: Chorai_IOS_Frontend/ArcNoteUITests/ArcNoteUITests.swift
- Modify: Chorai_IOS_Frontend/docs/qa/ios-background-multi-merge.md
- Create: Chorai_IOS_Frontend/docs/qa/ios-merge-wysiwyg-preview.md
- Create: Chorai_IOS_Frontend/docs/qa/assets/ios-merge-wysiwyg-preview/

**Required live flows:**

1. Three rate-1 sources create one job; creation minimizes; rail is above New Note; artifact becomes Complete; UI shows Notable green.
2. User edits body and tags, minimizes, reopens, terminates app, relaunches, and sees the same job/draft.
3. Accept flushes one artifact revision, commits it, removes only that task, opens the canonical Card, and Card DTO/UI show edited body/tags plus Notable material.
4. Discard on a sibling job cancels/removes only that sibling.
5. Offline edit, timeout replay, conflict choice, actor switch, and stale response preserve the existing safety invariants.

- [ ] **Step 1: Add the failing live contract assertions**

Before running, make tests assert exact backend observations: one create key/job, save request key replay, selected revision, presentation rate 3, edited tags, one commit ID, one Action, one Activity, one Card, and no second metadata endpoint.

- [ ] **Step 2: Start and verify the local stack**

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_Go/chorai-go
make run-stack
curl --fail http://127.0.0.1:8180/health
make verify-merge-vnext-presentation-transition
~~~

Do not run live UI against a partial or unhealthy stack.

- [ ] **Step 3: Run final Go gates**

~~~bash
make fmt
make test
make build
make verify-merge-vnext-cutover
make verify-merge-vnext-presentation-transition
go test ./tests/contract -run 'Merge'
go test ./tests/integration/merge_vnext -run 'ArtifactEdit|MergeNoteCommit|DurableHTTP'
~~~

Expected: all PASS; three rate-1 sources commit rate 3 and edited tags.

- [ ] **Step 4: Run final Swift package gates**

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend
swift test --package-path Packages/CoreFlow
swift test --package-path Packages/BlockNoteEditor
~~~

- [ ] **Step 5: Build both iOS schemes**

~~~bash
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' -configuration Debug-Production -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild build-for-testing -quiet -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
~~~

- [ ] **Step 6: Run clean UI batches**

Use the fresh ArcNoteUITests xctestrun. Run in one non-parallel batch:

- existing background multi-Merge create/discard flow;
- existing relaunch/commit/canonical Card flow;
- WYSIWYG edit/minimize/relaunch/Accept flow;
- five-task upward rail flow;
- actor-change/stale-response flow.

Repeat the WYSIWYG and five-task layout cases on the smallest supported iPhone.

- [ ] **Step 7: Capture and inspect the visual matrix**

Save original-resolution PNGs for:

- Basic, Notable, Valuable, Significant, Exceptional, Definitive;
- Notable focused and unfocused;
- tags with 0, 3, and 10 entries;
- long body at default and accessibility Dynamic Type;
- collapsed/expanded five-task rail on both phones;
- Reduce Motion Working;
- Reduce Transparency Notable;
- Increased Contrast Notable;
- Preview open with no rail and Preview closed with one Complete rail.

Compare Notable against docs/superpowers/specs/assets/2026-08-17-ios-merge-wysiwyg-preview-approved-v2.png. Reject any isolated purple/blue right edge, numeric rate, colored tag dot, clipped body/action, rail/New Note overlap, or duplicate rail.

- [ ] **Step 8: Update QA evidence**

Record:

- exact commands and exit codes;
- simulator model/OS/UDID;
- xcresult paths and individual test results;
- backend job/revision/commit IDs without credentials;
- committed rate/tags/current projection proof;
- accessibility-setting readback;
- screenshot dimensions and P0/P1/P2 verdict.

- [ ] **Step 9: Commit Go final test changes**

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_Go/chorai-go
git add tests/integration/merge_vnext/merge_note_commit_e2e_test.go tests/integration/merge_vnext/durable_http_e2e_test.go
git diff --cached --check
git commit -m "test(merge): verify wysiwyg artifact commit"
~~~

- [ ] **Step 10: Commit iOS final QA changes**

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend
git add ArcNoteUITests/ArcNoteUITests.swift docs/qa/ios-background-multi-merge.md docs/qa/ios-merge-wysiwyg-preview.md docs/qa/assets/ios-merge-wysiwyg-preview
git diff --cached --check
git commit -m "test(ios): verify merge wysiwyg preview"
~~~

## Final Acceptance Matrix

- [ ] Rail uses one global owner, aligns to the real New Note button, sits 12 points above it, expands upward, shows four tasks, and scrolls to task five.
- [ ] Completed Merge is one scroll/edit surface with no Preview/Edit tabs or layout jump.
- [ ] Body and tags survive Back, reopen, network loss, timeout replay, and app relaunch under the same actor/job.
- [ ] Card Editor tag visuals/normalization are reused; no colored dots or duplicate style implementation exists.
- [ ] Rate is source-derived, immutable across revisions, hidden numerically, and mapped by one shared six-tier value.
- [ ] Three rate-1 sources visibly produce Notable green and commit rate 3.
- [ ] A tag-only edit creates a revision; omitted Web tags preserve prior tags; client rate is rejected.
- [ ] Revision chain and immutable history bind document plus presentation hashes.
- [ ] Accept flushes and commits one exact revision with no post-commit metadata call.
- [ ] Commit/replay yields one Card, one Action, one Activity, exact body/tags/rate, and retryable current projection.
- [ ] Back removes nothing, Discard removes only its task, Accept removes only after successful commit and opens the canonical Card.
- [ ] Go full tests/build/transition checks, CoreFlow, BlockNoteEditor, both iOS builds, clean live UI batches, accessibility checks, and visual QA all pass.
