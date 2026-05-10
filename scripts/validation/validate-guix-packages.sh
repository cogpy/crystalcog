#!/bin/bash
# Validation script for CrystalCog Guix package definitions

# Intentionally avoid `set -e` so all checks run and are reported.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== CrystalCog Guix Package Validation ==="

ERRORS=0
WARNINGS=0

pass() { echo "✓ $1"; }
fail() { echo "✗ $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "⚠ $1"; WARNINGS=$((WARNINGS + 1)); }
info() { echo "ℹ $1"; }

echo ""
echo "Checking package and manifest files..."

required_files=(
  "gnu/packages/crystalcog.scm"
  "agent-zero/packages/cognitive.scm"
  ".guix-channel"
  "guix.scm"
  "shard.yml"
)

for file in "${required_files[@]}"; do
  if [ -f "$file" ]; then
    pass "$file exists"
  else
    fail "$file missing"
  fi
done

if [ -f "gnu/packages/opencog.scm" ]; then
  pass "gnu/packages/opencog.scm exists (compatibility module)"
else
  warn "gnu/packages/opencog.scm missing (compatibility module optional)"
fi

echo ""
echo "Checking directory structure..."
for dir in gnu gnu/packages src spec scripts docs; do
  if [ -d "$dir" ]; then
    pass "$dir/ exists"
  else
    fail "$dir/ missing"
  fi
done

echo ""
echo "Validating Scheme syntax..."
if command -v guile >/dev/null 2>&1; then
  for file in gnu/packages/crystalcog.scm agent-zero/packages/cognitive.scm guix.scm; do
    if [ -f "$file" ]; then
      if guile --no-auto-compile -c "(with-input-from-file \"$file\" read)" >/dev/null 2>&1; then
        pass "$file basic syntax valid"
      else
        fail "$file contains syntax errors"
      fi
    fi
  done
else
  warn "Guile not installed - skipping syntax checks"
fi

echo ""
echo "Testing Guix environment..."
if command -v guix >/dev/null 2>&1; then
  if guix shell -m guix.scm -- guile --no-auto-compile -c "(display \"Guix environment OK\\n\")" >/dev/null 2>&1; then
    pass "Guix shell environment test passed"
  else
    fail "Guix shell environment test failed (guix.scm may need updates)"
  fi
else
  warn "Guix not installed - skipping Guix environment test"
  info "Install Guix from https://guix.gnu.org to run full environment validation"
fi

echo ""
echo "=== Validation Summary ==="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"

if [ "$ERRORS" -eq 0 ]; then
  echo "✅ Guix package validation PASSED"
  exit 0
else
  echo "❌ Guix package validation FAILED"
  exit 1
fi
