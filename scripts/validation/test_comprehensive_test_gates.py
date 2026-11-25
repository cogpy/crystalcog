#!/usr/bin/env python3
"""Regression tests for fail-closed Comprehensive Unit & Integration Tests.

Install the test dependency with: python3 -m pip install PyYAML==6.0.2
Run with: python3 scripts/validation/test_comprehensive_test_gates.py

A stub `crystal` executable returns controlled statuses, so these tests check
the workflow's shell/status wiring. They do not compile or run Crystal specs.
"""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/comprehensive-tests.yml"
SPEC_LINE = re.compile(r"^\s*crystal spec\b.*$", re.M)

STUB = r'''#!/usr/bin/env python3
import os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["STUB_RECORD"], "a") as record:
    record.write(" ".join(args) + "\n")
if args and args[0] == "build":
    source = args[[a.startswith("src/") for a in args].index(True)]
    if os.environ.get("STUB_FAIL_SOURCE") == source:
        print("Error: stub compile failure for " + source, file=sys.stderr)
        sys.exit(1)
    output = Path(args[args.index("-o") + 1])
    output.write_text("#!/bin/sh\n")
    output.chmod(0o755)
    sys.exit(0)
status = int(os.environ.get("STUB_STATUS", "0"))
for arg in args:
    if arg.startswith("--junit_output="):
        Path(arg.split("=", 1)[1]).write_text(
            '<testsuites tests="7" failures="%d" errors="0">'
            '<testsuite tests="7" failures="%d" errors="0"/></testsuites>'
            % (int(status != 0), int(status != 0)))
print("stub spec stdout marker")
print("stub spec stderr marker", file=sys.stderr)
print("Finished in 0.01 seconds")
print("7 examples, %d failures, 0 errors, 0 pending" % int(status != 0))
sys.exit(status)
'''


def load_workflow():
    return yaml.safe_load(WORKFLOW.read_text())
REQUIRED_SPEC_TARGETS = [
    "spec/cogutil/", "spec/atomspace/", "spec/pln/", "spec/ure/", "spec/opencog/",
    "spec/moses/", "spec/attention/", "spec/nlp/", "spec/pattern_matching/",
    "spec/pattern_mining/", "spec/cogserver/", "spec/agent-zero/", "spec/spatial/",
    "spec/temporal/", "spec/behavior/", "spec/performance/",
    "spec/integration/", "spec/crystalcog_spec.cr", "spec/spec_helper.cr",
]
RUN_AFTER_EARLIER_FAILURE = "${{ !cancelled() }}"
def spec_target(step):
    lines = SPEC_LINE.findall(step["run"])
    assert len(lines) == 1, (step.get("name"), lines)
    targets = [arg for arg in shlex.split(lines[0]) if arg.startswith("spec/")]
    assert len(targets) == 1, (step.get("name"), targets)
    return targets[0]


