# Chorai iOS Guide

## Scope

This repository contains the native app: iOS 16.0+, iPhone-only. Work in
`ArcNote/` for app code, `ArcNoteUITests/` for simulator flows, and
`Packages/CoreFlow/` for testable domain and source contracts. Follow the user's
requested git workflow; do not create or switch branches unless explicitly
requested. Preserve unrelated changes.

## API Environments

Local Simulator development is the default.

| Scheme | API | Use |
| --- | --- | --- |
| `ArcNote` | `http://127.0.0.1:8180` | normal local development |
| `ArcNote Production` | `https://product.chorai.app` | explicit production-backed debugging through the product API proxy |
| Archive / Release | production | distribution |

Start and inspect the local backend from the outer Chorai workspace root:

```bash
cd Chorai_Go/chorai-go
make run-stack
make env-show
curl http://127.0.0.1:8180/health
```

Switch Local and Production from Xcode's Scheme picker, then rebuild. The selected
environment is compiled into the app and survives a Simulator-icon relaunch.
`127.0.0.1` is a Simulator default. For temporary physical-device diagnostics
only, a physical iPhone may use an explicit reachable Mac address through
`CHORAI_API_BASE_URL`; routine local development stays on the compiled Local
selection in the Simulator.

API routing has one runtime single source of truth: `ArcNote/APIEnvironment.swift`.
Build configurations select only `local` or `production`. Do not hard-code API
hosts or ports in views, services, schemes, or additional config files.
Complete runtime endpoint literals are forbidden outside `APIEnvironment.swift`.
Focused catalog contract/tests may assert or assemble expected endpoint components.
`CHORAI_API_BASE_URL` is reserved for tests and temporary diagnostics.
Do not add a customer-facing environment switch.

When data appears missing, first confirm the app's logged environment and URL,
then check `/health` and backend access logs. Do not assume the database is empty.

## Engineering Boundaries

- Prefer small, local changes that preserve existing navigation and data flow.
- Keep networking behind `APIConfiguration` and `NetworkManager`.
- Never log tokens, credentials, private note bodies, or full sensitive payloads.
- Reuse existing SwiftUI, CoreFlow, and editor primitives before adding variants.
- Use test-first changes for behavior and regression fixes.
- Do not edit generated or vendored package output.

## Zen Aesthetic

North star: `Zen Aesthetic + social knowledge flow + native, intuitive iOS behavior`.

- Content and writing are the protagonist: quiet, restrained, spacious, readable.
- Give each screen one visual focus; establish hierarchy before atmosphere.
- The editor is a calm, focused workspace, not a form. Keep tools secondary but
  immediately reachable.
- Glass communicates depth and hierarchy, not decoration. Never trade contrast or
  click clarity for material effects.
- Prefer semantic colors, system typography, Dynamic Type, safe areas, and native
  controls over custom novelty.
- Keep effective tap targets at least `44 x 44 pt`; provide clear VoiceOver labels.
- Respect Reduce Motion and Reduce Transparency. Motion stays short, soft,
  predictable, and functional.
- Prefer native keyboard focus, dismissal, navigation, menus, and sheet behavior.
- Keep copy brief, precise, calm, and actionable.

## Workflow

Before editing, inspect the owning view, its state owner, related CoreFlow contract,
and current scheme. During implementation, avoid parallel sources of truth and
unrelated refactors. Afterward, run the narrowest relevant tests, then build the
affected scheme and inspect the real Simulator flow.

## Definition of Done

- Behavior is correct in the intended Local or Production configuration.
- Default `ArcNote` and explicit `ArcNote Production` both build.
- Local survives termination and a Simulator-icon relaunch without changing ports.
- Relevant unit, source-contract, and UI tests pass.
- UI remains native, accessible, readable, and consistent with Zen Aesthetic.
- No new endpoint literal, visual noise, sensitive log, or undocumented exception
  was introduced.
