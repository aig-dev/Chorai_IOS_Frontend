# Approved prototype reference map and fidelity corrections

This map records the visual references actually linked by the V8 gallery. The screenshot paths below are relative to `docs/design/2026-10-21-native-visual-reform/revisions/`. Source paths are in `v8-grid-brush/prototype/` unless stated otherwise. V8 inherits V5 and V6 captures; it does not contain an approved new screenshot of every production screen.

| Surface | Approved screenshot reference | Prototype source | Required visual structure |
| --- | --- | --- | --- |
| Home | `v6-feature-journeys/screenshots/home-light.png`, `home-dark.png` | `ChoraiPrototype.swift`, `HomePrototype`, `NoteRow` | System large title; Notes/Collect segmented control; restrained secondary introduction; unboxed serif note excerpts with date/privacy, tags and separators; text-bearing New note capsule. |
| Editor | `v6-feature-journeys/screenshots/editor-light.png`, `editor-dark.png` | `ChoraiPrototype.swift`, `EditorPrototype` | Single body; full-page serif writing surface; quiet metadata; native inline Note title and top controls; tags and secondary tools below content. No independent title input. |
| Explore deck | `v5-explore-grid/screenshots/flow-light.png`, `flow-dark.png` | `ChoraiPrototype.swift`, `ExplorePrototype` | Native circular menu control and grouped browse/search controls; For you and position; large reading card; author/date, labeled Spark and anchored menu; restrained social footer; Previous and swipe hint. |
| Explore grid | `v8-grid-brush/screenshots/levels-grid-light.png`, `levels-grid-dark.png`, `levels-grid-lower-light.png`, `levels-grid-lower-dark.png` | `ExploreGrid.swift`, `CardLevelJourney.swift` | Two-column content-driven grid; Roman level/name, thin edge and colored brush; no Chora or reserved Chora clearance in grid. Inherited composition: `v5-explore-grid/screenshots/grid-light.png`, `grid-dark.png`. |
| Reader | `v8-grid-brush/screenshots/levels-reader-{basic,notable,valuable,significant,exceptional,definitive}-{light,dark}.png` | `CardLevelJourney.swift` | Native reader presentation; level and author grouped inside a calm reading surface; colored brush and matching Chora on detail; rich media and serif full body. Earlier full reader: `v5-explore-grid/screenshots/reader-{light,dark}.png`. |
| Spark | `v6-feature-journeys/screenshots/spark-{loading,results,deeper,reader,collected,error,empty,limit}-{light,dark}.png` | `SparkJourney.swift` | Source/context, depth and results remain distinct; native navigation/scrolling; text-led result hierarchy and explicit recovery states. |
| Merge | `v6-feature-journeys/screenshots/merge-{selection,selected,progress,background,ready,sync-error,conflict,saved,failed,cancelled}-{light,dark}.png` | `MergeJourney.swift` | Native selection rows; fixed source distinguished from candidates; clear count/action; progress separate from editable result and accept/discard. The saved screenshot is a sample, never proof of a production save. |
| Card menu | `v5-explore-grid/screenshots/menu-light.png` | `ChoraiPrototype.swift`, Explore native Menu | Real system anchored vertical Menu; ownership-aware actions. This image has no separately approved dark capture. |
| Share | `v5-explore-grid/screenshots/share-light.png`, `system-share-light.png` | `NoteActions.swift`, `shareContent` | Large native sheet, inline title/trailing close, grouped Form, content preview and system share action. Production must share the real prepared image artifact, not the sample text. No separately approved dark capture. |
| Link | `v5-explore-grid/screenshots/link-light.png` | `NoteActions.swift`, `linkContent` | Large native sheet, grouped candidate rows and readable source/ownership meaning; restrained gold. The prototype's local preview is not a production mutation or saved relationship. No separately approved dark capture. |
| Report | `v5-explore-grid/screenshots/report-light.png` | `NoteActions.swift`, `reportContent` | Large native sheet, inline title/trailing close, grouped reason/context and action/status. Real submit/retry/receipt remain authoritative. No separately approved dark capture. |
| Profile, author, comments, settings, auth, Chora, chat conversations | No approved actual screen capture mapped by V8 | `auxiliary-flows.js` explicitly sets author/comments images to null. `ChoraiPrototype.swift` contains service placeholders, not approved production account or conversation layouts. | Extend shared native typography, spacing, colors and controls; preserve actual production functionality. Do not claim a screenshot-perfect migration for an uncaptured surface or invent replacement workflows. |

