# Focused Nightly result-integrity checks

The Nightly persistence, monitoring, distributed benchmark and CogServer build
steps use `run_logged.sh LOG SECONDS COMMAND...`. The runner captures stdout and
stderr, preserves command/timeout failures (and logging failures), and uses GNU
`timeout` with a five-second kill grace period. It does not use `--foreground`:
the timeout owns the command's process group. Each invocation owns and removes
a temporary directory, including on failure or timeout. Existing `always()`
uploads retain the benchmark's `.txt` and the other steps' `.log` artifacts.
Missing benchmark source and compiler errors are required failures, not skips.

The SQLite scenario uses `SQLiteStorageNode`, checks `open`, every `store_atom`,
`close`/reopen, and `fetch_atom` for both concepts and the inheritance link. It
compares persisted content rather than newly generated in-memory handles, then
closes storage and deletes only its own temporary database and sidecars.

The WebSocket example uses a randomly assigned port and loopback client. It
asserts the HTTP endpoints/monitoring state, initial state, both command replies,
all ten test metric updates, statistics, and the named alert/notification. Reader
completion uses a buffered channel and a bounded `select`, not `Fiber#join`.
Monitoring and the dashboard are stopped in `ensure`. The existing monitor binds
all interfaces; this harness does not alter that production implementation.

The CogServer suite requires a successful build and an executable server binary.
Its load harness validates positive request/readiness limits, probes loopback
without proxies, waits only for request workers, and terminates/reaps its own
server on exit. Every POST must succeed at the HTTP layer and return `success`,
the submitted name and a positive numeric atom handle. The final summary must
report a running server and at least the requested number of nodes. Responses
must each contain exactly one JSON value; empty/multiple bodies are failures. These checks
are stronger than curl completion alone; they are not a durability or distributed
consistency test. The workflow retains a five-minute load-step bound.

## Local validation

With Crystal 1.20.1, native libraries and shards already available:

```bash
export CRYSTAL_WORKERS=2
bash scripts/e2e/run_logged.sh atomspace-persistence.log 300 \
  crystal run --error-trace scripts/e2e/atomspace_persistence_test.cr
bash scripts/e2e/run_logged.sh websocket-monitoring.log 180 \
  crystal run --error-trace examples/tests/test_websocket_monitoring.cr
bash scripts/e2e/run_logged.sh distributed-test-results.txt 600 \
  crystal run --release benchmarks/distributed_storage_benchmark.cr
bash scripts/e2e/run_logged.sh cogserver-build.log 600 \
  crystal build --verbose --stats --error-trace src/bin/cogserver.cr -o cogserver_bin
bash scripts/e2e/cogserver_load_test.sh ./cogserver_bin
NIGHTLY_TEST_LOG_DIR=/tmp/nightly-regression-logs \
  timeout 420 bash scripts/e2e/test_nightly_result_integrity.sh
python3 scripts/e2e/test_nightly_required_steps.py
bash scripts/e2e/test_e2e_harness.sh
```

These commands do not install dependencies or dispatch workflows. The Python
regressions require Python 3, PyYAML, curl and jq; the local HTTP fixtures need
port 18080 free. The required-gate regression fails before starting its fixtures
if that port already has a listener. `Validate Scripts` runs the shell/HTTP and
workflow regressions in a dedicated job, including on Nightly-workflow changes.

The result-integrity script exercises both output streams, an actual Crystal
compiler error, missing source, an actual runtime error, timeout/owned-child
cleanup, storage operation failures, a real SQLite open rejection, and failed
HTTP/WebSocket/command/update/alert outcomes. Expected negative cases are asserted,
not skipped. The workflow contract checks all four logged gates and artifact
paths, then executes the summary for success/skipped and each suite's
failure/cancelled result.

The required-gate script executes the owning distributed/build shell commands
with a stub compiler to check original exit statuses 0, 1 and 42 and diagnostic
visibility. It is not a Crystal compilation test. Its local CogServer fixtures
cover HTTP 400/500, malformed/rejected/wrong-name/invalid-handle atom outcomes,
failed/malformed/inactive/empty summaries, empty/multiple JSON bodies,
readiness failure, missing/nonexecutable
binaries, invalid limits and server cleanup. The separate no-bare-wait regression
requires a successful 20-request run to complete within its bound.

Passing local checks does not certify all five hosted Nightly suites or explain
the 24 historical benchmark failures whose diagnostics were unavailable. Inspect
the next naturally scheduled Nightly on the merged repair SHA for hosted
acceptance. No workflow dispatch or schedule change is part of this repair.
