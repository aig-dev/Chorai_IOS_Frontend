# iOS Command-Line Run Design

## Status

Reviewed and implemented on 2026-07-20, including final review fixes.

## Context

The iOS repository has shared Local and Production Xcode schemes but no
repository-level command for building, installing, and launching the current app
without opening Xcode. Developers currently need to remember a multi-command
`xcodebuild` and `simctl` sequence.

## Goal

Add `make ios-run` at the iOS repository root. The command builds the latest
checked-out Local app, prepares an iPhone Simulator, installs the resulting app,
and launches it without opening the Xcode GUI.

## Non-goals

- Do not start, restart, or modify the Go backend.
- Do not add an in-app environment switch.
- Do not change the Local or Production API configuration.
- Do not select or launch the Production scheme.
- Do not introduce a general-purpose iOS build system.

## Interface

Default local run:

```bash
make ios-run
```

Explicit simulator override:

```bash
make ios-run IOS_DEVICE="iPhone 16e"
```

Optional DerivedData override:

```bash
make ios-run IOS_DERIVED_DATA=/tmp/my-chorai-ios-build
```

Defaults:

- Scheme: `ArcNote`
- Configuration: `Debug`
- API environment: compiled Local selection (`http://127.0.0.1:8180`)
- DerivedData: `/tmp/chorai-ios-local`
- Bundle identifier: `com.michen.arcnote`

## Device Selection

The launcher resolves a device in this order:

1. a non-empty `IOS_DEVICE` value supplied to `make`;
2. the first currently booted available iPhone Simulator;
3. the fallback name `iPhone 17 Pro`.

The selected device may be a Simulator name or UDID. iPads are not selected
implicitly because the app is iPhone-only. An invalid or unavailable explicit
device fails with a clear command error rather than silently selecting another
device.

## Components

### Makefile

The root `Makefile` provides the public `ios-run` phony target and delegates to a
single launcher script. It forwards supported make variables as environment
variables and does not duplicate the orchestration commands.

### Launcher script

`scripts/ios-run.sh` owns:

- deterministic device selection;
- booting the selected Simulator and waiting until it is ready;
- bringing Apple Simulator to the foreground;
- building `ArcNote` Debug with an isolated DerivedData directory;
- installing `ArcNote.app` on the selected device;
- terminating an older app process and launching the new build;
- concise progress and failure messages.

The script uses `set -euo pipefail`. It resolves its repository root from its own
location so the make target works regardless of the caller's current shell path
after `make -C` or ordinary repository-root use.

## Error Handling

- Missing command-line tools, an unknown device, build failure, missing app
  product, installation failure, and launch failure all return non-zero.
- A device already being booted is accepted after `bootstatus` verifies it.
- Simulator and build errors remain visible; the command does not hide a real
  failure behind a successful make exit.
- Backend health is outside this target. If the app launches but shows no data,
  developers use the documented `make run-stack` and `/health` checks.

## Test Strategy

Add a focused CoreFlow contract test before implementation. It will prove RED
while the Makefile and launcher are absent, then verify:

- `make ios-run` delegates to the launcher;
- explicit `IOS_DEVICE` wins;
- a booted iPhone wins when no override exists;
- `iPhone 17 Pro` is the fallback;
- the launcher selects `ArcNote` Debug, uses isolated DerivedData, installs the
  built `.app`, and launches `com.michen.arcnote`.

The device chooser is a small sourceable shell function so the three selection
behaviors can be executed against fixture device-list text without booting or
mutating a Simulator. Final acceptance runs the real `make ios-run`, confirms a
zero exit, checks the installed bundle's Local environment, and verifies the app
process is running on the selected Simulator.

## Acceptance Criteria

- `make ios-run` works from `Chorai_IOS_Frontend` without opening Xcode.
- It builds the latest checked-out `ArcNote` Debug source.
- It prefers a booted iPhone and otherwise boots `iPhone 17 Pro`.
- `IOS_DEVICE="..."` overrides automatic selection.
- It installs and launches `com.michen.arcnote`.
- The installed bundle reports `ChoraiAPIEnvironment = local`.
- Selection contracts pass and the real launch completes successfully.
- The final tracked worktree remains clean on `main`.
