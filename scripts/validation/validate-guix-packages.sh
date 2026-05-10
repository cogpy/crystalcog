#!/bin/bash
# Validation script for CrystalCog Guix package definitions

# Note: Do not use 'set -e' here. We want to continue through each check
# and report a full validation summary at the end.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== CrystalCog Guix Package Validation ==="

ERRORS=0
WARNINGS=0

print_success() {
    echo "✓ $1"
}

print_error() {
    echo "✗ $1"
    ERRORS=$((ERRORS + 1))
}

print_warning() {
    echo "⚠ $1"
    WARNINGS=$((WARNINGS + 1))
}

echo ""
echo "Checking package files..."

REQUIRED_FILES=(
    "gnu/packages/crystalcog.scm"
    "agent-zero/packages/cognitive.scm"
    ".guix-channel"
    "guix.scm"
    "shard.yml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "$file exists"
    else
        print_error "$file missing"
    fi
done

if [ -f "gnu/packages/opencog.scm" ]; then
    print_success "gnu/packages/opencog.scm exists"
else
    print_warning "gnu/packages/opencog.scm missing"
fi

echo ""
echo "Checking package structure..."

EXPECTED_DIRS=("gnu" "gnu/packages" "agent-zero" "agent-zero/packages" "src" "spec" "scripts" "docs")
for dir in "${EXPECTED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        print_success "$dir/ exists"
    else
        print_error "$dir/ missing"
    fi
done

echo ""
echo "Checking Crystal project metadata..."

if [ -f "shard.yml" ]; then
    if grep -Eq "^name[[:space:]]*:[[:space:]]*crystalcog[[:space:]]*$" shard.yml; then
        print_success "shard.yml project name is crystalcog"
    else
        print_error "shard.yml project name mismatch"
    fi
else
    print_error "shard.yml missing"
fi

echo ""
echo "Validating Scheme syntax..."

if command -v guix > /dev/null 2>&1 && command -v guile > /dev/null 2>&1; then
    if GUILE_LOAD_PATH=".:${GUILE_LOAD_PATH:-}" guile -c "(use-modules (gnu packages crystalcog))" >/dev/null 2>&1; then
        print_success "CrystalCog package module syntax valid"
    else
        print_error "CrystalCog package module syntax invalid"
    fi

    if GUILE_LOAD_PATH=".:${GUILE_LOAD_PATH:-}" guile -c "(use-modules (gnu packages opencog))" >/dev/null 2>&1; then
        print_success "OpenCog compatibility module syntax valid"
    else
        print_warning "OpenCog compatibility module syntax could not be fully validated"
    fi

    if GUILE_LOAD_PATH=".:${GUILE_LOAD_PATH:-}" guile -c "(load \"guix.scm\")" >/dev/null 2>&1; then
        print_success "guix.scm manifest syntax valid"
    else
        print_error "guix.scm manifest syntax invalid"
    fi
elif command -v guile > /dev/null 2>&1; then
    for file in "gnu/packages/crystalcog.scm" "agent-zero/packages/cognitive.scm" "guix.scm"; do
        if guile --no-auto-compile -c "(with-input-from-file \"$file\" read)" >/dev/null 2>&1; then
            print_success "$file basic syntax valid"
        else
            print_error "$file has Scheme syntax errors"
        fi
    done

    print_warning "Full Guix module validation skipped because guix is not installed"
else
    print_warning "Guile not available, skipping Scheme syntax validation"
fi

echo ""
echo "Checking Guix environment tooling..."

if command -v guix > /dev/null 2>&1; then
    print_success "GNU Guix available: $(guix --version | head -n1)"
else
    print_warning "GNU Guix not installed"
fi

echo ""
echo "=== Validation Result ==="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"

if [ "$ERRORS" -eq 0 ]; then
    print_success "Guix validation completed successfully"
    exit 0
else
    print_error "Guix validation failed"
    exit 1
fi
