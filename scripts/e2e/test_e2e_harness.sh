#!/usr/bin/env bash
# Regression checks for the Nightly E2E harness bugs in run 37721515049.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WF="${ROOT}/.github/workflows/nightly-e2e.yml"

if grep -q '/tmp/multi_node_test.cr' "$WF"; then
  echo "multi-node simulation must not be compiled from /tmp"
  exit 1
fi

if ! grep -q 'scripts/e2e/multi_node_simulation.cr' "$WF"; then
  echo "nightly workflow must run scripts/e2e/multi_node_simulation.cr"
  exit 1
fi

if ! grep -q 'scripts/e2e/cogserver_load_test.sh' "$WF"; then
  echo "nightly workflow must run scripts/e2e/cogserver_load_test.sh"
  exit 1
fi

if grep -E '^[[:space:]]*wait[[:space:]]*$' "$WF"; then
  echo "nightly workflow must not use a bare wait (it hangs on the server process)"
  exit 1
fi

if ! grep -q 'cancelled' "$WF"; then
  echo "E2E summary must treat cancelled jobs as failures"
  exit 1
fi

STUB="$(mktemp)"
WRAPPER="$(mktemp)"
cleanup_stub() {
  rm -f "$STUB" "$WRAPPER"
}
trap cleanup_stub EXIT

cat > "$STUB" << 'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._send(200, '{"status":"ok","running":true}')

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length:
            self.rfile.read(length)
        self._send(201, '{"success":true}')

    def log_message(self, fmt, *args):
        return

ThreadingHTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
PY

cat > "$WRAPPER" << EOF
#!/bin/sh
exec python3 "$STUB"
EOF
chmod +x "$WRAPPER"

echo "Checking CogServer load test returns without waiting on the server..."
start=$(date +%s)
set +e
output="$(COGSERVER_LOAD_REQUESTS=20 COGSERVER_READY_TIMEOUT=10 \
  timeout 25 bash "${ROOT}/scripts/e2e/cogserver_load_test.sh" "$WRAPPER")"
status=$?
set -e
printf '%s\n' "$output"
if [ "$status" -ne 0 ]; then
  echo "load test exited ${status}"
  exit 1
fi
if ! printf '%s\n' "$output" | grep -q 'CogServer load test completed'; then
  echo "load test did not complete (it may have skipped the server)"
  exit 1
fi
elapsed=$(( $(date +%s) - start ))
if [ "$elapsed" -gt 25 ]; then
  echo "load test took ${elapsed}s; bare wait hang may have returned"
  exit 1
fi
echo "load test finished in ${elapsed}s"
echo "E2E harness regression checks passed"
