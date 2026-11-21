"""Regression coverage for concurrency gate inputs, builds, and UI results."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "check_concurrency", Path(__file__).resolve().parents[1] / "check-concurrency.py"
)
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


DEVICE = "EBACA372-C94A-4A14-9947-634DF3918495"
IOS_RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
DEFAULT_SELECTORS = tuple(f"ArcNoteUITests/ArcNoteUITests/{name}" for name in CHECK.EDITOR_FLOWS)
SAME_METHOD_SELECTORS = (
    "ArcNoteUITests/ArcNoteUITests/testShared",
    "ArcNoteUITests/NativeRemediationVisualTests/testShared",
    "AnotherBundle/ArcNoteUITests/testShared",
)


def result_tree(selectors=DEFAULT_SELECTORS):
    # xcresulttool get test-results tests: the bundle identity is in the URL,
    # while nodeIdentifier contains only the class and method.
    return {"testNodes": [{"nodeType": "Test Suite", "children": [
        {
            "nodeType": "Test Case",
            "nodeIdentifier": f"{selector.split('/', 1)[1]}()",
            "nodeIdentifierURL": f"test://com.apple.xcode/ArcNote/{selector}",
            "result": "Passed",
        } for selector in selectors
    ]}]}


class ConcurrencyRunnerTests(unittest.TestCase):
    def setUp(self):
        self.commands = {}

    def run_gate(self, tree=None, *, flags=(), selector_json=None, device=DEVICE.lower(),
                 inventory=None):
        self.commands.clear()
        if inventory is None:
            inventory = {"devices": {IOS_RUNTIME: [{"udid": DEVICE, "isAvailable": True}]}}
        with tempfile.TemporaryDirectory() as directory:
            args = ["check-concurrency.py", *flags]
            if selector_json is not None:
                path = Path(directory) / "selectors.json"
                path.write_text(selector_json)
                args.extend(["--ui-selectors-file", str(path)])

            def completed_command(output, label, command, **kwargs):
                # Simulate successful processes. The inventory and xcresult
                # contents are the authorities on availability and execution.
                self.commands[label] = command
                log = output / f"{label}.log"
                log.write_text(json.dumps(inventory if label == "simulators" else tree))
                return log

            with patch.dict(os.environ, {
                "CONCURRENCY_OUTPUT": directory,
                "IOS_DEVICE": device,
            }), patch("sys.argv", args), \
                    patch.object(CHECK, "check_settings"), \
                    patch.object(CHECK, "run", side_effect=completed_command), \
                    contextlib.redirect_stdout(io.StringIO()) as stdout, \
                    contextlib.redirect_stderr(io.StringIO()) as stderr:
                try:
                    CHECK.main()
                except SystemExit as error:
                    self.fail(f"unexpected argument parsing exit {error}: {stderr.getvalue()}")
                return stdout.getvalue()

    def test_json_stdout_is_not_corrupted_by_tool_status_on_stderr(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            output = Path(directory)
            log = CHECK.run(output, "manifest", [sys.executable, "-c",
                'import sys; print("waiting for another SwiftPM instance", file=sys.stderr); print(\'{"mode": "6"}\')'],
                json_stdout=True)
            self.assertEqual(json.loads(log.read_text()), {"mode": "6"})
            self.assertIn("waiting", (output / "manifest.stderr.log").read_text())

    def test_all_requested_cases_pass(self):
        self.run_gate(result_tree())

    def test_misspelled_selector_cannot_pass_with_remaining_green_cases(self):
        selectors = DEFAULT_SELECTORS[:-1] + (DEFAULT_SELECTORS[-1] + "Misspelled",)
        with self.assertRaisesRegex(RuntimeError, "Misspelled"):
            self.run_gate(result_tree(DEFAULT_SELECTORS[:-1]), selector_json=json.dumps(selectors))

    def test_zero_executed_cases_cannot_pass(self):
        with self.assertRaises(RuntimeError):
            self.run_gate({"testNodes": []})

    def test_optional_simulator_omission_reports_skip(self):
        stdout = self.run_gate(device="")
        self.assertIn("Simulator regressions skipped", stdout)
        self.assertNotIn("tests-App", self.commands)
        self.assertNotIn("tests-EditorUI", self.commands)

    def test_required_simulator_omission_fails_before_tools(self):
        with self.assertRaisesRegex(RuntimeError, "IOS_DEVICE"):
            self.run_gate(flags=["--require-simulator"], device="")
        self.assertEqual(self.commands, {})

    def test_required_simulator_unavailability_fails_before_builds(self):
        for devices, runtime in (
            ([], IOS_RUNTIME),
            ([{"udid": DEVICE, "isAvailable": False}], IOS_RUNTIME),
            ([{"udid": DEVICE, "isAvailable": True}], "com.apple.CoreSimulator.SimRuntime.tvOS-26-2"),
        ):
            with self.subTest(devices=devices, runtime=runtime):
                with self.assertRaisesRegex(RuntimeError, "available iOS simulator"):
                    self.run_gate(flags=["--require-simulator"],
                                  inventory={"devices": {runtime: devices}})
                self.assertEqual(list(self.commands), ["simulators"])

    def test_required_simulator_cannot_be_combined_with_settings_only(self):
        with self.assertRaisesRegex(RuntimeError, "settings-only"):
            self.run_gate(flags=["--require-simulator", "--settings-only"])
        self.assertEqual(self.commands, {})

    def test_invalid_selector_files_fail_before_tools(self):
        for contents in (
            "", "{}", "[]", "[null]", '["Bundle/Class"]', '["Bundle/Class/*"]',
            '["Bundle/Class/testOne()"]', '[" Bundle/Class/testOne"]',
            '["Bundle//testOne"]', '["Bundle/Class/testOne/"]',
            '["Bundle/Class/testOne", "Bundle/Class/testOne"]',
        ):
            with self.subTest(contents=contents):
                with self.assertRaisesRegex(RuntimeError, "selector"):
                    self.run_gate(flags=["--require-simulator"], selector_json=contents)
                self.assertEqual(self.commands, {})

    def test_selected_full_identifiers_are_forwarded_to_xcode_and_verified(self):
        stdout = self.run_gate(result_tree(SAME_METHOD_SELECTORS), flags=["--require-simulator"],
                               selector_json=json.dumps(SAME_METHOD_SELECTORS))
        self.assertEqual(list(self.commands)[0], "simulators")
        self.assertEqual(
            [part for part in self.commands["tests-EditorUI"] if part.startswith("-only-testing:")],
            [f"-only-testing:{selector}" for selector in SAME_METHOD_SELECTORS],
        )
        self.assertIn(f"platform=iOS Simulator,id={DEVICE}", self.commands["tests-EditorUI"])
        self.assertIn("All 3 requested UI cases passed.", stdout)

    def test_same_method_in_another_class_or_bundle_cannot_satisfy_selector(self):
        requested, *alternatives = SAME_METHOD_SELECTORS
        for other_selector in alternatives:
            with self.subTest(other_selector=other_selector):
                with self.assertRaisesRegex(RuntimeError, requested):
                    self.run_gate(result_tree([other_selector]),
                                  selector_json=json.dumps([requested]))

    def test_unsuccessful_or_mixed_results_cannot_pass(self):
        for status in ("Skipped", "Failed", None):
            for also_passed in (False, True):
                with self.subTest(status=status, also_passed=also_passed):
                    tree = result_tree(SAME_METHOD_SELECTORS)
                    cases = tree["testNodes"][0]["children"]
                    if also_passed:
                        cases.append(dict(cases[0], result=status))
                    else:
                        cases[0]["result"] = status
                    with self.assertRaisesRegex(RuntimeError, SAME_METHOD_SELECTORS[0]):
                        self.run_gate(tree, selector_json=json.dumps(SAME_METHOD_SELECTORS))


class ConcurrencySettingsTests(unittest.TestCase):
    def check(self, *, changed_configuration=None, changed_target=None, overrides=None):
        with tempfile.TemporaryDirectory() as directory:
            def configuration_command(output, label, command, **kwargs):
                log = Path(directory) / f"{label}.log"
                if label.startswith("manifest-"):
                    value = {"swiftLanguageVersions": ["6"], "targets": [],
                             "platforms": [{"platformName": "ios", "version": "16.0"}]}
                else:
                    value = []
                    for name in ("ArcNote", "ArcNoteTests", "ArcNoteUITests"):
                        settings = {"SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete",
                                    "IPHONEOS_DEPLOYMENT_TARGET": "16.0"}
                        if label == f"settings-{changed_configuration}" and name == changed_target:
                            settings.update(overrides or {})
                        value.append({"target": name, "buildSettings": settings})
                log.write_text(json.dumps(value))
                return log
            with patch.object(CHECK, "run", side_effect=configuration_command), \
                    contextlib.redirect_stdout(io.StringIO()):
                CHECK.check_settings(Path(directory))

    def test_all_first_party_targets_use_swift_six(self):
        self.check()

    def test_swift_five_cannot_return_in_any_target_or_configuration(self):
        for configuration in CHECK.CONFIGURATIONS:
            for target in ("ArcNote", "ArcNoteTests", "ArcNoteUITests"):
                with self.subTest(configuration=configuration, target=target):
                    with self.assertRaisesRegex(RuntimeError, "SWIFT_VERSION must be 6.0"):
                        self.check(changed_configuration=configuration, changed_target=target,
                                   overrides={"SWIFT_VERSION": "5.0"})

    def test_implicit_actor_and_approachable_modes_cannot_replace_explicit_boundaries(self):
        for key, value in (("SWIFT_DEFAULT_ACTOR_ISOLATION", "MainActor"),
                           ("SWIFT_APPROACHABLE_CONCURRENCY", "YES")):
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                self.check(changed_configuration="Debug", changed_target="ArcNote",
                           overrides={key: value})


class ConcurrencyDiagnosticTests(unittest.TestCase):
    def run_diagnostic(self, relative_path, diagnostic):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            message = f"{CHECK.ROOT / relative_path}:12:5: warning: {diagnostic}"
            # The compiler succeeds: legacy SDK callback checks can remain warnings
            # even in Swift 6. The gate must still inspect first-party diagnostics.
            return CHECK.run(Path(directory), "compile", [
                sys.executable, "-c", "import sys; print(sys.argv[1])", message
            ])

    def test_successful_compile_cannot_hide_legacy_sendable_warning(self):
        with self.assertRaisesRegex(RuntimeError, "concurrency diagnostics"):
            self.run_diagnostic("ArcNoteUITests/ArcNoteUITests.swift",
                                "mutation of captured var 'result' in concurrently-executing code [#SendableClosureCaptures]")

    def test_package_actor_warning_cannot_pass(self):
        with self.assertRaisesRegex(RuntimeError, "concurrency diagnostics"):
            self.run_diagnostic("Packages/CoreFlow/Sources/CoreFlow/Reader.swift",
                                "call to main actor-isolated instance method in a synchronous nonisolated context")

    def test_style_warning_remains_visible_without_failing_concurrency_gate(self):
        self.run_diagnostic("ArcNoteTests/CardImagePreparationTests.swift",
                            "weak variable was never mutated; consider changing to let")

    def test_vendor_diagnostic_does_not_redefine_first_party_migration_scope(self):
        self.run_diagnostic(".build/checkouts/Dependency/Legacy.swift",
                            "capture of a non-Sendable value")


class ConcurrencyRepeatRunTests(unittest.TestCase):
    def test_incremental_retry_cannot_erase_unchanged_source_diagnostic(self):
        original_run = CHECK.run
        for stage, product_flag, source in (
            ("tests-CoreFlow", "--scratch-path", "Packages/CoreFlow/Sources/CoreFlow/Probe.swift"),
            ("build-Debug", "-derivedDataPath", "ArcNote/Probe.swift"),
        ):
            compiled_products = set()
            with tempfile.TemporaryDirectory() as directory:
                def incremental_build(output, label, command, **kwargs):
                    log = Path(directory) / f"{label}.log"
                    if label == stage:
                        product = (command[command.index(product_flag) + 1]
                                   if product_flag in command else "reused-default-products")
                        warning = "" if product in compiled_products else (
                            f"{CHECK.ROOT}/{source}:10:5: "
                            "warning: mutation of captured var 'value' in concurrently-executing code"
                        )
                        # Successful compilers cache products even when the
                        # subsequent diagnostic check rejects the gate.
                        compiled_products.add(product)
                        return original_run(output, label, [
                            sys.executable, "-c", "import sys; print(sys.argv[1])", warning
                        ])
                    log.write_text("")
                    return log

                with patch.dict(os.environ, {"CONCURRENCY_OUTPUT": directory, "IOS_DEVICE": ""}), \
                        patch("sys.argv", ["check-concurrency.py"]), \
                        patch.object(CHECK, "check_settings"), \
                        patch.object(CHECK, "run", side_effect=incremental_build), \
                        contextlib.redirect_stdout(io.StringIO()):
                    for attempt in range(2):
                        with self.subTest(stage=stage, attempt=attempt):
                            with self.assertRaisesRegex(RuntimeError, "concurrency diagnostics"):
                                CHECK.main()

    def test_ordinary_variable_names_are_not_concurrency_diagnostics(self):
        helper = ConcurrencyDiagnosticTests()
        for name in ("factory", "actor"):
            with self.subTest(name=name):
                helper.run_diagnostic("ArcNoteTests/FixtureTests.swift",
                    f"variable '{name}' was never mutated; consider changing to 'let' constant")


class ConcurrencyProductLifetimeTests(unittest.TestCase):
    def test_package_products_are_released_before_xcode_builds(self):
        with tempfile.TemporaryDirectory() as directory:
            package_products = []
            def build(output, label, command, **kwargs):
                log = Path(directory) / f"{label}.log"
                log.write_text("")
                if label in ("tests-CoreFlow", "tests-BlockNoteEditor"):
                    products = Path(command[command.index("--scratch-path") + 1])
                    products.mkdir(parents=True, exist_ok=True)
                    (products / "compiled").write_text("build product")
                    package_products.append(products)
                if label.startswith("build-"):
                    self.assertFalse(any(path.exists() for path in package_products),
                                     "Completed package products must not inflate the Xcode disk peak")
                return log
            with patch.dict(os.environ, {"CONCURRENCY_OUTPUT": directory, "IOS_DEVICE": ""}), \
                    patch("sys.argv", ["check-concurrency.py"]), \
                    patch.object(CHECK, "check_settings"), \
                    patch.object(CHECK, "run", side_effect=build), \
                    contextlib.redirect_stdout(io.StringIO()):
                CHECK.main()

    def test_hosted_failure_results_survive_temporary_product_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            bundles = []
            def build(output, label, command, **kwargs):
                log = Path(directory) / f"{label}.log"
                log.write_text("")
                if label == "tests-App":
                    self.assertIn("-resultBundlePath", command)
                    bundle = Path(command[command.index("-resultBundlePath") + 1])
                    bundle.mkdir(parents=True)
                    (bundle / "failure.txt").write_text("failure evidence")
                    bundles.append(bundle)
                    raise RuntimeError("synthetic hosted failure")
                return log
            with patch.dict(os.environ, {"CONCURRENCY_OUTPUT": directory,
                    "IOS_DEVICE": "EBACA372-C94A-4A14-9947-634DF3918495"}), \
                    patch("sys.argv", ["check-concurrency.py"]), \
                    patch.object(CHECK, "check_settings"), \
                    patch.object(CHECK, "run", side_effect=build), \
                    contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, "synthetic hosted failure"):
                    CHECK.main()
            self.assertEqual(len(bundles), 1)
            self.assertEqual((bundles[0] / "failure.txt").read_text(), "failure evidence")
