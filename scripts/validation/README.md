# CrystalCog Validation Scripts

This directory contains validation and integration test scripts for the CrystalCog project.

## Overview

The validation scripts ensure that all CrystalCog components are properly configured, dependencies are installed, and the system is functioning correctly. These scripts are used for:

- Pre-deployment validation
- Integration testing
- Dependency verification
- Package validation
- Production readiness checks

## Scripts

### `validate_integration_test.sh` ⭐

**Purpose:** Comprehensive validation of the CogServer integration test suite.

**What it does:**
- Validates all required dependencies are installed
- Checks script functionality and permissions
- Verifies CogServer can be built successfully
- Analyzes test coverage completeness
- Runs functional tests with a live CogServer instance
- Confirms all API endpoints work correctly

**Prerequisites:**
```bash
# Crystal compiler
./scripts/install-crystal.sh

# System dependencies (Ubuntu/Debian)
sudo apt-get install -y curl jq libevent-dev librocksdb-dev libyaml-dev libsqlite3-dev

# Crystal dependencies
shards install
```

**Usage:**
```bash
./scripts/validation/validate_integration_test.sh
```

**Expected Output:**
```
🔄 Package Script Validation: test_cogserver_integration.sh
==========================================================
✅ Checking dependencies...
✅ Validating script functionality...
✅ Checking CogServer build compatibility...
✅ Analyzing script test coverage...
✅ Running functional validation...
✅ Dependency compatibility validation...

🎯 VALIDATION COMPLETE
======================================
✅ Script functionality: VALIDATED
✅ Dependency compatibility: CONFIRMED
✅ Guix environment tests: AVAILABLE
✅ Package documentation: UPDATED
```

**Validated Components:**
- HTTP REST API tests (7 endpoints)
- Telnet command interface tests (4 commands)
- WebSocket protocol tests
- Atom CRUD operation tests
- Error handling validation

### `test_cogserver_integration.sh`

**Purpose:** Integration test suite for CogServer Network API.

**Features Tested:**
- **HTTP Endpoints:**
  - `/status` - Server status
  - `/version` - Version information
  - `/ping` - Health check
  - `/atomspace` - AtomSpace statistics
  - `/atoms` - Atom listing
  - `/sessions` - Active sessions
  - 404 error handling
  
- **Telnet Interface:**
  - `help` command
  - `info` command
  - `atomspace` command
  - `stats` command

- **WebSocket Protocol:**
  - WebSocket upgrade requests
  - Invalid upgrade rejection
  
- **Atom Operations:**
  - Atom creation (POST)
  - Atom verification

**Usage:**
```bash
# Start CogServer in background
crystal run examples/tests/start_test_cogserver.cr &

# Wait for server to start (or check with curl)
sleep 2
curl http://localhost:18080/status

# Run integration tests
./scripts/validation/test_cogserver_integration.sh

# Cleanup
pkill -f start_test_cogserver
```

**Exit Codes:**
- `0` - All tests passed
- `1` - One or more tests failed

### `test_integration.sh`

**Purpose:** General CrystalCog integration tests.

**What it does:**
- Checks for Crystal compiler or pre-built binaries
- Runs Crystal specs
- Tests individual Crystal components
- Validates repository structure

**Usage:**
```bash
./scripts/validation/test_integration.sh
```

### `test_nlp_structure.sh`

**Purpose:** Tests natural language processing structure and components.

**Usage:**
```bash
./scripts/validation/test_nlp_structure.sh
```

### `validate-guix-packages.sh`

**Purpose:** Validates Guix package definitions for reproducible builds.

**Usage:**
```bash
./scripts/validation/validate-guix-packages.sh
```

### `validate-setup-production.sh`

**Purpose:** Validates production environment setup and configuration.

**Usage:**
```bash
./scripts/validation/validate-setup-production.sh
```

## Common Dependencies

All validation scripts require:
- **Bash** 4.0 or higher
- **curl** (for HTTP testing)
- **jq** (for JSON parsing)

CogServer-specific scripts require:
- **Crystal** 1.10.1 or higher
- **libevent-dev** (event-based networking)
- **librocksdb-dev** (persistent storage)
- **libyaml-dev** (YAML configuration)
- **libsqlite3-dev** (database support)

## Installation

### Quick Setup

```bash
# Install Crystal
./scripts/install-crystal.sh

# Install system dependencies (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y \
  curl \
  jq \
  libevent-dev \
  librocksdb-dev \
  libyaml-dev \
  libsqlite3-dev

# Install Crystal dependencies
cd /path/to/crystalcog
shards install
```

### Verify Installation

```bash
# Check all dependencies
./scripts/validation/validate_integration_test.sh
```

## CI/CD Integration

These validation scripts are designed to run in CI/CD pipelines:

```yaml
# Example GitHub Actions usage
- name: Run Integration Validation
  run: ./scripts/validation/validate_integration_test.sh

- name: Run CogServer Tests
  run: |
    crystal run examples/tests/start_test_cogserver.cr &
    sleep 5
    ./scripts/validation/test_cogserver_integration.sh
```

## Troubleshooting

### "Crystal not found"
```bash
# Install Crystal
./scripts/install-crystal.sh --method binary
```

### "curl not found" or "jq not found"
```bash
sudo apt-get install -y curl jq
```

### "cannot find -levent"
```bash
sudo apt-get install -y libevent-dev
```

### "cannot find -lrocksdb"
```bash
sudo apt-get install -y librocksdb-dev
```

### CogServer fails to build
```bash
# Install all dependencies
sudo apt-get install -y \
  libevent-dev \
  librocksdb-dev \
  libyaml-dev \
  libsqlite3-dev

# Reinstall shards
shards install
```

### Tests fail with "Server not responding"
```bash
# Check if server is running
curl http://localhost:18080/status

# Check if port is already in use
lsof -i :18080

# Kill existing processes
pkill -f cogserver
```

## Adding New Validation Scripts

When adding new validation scripts:

1. **Follow naming convention:** `validate_*.sh` or `test_*.sh`
2. **Make executable:** `chmod +x scripts/validation/your_script.sh`
3. **Include help text:** Add usage information in script header
4. **Use exit codes:** 0 for success, non-zero for failure
5. **Add to this README:** Document the new script
6. **Test thoroughly:** Ensure it works in clean environments

## Example Script Template

```bash
#!/bin/bash
# Script description and purpose

set -e  # Exit on error

echo "🔍 Script Name - Validation Starting"
echo "===================================="

# Check dependencies
command -v dependency >/dev/null 2>&1 || { 
  echo "❌ dependency not found"
  exit 1
}

# Run validation logic
echo "✅ Running validation..."

# Report success
echo "🎯 VALIDATION COMPLETE"
exit 0
```

## Validation Matrix

| Script | Crystal | curl | jq | CogServer | Guix |
|--------|---------|------|-------|-----------|------|
| `validate_integration_test.sh` | ✅ | ✅ | ✅ | ✅ | - |
| `test_cogserver_integration.sh` | ✅ | ✅ | ✅ | ✅ | - |
| `test_integration.sh` | ✅ | - | - | - | - |
| `test_nlp_structure.sh` | ✅ | - | - | - | - |
| `validate-guix-packages.sh` | - | - | - | - | ✅ |
| `validate-setup-production.sh` | - | ✅ | - | - | - |

## Contact

For issues with validation scripts:
- Open an issue on the CrystalCog repository
- Tag with `validation` and `scripts` labels
- Include full error output and environment details

## License

AGPL-3.0 - See LICENSE file for details
