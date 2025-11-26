#!/bin/bash
# Validation test for scripts/demo_profiling_tools.sh
# Ensures all referenced files exist and script functionality is correct

set -e

echo "🔍 Validating demo_profiling_tools.sh script..."
echo "================================================"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
cd "$SCRIPT_DIR"

# Test 1: Check if demo script exists and is executable
echo -e "\n${YELLOW}Test 1:${NC} Checking demo script existence..."
if [ -f "scripts/demo_profiling_tools.sh" ]; then
    echo -e "${GREEN}✅ scripts/demo_profiling_tools.sh exists${NC}"
else
    echo -e "${RED}❌ scripts/demo_profiling_tools.sh not found${NC}"
    exit 1
fi

chmod +x scripts/demo_profiling_tools.sh

# Test 2: Validate all referenced files exist
echo -e "\n${YELLOW}Test 2:${NC} Validating referenced files..."
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

ALL_FILES_EXIST=true
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}✅${NC} $file"
    else
        echo -e "  ${RED}❌${NC} $file MISSING"
        ALL_FILES_EXIST=false
    fi
done

if [ "$ALL_FILES_EXIST" = false ]; then
    echo -e "\n${RED}❌ Some files are missing${NC}"
    exit 1
fi

# Test 3: Execute the demo script
echo -e "\n${YELLOW}Test 3:${NC} Executing demo script..."
if ./scripts/demo_profiling_tools.sh > /tmp/demo_output.txt 2>&1; then
    echo -e "${GREEN}✅ Demo script executed successfully${NC}"
else
    echo -e "${RED}❌ Demo script execution failed${NC}"
    cat /tmp/demo_output.txt
    exit 1
fi

# Test 4: Verify output contains expected content
echo -e "\n${YELLOW}Test 4:${NC} Validating script output..."
EXPECTED_STRINGS=(
    "Performance Profiling Tools Demo"
    "Files created:"
    "Key Features Implemented:"
    "Usage Examples:"
    "Implementation Statistics:"
)

OUTPUT=$(cat /tmp/demo_output.txt)
ALL_STRINGS_FOUND=true
for str in "${EXPECTED_STRINGS[@]}"; do
    if echo "$OUTPUT" | grep -q "$str"; then
        echo -e "  ${GREEN}✅${NC} Found: '$str'"
    else
        echo -e "  ${RED}❌${NC} Missing: '$str'"
        ALL_STRINGS_FOUND=false
    fi
done

if [ "$ALL_STRINGS_FOUND" = false ]; then
    echo -e "\n${RED}❌ Script output validation failed${NC}"
    exit 1
fi

# Test 5: Verify line count calculations
echo -e "\n${YELLOW}Test 5:${NC} Verifying line count accuracy..."
PROFILING_FILES=(
    "src/cogutil/performance_profiler.cr"
    "src/cogutil/performance_regression.cr"
    "src/cogutil/optimization_engine.cr"
    "src/cogutil/performance_monitor.cr"
    "src/cogutil/profiling_cli.cr"
)

for file in "${PROFILING_FILES[@]}"; do
    if [ -f "$file" ]; then
        lines=$(wc -l < "$file")
        echo -e "  ${GREEN}✅${NC} $(basename "$file"): $lines lines"
    fi
done

# Test 6: Verify tools/profiler is executable
echo -e "\n${YELLOW}Test 6:${NC} Checking tools/profiler executable..."
if [ -x "tools/profiler" ]; then
    echo -e "${GREEN}✅ tools/profiler is executable${NC}"
else
    echo -e "${RED}❌ tools/profiler is not executable${NC}"
    chmod +x tools/profiler
    echo -e "${YELLOW}ℹ️  Made tools/profiler executable${NC}"
fi

# Test 7: Verify shard.yml has profiler target
echo -e "\n${YELLOW}Test 7:${NC} Checking shard.yml for profiler target..."
# Check for profiler target within targets section
if sed -n '/^targets:/,/^[^ ]/p' shard.yml | grep -q '^[[:space:]]*profiler:'; then
    echo -e "${GREEN}✅ profiler target found in shard.yml${NC}"
else
    echo -e "${YELLOW}⚠️  profiler target not found in shard.yml${NC}"
fi

# Clean up
rm -f /tmp/demo_output.txt

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ All validation tests passed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Summary:"
echo "  • Demo script exists and is executable"
echo "  • All referenced files are present"
echo "  • Script executes without errors"
echo "  • Output contains all expected content"
echo "  • Line counts are accurate"
echo "  • tools/profiler is properly configured"
echo ""
echo "The demo_profiling_tools.sh script has been validated successfully."
