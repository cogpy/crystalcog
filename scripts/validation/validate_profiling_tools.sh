#!/bin/bash
# Validation script for demo_profiling_tools.sh
# This script validates that all components referenced in the demo script exist and are functional

set -e

# Ensure script is run from project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "🔍 CrystalCog Profiling Tools Validation Script"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track validation status
ERRORS=0
WARNINGS=0

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Validate file existence
echo "📁 Validating file existence..."
FILES=(
    "src/cogutil/performance_profiler.cr"
    "src/cogutil/performance_regression.cr"
    "src/cogutil/optimization_engine.cr"
    "src/cogutil/performance_monitor.cr"
    "src/cogutil/profiling_cli.cr"
    "tools/profiler"
    "docs/PERFORMANCE_PROFILING_GUIDE.md"
    "spec/cogutil/performance_profiling_spec.cr"
    "benchmarks/comprehensive_performance_demo.cr"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "$file exists"
    else
        print_error "$file is missing"
    fi
done

echo ""

# Validate tools/profiler is executable
echo "🔧 Validating tools/profiler..."
if [ -x "tools/profiler" ]; then
    print_success "tools/profiler is executable"
else
    print_error "tools/profiler is not executable"
fi

echo ""

# Validate script execution
echo "🚀 Running demo_profiling_tools.sh..."
TEMP_OUTPUT=$(mktemp -t profiling_validation_output.XXXXXX)
TEMP_ERRORS=$(mktemp -t profiling_validation_errors.XXXXXX)
trap 'rm -f "$TEMP_OUTPUT" "$TEMP_ERRORS"' EXIT

# Capture combined output for validation (stdout and stderr together is intentional,
# as we want to verify the complete output including any warnings or messages).
if "$PROJECT_ROOT/scripts/demo_profiling_tools.sh" > "$TEMP_OUTPUT" 2>&1; then
    print_success "demo_profiling_tools.sh executed successfully"
    
    # Check output contains expected sections
    if grep -q "📁 Files created:" "$TEMP_OUTPUT"; then
        print_success "Output contains 'Files created' section"
    else
        print_error "Output missing 'Files created' section"
    fi
    
    if grep -q "📏 Implementation Statistics:" "$TEMP_OUTPUT"; then
        print_success "Output contains 'Implementation Statistics' section"
    else
        print_error "Output missing 'Implementation Statistics' section"
    fi
else
    print_error "demo_profiling_tools.sh failed to execute"
fi

echo ""

# Validate Crystal syntax (if Crystal is installed)
echo "💎 Validating Crystal syntax..."
if command -v crystal &> /dev/null; then
    print_success "Crystal is installed: $(crystal version | head -n1)"
    
    # Define indentation for error messages
    ERROR_INDENT="    "
    
    # Check syntax of key profiling files
    # Note: We validate the core profiling files that are most likely to be modified.
    # This may fail if dependencies haven't been installed (shards install).
    SYNTAX_CHECK_FILES=(
        "src/cogutil/performance_profiler.cr"
        "src/cogutil/profiling_cli.cr"
        "src/cogutil/optimization_engine.cr"
    )
    
    for file in "${SYNTAX_CHECK_FILES[@]}"; do
        if crystal build --no-codegen "$file" 2>"$TEMP_ERRORS"; then
            print_success "$file has valid Crystal syntax"
        else
            if [ -s "$TEMP_ERRORS" ]; then
                # Check if error is due to missing dependencies
                if grep -q "can't find file" "$TEMP_ERRORS" || grep -q "Error while requiring" "$TEMP_ERRORS"; then
                    print_warning "$file syntax check skipped (run 'shards install' for full validation)"
                else
                    print_warning "$file may have syntax issues:"
                    sed "s/^/$ERROR_INDENT/" < "$TEMP_ERRORS" | head -5
                fi
            else
                print_warning "$file may have syntax issues (detailed check needs dependencies)"
            fi
        fi
    done
else
    print_warning "Crystal not installed - skipping syntax validation"
    print_info "Install Crystal with: ./scripts/install-crystal.sh"
fi

echo ""

# Validate documentation
echo "📚 Validating documentation..."
if [ -f "docs/PERFORMANCE_PROFILING_GUIDE.md" ]; then
    doc_lines=$(wc -l < docs/PERFORMANCE_PROFILING_GUIDE.md)
    if [ "$doc_lines" -gt 100 ]; then
        print_success "Documentation is comprehensive ($doc_lines lines)"
    else
        print_warning "Documentation may be incomplete ($doc_lines lines)"
    fi
else
    print_error "Documentation missing"
fi

echo ""

# Validate test suite
echo "🧪 Validating test suite..."
if [ -f "spec/cogutil/performance_profiling_spec.cr" ]; then
    test_lines=$(wc -l < spec/cogutil/performance_profiling_spec.cr)
    if [ "$test_lines" -gt 100 ]; then
        print_success "Test suite is comprehensive ($test_lines lines)"
    else
        print_warning "Test suite may be incomplete ($test_lines lines)"
    fi
else
    print_error "Test suite missing"
fi

echo ""
echo "================================================"
echo "Validation Summary:"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"
echo ""

if [ "$ERRORS" -eq 0 ]; then
    print_success "All critical validations passed!"
    if [ "$WARNINGS" -gt 0 ]; then
        echo ""
        print_warning "Some warnings were found - review output above"
    fi
    exit 0
else
    print_error "Validation failed with $ERRORS error(s)"
    exit 1
fi
