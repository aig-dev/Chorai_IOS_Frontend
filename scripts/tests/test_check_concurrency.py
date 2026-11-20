"""Regression coverage for successful xcodebuild exits with missing UI results."""

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


def result_tree():
    # xcresulttool get test-results tests: the bundle identity is in the URL,
    # while nodeIdentifier contains only the class and method.
    return {"testNodes": [{"nodeType": "Test Suite", "children": [
        {
            "nodeType": "Test Case",
            "nodeIdentifier": f"ArcNoteUITests/{name}()",
            "nodeIdentifierURL": f"test://com.apple.xcode/ArcNote/ArcNoteUITests/ArcNoteUITests/{name}",
            "result": "Passed",
        } for name in CHECK.EDITOR_FLOWS
    ]}]}


class ConcurrencyRunnerTests(unittest.TestCase):
    def run_gate(self, tree, flows=None):
        with tempfile.TemporaryDirectory() as directory:
            def completed_command(output, label, command, **kwargs):
                # All processes exit successfully, including the filtered UI run.
                # The returned xcresult is the authority on what actually ran.
                log = Path(directory) / f"{label}.log"
                log.write_text(json.dumps(tree))
                return log

            with patch.dict(os.environ, {
                "CONCURRENCY_OUTPUT": directory,
                "IOS_DEVICE": "ebaca372-c94a-4a14-9947-634df3918495",
            }), patch("sys.argv", ["check-concurrency.py"]), \
                    patch.object(CHECK, "check_settings"), \
                    patch.object(CHECK, "run", side_effect=completed_command), \
                    patch.object(CHECK, "EDITOR_FLOWS", flows or CHECK.EDITOR_FLOWS), \
                    contextlib.redirect_stdout(io.StringIO()):
                CHECK.main()

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
        tree = result_tree()
        tree["testNodes"][0]["children"].pop()
        flows = CHECK.EDITOR_FLOWS[:-1] + (CHECK.EDITOR_FLOWS[-1] + "Misspelled",)
        with self.assertRaisesRegex(RuntimeError, "Misspelled"):
            self.run_gate(tree, flows)

    def test_zero_executed_cases_cannot_pass(self):
        with self.assertRaises(RuntimeError):
            self.run_gate({"testNodes": []})

    def test_skipped_case_cannot_pass(self):
        tree = result_tree()
        tree["testNodes"][0]["children"][0]["result"] = "Skipped"
        with self.assertRaises(RuntimeError):
            self.run_gate(tree)

    def test_failed_case_cannot_pass(self):
        tree = result_tree()
        tree["testNodes"][0]["children"][0]["result"] = "Failed"
        with self.assertRaises(RuntimeError):
            self.run_gate(tree)

    def test_same_method_in_another_bundle_cannot_satisfy_selector(self):
        tree = result_tree()
        node = tree["testNodes"][0]["children"][0]
        node["nodeIdentifierURL"] = node["nodeIdentifierURL"].replace(
            "/ArcNote/ArcNoteUITests/", "/ArcNote/AnotherBundle/"
        )
        with self.assertRaises(RuntimeError):
            self.run_gate(tree)


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
