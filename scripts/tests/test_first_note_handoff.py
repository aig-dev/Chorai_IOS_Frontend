import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "check_first_note", Path(__file__).resolve().parents[1] / "check-first-note-handoff.py"
)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class HandoffEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.run_data = dict(session_id="onb_current", actor_id="act_A",
                             note_id="ast_note", body="first chunk and second chunk")
        self.event = ["act_A", self.run_data["body"]]
        self.actual = dict(session_id="onb_current", actor_id="act_A",
                           events=[self.event], notes=["ast_note"])

    def test_exact_evidence_passes(self):
        check.verify(self.run_data, self.actual)

    def test_requires_one_full_body_event_from_the_same_actor(self):
        for events in ([], [self.event, self.event], [["act_A", "first chunk"]],
                       [["act_B", self.run_data["body"]]]):
            with self.subTest(events=events), self.assertRaises(ValueError):
                check.verify(self.run_data, dict(self.actual, events=events))

    def test_rejects_missing_stale_session_and_wrong_or_duplicate_notes(self):
        for change in (dict(session_id="onb_old"), dict(actor_id="act_B"),
                       dict(notes=[]), dict(notes=["ast_other"]), dict(notes=["ast_note", "ast_other"])):
            with self.subTest(change=change), self.assertRaises(ValueError):
                check.verify(self.run_data, dict(self.actual, **change))
        with self.assertRaises(ValueError):
            check.verify(self.run_data, None)
