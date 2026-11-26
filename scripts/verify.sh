#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

install_dependencies() {
  shards install --frozen
  shards check
}

check_format() {
  local base="${FORMAT_BASE:-}"
  local list
  local files=()
  list="$(mktemp)"
  trap 'rm -f "$list"' RETURN

  if [[ "$base" =~ ^0+$ ]]; then
    git ls-files -z -- '*.cr' >"$list"
  elif [[ -n "$base" ]]; then
    git rev-parse --verify "${base}^{commit}" >/dev/null
    git diff --name-only -z --diff-filter=ACMR "$base" HEAD -- '*.cr' >"$list"
  else
    git diff --name-only -z --diff-filter=ACMR HEAD -- '*.cr' >"$list"
    if [[ ! -s "$list" ]] && git rev-parse --verify "HEAD^" >/dev/null 2>&1; then
      git diff --name-only -z --diff-filter=ACMR "HEAD^" HEAD -- '*.cr' >"$list"
    fi
  fi

  git ls-files --others --exclude-standard -z -- '*.cr' >>"$list"
  mapfile -d '' -t files <"$list"
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
