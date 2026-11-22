#!/usr/bin/env bash
# Nightly CogServer load test. Wait only for request workers, never the server.
set -euo pipefail

REQUESTS="${COGSERVER_LOAD_REQUESTS:-100}"
READY_TIMEOUT="${COGSERVER_READY_TIMEOUT:-30}"
if [[ ! $REQUESTS =~ ^[1-9][0-9]*$ || ! $READY_TIMEOUT =~ ^[1-9][0-9]*$ ]]; then
  echo "Load requests and readiness timeout must be positive integers" >&2
  exit 2
fi
if [[ $# -lt 1 || ! -f $1 || ! -x $1 ]]; then
  echo "Required CogServer binary is missing or not executable" >&2
  exit 1
fi

COGSERVER_PID=""
cleanup() {
  if [[ -n $COGSERVER_PID ]]; then
    if kill -0 "$COGSERVER_PID" 2>/dev/null; then
      kill "$COGSERVER_PID" 2>/dev/null || true
      for _ in 1 2 3 4 5; do
        kill -0 "$COGSERVER_PID" 2>/dev/null || break
        sleep 1
      done
      kill -9 "$COGSERVER_PID" 2>/dev/null || true
    fi
    wait "$COGSERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Starting CogServer..."
"$@" &
COGSERVER_PID=$!

echo "Waiting for CogServer to accept connections..."
BASE_URL=""
ready_attempt=0
while [[ $ready_attempt -lt $READY_TIMEOUT ]]; do
  ready_attempt=$((ready_attempt + 1))
  if ! kill -0 "$COGSERVER_PID" 2>/dev/null; then
    echo "CogServer exited before becoming ready" >&2
    exit 1
  fi
  # CI binds localhost to [::1]. Probe IPv6 and IPv4 without using proxies.
  for candidate in "http://[::1]:18080" "http://127.0.0.1:18080" "http://localhost:18080"; do
    if curl --noproxy '*' -sf --max-time 2 "${candidate}/ping" >/dev/null 2>&1; then
      BASE_URL="$candidate"
      break
    fi
  done
  if [[ -n $BASE_URL ]]; then
    echo "CogServer ready at ${BASE_URL}"
    break
  fi
  sleep 1
done
if [[ -z $BASE_URL ]]; then
  echo "CogServer did not become ready within ${READY_TIMEOUT}s" >&2
  exit 1
fi

create_atom() {
  local name="load_test_$1" response
  if ! response=$(curl --noproxy '*' -fsS --max-time 5 -X POST \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"ConceptNode\",\"name\":\"$name\"}" "${BASE_URL}/atom"); then
    echo "Load request $1 failed HTTP/transport validation" >&2
    return 1
  fi
  if ! jq -es --arg name "$name" \
    'length == 1 and (.[0] | .success == true and .atom.name == $name and (.atom.handle | type == "number" and . > 0))' \
    <<< "$response" >/dev/null; then
    echo "Load request $1 returned an invalid atom outcome: $response" >&2
    return 1
  fi
}

echo "Running load test..."
pids=()
for ((request = 1; request <= REQUESTS; request++)); do
  create_atom "$request" &
  pids+=("$!")
done
# Wait only for request workers, never for the long-running server.
fail=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    fail=1
  fi
done
if [[ $fail -ne 0 ]]; then
  echo "One or more load-test requests failed" >&2
  exit 1
fi
if ! kill -0 "$COGSERVER_PID" 2>/dev/null; then
  echo "CogServer exited during load testing" >&2
  exit 1
fi

echo "Summary:"
if ! summary=$(curl --noproxy '*' -fsS --max-time 5 "${BASE_URL}/summary"); then
  echo "Failed to read CogServer summary" >&2
  exit 1
fi
if ! jq -es --argjson requests "$REQUESTS" \
  'length == 1 and (.[0] | .running == true and (.atomspace.nodes | type == "number" and . >= $requests))' \
  <<< "$summary" >/dev/null; then
  echo "CogServer summary does not confirm the required running/node outcomes: $summary" >&2
  exit 1
fi
jq . <<< "$summary"
echo "Validated $REQUESTS successful atom outcomes"
echo "✓ CogServer load test completed"
