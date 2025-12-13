#!/bin/bash
# Build all CrystalCog components
# Usage: ./build_all_components.sh [--release]

set -e

RELEASE_FLAG=""
if [ "$1" = "--release" ]; then
    RELEASE_FLAG="--release"
    echo "Building in RELEASE mode"
fi

echo "========================================"
echo "Building All CrystalCog Components"
echo "========================================"
echo ""

# Create bin directory
mkdir -p bin

# Track build results
BUILT=0
SKIPPED=0
FAILED=0

# Function to build a component
build_component() {
    local src=$1
    local output=$2
    local name=$3
    
    echo -n "Building $name... "
    if timeout 60 crystal build $RELEASE_FLAG --error-trace "$src" -o "$output" 2>/dev/null; then
        echo "✓"
        ((BUILT++))
        return 0
    else
        echo "✗"
        ((FAILED++))
        return 1
    fi
}

# Build main application
echo "Main Application:"
echo "-----------------"
build_component "src/crystalcog.cr" "crystalcog" "crystalcog"
echo ""

# Build core libraries
echo "Core Libraries:"
echo "---------------"
build_component "src/cogutil/cogutil.cr" "bin/cogutil" "cogutil"
build_component "src/atomspace/atomspace.cr" "bin/atomspace" "atomspace"
build_component "src/opencog/opencog.cr" "bin/opencog" "opencog"
build_component "src/pln/pln.cr" "bin/pln" "pln"
build_component "src/ure/ure.cr" "bin/ure" "ure"
echo ""

# Build main executables
echo "Main Executables:"
echo "-----------------"
build_component "src/atomspace/atomspace_main.cr" "bin/atomspace_main" "atomspace_main"
build_component "src/cogserver/cogserver_main.cr" "bin/cogserver" "cogserver"
build_component "src/attention/attention_main.cr" "bin/attention" "attention"
build_component "src/pattern_matching/pattern_matching_main.cr" "bin/pattern_matching" "pattern_matching"
build_component "src/pattern_mining/pattern_mining_main.cr" "bin/pattern_mining" "pattern_mining"
build_component "src/nlp/nlp_main.cr" "bin/nlp" "nlp"
build_component "src/moses/moses_main.cr" "bin/moses" "moses"
build_component "src/learning/learning_main.cr" "bin/learning" "learning"
build_component "src/ml/ml_main.cr" "bin/ml" "ml"
build_component "src/agent-zero/agent_zero_main.cr" "bin/agent_zero" "agent_zero"
echo ""

# Summary
echo "========================================"
echo "Build Summary"
echo "========================================"
echo ""
echo "Built successfully: $BUILT"
echo "Failed: $FAILED"
echo "Total attempted: $((BUILT + FAILED))"
echo ""

if [ $BUILT -gt 0 ]; then
    echo "Binaries created:"
    echo "-----------------"
    ls -lh crystalcog bin/* 2>/dev/null | awk '{print $9, $5}'
    echo ""
    
    echo "Total binary size: $(du -sh bin/ 2>/dev/null | cut -f1)"
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo "✓ All components built successfully!"
    exit 0
else
    echo "⚠️  Some components failed to build"
    exit 1
fi
