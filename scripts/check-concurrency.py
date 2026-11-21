#!/usr/bin/env python3
"""Validate the staged Swift migration using persisted settings, never overrides."""

import argparse
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit
import uuid


ROOT = Path(__file__).resolve().parents[1]
CONFIGURATIONS = ("Debug", "Debug-Production", "Release")
EDITOR_FLOWS = (
    "testCardEditorLeadingControlChangesFromBackToSaveAndBack",
    "testCardEditorBridgeFailureFallbackRetriesIntoFreshWebView",
    "testCardEditorInlineImageRendersPixelsWithinPhoneViewport",
    "testCardEditorShellCompatibilityBlockIsReadOnlyAndCannotSave",
    "testMergeArtifactImmediateBackReopensWithBodyAndPendingTag",
    "testMergeArtifactBackRetainsLossyDraftAndCompletedTag",
)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)



def check_concurrency_diagnostics(log):
    # SDK @preconcurrency imports can downgrade Swift 6 violations to warnings.
    # Preserve ordinary/vendor warnings while rejecting first-party concurrency debt.
    source_roots = [ROOT / name for name in (
        "ArcNote", "ArcNoteTests", "ArcNoteUITests",
        "Packages/CoreFlow/Sources", "Packages/CoreFlow/Tests",
        "Packages/BlockNoteEditor/Sources", "Packages/BlockNoteEditor/Tests",
    )]
    violations = []
    for line in log.read_text().splitlines():
        match = re.match(r"^(.+\.swift):\d+:\d+: warning: (.+)$", line)
        if not match:
            continue
        # Source identifiers/types are quoted. A variable named 'factory' or
        # 'actor' does not turn an ordinary style warning into an isolation issue.
        diagnostic = re.sub(r"'[^']*'|`[^`]*`", "", match[2])
        if not re.search(r"\b(?:sendable|(?:main|global)?actor|(?:non)?isolated|isolation|concurren\w*|data races?)\b",
                         diagnostic, re.I):
            continue
        source = (ROOT / match[1]).resolve()
        if any(source.is_relative_to(root) for root in source_roots):
            violations.append(line)
    require(not violations, f"First-party concurrency diagnostics in {log}:\n"
            + "\n".join(dict.fromkeys(violations)))


def run(output, label, command, *, json_stdout=False):
    log = output / f"{label}.log"
    print(f"[concurrency] {label} → {log}", flush=True)
    with log.open("w") as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream,
                                stderr=subprocess.PIPE if json_stdout else subprocess.STDOUT)
    if json_stdout:
        # SwiftPM can announce a build-lock wait on stderr before emitting valid
        # JSON. Keep that diagnostic without contaminating machine-readable output.
        (output / f"{label}.stderr.log").write_bytes(result.stderr)
    if result.returncode:
        print("\n".join(log.read_text().splitlines()[-25:]), file=sys.stderr)
        if json_stdout:
            print(result.stderr.decode(errors="replace"), file=sys.stderr)
        raise RuntimeError(f"{label} exited {result.returncode}; see {log}")
    if not json_stdout:
        check_concurrency_diagnostics(log)
    return log


def check_settings(output):
    for name, mode in (("CoreFlow", "6"), ("BlockNoteEditor", "6")):
        log = run(output, f"manifest-{name}", [
            "swift", "package", "--package-path", f"Packages/{name}", "dump-package",
        ], json_stdout=True)
        manifest = json.loads(log.read_text())
        require(manifest["swiftLanguageVersions"] == [mode], f"{name} must use Swift {mode}")
        require(any(p["platformName"] == "ios" and p["version"] == "16.0"
                    for p in manifest["platforms"]), f"{name} must retain iOS 16")
        for target in manifest["targets"]:
            settings = target.get("settings", [])
            require(not any("swiftLanguageMode" in s["kind"] for s in settings),
                    f"{target['name']} must inherit the package language mode")

    for configuration in CONFIGURATIONS:
        log = run(output, f"settings-{configuration}", [
            "xcodebuild", "-project", "ArcNote.xcodeproj", "-alltargets",
            "-configuration", configuration, "-sdk", "iphonesimulator",
            "-showBuildSettings", "-json",
        ], json_stdout=True)
        targets = json.loads(log.read_text())
        require({t["target"] for t in targets} >= {"ArcNote", "ArcNoteTests", "ArcNoteUITests"},
                f"{configuration}: missing App or test target settings")
        for target in targets:
            settings = target["buildSettings"]
            context = f"{configuration}/{target['target']}"
            for key, value in (("SWIFT_VERSION", "6.0"),
                               ("SWIFT_STRICT_CONCURRENCY", "complete"),
                               ("IPHONEOS_DEPLOYMENT_TARGET", "16.0")):
                require(settings.get(key) == value, f"{context}: {key} must be {value}")
            require(settings.get("SWIFT_DEFAULT_ACTOR_ISOLATION", "nonisolated") == "nonisolated",
                    f"{context}: default actor isolation changed")
            require(settings.get("SWIFT_APPROACHABLE_CONCURRENCY", "NO") == "NO",
                    f"{context}: Approachable Concurrency would change the explicit execution boundaries")
    print("[concurrency] Persisted Swift 6 language modes and complete checks verified.", flush=True)


def load_ui_selectors(path):
    try:
        selectors = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise RuntimeError(f"Cannot read UI selector file {path}: {error}") from error
    require(isinstance(selectors, list) and selectors, f"{path}: expected a nonempty UI selector array")
    for selector in selectors:
        require(
            isinstance(selector, str)
            and re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*/[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*",
                             selector),
            f"{path}: invalid UI selector {selector!r}; expected bundle/class/method",
        )
    require(len(set(selectors)) == len(selectors), f"{path}: duplicate UI selectors")
    return selectors


