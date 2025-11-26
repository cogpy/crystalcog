#!/bin/bash

# Wrapper script to run cogserver integration tests
# This script builds the cogserver and runs the integration test suite
# Usage: ./scripts/validation/run_cogserver_integration_test.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_ROOT"

print_status "CogServer Integration Test Runner"
print_status "==================================="
echo ""

# Check if Crystal is installed
if ! command -v crystal &> /dev/null; then
    print_error "Crystal is not installed"
    print_status "Install Crystal using: ./scripts/install-crystal.sh"
    exit 1
fi

print_status "Using Crystal version: $(crystal version | head -n1)"

# Install dependencies if needed
if [ ! -d "lib" ]; then
    print_status "Installing Crystal dependencies..."
    shards install
fi

# Build cogserver
print_status "Building CogServer..."
if [ -f "cogserver_bin" ]; then
    print_warning "Removing existing cogserver_bin"
    rm -f cogserver_bin
fi

# Build without RocksDB for now (can be enabled if librocksdb-dev is installed)
print_status "Building with DISABLE_ROCKSDB=1..."
if ! DISABLE_ROCKSDB=1 crystal build --error-trace src/cogserver/cogserver_main.cr -o cogserver_bin; then
    print_error "Build failed"
    exit 1
fi

if [ ! -f "cogserver_bin" ]; then
    print_error "Build did not produce cogserver_bin"
    exit 1
fi

print_success "CogServer built successfully ($(du -h cogserver_bin | cut -f1))"

# Start cogserver in background
print_status "Starting CogServer..."
./cogserver_bin > /tmp/cogserver_test.log 2>&1 &
COGSERVER_PID=$!

# Function to cleanup on exit
cleanup() {
    if [ -n "$COGSERVER_PID" ]; then
        print_status "Stopping CogServer (PID: $COGSERVER_PID)..."
        kill $COGSERVER_PID 2>/dev/null || true
        wait $COGSERVER_PID 2>/dev/null || true
        print_status "CogServer stopped"
    fi
}

trap cleanup EXIT INT TERM

# Wait for server to be ready
print_status "Waiting for server to initialize..."
sleep 5

# Check if server is running
if ! ps -p $COGSERVER_PID > /dev/null; then
    print_error "CogServer failed to start"
    print_status "Server log:"
    cat /tmp/cogserver_test.log
    exit 1
fi

# Check if server is responding
print_status "Checking server status..."
if ! curl -s -f http://localhost:18080/status > /dev/null; then
    print_error "CogServer is not responding on port 18080"
    print_status "Server log:"
    cat /tmp/cogserver_test.log
    exit 1
fi

print_success "CogServer is running and responding"
echo ""

# Run integration test
print_status "Running integration tests..."
echo ""

if bash scripts/validation/test_cogserver_integration.sh; then
    echo ""
    print_success "All integration tests passed!"
    exit 0
else
    echo ""
    print_error "Integration tests failed"
    print_status "Server log:"
    tail -50 /tmp/cogserver_test.log
    exit 1
fi
