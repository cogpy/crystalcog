# Validation Scripts
# CrystalCog Validation Scripts

This directory contains validation and integration test scripts for the CrystalCog project.

## Overview

The validation scripts ensure that all components of the CrystalCog system are functioning correctly and meet the specified requirements.

## Scripts

### validate_integration_test.sh

**Purpose**: Comprehensive validation of the CogServer integration test script.

**What it validates**:
- ✅ Script functionality
- ✅ Dependency compatibility (curl, jq, crystal)
- ✅ CogServer build compatibility
- ✅ Test coverage across all categories
- ✅ Functional integration testing

**Usage**:
```bash
cd /path/to/crystalcog
bash scripts/validation/validate_integration_test.sh
```

**Requirements**:
- Crystal 1.10.1 or higher
- curl (for HTTP API testing)
- jq (for JSON parsing)
- librocksdb-dev (for storage backends)
- libevent-dev (for network server)

**Expected Output**:
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
```

### test_cogserver_integration.sh

**Purpose**: Integration testing for CogServer Network API.

**Test Categories**:
1. **HTTP REST API Endpoints** (7 endpoints)
   - Status, Version, Ping, AtomSpace, Atoms, Sessions
   - 404 error handling

2. **Telnet Command Interface** (4 commands)
   - Help, Info, AtomSpace, Stats

3. **WebSocket Protocol**
   - Valid upgrade requests
   - Invalid upgrade rejection

4. **Atom CRUD Operations**
   - Create, Read, Verify atoms

5. **Error Handling**
   - HTTP status codes
   - JSON validation
   - Protocol compliance

**Usage**:
```bash
# Start CogServer first
crystal run examples/tests/start_test_cogserver.cr &

# Run integration tests
bash scripts/validation/test_cogserver_integration.sh

# Cleanup
killall start_test_cogserver
```

### test_nlp_structure.sh

**Purpose**: Validation of Natural Language Processing structure and components.

**Usage**:
```bash
bash scripts/validation/test_nlp_structure.sh
```

### validate-guix-packages.sh

**Purpose**: Validation of Guix package definitions and environment compatibility.

**Usage**:
```bash
bash scripts/validation/validate-guix-packages.sh
```

### validate-setup-production.sh

**Purpose**: Validation of production deployment setup and configuration.

**Usage**:
```bash
bash scripts/validation/validate-setup-production.sh
```

## Dependencies Installation

### Install Crystal

```bash
bash scripts/install-crystal.sh
```

### Install System Dependencies

On Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y \
    librocksdb-dev \
    libevent-dev \
    libsqlite3-dev \
    libpq-dev \
    curl \
    jq
```

### Install Crystal Dependencies

```bash

🎯 VALIDATION COMPLETE
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

## Continuous Integration

These validation scripts are designed to be run as part of the CI/CD pipeline to ensure code quality and functionality.

### GitHub Actions Integration

The validation scripts are integrated into the GitHub Actions workflow:

```yaml
- name: Validate Integration Tests
  run: bash scripts/validation/validate_integration_test.sh
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

### CogServer fails to start

**Issue**: CogServer binary not found or fails to compile

**Solution**:
```bash
# Build CogServer manually
crystal build src/cogserver/cogserver_main.cr -o cogserver_bin

# Check for compilation errors
crystal build src/cogserver/cogserver_main.cr --error-trace
```

### Missing dependencies

**Issue**: curl, jq, or crystal not found

**Solution**:
```bash
# Install missing tools
sudo apt-get install curl jq

# Install Crystal
bash scripts/install-crystal.sh
```

### RocksDB linking errors

**Issue**: Cannot find -lrocksdb

**Solution**:
```bash
sudo apt-get install librocksdb-dev
```

### Test server path issues

**Issue**: Cannot find cogserver_main.cr

**Solution**: Ensure you're running scripts from the repository root:
```bash
cd /path/to/crystalcog
bash scripts/validation/validate_integration_test.sh
```

## Contributing

When adding new validation scripts:

1. Make the script executable: `chmod +x script_name.sh`
2. Add comprehensive error handling with `set -e`
3. Use colored output for better readability
4. Document all requirements and dependencies
5. Include usage examples in this README
6. Add validation for all critical paths
7. Ensure the script can be run from the repository root

## Documentation

For more details, see:
- [CogServer Integration Test Validation](../../docs/COGSERVER_INTEGRATION_TEST_VALIDATION.md)
- [Validation Summary](../../docs/VALIDATION_SUMMARY.md)
- [Test Automation Validation Report](../../docs/TEST_AUTOMATION_VALIDATION_REPORT.md)

## Success Metrics

A successful validation run should show:
- ✅ All dependencies available
- ✅ CogServer builds successfully
- ✅ All test categories passing (5/5)
- ✅ Integration tests execute without errors
- ✅ All API endpoints responding correctly

## License

These scripts are part of the CrystalCog project and are licensed under AGPL-3.0.
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
