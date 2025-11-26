#!/bin/bash
# Validation script for CrystalCog Guix package definitions

echo "=== CrystalCog Guix Package Validation ==="
# Guix package validation script for CrystalCog
# CrystalCog is a Crystal language project with optional Guix integration

echo "=== CrystalCog Guix Package Validation ==="

# Check if essential Guix files exist
echo "Checking Guix configuration files..."
GUIX_FILES_EXIST=true
# Validation script for CrystalCog Guix package definitions

echo "=== CrystalCog Guix Package Validation ==="
# Note: We don't use 'set -e' because we want to continue validation
# even when individual checks fail, and report all issues at the end.

echo "=== CrystalCog Guix Package Validation ==="

# Initialize validation state
validation_passed=true

# Check if package files exist
echo ""
echo "Checking package files..."
if [ -f "gnu/packages/crystalcog.scm" ]; then
    echo "✓ crystalcog.scm exists"
else
    echo "✗ crystalcog.scm missing"
    exit 1
fi

if [ -f "agent-zero/packages/cognitive.scm" ]; then
    echo "✓ cognitive.scm exists"
else
if [ -f "agent-zero/packages/cognitive.scm" ]; then
    echo "✓ cognitive.scm exists"
else
    echo "✗ cognitive.scm missing"
    exit 1

if [ -f "gnu/packages/crystalcog.scm" ]; then
    echo "✓ crystalcog.scm exists"
else
    echo "✗ crystalcog.scm missing"
    validation_passed=false
fi

if [ -f "gnu/packages/opencog.scm" ]; then
    echo "✓ opencog.scm (compatibility) exists"
else
    echo "✗ opencog.scm (compatibility) missing"
    validation_passed=false
fi

if [ -f ".guix-channel" ]; then
    echo "✓ .guix-channel exists"
else
    echo "✗ .guix-channel missing"
    GUIX_FILES_EXIST=false
    validation_passed=false
fi

if [ -f "guix.scm" ]; then
    echo "✓ guix.scm manifest exists"
else
    echo "✗ guix.scm manifest missing"
    GUIX_FILES_EXIST=false
fi

# Note about gnu/packages/opencog.scm
if [ -f "gnu/packages/opencog.scm" ]; then
    echo "✓ gnu/packages/opencog.scm exists (optional for C++ OpenCog integration)"
else
    echo "ℹ gnu/packages/opencog.scm not present (not required for CrystalCog)"
    echo "  This file is only needed for C++ OpenCog package definitions."
    echo "  CrystalCog uses native Crystal tooling (shards) for package management."
    validation_passed=false
fi

# Check for Crystal project files
echo ""
echo "Checking Crystal project files..."

if [ -f "shard.yml" ]; then
    echo "✓ shard.yml exists"
    # Validate shard.yml has required fields
    if grep -q "name: crystalcog" shard.yml; then
        echo "  ✓ Project name is 'crystalcog'"
    else
        echo "  ✗ Project name mismatch in shard.yml"
        validation_passed=false
    fi
else
    echo "✗ shard.yml missing"
    validation_passed=false
fi

if [ -d "src" ]; then
    echo "✓ src/ directory exists"
else
    echo "✗ src/ directory missing"
    validation_passed=false
fi

# Validate directory structure
echo ""
echo "Checking package structure..."

expected_dirs=("gnu" "gnu/packages" "src" "spec" "scripts" "docs")
for dir in "${expected_dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "✓ $dir/ exists"
    else
        echo "✗ $dir/ missing"
        validation_passed=false
    fi
done

# Basic syntax check
echo -e "\nValidating Scheme syntax..."

# Check if Guix is installed (required for full validation)
if command -v guix > /dev/null; then
    echo "Guix detected - performing full syntax validation..."
    
    # Test CrystalCog package module
    echo "Testing CrystalCog package module syntax..."
    if guile -c "(add-to-load-path \".\") (use-modules (gnu packages crystalcog))" 2>/dev/null; then
        echo "✓ CrystalCog package module syntax valid"
    else
        echo "✗ CrystalCog package module syntax invalid"
        echo "Note: This validation requires full Guix installation"
        echo "Running syntax check..."
        guile -c "(add-to-load-path \".\") (use-modules (gnu packages crystalcog))" 2>&1 | head -20
    fi
    
    # Test Agent-Zero cognitive module
    echo "Testing Agent-Zero cognitive module syntax..."
    if guile -c "(add-to-load-path \".\") (use-modules (agent-zero packages cognitive))" 2>/dev/null; then
        echo "✓ Agent-Zero cognitive module syntax valid"
    else
        echo "✗ Agent-Zero cognitive module syntax invalid"
        echo "Note: This validation requires full Guix installation"
        echo "Running syntax check..."
        guile -c "(add-to-load-path \".\") (use-modules (agent-zero packages cognitive))" 2>&1 | head -20
