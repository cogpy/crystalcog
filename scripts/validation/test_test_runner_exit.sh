#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/spec"
touch "$tmp/shard.yml" "$tmp/spec/a_spec.cr" "$tmp/spec/b_spec.cr" "$tmp/spec/fail_spec.cr"
cat > "$tmp/bin/crystal" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == version ]]; then echo 'Crystal test fixture'; exit 0; fi
if [[ "$*" == *fail_spec.cr* ]]; then exit 1; fi
exit 0
EOF
cat > "$tmp/bin/shards" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/bin/"*
cd "$tmp"
if PATH="$tmp/bin:$PATH" bash "$repo/scripts/test-runner.sh" > result.log 2>&1; then
  cat result.log
  echo 'Runner incorrectly accepted a failing spec' >&2
  exit 1
fi
grep -q '2 passed, 1 failed' result.log
grep -q 'One or more spec files failed' result.log
rm spec/fail_spec.cr
PATH="$tmp/bin:$PATH" bash "$repo/scripts/test-runner.sh" > result.log 2>&1
grep -q '2 passed, 0 failed' result.log
printf 'Test-runner exit-status regression passed.\n'
