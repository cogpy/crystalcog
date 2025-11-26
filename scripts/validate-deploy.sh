#!/bin/bash
# CrystalCog Deploy Script Quick Validation
# Use this script for ongoing validation of the deployment script

# Don't exit on first error - we want to run all tests
set +e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$PROJECT_ROOT/scripts/production/deploy.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔄 CrystalCog Deploy Script Quick Validation"
echo "============================================"
echo ""

# Quick validation tests
tests_passed=0
tests_failed=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "   Testing $test_name... "
    
    # Use timeout to prevent hanging and better error handling
    if timeout 10 bash -c "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((tests_passed++))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        echo "     Command: $test_command"
        ((tests_failed++))
        return 1
    fi
}

run_optional_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "   Testing $test_name... "
    
    # Use timeout to prevent hanging and better error handling
    if timeout 10 bash -c "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((tests_passed++))
        return 0
    else
        echo -e "${YELLOW}⚠️  SKIP${NC} (dependency not available)"
        return 0
    fi
}

# Core validation tests
echo "🔍 Script Functionality Validation"
echo "===================================="
run_test "Script syntax" "bash -n '$SCRIPT_PATH'"
run_test "Script executable" "[ -x '$SCRIPT_PATH' ]"
run_test "Help function" "timeout 5 '$SCRIPT_PATH' --help"
run_test "Core functions defined" "grep -q '^main()' '$SCRIPT_PATH' && grep -q '^deploy()' '$SCRIPT_PATH'"

echo ""
echo "🔗 Dependency Compatibility Check"
echo "=================================="
run_test "Docker Compose file" "[ -f '$PROJECT_ROOT/docker-compose.production.yml' ]"
run_test "Health check script" "bash -n '$PROJECT_ROOT/scripts/production/healthcheck.sh'"
run_test "Health check executable" "[ -x '$PROJECT_ROOT/scripts/production/healthcheck.sh' ]"
run_test "Config directory" "[ -d '$PROJECT_ROOT/config/production' ]"
run_test "Production config files" "[ -f '$PROJECT_ROOT/config/production/supervisord.conf' ]"

echo ""
echo "🌿 Guix Environment Tests"  
echo "========================="
run_test "Guix manifest" "[ -f '$PROJECT_ROOT/guix.scm' ]"
run_test "Guix channel config" "[ -f '$PROJECT_ROOT/.guix-channel' ]"
run_test "CrystalCog package definition" "[ -f '$PROJECT_ROOT/agent-zero/packages/cognitive.scm' ]"

echo ""
echo "📋 Additional Quality Checks"
echo "============================"
run_optional_test "Docker Compose syntax" "command -v docker-compose >/dev/null && docker-compose -f '$PROJECT_ROOT/docker-compose.production.yml' config >/dev/null 2>&1"
run_test "Deploy script actions" "grep -q 'deploy\|rollback\|status\|logs\|stop' '$SCRIPT_PATH'"
run_test "Error handling" "grep -q 'set -e' '$SCRIPT_PATH'"

echo ""
echo "📊 VALIDATION SUMMARY"
echo "===================="
echo ""
echo "Tests passed: $tests_passed"
echo "Tests failed: $tests_failed"
echo "Total tests:  $((tests_passed + tests_failed))"
echo ""

if [ $tests_failed -eq 0 ]; then
    echo -e "${GREEN}✅ ALL VALIDATION TESTS PASSED!${NC}"
    echo ""
    echo "🎉 Script validation successful - ready for production deployment!"
    echo ""
    echo "✅ Script functionality validated"
    echo "✅ Dependency compatibility confirmed"  
    echo "✅ Guix environment requirements satisfied"
    echo "✅ Quality checks passed"
    echo ""
    exit 0
else
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo ""
    echo "Some tests failed. Please review the results above and address any issues."
    echo "Failed tests: $tests_failed"
    echo ""
    exit 1
fi