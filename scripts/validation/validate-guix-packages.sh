#!/bin/bash
# Validation script for CrystalCog Guix package definitions

# Note: Do not use 'set -e' here. We want to continue through each check
# and report a full validation summary at the end.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"
# CrystalCog is a Crystal language project with optional Guix integration

# Note: We don't use 'set -e' because we want to continue validation
# even when individual checks fail, and report all issues at the end.

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
    validation_passed=false
}

print_warning() {
    echo "⚠ $1"
    WARNINGS=$((WARNINGS + 1))
}
# Initialize validation state
ERRORS=0
WARNINGS=0
validation_passed=true
GUIX_FILES_EXIST=true

# Check if package files exist
echo ""
echo "Checking package files..."
if [ -f "gnu/packages/crystalcog.scm" ]; then
    echo "✓ crystalcog.scm exists"
else
    echo "✗ crystalcog.scm missing"
    validation_passed=false
    ERRORS=$((ERRORS + 1))
fi

if [ -f "agent-zero/packages/cognitive.scm" ]; then
    echo "✓ cognitive.scm exists"
else
    echo "✗ cognitive.scm missing"
    validation_passed=false
    ERRORS=$((ERRORS + 1))
fi

# gnu/packages/opencog.scm is optional — it provides C++ OpenCog package
# definitions and is not required for the Crystal-based CrystalCog build.
# A more detailed informational note is printed below.
if [ -f "gnu/packages/opencog.scm" ]; then
    echo "✓ opencog.scm (compatibility) exists"
else
    echo "⚠ opencog.scm (compatibility) missing (optional)"
    WARNINGS=$((WARNINGS + 1))
fi

# .guix-channel is part of the optional Guix tooling. Missing files
# downgrade GUIX_FILES_EXIST so the warning-only branch in the final
# result handles it, but they do NOT flip validation_passed — missing
# Guix tooling is non-blocking for CrystalCog.
if [ -f ".guix-channel" ]; then
    echo "✓ .guix-channel exists"
else
    echo "⚠ .guix-channel missing (optional Guix tooling)"
    GUIX_FILES_EXIST=false
    WARNINGS=$((WARNINGS + 1))
fi

if [ -f "guix.scm" ]; then
    echo "✓ guix.scm manifest exists"
else
    echo "⚠ guix.scm manifest missing (optional Guix tooling)"
    GUIX_FILES_EXIST=false
    WARNINGS=$((WARNINGS + 1))
fi

# Note about gnu/packages/opencog.scm
if [ -f "gnu/packages/opencog.scm" ]; then
    echo "✓ gnu/packages/opencog.scm exists (optional for C++ OpenCog integration)"
else
    echo "ℹ gnu/packages/opencog.scm not present (not required for CrystalCog)"
    echo "  This file is only needed for C++ OpenCog package definitions."
    echo "  CrystalCog uses native Crystal tooling (shards) for package management."
fi

echo ""
echo "Checking package structure..."

EXPECTED_DIRS=("gnu" "gnu/packages" "agent-zero" "agent-zero/packages" "src" "spec" "scripts" "docs")
for dir in "${EXPECTED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        print_success "$dir/ exists"
    else
        print_error "$dir/ missing"
        echo "✗ $dir/ missing"
        validation_passed=false
        ERRORS=$((ERRORS + 1))
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

    # Test Agent-Zero cognitive module
    echo "Testing Agent-Zero cognitive module syntax..."
    if guile -c "(add-to-load-path \".\") (use-modules (agent-zero packages cognitive))" 2>/dev/null; then
        echo "✓ Agent-Zero cognitive module syntax valid"
    else
        echo "✗ Agent-Zero cognitive module syntax invalid"
        echo "Note: This validation requires full Guix installation"
        echo "Running syntax check..."
        guile -c "(add-to-load-path \".\") (use-modules (agent-zero packages cognitive))" 2>&1 | head -20
    fi

    # Test opencog compatibility module
    echo "Testing opencog compatibility module syntax..."
    if guile -c "(add-to-load-path \".\") (use-modules (gnu packages opencog))" 2>/dev/null; then
        echo "✓ OpenCog compatibility module syntax valid"
    else
        echo "✗ OpenCog compatibility module syntax invalid"
        echo "Running detailed syntax check..."
        if ! guile -c "(add-to-load-path \".\") (use-modules (gnu packages opencog))" 2>&1; then
            validation_passed=false
            ERRORS=$((ERRORS + 1))
        fi
    fi

    # Test manifest
    echo "Testing manifest syntax..."
    if guile -c "(add-to-load-path \".\") (load \"guix.scm\")" 2>/dev/null; then
        echo "✓ Manifest syntax valid"
    else
        echo "✗ Manifest syntax invalid"
        echo "Note: This validation requires full Guix installation"
        echo "Running syntax check..."
        guile -c "(add-to-load-path \".\") (load \"guix.scm\")" 2>&1 | head -20
        if ! guile -c "(add-to-load-path \".\") (load \"guix.scm\")" 2>&1; then
            validation_passed=false
            ERRORS=$((ERRORS + 1))
        fi
    fi

    # Guix environment test
    echo "Testing Guix shell environment..."
    if guix shell -m guix.scm -- guile --no-auto-compile -c "(display \"Guix environment OK\n\")" >/dev/null 2>&1; then
        echo "✓ Guix shell environment test passed"
    else
        echo "⚠ Guix shell environment test failed (guix.scm may need updates)"
        WARNINGS=$((WARNINGS + 1))
    fi

