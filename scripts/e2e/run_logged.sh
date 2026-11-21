#!/usr/bin/env bash
# Usage: bash scripts/e2e/run_logged.sh LOG SECONDS COMMAND [ARG...]
# GNU timeout owns the command process group; never use --foreground here.
set -euo pipefail

if [[ $# -lt 3 || ! $2 =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 LOG POSITIVE_SECONDS COMMAND [ARG...]" >&2
  exit 2
fi
log=$1
seconds=$2
shift 2
mkdir -p "$(dirname "$log")"
# Isolate temporary databases/compiler files, including on timeout/failure.
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export TMPDIR="$work"
export CRYSTAL_WORKERS="${CRYSTAL_WORKERS:-2}"

set +e
{
  printf 'Running (timeout %ss):' "$seconds"
  printf ' %q' "$@"
  printf '\n'
  timeout --kill-after=5s "${seconds}s" "$@"
} 2>&1 | tee "$log"
statuses=("${PIPESTATUS[@]}")
set -e
status=${statuses[0]}
if [[ ${statuses[1]} -ne 0 && $status -eq 0 ]]; then
  status=${statuses[1]}
fi
printf 'Command exit status: %s\n' "$status" | tee -a "$log"
exit "$status"
