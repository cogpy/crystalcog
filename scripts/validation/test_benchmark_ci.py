#!/usr/bin/env python3
"""Regression tests for the scheduled AtomSpace benchmark workflow.

Install the test dependency with: python3 -m pip install PyYAML==6.0.3
Run fixtures with: python3 scripts/validation/test_benchmark_ci.py
Run the workflow's real benchmark (requires Crystal, shards and native libraries)
with: python3 scripts/validation/test_benchmark_ci.py --run-benchmark
"""

import argparse
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/crystal-comprehensive-ci.yml"


def load_workflow():
    return yaml.safe_load(WORKFLOW.read_text())


def step_named(workflow, job, name):
    return next(step for step in workflow["jobs"][job]["steps"]
                if step.get("name") == name)


def run_block(workflow, block, cwd, env=None, capture=True):
    """Use the workflow's own shell, including its errexit/pipefail behavior."""
    shell = workflow["defaults"]["run"]["shell"]
    with tempfile.NamedTemporaryFile(mode="w", suffix=".sh") as script:
        script.write(block)
        script.flush()
        command = [part.replace("{0}", script.name) for part in shlex.split(shell)]
        return subprocess.run(command, cwd=cwd, env=env, text=True,
                              stdout=subprocess.PIPE if capture else None,
                              stderr=subprocess.STDOUT)


