#!/usr/bin/env bash
# Nightly CogServer load test.
#
# A bare `wait` also waits for the server process, which runs until killed.
# That hung the Nightly E2E CogServer job until the 30-minute timeout
# (actions run 37721515049). Wait only for the request workers.
set -u

REQUESTS="${COGSERVER_LOAD_REQUESTS:-100}"
READY_TIMEOUT="${COGSERVER_READY_TIMEOUT:-30}"

if [ "$#" -lt 1 ] || [ ! -e "$1" ]; then
  echo "CogServer binary not available, skipping load test"
  exit 0
fi

COGSERVER_PID=""
cleanup() {
  if [ -n "${COGSERVER_PID}" ] && kill -0 "${COGSERVER_PID}" 2>/dev/null; then
    kill "${COGSERVER_PID}" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "${COGSERVER_PID}" 2>/dev/null || return 0
      sleep 1
    done
    kill -9 "${COGSERVER_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "Starting CogServer..."
"$@" &
COGSERVER_PID=$!

echo "Waiting for CogServer to accept connections..."
BASE_URL=""
ready_attempt=0
while [ "$ready_attempt" -lt "$READY_TIMEOUT" ]; do
  ready_attempt=$((ready_attempt + 1))
  if ! kill -0 "${COGSERVER_PID}" 2>/dev/null; then
    echo "CogServer exited before becoming ready"
    exit 1
  fi
  # CI binds the HTTP API to [::1] when host is localhost. Probe IPv6 and IPv4.
  for candidate in "http://[::1]:18080" "http://127.0.0.1:18080" "http://localhost:18080"; do
    if curl -sf --max-time 2 "${candidate}/ping" >/dev/null 2>&1; then
      BASE_URL="$candidate"
      break
    fi
  done
  if [ -n "$BASE_URL" ]; then
    echo "CogServer ready at ${BASE_URL}"
    break
  fi
  sleep 1
done

if [ -z "$BASE_URL" ]; then
  echo "CogServer did not become ready within ${READY_TIMEOUT}s"
  exit 1
fi

echo "Running load test..."
pids=()
request=1
while [ "$request" -le "$REQUESTS" ]; do
  curl -s --max-time 5 -o /dev/null -X POST \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"ConceptNode\",\"name\":\"load_test_${request}\"}" \
    "${BASE_URL}/atom" &
  pids+=("$!")
  request=$((request + 1))
done

# Wait only for request workers, never for the long-running server.
fail=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    fail=1
  fi
done

echo "Summary:"
if ! curl -sf --max-time 5 "${BASE_URL}/summary" | jq .; then
  echo "Failed to read CogServer summary"
  exit 1
fi

if [ "$fail" -ne 0 ]; then
  echo "One or more load-test requests failed"
  exit 1
fi

echo "✓ CogServer load test completed"
