# iOS API Environment and Project Guidance Design

## Status

Approved design checkpoint for making local iOS development reliably target the local Go backend while keeping production switching explicit and convenient.

## Context

The current app has two conflicting configuration sources. `APIConfiguration.swift` falls back to `http://127.0.0.1:8080` in Debug, while the shared `ArcNote` scheme injects `http://127.0.0.1:8180` only for an Xcode-run process. Opening the installed app from the Simulator drops that launch-only environment variable and silently returns to port `8080`. The live development backend resolves to port `8180`, so the app fails before receiving an HTTP response even though the backend and database are healthy.

The iOS repository also lacks a project-level `AGENTS.md`. Contributors therefore have no nearby source for backend startup, environment switching, design direction, native interaction rules, or completion checks.

## Goals

- Make the ordinary `ArcNote` Debug build target the local Go backend at `http://127.0.0.1:8180` by default.
- Provide an explicit Xcode Scheme switch for running a Debug build against `https://api.chorai.top`.
- Preserve the selected environment when the installed app is relaunched from the Simulator icon.
- Keep endpoint URLs in one shared configuration catalog rather than duplicating them across Swift, schemes, build files, and tests.
- Keep `CHORAI_API_BASE_URL` as an explicit override for UI tests and temporary diagnostics.
- Add a concise iOS `AGENTS.md` with durable engineering, environment, product, UX, accessibility, and verification guidance.
- Translate the Web project's Zen Aesthetic into native iOS conventions without copying Web-specific CSS rules.

## Non-goals

- No user-facing environment switch inside Chorai.
- No backend port, route, database, or deployment changes.
- No redesign of authentication storage; switching environments may invalidate the current token and return the developer to sign-in through the existing verification flow.
- No separate staging environment in this change.
- No unrelated editor, navigation, or visual implementation changes.
- No promise that `127.0.0.1` reaches a Mac from a physical iPhone; the default local workflow in this design is the iOS Simulator.

## Decision

Use build configurations to select a named API environment, and use a shared Swift endpoint catalog to resolve that name to a URL.

### Environment Matrix

| Xcode Scheme | Run configuration | API environment | Base URL | Purpose |
| --- | --- | --- | --- | --- |
| `ArcNote` | `Debug` | `local` | `http://127.0.0.1:8180` | Default Simulator development |
| `ArcNote Production` | `Debug-Production` | `production` | `https://api.chorai.top` | Explicit production-backed debugging |
| Archive | `Release` | `production` | `https://api.chorai.top` | Distribution |

`ArcNote` remains the existing default scheme to avoid breaking habitual use and automation. `ArcNote Production` is a new shared scheme visible in Xcode's scheme picker. The scheme files select build configurations; they do not contain endpoint literals.

### Configuration Resolution

`APIConfiguration` resolves the base URL in this order:

1. a non-empty `CHORAI_API_BASE_URL` process environment override;
2. the compiled `ChoraiAPIEnvironment` value from the app bundle;
3. a clear configuration failure if neither value is valid.

The override supports deterministic UI tests, unreachable-server fixtures, physical-device diagnostics, and temporary developer experiments. It is not the daily environment switch and must not be committed as a literal URL inside a shared scheme.

The bundle value is produced from `CHORAI_API_ENVIRONMENT` in the selected `.xcconfig`. Local and production configurations store only the names `local` and `production`. A small shared Swift type maps those names to the two canonical URLs. App code and UI-test helpers consume that type instead of declaring their own fallback ports.

Invalid environment names and malformed override URLs fail immediately with a message naming the invalid source. The app must never silently guess a different backend.

### Persistence Across Launches

The selected environment is compiled into the app bundle. It therefore survives process termination and a later Simulator-icon launch. This directly removes the failure mode caused by launch-only scheme variables.

Changing schemes requires rebuilding and launching the app. Runtime network-session mutation is intentionally excluded: it would require rebuilding the `NetworkManager` singleton, coordinating in-flight requests, separating authentication state, and adding product-facing developer UI for no user benefit.

## Components

### Endpoint Catalog

`ArcNote/APIEnvironment.swift` is compiled into both the `ArcNote` and
`ArcNoteUITests` targets. Its focused shared type owns:

- the supported names `local` and `production`;
- the canonical base URL for each name;
- parsing from a build-configuration string;
- safe normalization of an explicit URL override.

The type contains no networking, authentication, UI, or persistence behavior.
`ArcNoteUITests/APIEnvironmentTests.swift` exercises the catalog directly;
the existing CoreFlow source-contract suite verifies its project wiring.

### Build Configuration

- `Config/Local.xcconfig` selects `local`.
- `Config/Production.xcconfig` selects `production`.
- the existing `Debug` configuration uses Local;
- a new `Debug-Production` configuration mirrors Debug compiler/debug behavior but uses Production;
- `Release` uses Production.

`Info.plist` exposes the selected name as `ChoraiAPIEnvironment`. URL literals do not appear in `Info.plist`, `.xcconfig`, or shared schemes.

### App Configuration