class ComprehensiveTestGates(unittest.TestCase):
    def setUp(self):
        self.workflow = load_workflow()
        self.jobs = self.workflow["jobs"]
        self.shell = self.workflow["defaults"]["run"]["shell"]
        self.tmp = tempfile.TemporaryDirectory(prefix="comprehensive-gates-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        tools = self.root / "tools"
        tools.mkdir()
        crystal = tools / "crystal"
        crystal.write_text(STUB)
        crystal.chmod(0o755)
        self.record = self.root / "crystal-calls.txt"
        self.summary = self.root / "step-summary.md"
        self.env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                        STUB_RECORD=str(self.record), GITHUB_STEP_SUMMARY=str(self.summary))

    def run_block(self, block, cwd=None, **env):
        self.record.unlink(missing_ok=True)
        with tempfile.NamedTemporaryFile("w", suffix=".sh", dir=self.root, delete=False) as script:
            script.write(block)
        command = [part.replace("{0}", script.name) for part in shlex.split(self.shell)]
        return subprocess.run(command, cwd=cwd or self.root, env=dict(self.env, **env), text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)

    def spec_steps(self, job):
        return [s for s in self.jobs[job]["steps"] if "crystal spec" in s.get("run", "")]

    def test_shell_enables_errexit_and_pipefail(self):
        self.assertEqual(shlex.split(self.shell), ["bash", "-ex", "-o", "pipefail", "{0}"])

    def test_no_spec_command_masks_its_status(self):
        lines = [line for job in self.jobs.values() for step in job.get("steps", [])
                 for line in SPEC_LINE.findall(step.get("run", ""))]
        self.assertEqual(len(lines), 21)  # matrix + full + 16 components + 3 integration
        for line in lines:
            self.assertNotRegex(line, r"\|\||;\s*true|continue-on-error", line)
        for job in self.jobs.values():
            for step in job.get("steps", []):
                self.assertFalse(step.get("continue-on-error", False), step.get("name"))

    def test_component_and_integration_steps_propagate_status(self):
        steps = self.spec_steps("component-tests") + self.spec_steps("integration-tests")
        self.assertEqual(len(steps), 19)
        for step in steps:
            target = spec_target(step)
            for status in (0, 1, 42):
                with self.subTest(step=step["name"], status=status):
                    result = self.run_block(step["run"], STUB_STATUS=str(status))
                    self.assertEqual(result.returncode, status, result.stdout)
                    recorded = [shlex.split(line) for line in self.record.read_text().splitlines()]
                    self.assertEqual(len(recorded), 1, recorded)
                    self.assertEqual([a for a in recorded[0] if a.startswith("spec/")], [target])
                    self.assertIn("stub spec stderr marker", result.stdout)
                    self.assertNotIn("tests completed", result.stdout.replace("echo", ""))

    def test_required_suites_are_present_and_not_skippable(self):
        steps = self.spec_steps("component-tests") + self.spec_steps("integration-tests")
        self.assertEqual([spec_target(s) for s in steps], REQUIRED_SPEC_TARGETS)
        for job in ("component-tests", "integration-tests", "full-test-suite"):
            self.assertNotIn("if", self.jobs[job], job)
        for step in steps:
            with self.subTest(step=step["name"]):
                # Later suites still run after an earlier suite fails, so every
                # failure is reported; the failed step still fails the job.
                self.assertEqual(step.get("if"), RUN_AFTER_EARLIER_FAILURE)
                self.assertFalse(step.get("continue-on-error", False))
        full = self.full_suite_step()
        self.assertNotIn("if", full)
    def full_suite_step(self):
        return next(s for s in self.jobs["full-test-suite"]["steps"] if s.get("name") == "Run full test suite")

    def test_full_suite_returns_spec_status_and_keeps_summary(self):
        for status in (0, 1, 42):
            with self.subTest(status=status):
                for name in ("test-output.log", "test-summary.txt", "test-results.xml"):
                    (self.root / name).unlink(missing_ok=True)
                result = self.run_block(self.full_suite_step()["run"], STUB_STATUS=str(status))
                self.assertEqual(result.returncode, status, result.stdout)
                log = (self.root / "test-output.log").read_text()
                self.assertIn("stub spec stdout marker", log)
                self.assertIn("stub spec stderr marker", log)
                summary = (self.root / "test-summary.txt").read_text()
                self.assertIn("7 examples, %d failures" % int(status != 0), summary)
                self.assertIn("crystal spec exit status: %d" % status, summary)
                if status:
                    self.assertIn("::error::Full test suite failed with exit status %d" % status, result.stdout)

    def test_full_suite_fails_when_log_cannot_be_written(self):
        (self.root / "test-output.log").unlink(missing_ok=True)
        (self.root / "test-output.log").mkdir()
        result = self.run_block(self.full_suite_step()["run"], STUB_STATUS="0")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Could not write test-output.log", result.stdout)

    def test_junit_counts_are_single_values_under_pipefail(self):
        step = next(s for s in self.jobs["full-test-suite"]["steps"] if s.get("name") == "Parse test results")
        (self.root / "test-results.xml").write_text(
            '<testsuites tests="7" failures="0" errors="0">' + '<testsuite tests="3" failures="0" errors="0"/>' * 5000 + '</testsuites>')
        self.summary.unlink(missing_ok=True)
        result = self.run_block(step["run"])
        self.assertEqual(result.returncode, 0, result.stdout)
        text = self.summary.read_text()
        self.assertIn("| Tests | 7 |\n| Failures | 0 |\n| Errors | 0 |", text)
        self.assertNotIn("N/A", text)
        (self.root / "test-results.xml").write_text(
            '<?xml version="1.0"?>\n<testsuites name="x" tests="12" failures="2" errors="1">\n<testsuite tests="12"/>\n</testsuites>\n')
        self.summary.unlink()
        self.assertEqual(self.run_block(step["run"]).returncode, 0)
        self.assertIn("| Tests | 12 |\n| Failures | 2 |\n| Errors | 1 |", self.summary.read_text())
        (self.root / "test-results.xml").write_text("<testsuites/>")
        self.summary.unlink()
        self.assertEqual(self.run_block(step["run"]).returncode, 0)
        self.assertIn("| Tests | N/A |", self.summary.read_text())

    def build_step(self):
        return next(s for s in self.jobs["binary-build-test"]["steps"] if s.get("name") == "Build all binaries")

    def make_sources(self, skip=None):
        sources = re.findall(r'\]="(src/[^"]+)"', self.build_step()["run"])
        self.assertEqual(len(sources), 23)
        for source in sources:
            if source != skip:
                path = self.root / source
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
        return sources

    def test_binary_build_succeeds_only_when_every_target_builds(self):
        sources = self.make_sources()
        result = self.run_block(self.build_step()["run"])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Successful: 23", result.stdout)
        self.assertEqual(len(self.record.read_text().splitlines()), 23)
        failed = self.run_block(self.build_step()["run"], STUB_FAIL_SOURCE="src/bin/cogserver.cr")
        self.assertEqual(failed.returncode, 1, failed.stdout)
        self.assertIn("1 binary target(s) failed", failed.stdout)
        self.assertIn("stub compile failure for src/bin/cogserver.cr", failed.stdout)
        self.assertIn("src/pln/pln.cr", sources)

    def test_binary_build_fails_for_missing_source(self):
        shutil_root = self.root / "src"
        if shutil_root.exists():
            subprocess.run(["rm", "-rf", str(shutil_root)], check=True)
        self.make_sources(skip="src/spatial/spatial.cr")
        result = self.run_block(self.build_step()["run"])
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("Source file src/spatial/spatial.cr not found", result.stdout)

    def test_aggregate_status_requires_every_job_success(self):
        block = self.jobs["test-status"]["steps"][0]["run"]
        needs = self.jobs["test-status"]["needs"]
        self.assertEqual(needs, ["version-matrix", "component-tests", "full-test-suite",
                                 "integration-tests", "binary-build-test"])

        def render(values):
            return re.sub(r"\$\{\{\s*needs\.([a-z-]+)\.result\s*\}\}", lambda m: values[m.group(1)], block)

        ok = {name: "success" for name in needs}
        self.summary.unlink(missing_ok=True)
        self.assertEqual(self.run_block(render(ok)).returncode, 0)
        self.assertIn("All tests passed", self.summary.read_text())
        for name in needs:
            for outcome in ("failure", "skipped", "cancelled"):
                with self.subTest(job=name, outcome=outcome):
                    self.summary.unlink(missing_ok=True)
                    result = self.run_block(render(dict(ok, **{name: outcome})))
                    self.assertEqual(result.returncode, 1, result.stdout)
                    self.assertIn("Tests require attention", self.summary.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