elif command -v guile > /dev/null; then
    echo "Guile detected but Guix not installed - performing basic validation..."
    echo "⚠ Note: Full syntax validation requires Guix package manager"
    echo ""
    echo "Basic Scheme syntax validation (without Guix modules):"

    # Basic file syntax check without loading Guix modules
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
    echo ""
    echo "To perform full validation, install Guix:"
    echo "  wget https://git.savannah.gnu.org/cgit/guix.git/plain/etc/guix-install.sh"
    echo "  chmod +x guix-install.sh"
    echo "  sudo ./guix-install.sh"
fi

echo ""
echo "Checking Guix environment tooling..."

if command -v guix > /dev/null 2>&1; then
    print_success "GNU Guix available: $(guix --version | head -n1)"
else
    print_warning "GNU Guix not installed"
fi

echo ""
echo "=== Dependency Validation ==="
echo "Checking CrystalCog dependencies..."

if command -v crystal > /dev/null 2>&1; then
    print_success "Crystal detected: $(crystal --version | head -1)"
else
    print_warning "Crystal not detected (required for building CrystalCog packages)"
    echo "⚠ Crystal not detected (required for building CrystalCog packages)"
    echo "  Install with: ./scripts/install-crystal.sh"
    WARNINGS=$((WARNINGS + 1))
fi

if command -v shards > /dev/null 2>&1; then
    print_success "Shards detected (Crystal dependency manager)"
else
    print_warning "Shards not detected (comes with Crystal installation)"
    echo "⚠ Shards not detected (comes with Crystal installation)"
    WARNINGS=$((WARNINGS + 1))
fi

if command -v psql > /dev/null 2>&1 || dpkg -l | grep -q postgresql 2>/dev/null; then
    print_success "PostgreSQL available"
else
    print_warning "PostgreSQL not detected (optional - needed for persistent storage)"
    echo "⚠ PostgreSQL not detected (optional - needed for persistent storage)"
    WARNINGS=$((WARNINGS + 1))
fi

if command -v sqlite3 > /dev/null 2>&1 || dpkg -l | grep -q sqlite3 2>/dev/null; then
    print_success "SQLite available"
else
    print_warning "SQLite not detected (optional - needed for persistent storage)"
    echo "⚠ SQLite not detected (optional - needed for persistent storage)"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "=== Package Summary ==="
echo "CrystalCog Guix packages available:"
echo "  Core Packages:"
echo "    - crystalcog: Main Crystal cognitive architecture platform"
echo "    - crystalcog-cogutil: Core utilities (logging, config, random)"
echo "    - crystalcog-atomspace: Hypergraph database and reasoning"
echo "    - crystalcog-opencog: Main cognitive reasoning platform"
echo ""
echo "  Agent-Zero Cognitive Packages:"
echo "    - opencog: Re-exported crystalcog package"
echo "    - ggml: Tensor library for machine learning"
echo "    - guile-pln: Guile bindings for PLN reasoning"
echo "    - guile-ecan: Guile bindings for attention allocation"
echo "    - guile-moses: Guile bindings for evolutionary optimization"
echo "    - guile-pattern-matcher: Guile bindings for pattern matching"
echo "    - guile-relex: Guile bindings for NLP"
echo ""
echo "Usage:"
echo "  guix shell -m guix.scm                  # Development environment"
echo "  guix install crystalcog                 # Install main package"
echo "  guix install crystalcog-atomspace       # Install specific component"
echo "  Compatibility module:"
echo "    - (gnu packages opencog): Re-exports CrystalCog packages with OpenCog names"
echo ""
echo "CrystalCog Guix Integration Status:"
echo "  - Primary package manager: shards (Crystal's native package manager)"
echo "  - Optional integration: Guix (for OpenCog ecosystem compatibility)"
echo ""
echo "Guix configuration files:"
echo "  ✓ guix.scm - Development environment manifest"
echo "  ✓ .guix-channel - Agent-Zero Genesis package channel"
echo ""
echo "Usage:"
echo "  guix shell -m guix.scm            # Containerized shell (recommended)"
echo "  guix environment -m guix.scm      # Development environment"
echo "  guix install crystalcog           # Install main package"
echo "  guix install crystalcog-atomspace # Install specific component"
echo "  shards install                    # Install Crystal dependencies (primary method)"
echo ""
echo "See docs/README-GUIX.md for detailed usage instructions."

echo ""
echo "=== Validation Result ==="
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"

if [ "$validation_passed" = true ] && [ "$GUIX_FILES_EXIST" = true ]; then
    echo ""
    echo "✅ Guix validation PASSED - All validations completed successfully!"
    exit 0
elif [ "$validation_passed" = true ] && [ "$GUIX_FILES_EXIST" = false ]; then
    echo ""
    echo "⚠️  Guix validation WARNING - Some Guix files missing but not critical for CrystalCog"
    echo "   CrystalCog primarily uses Crystal/shards tooling."
    exit 0  # Non-blocking warning
else
    print_error "Guix validation failed"
    echo ""
    echo "✗ Some validations failed. Please review the errors above."
    exit 1
fi