`APIConfiguration` remains the application-facing gateway. `NetworkManager` continues to capture the resolved value when its singleton initializes. That behavior is correct because environments change through rebuilds, not during a running session.

The existing startup diagnostic should identify both the resolved environment and base URL in Debug logs. It must not print tokens or credentials.

### UI-Test Configuration

UI tests use the shared local endpoint catalog when no explicit override is supplied. Tests that intentionally simulate transport failure may continue to set `CHORAI_API_BASE_URL` to an unreachable address. Repeated `8080` fallback literals are removed so future port changes occur in one place.

### Project-Level `AGENTS.md`

`Chorai_IOS_Frontend/AGENTS.md` remains concise and operational. It covers:

1. project scope and key directories;
2. the environment matrix and Xcode switching workflow;
3. starting the backend with `make run-stack`, inspecting its resolved profile with `make env-show`, and checking `http://127.0.0.1:8180/health`;
4. the single-source API rule and the limited role of overrides;
5. the product direction: knowledge workflow plus social discovery, expressed through Zen Aesthetic;
6. native iOS UX, accessibility, editor, material, motion, and copy principles;
7. focused engineering workflow and Definition of Done.

The guide does not copy the Web document wholesale. It distills the durable principles and expresses them through native behavior: semantic colors and materials, Dynamic Type, safe areas, minimum `44 x 44 pt` targets, VoiceOver, Reduce Motion, predictable focus, and system keyboard conventions.

## Zen Aesthetic Direction

The iOS design north star is:

`Zen Aesthetic + social knowledge flow + native, intuitive iOS behavior`

- Content and writing are the visual protagonist.
- Interfaces are quiet, restrained, spacious, readable, and immediately understandable.
- The editor is an immersive workspace rather than a form; its toolbar remains subordinate but quickly reachable.
- Glass communicates spatial hierarchy rather than decoration. Primary surfaces may use expressive Liquid Glass; tools and secondary surfaces use quieter material. Neither may reduce contrast or click clarity.
- Each screen has one visual protagonist. Structure and task flow come before atmosphere and motion.
- Motion is short, soft, predictable, functional, and compatible with Reduce Motion.
- Copy is brief, precise, calm, and actionable.
- Native platform behavior wins over custom novelty, especially for keyboard focus, dismissal, navigation, sheets, menus, and destructive actions.

## Error and Safety Behavior

- Missing or unknown compiled environments produce an explicit startup configuration failure rather than falling back to a guessed port.
- Malformed overrides are rejected before constructing requests.
- Production builds are bound to the production environment by `Release` configuration and contract tests.
- Switching Local and Production can cause the existing restored token to fail verification; the current authentication flow then clears the invalid local session. This prevents a token from being treated as valid on the wrong backend.
- A production-backed Debug build is intentionally explicit in Xcode. No production selector is added to the customer UI.

## Test Strategy

### Test-first Contracts

Extend `LocalRunSchemeContractTests` before implementation so it initially fails against the current scheme-only setup. The contracts must prove:

- `Debug` selects Local and `Debug-Production` selects Production;
- `Release` selects Production;
- `ArcNote` runs Debug and `ArcNote Production` runs Debug-Production;
- shared schemes contain no literal API base URL;
- the endpoint catalog is the only tracked source containing the canonical Local and Production URLs;
- `APIConfiguration` keeps the explicit override at highest priority;
- UI-test helpers do not contain a `127.0.0.1:8080` fallback.

Add direct endpoint-catalog tests for name parsing, exact URLs, trailing-slash normalization, invalid names, and malformed overrides.

### Build Verification

- Build the `ArcNote` scheme for the Simulator.
- Build the `ArcNote Production` scheme for the Simulator.
- Inspect the produced app bundles and prove that Local contains `local` while Production contains `production`.
- Confirm Archive/Release resolves to Production through build settings or an archive-safe build-settings check.

### Runtime Verification

With the Go development stack running:

1. launch `ArcNote` from Xcode and confirm Debug logs and requests use port `8180`;
2. terminate the process and relaunch the installed app from the Simulator icon;
3. confirm the second process still uses port `8180` and `/health` remains reachable;
4. launch `ArcNote Production` and confirm its startup diagnostic resolves to `https://api.chorai.top` without performing mutating API actions;
5. return to `ArcNote`, rebuild, and confirm the local endpoint is restored.

## Acceptance Criteria

- A clean default `ArcNote` Debug build connects to `http://127.0.0.1:8180` without a launch environment variable.
- Relaunching that installed build from the Simulator icon still connects to port `8180`.
- `ArcNote Production` is available as a shared scheme and resolves to `https://api.chorai.top`.
- Release/Archive configuration resolves to Production.
- No tracked shared scheme contains a literal API URL.
- No app or UI-test code falls back to port `8080`.
- Canonical endpoint URLs exist in one shared catalog and are covered by tests.
- `CHORAI_API_BASE_URL` remains available for explicit tests and diagnostics.
- The focused configuration tests and both Simulator builds pass.
- The iOS repository contains a concise `AGENTS.md` covering environment operation, single-source configuration, Zen Aesthetic, native UX/accessibility, engineering workflow, and completion checks.
