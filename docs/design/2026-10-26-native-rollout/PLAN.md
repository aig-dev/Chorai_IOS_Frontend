> Status correction · 2026-10-27: the checked tasks below are historical implementation records, not whole-frontend fidelity sign-off. The current authoritative remaining scope and evidence are in [full remediation](../2026-10-27-full-native-remediation/PROGRESS.md) and [page audit](../2026-10-27-full-native-remediation/PAGE-AUDIT.md).

# Chorai native frontend Implementation Plan

> **For agentic workers:** Implement tasks in assigned file ownership groups; root integrates and verifies. Follow the approved SPEC.md and native AGENTS.md. User explicitly authorized full implementation; do not stop for a repeat design gate.

**Goal:** Bring the accepted native visual and interaction direction into all existing iOS frontend surfaces.

**Architecture:** Shared adaptive semantic colors and native glass controls, with existing state owners and service contracts retained. Explore adds tested browse history and shared favorite state; the editor receives appearance through its existing native bridge. Separate agents own Explore, editing/AI and secondary surfaces; root owns shared theme, tier art, Home, shell, integration and end-to-end verification.

**Tech Stack:** SwiftUI/UIKit, iOS 16+, SwiftPM CoreFlow/BlockNoteEditor, Xcode; genuine Liquid Glass on iOS 26+.

**Spec:** [SPEC.md](SPEC.md)

## Global Constraints

- Follow system light/dark; approved warm-white/forest/gold tokens from SPEC.md.
- Original business actions, data, state owners, permissions and backend routes stay intact.
- No generated/vendored resources or package version updates; no network to production.
- No branch changes, commits or push; keep pre-existing modifications and V1–V8.
- Only root operates Simulator and app builds, avoiding shared destination collisions.

## Review Focus

1. Right swipe/favorite failure or concurrent card changes must not lose a card or revert another field.
2. Grid/detail/Deck mode changes must retain note identity, level, collection and browsing context.
3. System theme changes must reach WebKit editor, UIKit sheets and all contrast-critical text.
4. Save/AI/Merge state recovery and ownership must survive cosmetic migrations without altered defaults.
5. Dynamic Type, keyboard, safe areas, Reduce Motion/Transparency must leave actions usable.

## Tasks

- [x] **1. Theme, tier materials, app shell and Home** — root. Create `ArcNote/ChoraiTheme.swift`, `ChoraiCardLevel.swift`, register assets/source; update `CardLevelMaterial.swift`, `CoreShellViews.swift`, `TabBarView.swift`, `HomeView.swift`, app root tint/config. Replace image tab navigation with native TabView while preserving coordinator and routes. Verify source contracts, native builds, light/dark Home/editor routes.
- [x] **2. Explore browse behavior and presentation** — ios_explore_migration. Own `ExploreView.swift`, `CoreFlow/FlowViews.swift`, `CardEngagementCenter.swift`, `NetworkCoreFlowService.swift`, CoreFlow `FlowDeckStore.swift` / `CoreFlowModels.swift`, related tests. RED→GREEN tests for history, collect-and-advance, error, undo and external favorite sync. Shared real rich content; never copy demo SampleNote.
- [x] **3. Reader, writing, Spark and Merge** — ios_editor_migration. Own `CardEditor/*` except root's `CardLevelMaterial`, `DetailView`, `NewNoteView`, `NewInsightView`, `MergeView`, `SparkView`, CoreFlow `MergeArtifactEditorSurface`, `MergeLifecycleViews`, `MergeTaskRail`, `SparkContinuationViews`; non-vendored BlockNoteEditor Swift files. Preserve protocol, command/session rules and service callbacks; add theme bridge checks and update obsolete visual assertions only.
- [x] **4. All auxiliary surfaces** — ios_secondary_migration. Own Content/SignIn/SignUp/AccessGate/Interests; settings/account/privacy/plugins; profiles/social; notifications; invitations/credit; Chora; chat; comment/link/trash/discovery; ShareCard/ContentReport/PopupMenu/Search/ActionBox. Keep source-contract behavior and accessibility IDs; audit every remaining hard-coded appearance.
- [x] **5. Integration and verification** — root. Compile both original schemes with original pins, run full CoreFlow and BlockNoteEditor tests, select relevant offline UI cases, inspect actual app on Simulator in both themes, accessibility/keyboard checks, preserve evidence and coverage ledger. Independent code review, fix material findings, final checked source state and honest limits.

## Shared interfaces

`ChoraiTheme`: static adaptive Color background/surface/raisedSurface/ink/secondaryInk/tertiaryInk/accent/gold/separator/onAccent. `ChoraiBackground(): View`, `.choraiGlassSurface(cornerRadius: CGFloat = 24)`, `.choraiPageBackground()`.

`ChoraiLevelBadge(rate: Int?, compact: Bool = false)`; `.choraiCardLevel(rate: Int?, showsChora: Bool = false)` adds clearance derived from the actual artwork only when true. Existing `CardLevelStyle` thresholds/defaults remain.

Favorite success event: `Notification.Name.choraiFavoriteChanged`, userInfo `cardID: String`, `isFavorited: Bool`, optional `count: Int`. Real successful mutation owners publish; Explore reconciles by ID. Do not publish optimistic or fixture fake success.
