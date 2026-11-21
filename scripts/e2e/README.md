# Focused Nightly result-integrity checks

The Nightly persistence and monitoring steps use `run_logged.sh LOG SECONDS COMMAND...`.
The runner captures stdout and stderr in a `.log`, preserves command/timeout failures
(and logging failures), and uses GNU `timeout` with a five-second kill grace period.
It does not use `--foreground`: the timeout owns the command's process group.
Each invocation owns and removes a temporary directory, including on failure or timeout.

The SQLite scenario uses `SQLiteStorageNode`, checks `open`, every `store_atom`,
`close`/reopen, and `fetch_atom` for both concepts and the inheritance link. It
compares persisted content rather than newly generated in-memory handles, then
closes storage and deletes only its own temporary database and sidecars.

The WebSocket example uses a randomly assigned port and loopback client. It
asserts the HTTP endpoints/monitoring state, initial state, both command replies,
all ten test metric updates, statistics, and the named alert/notification. Reader
completion uses a buffered channel and a bounded `select`, not `Fiber#join`.
Monitoring and the dashboard are stopped in `ensure`. The existing monitor binds
all interfaces; this change does not alter that production implementation.

## Local validation

With Crystal 1.20.1, native libraries and shards already available (no installation
or downloads are performed by these commands):

```bash
export CRYSTAL_WORKERS=2
bash scripts/e2e/run_logged.sh atomspace-persistence.log 300 \
  crystal run --error-trace scripts/e2e/atomspace_persistence_test.cr
bash scripts/e2e/run_logged.sh websocket-monitoring.log 180 \
  crystal run --error-trace examples/tests/test_websocket_monitoring.cr
NIGHTLY_TEST_LOG_DIR=/tmp/nightly-regression-logs \
  timeout 420 bash scripts/e2e/test_nightly_result_integrity.sh
```

The regression script requires Python 3 and PyYAML. It exercises stdout/stderr
capture, an actual Crystal compiler error, missing source, an actual Crystal runtime
error, timeout/owned-child cleanup, storage operation failures, a real SQLite open
rejection, and failed HTTP/WebSocket/command/update/alert outcomes. Expected
negative cases return nonzero and are asserted by the script; they are not skipped.
The workflow contract checks the two owning steps and existing log upload paths,
then executes the unchanged summary for success/skipped and each required job's
failure/cancelled result. It does not run GitHub Actions or access credentials.

This validates only these two repaired scenarios and their result contracts. It
is not certification of all five Nightly suites or a shared explanation of historical
alerts. The next naturally scheduled Nightly run on the merged revision still needs
inspection; no workflow dispatch is part of this repair.