## High-impact differences found in the first rollout captures

The original rollout screenshot files remain in `screenshots/` as evidence of the rejected first implementation. This audit does not label them as fidelity-approved.

- Home used a single-row serif heading, framed level cards and a bare plus button. The approved V6 capture uses a native large title, open reading rows and a labeled New note capsule.
- Editor used a large rounded white panel with a strong shadow and sans-serif body. V6 shows an open, full-page serif writing surface with a native inline Note title and quiet metadata.
- Explore replaced grouped native top controls with a second segmented mode row, used an unlabeled Spark glyph and promoted large social icons. V5 has quieter controls, a labeled Spark capsule and more usable reading area. Data/fixture content differs and cannot itself be judged as a layout regression.
- Reader used a large author/action block above a small sans-serif content card. V8 groups level/author with the rich reading body, maintains serif hierarchy and places Chora at the reading edge. Production follow/chat/related content must still remain accessible.
- Share, Report and Link retained custom headers and floating overlays instead of the approved grouped native sheets. They now use native NavigationStack/Form surfaces; real service models provide the content, permissions, failures and final receipts.
- The old card action grid is not the native menu shown in the prototype. `NativeCardActionsMenu` now exposes a real anchored SwiftUI Menu while reusing existing ownership branches and action dispatch. Callers retain their route owner and can prepare the selected card without opening the legacy overlay.

## Secondary implementation boundaries

`ShareCardView`, `ContentReportView` and `LinkPopupView` have native grouped layouts and trailing close controls. The existing stores, request protocols, report reasons, mutation ownership, selection-only behavior and share artifact pipeline remain intact. Link candidate activation still uses the existing immediate action; the unconnected prototype preview step is not copied into production. Source summaries unavailable from the existing contract are not fabricated.

`NativeCardActionsMenu` takes the current UserCard, menu layout/ownership, optional preparation and action callbacks, and a caller-provided label. It uses the existing `navigateCard` environment. The old overlay remains for unconverted callers; native menu items retain `popup-menu.item.<name>` accessibility identifiers.

These changes require the parent agent's full app build and real Simulator verification. Source parse and domain/source checks do not establish visual fidelity or live-service readiness.

## Explicit deletion target safety

The legacy default `DeleteCard` notification previously carried no card ID, so Home could prepare deletion of its last menu card when Remove was requested from another screen. The fallback now sends the invoking menu's explicit card ID only for an owned card. A custom `onDelete` callback, including MyProfile's handler, keeps its existing behavior.

Home uses `CardDeletionConfirmationPolicy` to resolve that exact ID from its current cards or an exactly matching menu card. Missing, blank or unknown IDs are rejected. An already displayed confirmation or in-flight deletion cannot be retargeted. Receiving the notification only prepares the existing confirmation; it never sends a deletion request. Confirmation still deletes the captured `cardToDelete.id` through the existing service.

This correction guarantees explicit target identity for this path. It does **not** claim that the historic Detail/Spark deletion presentation is fully repaired: when Home is not mounted, lacks the target, or is covered, those entry points can still lack a reachable confirmation. There is no network lookup or automatic-delete fallback. Behavioral tests cover missing/empty/mismatched IDs, an explicit B request with stale menu A, exact menu-card matches and confirmation/in-flight locks; source contracts retain the callback and confirmation boundary.
