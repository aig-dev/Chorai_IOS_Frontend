# Chorai native V7 · Card levels & Chora

Independent SwiftUI prototype; `com.chorai.nativeprototype.v7`. No account, API, real rating write, or growth mutation.

Run `../Open-Prototype.command --journey levels --step guide --appearance light` for the comparison; omit appearance or use `system` to follow iOS. Build outputs stay at `/tmp/chorai-native-prototype-v7`.

Available steps: `guide`, `basic`, `notable`, `valuable`, `significant`, `exceptional`, `definitive`, `grid`, `merge`, `growth`, `unknown`.

The native guide opens tiers, cards open their full text, and explicit collection actions update this in-memory sample session. Reopening the app resets it. Menu scenario selection is a design-review control, not an in-product rating editor. Merge placement is read-only; use the retained Merge journey for its acceptance flow.

UI verification uses `-only-testing:ChoraiPrototypeUITests/CardLevelJourneyTests`. Older copied test classes still target V6 and were not rerun for this supplement. See `../VALIDATION.md` for exact results.