class BenchmarkCIRegression(unittest.TestCase):
    def setUp(self):
        self.workflow = load_workflow()
        self.benchmark = self.workflow["jobs"]["benchmarks"]
        self.run_step = step_named(self.workflow, "benchmarks", "Run benchmarks")
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        (self.root / "benchmarks").mkdir()
        (self.root / "benchmarks/atomspace_benchmark.cr").touch()
        tools = self.root / "tools"
        tools.mkdir()
        crystal = tools / "crystal"
        crystal.write_text(
            '#!/usr/bin/env bash\n'
            'printf "%s\\n" "$*" > "$CRYSTAL_CALL_LOG"\n'
            'printf "%s\\n" "${FAKE_CRYSTAL_STDOUT:-benchmark completed}"\n'
            'printf "%s\\n" "${FAKE_CRYSTAL_STDERR:-}" >&2\n'
            'exit "${FAKE_CRYSTAL_STATUS:-0}"\n'
        )
        crystal.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                        CRYSTAL_CALL_LOG=str(self.root / "crystal-call.txt"),
                        FAKE_CRYSTAL_STATUS="0", FAKE_CRYSTAL_STDOUT="benchmark completed",
                        FAKE_CRYSTAL_STDERR="")

    def run_benchmark(self, **overrides):
        return run_block(self.workflow, self.run_step["run"], self.root,
                         dict(self.env, **overrides))

    def test_success_runs_release_benchmark_and_saves_output(self):
        result = self.run_benchmark(FAKE_CRYSTAL_STDERR="runtime diagnostic")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.root / "crystal-call.txt").read_text().strip(),
                         "run --release benchmarks/atomspace_benchmark.cr")
        log = (self.root / "benchmark-results.txt").read_text()
        for message in ("benchmark completed", "runtime diagnostic"):
            self.assertIn(message, log)
            self.assertIn(message, result.stdout)

    def test_linker_failure_is_red_and_keeps_diagnostics(self):
        diagnostic = "/usr/bin/ld: cannot find -lrocksdb: No such file or directory"
        result = self.run_benchmark(FAKE_CRYSTAL_STATUS="1", FAKE_CRYSTAL_STDERR=diagnostic)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(diagnostic, result.stdout)
        self.assertIn(diagnostic, (self.root / "benchmark-results.txt").read_text())

    def test_nonzero_compiler_or_runtime_status_is_propagated(self):
        for status in (42, 130):
            with self.subTest(status=status):
                result = self.run_benchmark(FAKE_CRYSTAL_STATUS=str(status))
                self.assertEqual(result.returncode, status, result.stdout)

    def test_missing_input_fails_without_reusing_stale_results(self):
        (self.root / "benchmarks/atomspace_benchmark.cr").unlink()
        (self.root / "benchmark-results.txt").write_text("stale successful result")
        result = self.run_benchmark()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.root / "crystal-call.txt").exists())
        log = (self.root / "benchmark-results.txt").read_text()
        self.assertIn("Missing benchmarks/atomspace_benchmark.cr", log)
        self.assertNotIn("stale successful result", log)

    def test_output_write_failure_is_not_success(self):
        (self.root / "benchmark-results.txt").mkdir()
        result = self.run_benchmark()
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_tee_failure_is_not_success(self):
        tee = self.root / "tools/tee"
        tee.write_text("#!/usr/bin/env bash\ncat >/dev/null\nexit 17\n")
        tee.chmod(0o755)
        result = self.run_benchmark()
        self.assertEqual(result.returncode, 17, result.stdout)

    def test_native_libraries_are_installed_in_the_benchmark_job(self):
        steps = self.benchmark["steps"]
        install = step_named(self.workflow, "benchmarks", "Install benchmark system dependencies")
        for library in ("librocksdb-dev", "libsqlite3-dev", "libpq-dev", "libyaml-dev"):
            self.assertIn(library, shlex.split(install["run"]))
        self.assertLess(steps.index(install), steps.index(
            step_named(self.workflow, "benchmarks", "Install dependencies")))
        self.assertNotIn("DISABLE_ROCKSDB", self.benchmark.get("env", {}))

    def test_failed_benchmarks_still_upload_results_without_tolerating_errors(self):
        upload = step_named(self.workflow, "benchmarks", "Upload benchmark results")
        self.assertEqual(upload["if"], "always()")
        self.assertEqual(upload["with"]["path"], "benchmark-results.txt")
        self.assertFalse(self.benchmark.get("continue-on-error", False))
        self.assertFalse(self.run_step.get("continue-on-error", False))

    def run_summary(self, benchmark, core="success"):
        summary = step_named(self.workflow, "ci-status", "Check overall status")["run"]
        results = {"test-matrix": core, "benchmarks": benchmark,
                   "coverage": "skipped", "security": "success"}
        summary = re.sub(r"\$\{\{\s*needs\.([\w-]+)\.result\s*\}\}",
                         lambda match: results[match.group(1)], summary)
        return run_block(self.workflow, summary, self.root)

    def test_summary_accepts_successful_or_intentionally_skipped_benchmarks(self):
        for status in ("success", "skipped"):
            with self.subTest(status=status):
                result = self.run_summary(status)
                self.assertEqual(result.returncode, 0, result.stdout)

    def test_summary_rejects_failed_cancelled_or_unknown_benchmarks(self):
        for status in ("failure", "cancelled", "unknown"):
            with self.subTest(status=status):
                result = self.run_summary(status)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertNotIn("Pipeline completed successfully!", result.stdout)

    def test_summary_still_rejects_unsuccessful_core_tests(self):
        for status in ("failure", "cancelled", "skipped"):
            with self.subTest(status=status):
                result = self.run_summary("success", core=status)
                self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_workflow_shell_blocks_have_valid_bash_syntax(self):
        for job, name in (("benchmarks", "Install benchmark system dependencies"),
                          ("benchmarks", "Create benchmark script"),
                          ("benchmarks", "Run benchmarks"),
                          ("ci-status", "Check overall status")):
            with self.subTest(step=name):
                block = step_named(self.workflow, job, name)["run"]
                result = subprocess.run(["bash", "-n"], input=block, text=True,
                                        capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)


def main():
    global WORKFLOW
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workflow", type=Path, default=WORKFLOW,
                        help="Workflow under test (also useful for checking historical regressions)")
    parser.add_argument("--run-benchmark", action="store_true",
                        help="Execute the workflow's actual benchmark generation and release run")
    args = parser.parse_args()
    WORKFLOW = args.workflow
    if args.run_benchmark:
        workflow = load_workflow()
        for name in ("Create benchmark script", "Run benchmarks"):
            print(f"Executing workflow step: {name}", flush=True)
            block = step_named(workflow, "benchmarks", name)["run"]
            result = run_block(workflow, block, ROOT, capture=False)
            if result.returncode:
                raise SystemExit(result.returncode)
    else:
        unittest.main(argv=[__file__], verbosity=2)


if __name__ == "__main__":
    main()
