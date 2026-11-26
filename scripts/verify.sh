#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

install_dependencies() {
  shards install --frozen
  shards check
}

check_format() {
  local base="${FORMAT_BASE:-HEAD}"
  local files
  mapfile -t files < <(git diff --name-only --diff-filter=ACMR "$base" -- '*.cr')
  if [[ ${#files[@]} -eq 0 ]] && git rev-parse "${base}^" >/dev/null 2>&1; then
    mapfile -t files < <(git diff --name-only --diff-filter=ACMR "${base}^" "$base" -- '*.cr')
  fi
  if [[ ${#files[@]} -gt 0 ]]; then
    crystal tool format --check "${files[@]}"
  fi
}

build_all() {
  mkdir -p bin
  crystal build --no-codegen src/atomspace/atomspace_core.cr
  shards build --verbose --error-trace
}

test_all() {
  crystal spec --stats -v --error-trace --no-color \
    ${JUNIT_OUTPUT:+--junit_output="$JUNIT_OUTPUT"}
}

smoke_all() {
  BIN_DIR=bin ./scripts/ci-smoke.sh
}

case "${1:-all}" in
  deps)
    install_dependencies
    ;;
  format)
    check_format
    ;;
  build)
    install_dependencies
    build_all
    ;;
  test)
    install_dependencies
    test_all
    ;;
  smoke)
    smoke_all
    ;;
  all)
    install_dependencies
    check_format
    build_all
    test_all
    smoke_all
    ;;
  *)
    echo "Usage: $0 [all|deps|format|build|test|smoke]" >&2
    exit 2
    ;;
esac