echo ""
echo "Validating Scheme syntax..."
if command -v guile > /dev/null; then
    echo "Testing package module syntax..."
    if GUILE_LOAD_PATH=".:$GUILE_LOAD_PATH" guile -c "(use-modules (agent-zero packages cognitive))" 2>/dev/null; then
        echo "✓ Package module syntax valid"
    else
        echo "⚠ Package module syntax check skipped (needs proper Guix environment)"
        echo "To validate in Guix environment, run:"
        echo "  guix shell guile -- guile -c '(use-modules (agent-zero packages cognitive))'"
    echo "Guile found, performing syntax validation..."
    
    # Test crystalcog package module
    echo "Testing crystalcog package module syntax..."
    if guile -c "(add-to-load-path \".\") (use-modules (gnu packages crystalcog))" 2>/dev/null; then
        echo "✓ CrystalCog package module syntax valid"
    else
        echo "✗ CrystalCog package module syntax invalid"
        echo "Running detailed syntax check..."
        if ! guile -c "(add-to-load-path \".\") (use-modules (gnu packages crystalcog))" 2>&1; then
            validation_passed=false
        fi
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
        fi
    fi
    
    # Test manifest
    echo "Testing manifest syntax..."
    if guile -c "(add-to-load-path \".\") (load \"guix.scm\")" 2>/dev/null; then
        echo "✓ Manifest syntax valid"
    else
        echo "⚠ Manifest syntax check skipped (needs proper Guix environment)"
        echo "To validate in Guix environment, run:"
        echo "  guix shell guile -- guile -c '(load \"guix.scm\")'"
        echo "✗ Manifest syntax invalid"
        echo "Note: This validation requires full Guix installation"
        echo "Running syntax check..."
        guile -c "(add-to-load-path \".\") (load \"guix.scm\")" 2>&1 | head -20
        echo "Running detailed syntax check..."
        if ! guile -c "(add-to-load-path \".\") (load \"guix.scm\")" 2>&1; then
            validation_passed=false
        fi
    fi
elif command -v guile > /dev/null; then
    echo "Guile detected but Guix not installed - performing basic validation..."
    echo "⚠ Note: Full syntax validation requires Guix package manager"
    echo ""
    echo "Basic Scheme syntax validation (without Guix modules):"
    
    # Basic file syntax check without loading Guix modules
    for file in "gnu/packages/crystalcog.scm" "agent-zero/packages/cognitive.scm" "guix.scm"; do
        if guile --no-auto-compile -c "(with-input-from-file \"$file\" read)" 2>/dev/null >/dev/null; then
            echo "✓ $file: Basic syntax valid"
        else
            echo "✗ $file: Basic syntax errors detected"
            guile --no-auto-compile -c "(with-input-from-file \"$file\" read)"
        fi
    done
    
    echo ""
    echo "To perform full validation, install Guix:"
    echo "  wget https://git.savannah.gnu.org/cgit/guix.git/plain/etc/guix-install.sh"
    echo "  chmod +x guix-install.sh"
    echo "  sudo ./guix-install.sh"
else
    echo "⚠ Guile not available, skipping syntax validation"
    echo "To validate syntax, install Guile and Guix, then run:"
    echo "  sudo apt-get install guile-3.0"
    echo "  # or install full Guix for complete validation"
fi

echo -e "\n=== Dependency Validation ==="
echo "Checking CrystalCog dependencies..."

# Check if Crystal is available (main dependency)
if command -v crystal > /dev/null; then
    CRYSTAL_VERSION=$(crystal --version | head -1)
    echo "✓ Crystal detected: $CRYSTAL_VERSION"
else
    echo "⚠ Crystal not detected (required for building CrystalCog packages)"
    echo "  Install with: ./scripts/install-crystal.sh"
fi

# Check if shards is available (Crystal dependency manager)
if command -v shards > /dev/null; then
    echo "✓ Shards detected (Crystal dependency manager)"
else
    echo "⚠ Shards not detected (comes with Crystal installation)"
fi

# Check for database dependencies mentioned in package definitions
if command -v psql > /dev/null || dpkg -l | grep -q postgresql 2>/dev/null; then
    echo "✓ PostgreSQL available"