def check_simulator(output, device):
    log = run(output, "simulators", ["xcrun", "simctl", "list", "devices", "available", "-j"],
              json_stdout=True)
    inventory = json.loads(log.read_text())["devices"]
    require(
        any(entry["udid"] == device and entry["isAvailable"]
            for runtime, devices in inventory.items()
            if runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            for entry in devices),
        f"IOS_DEVICE={device} must refer to an available iOS simulator; see {log}",
    )


def check_editor_results(tree, selectors):
    results = {}
    pending = list(tree.get("testNodes", []))
    while pending:
        node = pending.pop()
        pending.extend(node.get("children", []))
        if node.get("nodeType") == "Test Case":
            # Include the test bundle: nodeIdentifier alone contains only class/method.
            path = urlsplit(node.get("nodeIdentifierURL", "")).path.split("/")
            if len(path) == 5 and path[0] == "":
                identifier = "/".join(unquote(component) for component in path[2:])
                results.setdefault(identifier, set()).add(node.get("result"))
    missing = [selector for selector in selectors if results.get(selector) != {"Passed"}]
    require(not missing, "UI cases missing or not passed: " + ", ".join(missing))
    print(f"[concurrency] All {len(selectors)} requested UI cases passed.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--settings-only", action="store_true", help="check effective configuration only")
    parser.add_argument("--require-simulator", action="store_true",
                        help="require an available iOS simulator UUID in IOS_DEVICE before building")
    parser.add_argument("--ui-selectors-file", type=Path, metavar="PATH",
                        help="select simulator UI tests with a JSON array of bundle/class/method identifiers")
    args = parser.parse_args()
    require(not (args.settings_only and args.require_simulator),
            "--require-simulator cannot be combined with --settings-only")
    selectors = (load_ui_selectors(args.ui_selectors_file) if args.ui_selectors_file else
                 [f"ArcNoteUITests/ArcNoteUITests/{name}" for name in EDITOR_FLOWS])
    device = os.environ.get("IOS_DEVICE", "").strip()
    require(device or not args.require_simulator,
            "--require-simulator needs IOS_DEVICE set to a dedicated simulator UUID")
    if device:
        # Xcode destination IDs are case-sensitive even though UUID parsing is not.
        device = str(uuid.UUID(device)).upper()
    output = Path(os.environ.get("CONCURRENCY_OUTPUT", ROOT / ".build/concurrency")).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.require_simulator:
        check_simulator(output, device)
    run(output, "toolchain", ["xcrun", "swift", "--version"])
    run(output, "xcode", ["xcodebuild", "-version"])
    check_settings(output)
    if args.settings_only:
        return

    run(output, "tests-Runner", [sys.executable, "-B", "-m", "unittest", "discover",
                                 "-s", "scripts/tests", "-p", "test_*.py"])
    # A rejected warning still leaves successful compiler products behind.
    # Reusing them can hide the unchanged diagnostic on the next invocation.
    # Keep downloaded dependencies, but compile into fresh per-run products.
    # Release each package's products before the next suite and Xcode builds,
    # rather than retaining all compiler output until the entire gate finishes.
    for package in ("CoreFlow", "BlockNoteEditor"):
        with tempfile.TemporaryDirectory(prefix=f"{package}-products-", dir=output) as directory:
            run(output, f"tests-{package}", ["swift", "test", "--package-path", f"Packages/{package}",
                                                           "--scratch-path", directory])

    with tempfile.TemporaryDirectory(prefix="xcode-products-", dir=output) as directory:
        products = Path(directory)
        common = ["xcodebuild", "-quiet", "-project", "ArcNote.xcodeproj",
                  "-derivedDataPath", str(products / "DerivedData"),
                  "-clonedSourcePackagesDirPath", str(output / "SourcePackages"), "CODE_SIGNING_ALLOWED=NO"]
        for configuration in CONFIGURATIONS:
            scheme = "ArcNote Production" if configuration != "Debug" else "ArcNote"
            run(output, f"build-{configuration}", common + [
                "-scheme", scheme, "-configuration", configuration,
                "-destination", "generic/platform=iOS Simulator", "build",
            ])

        if device:
            destination = ["-destination", f"platform=iOS Simulator,id={device}"]
            app_results = Path(tempfile.mkdtemp(prefix="app-tests-", dir=output)) / "App.xcresult"
            run(output, "tests-App", common + ["-scheme", "ArcNoteTests"] + destination
                + ["-resultBundlePath", str(app_results), "test"])
            results = Path(tempfile.mkdtemp(prefix="editor-ui-", dir=output)) / "EditorUI.xcresult"
            run(output, "tests-EditorUI", common + ["-scheme", "ArcNoteUITests", "-parallel-testing-enabled", "NO"]
                + destination + ["-resultBundlePath", str(results)]
                + [f"-only-testing:{selector}" for selector in selectors]
                + ["test"])
            tree = run(output, "results-EditorUI", ["xcrun", "xcresulttool", "get", "test-results",
                                                   "tests", "--path", str(results)], json_stdout=True)
            check_editor_results(json.loads(tree.read_text()), selectors)
        else:
            print("[concurrency] Simulator regressions skipped; set IOS_DEVICE to a dedicated simulator UUID.")
    print(f"[concurrency] PASS. Logs: {output}. First-party targets use Swift 6.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        sys.exit(f"[concurrency] FAIL: {error}")
