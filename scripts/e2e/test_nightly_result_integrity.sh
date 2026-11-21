#!/usr/bin/env bash
# No network credentials, remote services, installs, or workflow dispatches.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
logs=${NIGHTLY_TEST_LOG_DIR:-$work/logs}
mkdir -p "$logs"
runner="$ROOT/scripts/e2e/run_logged.sh"
export CRYSTAL_WORKERS="${CRYSTAL_WORKERS:-2}"

expect_status() {
  local expected=$1 name=$2 seconds=$3
  shift 3
  local status=0
  bash "$runner" "$logs/$name.log" "$seconds" "$@" || status=$?
  if [[ $status -ne $expected ]]; then
    echo "FAIL $name: expected $expected, got $status" >&2
    exit 1
  fi
  grep -q "Command exit status: $expected" "$logs/$name.log"
  echo "PASS $name (expected exit $status)"
}

bash -n scripts/e2e/run_logged.sh scripts/e2e/test_nightly_result_integrity.sh
expect_status 0 stdout-stderr 5 bash -c 'echo stdout-marker; echo stderr-marker >&2; echo "owned-tmp=$TMPDIR"'
grep -q stdout-marker "$logs/stdout-stderr.log"
grep -q stderr-marker "$logs/stdout-stderr.log"
owned_tmp=$(sed -n 's/^owned-tmp=//p' "$logs/stdout-stderr.log")
[[ ! -e $owned_tmp ]]
echo "PASS runner temporary directory cleanup on success"

cat > "$work/compiler_failure.cr" <<'CR'
ThisNightlyConstantDoesNotExist.new
CR
cat > "$work/runtime_failure.cr" <<'CR'
STDOUT.puts "runtime stdout marker"
STDERR.puts "runtime stderr marker"
raise "deliberate runtime failure"
CR
expect_status 1 compiler-failure 60 crystal run --error-trace "$work/compiler_failure.cr"
grep -q 'undefined constant ThisNightlyConstantDoesNotExist' "$logs/compiler-failure.log"
expect_status 1 missing-source 60 crystal run "$work/missing.cr"
expect_status 1 runtime-failure 60 crystal run --error-trace "$work/runtime_failure.cr"
grep -q 'runtime stdout marker' "$logs/runtime-failure.log"
grep -q 'runtime stderr marker' "$logs/runtime-failure.log"
expect_status 124 timeout 1 bash -c 'echo "owned-tmp=$TMPDIR"; sleep 30 & child=$!; echo "owned-child=$child"; wait "$child"'
owned_tmp=$(sed -n 's/^owned-tmp=//p' "$logs/timeout.log")
[[ ! -e $owned_tmp ]]
child=$(sed -n 's/^owned-child=//p' "$logs/timeout.log")
python3 - "$child" <<'PY'
import pathlib, sys, time
path = pathlib.Path('/proc') / sys.argv[1] / 'stat'
for _ in range(50):
    if not path.exists() or path.read_text().split(') ', 1)[1].split()[0] == 'Z':
        print('PASS timeout terminated its owned descendant')
        break
    time.sleep(.02)
else:
    raise SystemExit('FAIL timeout left its owned descendant running')
PY
echo "PASS runner temporary directory cleanup on timeout"

# Build once, then run bounded negative fixtures against the actual scenarios.
expect_status 0 fixture-build 180 crystal build --error-trace scripts/e2e/fixtures/nightly_failure.cr -o "$work/nightly-failure"
for mode in sqlite-open open store reopen fetch mismatch http connection commands updates alert; do
  expect_status 1 "negative-$mode" 15 "$work/nightly-failure" "$mode"
done
for mode in open store reopen fetch mismatch; do
  grep -q 'Fixture verified storage cleanup' "$logs/negative-$mode.log"
done
grep -q 'Fixture verified real SQLite cleanup' "$logs/negative-sqlite-open.log"
grep -q 'SQLite open failed' "$logs/negative-sqlite-open.log"
grep -q 'SQLite open failed' "$logs/negative-open.log"
grep -q 'SQLite store failed' "$logs/negative-store.log"
grep -q 'SQLite reopen failed' "$logs/negative-reopen.log"
grep -q 'SQLite fetch failed' "$logs/negative-fetch.log"
grep -q 'SQLite round-trip mismatch' "$logs/negative-mismatch.log"
grep -q 'HTTP summary reports inactive monitoring' "$logs/negative-http.log"
grep -q 'Timed out waiting for summary and alerts command responses' "$logs/negative-commands.log"
grep -q 'Expected high_test_metric alert was not triggered' "$logs/negative-alert.log"
grep -q 'Timed out waiting for 10 test_metric updates' "$logs/negative-updates.log"
for mode in http connection commands updates alert; do
  grep -q 'Performance monitoring stopped' "$logs/negative-$mode.log"
  grep -q 'Performance dashboard stopped' "$logs/negative-$mode.log"
done
python3 scripts/e2e/test_nightly_workflow_contract.py
echo "Nightly result integrity regression checks passed"
