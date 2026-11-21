"""Check a canonical onboarding UI run against its isolated local PostgreSQL fixture."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


TEST = "ArcNoteUITests/testCanonicalOnboardingLibraryNoteAndFlowResumeGoV1()"
ATTACHMENT = "first-note-guide-expectation"

# The selector trashes its NOTE during cleanup. Its projection and ownership
# still identify the exact server NOTE after the XCTest process has exited.
QUERY = """
BEGIN READ ONLY;
SELECT json_build_object(
    'session_id', s.session_id, 'actor_id', s.actor_id,
    'events', ARRAY(
        SELECT json_build_array(e.actor_id, e.payload_json->>'text')
        FROM domain.onboarding_events e
        WHERE e.session_id = s.session_id AND e.role = 'user'
          AND e.event_type = 'user_input' AND e.payload_json->>'input_type' = 'text'
        ORDER BY e.seq
    ),
    'notes', ARRAY(
        SELECT n.asset_id FROM domain.asset_note_data n
        JOIN ontology.assets a ON a.asset_id = n.asset_id AND a.schema_type = 'NOTE'
        WHERE n.content_text = :'body' AND EXISTS (
            SELECT 1 FROM ontology.relations r WHERE r.relation_type = 'OWNS'
            AND r.from_type = 'Actor' AND r.from_id = s.actor_id
            AND r.to_type = 'Asset' AND r.to_id = n.asset_id
        )
    )
) FROM domain.onboarding_sessions s WHERE s.flow_version = 1 AND s.session_id = :'session_id';
COMMIT;
"""


def read_expectation(bundle):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--test-id", TEST,
                        "--path", str(bundle), "--filter", ATTACHMENT + "*", "--output-path", directory],
                       check=True, stdout=subprocess.DEVNULL)
        groups = json.loads((root / "manifest.json").read_text())
        files = [attachment["exportedFileName"] for group in groups if group["testIdentifier"] == TEST
                 for attachment in group["attachments"]
                 if attachment["suggestedHumanReadableName"].startswith(ATTACHMENT + "_")]
        if len(files) != 1:
            raise ValueError("Expected one first-note attachment from the canonical selector")
        expected = json.loads((root / files[0]).read_text())
        for key in ("session_id", "actor_id", "note_id", "body"):
            if not isinstance(expected.get(key), str) or not expected[key].strip():
                raise ValueError(f"Missing attachment field {key}")
        return expected


def verify(expected, actual):
    if not actual or actual["session_id"] != expected["session_id"] or actual["actor_id"] != expected["actor_id"]:
        raise ValueError("Canonical session or actor mismatch")
    if actual["events"] != [[expected["actor_id"], expected["body"]]]:
        raise ValueError("Expected exactly one guide text event from the actor with the complete submitted body")
    if actual["notes"] != [expected["note_id"]]:
        raise ValueError("Expected exactly one matching NOTE owned by the actor, with the recorded server ID")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xcresult", type=Path)
    parser.add_argument("--database", required=True, help="Isolated ios_live_* QA database")
    args = parser.parse_args()
    if not re.fullmatch(r"ios_live_[a-z0-9_]+", args.database):
        parser.error("--database must name an isolated ios_live_* QA fixture")
    expected = read_expectation(args.xcresult)
    result = subprocess.run(["docker", "exec", "-i", "chorai-postgres-dev", "psql", "-XqAt",
                             "-v", "ON_ERROR_STOP=1", "-U", "chorai", "-d", args.database,
                             "-v", "session_id=" + expected["session_id"], "-v", "body=" + expected["body"]],
                            input=QUERY, text=True, capture_output=True, check=True)
    verify(expected, json.loads(result.stdout) if result.stdout.strip() else None)
    print(f"PASS {expected['session_id']}: one exact guide input and one exact actor-owned NOTE")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
