#!/bin/bash
# Dependency Compatibility Check for CrystalCog Profiling Tools
# This script validates that all dependencies are compatible and available

set -e

echo "🔍 CrystalCog Dependency Compatibility Check"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "📦 Checking Crystal Dependencies..."
echo ""

# Check if shard.yml exists
if [ -f "shard.yml" ]; then
    print_success "shard.yml found"
    
    # Parse dependencies from shard.yml
    echo ""
    echo "Dependencies declared in shard.yml:"
    
    # Check for sqlite3
    if grep -q "sqlite3:" shard.yml; then
        print_success "sqlite3 dependency declared"
    else
        print_warning "sqlite3 dependency not declared"
    fi
    
    # Check for pg (PostgreSQL)
    if grep -q "pg:" shard.yml; then
        print_success "pg (PostgreSQL) dependency declared"
    else
        print_warning "pg dependency not declared"
    fi
else
    print_error "shard.yml not found"
fi

echo ""
echo "🔧 Checking System Dependencies..."
echo ""

# Check for Crystal compiler
if command -v crystal &> /dev/null; then
    CRYSTAL_VERSION=$(crystal version | head -n1)
    print_success "Crystal compiler available: $CRYSTAL_VERSION"
    
    # Check if version matches requirement
    REQUIRED_VERSION="1.10.1"
    if grep -q "crystal: $REQUIRED_VERSION" shard.yml 2>/dev/null; then
        print_info "Required Crystal version: $REQUIRED_VERSION"
    fi
else
    print_warning "Crystal compiler not installed"
    print_info "Install with: ./scripts/install-crystal.sh"
fi

# Check for shards
if command -v shards &> /dev/null; then
    SHARDS_VERSION=$(shards version | head -n1)
    print_success "Shards package manager available: $SHARDS_VERSION"
else
    print_warning "Shards not installed (comes with Crystal)"
fi

echo ""
echo "💾 Checking Database Dependencies..."
echo ""

# Check for SQLite
if command -v sqlite3 &> /dev/null; then
    SQLITE_VERSION=$(sqlite3 --version | awk '{print $1}')
    print_success "SQLite3 available: $SQLITE_VERSION"
else
    print_warning "SQLite3 not installed"
    print_info "Install with: sudo apt-get install sqlite3 libsqlite3-dev"
fi

# Check for PostgreSQL
if command -v psql &> /dev/null; then
    PG_VERSION=$(psql --version | awk '{print $3}')
    print_success "PostgreSQL client available: $PG_VERSION"
else
    print_warning "PostgreSQL client not installed"
    print_info "Install with: sudo apt-get install postgresql-client libpq-dev"
fi

echo ""
echo "📚 Checking Profiling Tool Dependencies..."
echo ""

# Check profiling tool files exist
PROFILING_FILES=(
    "src/cogutil/performance_profiler.cr"
    "src/cogutil/performance_regression.cr"
    "src/cogutil/optimization_engine.cr"
    "src/cogutil/performance_monitor.cr"
    "src/cogutil/profiling_cli.cr"
)

for file in "${PROFILING_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "$(basename "$file") exists"
    else
        print_error "$(basename "$file") missing"
    fi
done

echo ""
echo "🔄 Checking Guix Dependencies..."
echo ""

# Check for Guix
if command -v guix &> /dev/null; then
    GUIX_VERSION=$(guix --version | head -n1)
    print_success "GNU Guix available: $GUIX_VERSION"
    
    # Check if guix.scm exists
    if [ -f "guix.scm" ]; then
        print_success "guix.scm manifest found"
    else
        print_error "guix.scm manifest missing"
    fi
    
    # Check if .guix-channel exists
    if [ -f ".guix-channel" ]; then
        print_success ".guix-channel file found"
    else
        print_warning ".guix-channel file missing"
    fi
    
    # Check if gnu/packages/opencog.scm exists
    if [ -f "gnu/packages/opencog.scm" ]; then
        print_success "gnu/packages/opencog.scm package definition found"
    else
        print_warning "gnu/packages/opencog.scm package definition missing"
    fi
else
    print_warning "GNU Guix not installed"
    print_info "Visit https://guix.gnu.org for installation instructions"
fi

echo ""
echo "=============================================="
echo "Dependency Compatibility Summary:"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"
echo ""

if [ "$ERRORS" -eq 0 ]; then
    print_success "All critical dependencies are compatible!"
    if [ "$WARNINGS" -gt 0 ]; then
        echo ""
        print_warning "Some optional dependencies are missing - see output above"
        print_info "The profiling tools will work but some features may be limited"
    fi
    exit 0
else
    print_error "Dependency compatibility check failed with $ERRORS error(s)"
    echo ""
    print_info "Review the errors above and install missing dependencies"
    exit 1
fi
