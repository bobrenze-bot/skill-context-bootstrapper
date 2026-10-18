"""Regression tests using only temporary, synthetic workspaces."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "bootstrap.sh"


class QueueCountsTest(unittest.TestCase):
    def test_queue_counts(self):
        cases = {
            "missing": None,
            "empty": [],
            "pending_only": ["pending", "pending"],
            "blocked_only": ["blocked"],
            "completed_only": ["completed", "completed"],
            "mixed": ["pending", "blocked", "completed", "completed"],
        }
        for label, statuses in cases.items():
            for mode in ("json", "terminal"):
                with self.subTest(queue=label, mode=mode):
                    with tempfile.TemporaryDirectory(prefix="bootstrap-test-") as tmp:
                        workspace = Path(tmp)
                        env = dict(os.environ, WORKSPACE=tmp, HOME=tmp,
                                   GIT_CONFIG_NOSYSTEM="1", LC_ALL="C")
                        subprocess.run(["git", "init", "-q", tmp], env=env, check=True)
                        if statuses is not None:
                            lines = ["tasks:"]
                            for number, status in enumerate(statuses, 1):
                                lines.extend([
                                    f"  - id: {number}",
                                    f"    status: {status}",
                                    "    priority: high",
                                    f'    task: "Fixture task {number}"',
                                ])
                            (workspace / "autonomous-queue.yaml").write_text(
                                "\n".join(lines) + "\n"
                            )
                        args = ["bash", str(SCRIPT)]
                        if mode == "json":
                            args.append("--json")
                        result = subprocess.run(
                            args, cwd=tmp, env=env, capture_output=True,
                            text=True, timeout=10,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stderr, "")
                        expected = {
                            status: (statuses or []).count(status)
                            for status in ("pending", "blocked", "completed")
                        }
                        if mode == "json":
                            data = json.loads(result.stdout)
                            for status, count in expected.items():
                                self.assertIs(type(data["queue"][status]), int)
                                self.assertEqual(data["queue"][status], count)
                            self.assertEqual(data["stats"]["total_completed"],
                                             expected["completed"])
                        else:
                            plain = re.sub(r"\x1b\[[0-9;]*m", "", result.stdout)
                            for status, count in expected.items():
                                self.assertRegex(
                                    plain, rf"{status.title()}:\s+{count}\b"
                                )
                            self.assertRegex(
                                plain, rf"Total: {expected['completed']} tasks"
                            )


if __name__ == "__main__":
    unittest.main()
