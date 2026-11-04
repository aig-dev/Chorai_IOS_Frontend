# Chorai Journeys V6 · 原生离线原型

完整操作方式、覆盖范围和边界见 [上一级 README](../README.md)。

- Build: `bash build.sh`
- App: `/tmp/chorai-native-prototype-v6/ChoraiPrototype.app`
- Bundle: `com.chorai.nativeprototype.v6`
- Launcher: `../Open-Prototype.command`
- Default: Feature journeys, including Spark, Merge and shared Explore / Home / writing workspace.
- Direct review: `--journey spark|merge --step <state> --appearance light|dark`.
- Source contracts: `../SPARK-FLOW.md`, `../MERGE-FLOW.md`, `../FLOW-MAP.md`.
- Final checks: `../VALIDATION.md` and `../design-qa.md`.

This is an independent SwiftUI design sample. Production ArcNote, V1–V5, account data and backend contracts are not changed. Only an explicit Merge Accept inserts an in-memory private sample note; process relaunch resets samples.
