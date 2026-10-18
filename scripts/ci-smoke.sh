#!/usr/bin/env bash
set -euo pipefail
# Trace every command and print every response so CI logs show what ran.
set -x
cd "$(dirname "$0")/.."

bin_dir="${BIN_DIR:-bin}"
"$bin_dir/crystalcog" test | grep 'AtomSpace size: 3'
printf 'add smoke concept\nstats\nquit\n' | "$bin_dir/cogshell" | grep 'Atoms: 1, nodes: 1, links: 0'

http_port="${SMOKE_HTTP_PORT:-18080}"
telnet_port="${SMOKE_TELNET_PORT:-17001}"
base="http://127.0.0.1:$http_port"
"$bin_dir/cogserver" --host 127.0.0.1 --port "$telnet_port" --ws-port "$http_port" > cogserver-smoke.log 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
ready=false
for _ in $(seq 1 30); do
  if ! kill -0 "$pid" 2>/dev/null; then
    cat cogserver-smoke.log
    echo 'CogServer exited before becoming ready' >&2
    exit 1
  fi
  if curl --fail --silent --show-error --max-time 2 "$base/status"; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  cat cogserver-smoke.log
  echo 'CogServer readiness timeout' >&2
  exit 1
fi
curl --fail --silent --show-error --max-time 5 "$base/status" | jq -e '.running == true'
curl --fail --silent --show-error --max-time 5 -H 'Content-Type: application/json' \
  -d '{"type":"CONCEPT_NODE","name":"ci_smoke"}' "$base/atoms" | jq -e '.success == true and .atom.handle > 0'
curl --fail --silent --show-error --max-time 5 "$base/atoms" | jq -e '.count >= 1 and any(.atoms[]; .name == "ci_smoke")'
curl --fail --silent --show-error --max-time 5 "$base/atomspace" | jq -e '.size >= 1 and (.atoms | length) >= 1'
printf 'Compiled CLI, shell, and CogServer HTTP smoke checks passed.\n'