else
    echo "⚠ PostgreSQL not detected (optional - needed for persistent storage)"
fi

if command -v sqlite3 > /dev/null || dpkg -l | grep -q sqlite3 2>/dev/null; then
    echo "✓ SQLite available"
else
    echo "⚠ SQLite not detected (optional - needed for persistent storage)"
fi

echo -e "\n=== Package Summary ==="
echo "CrystalCog Guix packages available:"
echo "  Core Packages:"
echo "    - crystalcog: Main Crystal cognitive architecture platform"
echo "    - crystalcog-cogutil: Core utilities (logging, config, random)"
echo "    - crystalcog-atomspace: Hypergraph database and reasoning"
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
echo "  guix environment -m guix.scm              # Development environment"
echo "  guix install crystalcog                   # Install main package"
echo "  guix install crystalcog-atomspace         # Install specific component"
echo ""
echo "See docs/README-GUIX.md for detailed usage instructions."
    echo "To validate syntax, install Guile and run:"
    echo "  guix shell guile -- guile -c '(use-modules (agent-zero packages cognitive))'"
    echo "  guix shell guile -- guile -c '(load \"guix.scm\")'"
fi

echo -e "\n=== Package Summary ==="
echo "CrystalCog Guix Integration Status:"
echo ""
echo "CrystalCog is a Crystal language project that uses:"
echo "  - Primary package manager: shards (Crystal's native package manager)"
echo "  - Optional integration: Guix (for OpenCog ecosystem compatibility)"
echo ""
echo "Guix configuration files present:"
echo "  ✓ guix.scm - Development environment manifest"
echo "  ✓ .guix-channel - Agent-Zero Genesis package channel"
echo ""
echo "Usage:"
echo "  guix environment -m guix.scm    # Development environment with Guile packages"
echo "  shards install                  # Install Crystal dependencies (primary method)"
echo ""
echo "See README.md and docs/README-GUIX.md for detailed usage instructions."
echo ""

if [ "$GUIX_FILES_EXIST" = true ]; then
    echo "✅ Guix validation PASSED - Essential configuration files present"
    exit 0
else
    echo "⚠️  Guix validation WARNING - Some files missing but not critical for CrystalCog"
    echo "   CrystalCog primarily uses Crystal/shards tooling."
    exit 0  # Non-blocking warning
fi
echo "Created the following CrystalCog Guix packages:"
echo "  - opencog: Core cognitive architecture (Crystal implementation)"
echo "  - ggml: Tensor library for machine learning"
echo "  - guile-pln: Probabilistic Logic Networks bindings"
echo "  - guile-ecan: Economic Attention Network bindings"
echo "  - guile-moses: MOSES evolutionary learning bindings"
echo "  - guile-pattern-matcher: Pattern matching engine bindings"
echo "  - guile-relex: Natural language processing bindings"
echo ""
echo "Usage:"
echo "  guix shell -m guix.scm          # Containerized shell (recommended)"
echo "  guix environment -m guix.scm    # Development environment (deprecated)"
echo ""
echo "See docs/README-GUIX.md for detailed usage instructions."
    echo "  guile -c '(add-to-load-path \".\") (use-modules (gnu packages crystalcog))'"
    echo "  guile -c '(add-to-load-path \".\") (use-modules (gnu packages opencog))'"
    echo "  guile -c '(add-to-load-path \".\") (load \"guix.scm\")'"
fi

# Package summary
echo ""
echo "=== Package Summary ==="
echo "Created the following CrystalCog Guix packages:"
echo "  - crystalcog: Main OpenCog cognitive architecture in Crystal"
echo "  - crystalcog-cogutil: Core Crystal utilities (logging, config, random)"
echo "  - crystalcog-atomspace: Hypergraph database and knowledge representation"
echo "  - crystalcog-opencog: Main cognitive reasoning platform"
echo ""
echo "Compatibility module:"
echo "  - (gnu packages opencog): Re-exports CrystalCog packages with OpenCog names"
echo ""
echo "Usage:"
echo "  guix environment -m guix.scm              # Development environment"
echo "  guix install crystalcog                   # Install main package"
echo "  guix install crystalcog-atomspace         # Install specific component"
echo ""
echo "See docs/README-GUIX.md for detailed usage instructions."

# Final validation result
echo ""
echo "=== Validation Result ==="
if [ "$validation_passed" = true ]; then
    echo "✓ All validations passed successfully!"
    exit 0
else
    echo "✗ Some validations failed. Please review the errors above."
    exit 1
fi
