# CrystalCog Validation Scripts

This directory contains validation scripts for testing and verifying CrystalCog components.

## Available Scripts

### `test_cogserver_integration.sh` - CogServer Network API Integration Test

Tests the CogServer Network API functionality including HTTP REST endpoints, telnet interface, WebSocket protocol, and atom operations.

**Prerequisites:**
- Crystal compiler installed
- `curl` command-line tool
- `jq` JSON processor
- CogServer must be running on localhost:18080 (HTTP) and localhost:17001 (Telnet)

**Usage:**
```bash
./test_cogserver_integration.sh
```

**What it tests:**
- ✅ HTTP REST API endpoints (7 endpoints)
  - Status endpoint (`/status`)
  - Version endpoint (`/version`)
  - Ping endpoint (`/ping`)
  - AtomSpace endpoint (`/atomspace`)
  - Atoms endpoint (`/atoms`)
  - Sessions endpoint (`/sessions`)
  - 404 error handling
- ✅ Telnet command interface (4 commands)
  - Help command
  - Info command
  - AtomSpace command
  - Stats command
- ✅ WebSocket protocol
  - WebSocket upgrade handshake
  - Invalid upgrade rejection
- ✅ Atom CRUD operations
  - Create atom via POST
  - Verify atom existence

**Starting the test server:**
```bash
# From repository root
DISABLE_ROCKSDB=1 crystal run examples/tests/start_test_cogserver.cr
```

**Example output:**
```
🧪 CogServer Network API Integration Test
📡 Testing server endpoints on localhost:18080...

🔍 Testing HTTP Endpoints:
   📊 Status endpoint...
      ✅ Status endpoint working
   📋 Version endpoint...
      ✅ Version endpoint working
...
✨ Integration test completed successfully!
```

**Validation Status:**
- ✅ Script functionality validated
- ✅ All test categories passing (5/5)
- ✅ Dependency compatibility confirmed
- ✅ Error handling robust with graceful fallbacks

### `validate_integration_test.sh` - Comprehensive Validation Test

Meta-validation script that validates the `test_cogserver_integration.sh` script itself. This ensures the integration test meets all quality requirements.

**Prerequisites:**
- Crystal compiler installed
- All dependencies from `test_cogserver_integration.sh`

**Usage:**
```bash
# From repository root
./scripts/validation/validate_integration_test.sh
```

**What it validates:**
1. **Dependency Checking**
   - Verifies `curl`, `jq`, and `crystal` are available
   - Reports version information

2. **Script Functionality**
   - Confirms script exists and is executable
   - Validates test coverage categories

3. **Build Compatibility**
   - Builds CogServer with DISABLE_ROCKSDB=1 flag
   - Verifies successful compilation

4. **Test Coverage Analysis**
   - HTTP REST API tests
   - Telnet command interface tests
   - WebSocket protocol tests
   - Atom CRUD operation tests
   - Error handling validation

5. **Functional Validation**
   - Starts CogServer for testing
   - Executes integration test script
   - Verifies all endpoints respond correctly
   - Confirms success messages and feature summaries

**Example output:**
```
🔄 Package Script Validation: test_cogserver_integration.sh
✅ Checking dependencies...
   • curl: curl 8.5.0
   • jq: jq-1.7
   • crystal: Crystal 1.10.1

✅ Validating script functionality...
   • Script exists and is executable

✅ Checking CogServer build compatibility...
   • Building CogServer...
   • CogServer built successfully

✅ Analyzing script test coverage...
   • HTTP REST API tests: ✓
   • Telnet command interface tests: ✓
   • WebSocket protocol tests: ✓
   • Atom CRUD operation tests: ✓
   • Error handling validation: ✓
   • Total test categories: 5/5

✅ Running functional validation...
   • CogServer is ready after 7 seconds ✓
   • Integration test PASSED ✓

🎯 VALIDATION COMPLETE
This directory contains validation and integration test scripts for the CrystalCog project.

## Available Scripts

### CogServer Integration Testing

#### `test_cogserver_integration.sh`
Comprehensive integration test for the CogServer Network API.

**Tests**:
- HTTP REST API endpoints (7 endpoints)
- Telnet command interface (4 commands)
- WebSocket protocol upgrade
- Atom CRUD operations
- Error handling and validation

**Usage**:
```bash
# Requires a running CogServer instance on localhost:17001 (telnet) and localhost:18080 (HTTP/WebSocket)
./scripts/validation/test_cogserver_integration.sh
```

**Prerequisites**:
- CogServer must be running before executing the test
- `jq` utility must be installed for JSON parsing
- `curl` must be available for HTTP requests

#### `run_cogserver_integration_test.sh` (Recommended)
Automated wrapper that builds the CogServer, starts it, runs the integration tests, and cleans up.

**Usage**:
```bash
# This is the easiest way to run the integration tests
./scripts/validation/run_cogserver_integration_test.sh
```

**What it does**:
1. Verifies Crystal is installed
2. Installs Crystal dependencies (shards)
3. Builds the cogserver binary
4. Starts the cogserver in the background
5. Waits for server initialization
6. Runs the integration test suite
7. Stops the cogserver and cleans up

**Exit codes**:
- 0: All tests passed
- 1: Tests failed or server didn't start

### Other Validation Scripts

#### `test_integration.sh`
General integration testing script.

#### `test_nlp_structure.sh`
Natural language processing structure validation.

#### `validate-guix-packages.sh`
Validates Guix package definitions.

#### `validate-setup-production.sh`
Validates production environment setup.

#### `validate_integration_test.sh`
General integration test validation.

#### `test_comprehensive_test_gates.py`
Checks that `.github/workflows/comprehensive-tests.yml` fails closed. The workflow shell uses
`errexit` and `pipefail`; component, integration and full-suite spec steps return the real
Crystal status, the full suite keeps its log and summary on failure, binary verification
fails on any missing or failed target, and the aggregate status rejects failed, skipped or
cancelled jobs. A stub `crystal` returns statuses 0, 1 and 42, so this tests workflow wiring,
not Crystal compilation or spec behavior. Run with `python3 -m pip install PyYAML==6.0.2`
and `python3 scripts/validation/test_comprehensive_test_gates.py`. Validate Scripts runs it
when this workflow changes.

## Test Requirements

### System Dependencies
- Crystal 1.10.1 or later
- jq (JSON processor)
- curl (HTTP client)
- libevent-dev (for Crystal HTTP server)

### Crystal Dependencies
- sqlite3 (database support)
- pg (PostgreSQL support)
- db (database abstraction)

## Running Tests

### Quick Start
```bash
# Run all cogserver integration tests (easiest method)
./scripts/validation/run_cogserver_integration_test.sh
```

### Manual Testing
```bash
# 1. Install Crystal if needed
./scripts/install-crystal.sh

# 2. Install dependencies
shards install

# 3. Build cogserver
DISABLE_ROCKSDB=1 crystal build src/cogserver/cogserver_main.cr -o cogserver_bin

# 4. Start cogserver in background
./cogserver_bin &
COGSERVER_PID=$!

# 5. Wait for initialization
sleep 5

# 6. Run integration test
./scripts/validation/test_cogserver_integration.sh

# 7. Stop cogserver
kill $COGSERVER_PID
```

### CI/CD Integration
```bash
# For automated CI/CD pipelines
./scripts/validation/run_cogserver_integration_test.sh
```

## Test Results

See [COGSERVER_INTEGRATION_VALIDATION.md](../../docs/COGSERVER_INTEGRATION_VALIDATION.md) for detailed validation results and performance metrics.

## Troubleshooting

### Server Won't Start
- Check if ports 17001 and 18080 are available
- Verify libevent-dev is installed: `sudo apt-get install libevent-dev`
- Check server logs in `/tmp/cogserver_test.log`

### Build Failures
- Ensure Crystal is properly installed: `crystal --version`
- Install dependencies: `shards install`
- For RocksDB issues, use: `DISABLE_ROCKSDB=1` before the build command

### Test Failures
- Ensure cogserver is running: `curl http://localhost:18080/status`
- Check if jq is installed: `which jq`
- Verify network connectivity to localhost
This directory contains validation and testing scripts for the CrystalCog project. These scripts ensure that the Crystal implementation of the OpenCog framework is functioning correctly and meets all quality standards.

## Overview

The validation scripts perform comprehensive testing of:
- Crystal compiler installation and compatibility
- Project dependencies (shards)
- Repository structure integrity
- Core CrystalCog components
- Integration tests
- Guix environment compatibility
- Package documentation

## Scripts

### test_integration.sh

**Purpose**: Comprehensive integration testing of CrystalCog components

**What it validates**:
1. ✓ Crystal compiler installation
2. ✓ Dependency compatibility (shards)
3. ✓ Repository structure (required directories and files)
4. ✓ Crystal specs execution
5. ✓ Individual component tests (basic, attention, pattern matching)
6. ✓ Guix environment configuration
7. ✓ Package documentation completeness
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
bash scripts/validation/test_integration.sh
```

**Exit codes**:
- `0`: Validation passed (≥80% success rate)
- `0`: Partial validation (50-79% success rate)  
- `1`: Validation failed (<50% success rate)

**Output format**:
- Color-coded status messages (INFO, SUCCESS, WARNING, ERROR)
- Test tracking (passed/failed/skipped)
- Success rate percentage
- Comprehensive validation checklist

**Example output**:
```
=== CrystalCog Integration Test ===
Testing Crystal implementation components and dependencies

1. Checking prerequisites...
[SUCCESS] Crystal compiler found: Crystal 1.10.1 [c6f3552f5] (2023-10-13)

...

=== Integration Test Complete ===
Total: 19 tests (18 passed, 0 failed, 1 skipped)
Success rate: 100%
[SUCCESS] Integration validation PASSED ✓
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
✅ Checking dependencies...
✅ Validating script functionality...
✅ Checking CogServer build compatibility...
✅ Analyzing script test coverage...
✅ Running functional validation...
✅ Dependency compatibility validation...
🎯 VALIDATION COMPLETE
```

### test_cogserver_integration.sh

**Purpose**: Validates CogServer network API functionality

**What it tests**:
- HTTP REST API endpoints
- Telnet command interface
- WebSocket protocol support
- Atom CRUD operations
- Error handling and 404 responses

**Usage**:
```bash
bash scripts/validation/test_cogserver_integration.sh
```

### validate_integration_test.sh

**Purpose**: Meta-validation script that validates the integration test itself

**What it checks**:
- Test script structure and completeness
- Required test categories present
- CogServer build compatibility
- Functional execution verification

**Usage**:
```bash
bash scripts/validation/validate_integration_test.sh
```

### test_nlp_structure.sh

**Purpose**: Validates natural language processing components

**What it tests**:
- NLP module structure
- Tokenization functionality
- Linguistic atom creation
- Text processing capabilities

### validate-guix-packages.sh

**Purpose**: Validates Guix package definitions and environment

**What it checks**:
- Guix package definition syntax
- Required dependencies
- Build reproducibility
- Environment isolation

## Test Files

The validation scripts test the following example files in `examples/tests/`:

- `test_basic.cr` - Core AtomSpace and OpenCog functionality
- `test_attention_simple.cr` - Attention allocation system
- `test_pattern_matching.cr` - Pattern matching engine

## Requirements

### System Requirements
- Crystal compiler (1.10.1 or later)
- Shards package manager
- Bash 4.0 or later
- ANSI color support (for colored output)

### Optional Requirements
- Guix package manager (for Guix environment tests)
- curl and jq (for CogServer API tests)

## Continuous Integration

These validation scripts are designed to run in CI/CD pipelines. They provide:
- Clear exit codes for automation
- Structured output for logging
- Graceful handling of missing dependencies
- Progressive validation (continues even if some tests fail)

## Development Workflow

### Running All Validations
```bash
# Run integration tests
bash scripts/validation/test_integration.sh

# Run CogServer tests (requires running server)
bash scripts/validation/test_cogserver_integration.sh

# Run NLP validation
bash scripts/validation/test_nlp_structure.sh
```

### Interpreting Results

**Success indicators**:
- Green `[SUCCESS]` messages
- Exit code 0
- Success rate ≥80%

**Warning indicators**:
- Yellow `[WARNING]` messages  
- Skipped tests (may be expected)
- Success rate 50-79%

**Failure indicators**:
- Red `[ERROR]` messages
- Exit code 1
- Success rate <50%

## Troubleshooting

### Crystal not found
```bash
# Install Crystal using the provided script
bash scripts/install-crystal.sh
```

### Dependencies not installed
```bash
# Install shards dependencies
cd /path/to/crystalcog
shards install
```

### Test file path errors
Ensure test files use correct relative paths from their location:
```crystal
# Correct: from examples/tests/
require "../../src/cogutil/cogutil"

# Incorrect:
require "./src/cogutil/cogutil"
```

### Spec compilation errors
Some specs may have syntax issues or missing dependencies. The integration test continues with other tests and reports the success rate.

## Maintenance

### Adding New Validation Tests

1. Create a new test script in `scripts/validation/`
2. Follow the naming convention: `test_*.sh` or `validate_*.sh`
3. Use colored output functions from existing scripts
4. Track test results (passed/failed/skipped)
5. Provide clear success/failure messages
6. Update this README

### Updating Existing Tests

1. Maintain backward compatibility
2. Update test tracking counters
3. Add new validation checks at the end
4. Update documentation
5. Test in both CI and local environments

## Issue Tracking

This validation framework was created to address:
- **Issue**: Package Script Updated: scripts/validation/test_integration.sh - Validation Required
- **Priority**: High
- **Status**: ✓ Resolved

**Validation requirements met**:
- [x] Validate script functionality
- [x] Check dependency compatibility
- [x] Run Guix environment tests
- [x] Update package documentation

## Contributing

When contributing new validation scripts:

1. Follow the existing pattern for colored output
2. Track test results (TESTS_PASSED, TESTS_FAILED, TESTS_SKIPPED)
3. Provide clear, actionable error messages
4. Include usage examples in comments
5. Update this README
6. Test in multiple environments

## References

- CrystalCog main documentation: `/docs/`
- Crystal language: https://crystal-lang.org/
- Shards package manager: https://github.com/crystal-lang/shards
- Guix package manager: https://guix.gnu.org/

## License

AGPL-3.0 - See LICENSE file in repository root.
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

**Validation Status:**
- ✅ Meta-validation complete
- ✅ All quality gates passing
- ✅ Documentation updated

### `test_integration.sh` - General Integration Test

Tests Crystal implementation components including specs and example tests.

**Usage:**
```bash
./test_integration.sh
```

### `test_nlp_structure.sh` - NLP Structure Test

Validates Natural Language Processing component structure and functionality.

**Usage:**
```bash
./test_nlp_structure.sh
```

### `validate-guix-packages.sh` - Guix Package Validation

Validates Guix package definitions and dependencies for the Agent-Zero ecosystem.

**Usage:**
```bash
./validate-guix-packages.sh
```

### `validate-setup-production.sh` - Production Setup Validation

Validates production deployment setup and configuration.

**Usage:**
```bash
./validate-setup-production.sh
```

## Running All Validation Tests

To run all validation tests:

```bash
# From repository root
for script in scripts/validation/*.sh; do
    echo "Running: $script"
    bash "$script"
done
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

These validation scripts are designed to work in CI/CD environments:
- Exit code 0 indicates success
- Exit code non-zero indicates failure
- Detailed output for debugging
- Graceful handling of missing dependencies

## Troubleshooting

### CogServer won't start
```bash
# Check if Crystal is installed
crystal --version

# Try building with DISABLE_ROCKSDB flag
DISABLE_ROCKSDB=1 crystal build src/cogserver/cogserver_main.cr -o cogserver

# Start the server manually
./cogserver
```

### Tests fail with connection errors
```bash
# Ensure CogServer is running first
DISABLE_ROCKSDB=1 crystal run examples/tests/start_test_cogserver.cr &

# Wait for server to be ready (check logs)
sleep 5

# Then run tests
./scripts/validation/test_cogserver_integration.sh
```

### Missing dependencies
```bash
# Install jq (Ubuntu/Debian)
sudo apt-get install jq

# Install curl (usually pre-installed)
sudo apt-get install curl

# Install Crystal
./scripts/install-crystal.sh --method auto
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
1. Follow the naming convention: `test_*.sh` or `validate_*.sh`
2. Make scripts executable: `chmod +x scripts/validation/your_script.sh`
3. Add comprehensive error handling
4. Provide clear output with ✅ and ❌ indicators
5. Update this README with script documentation
6. Ensure scripts work in CI/CD environments
2. Add appropriate error handling with `set -e`
3. Include colored output for better readability
4. Document the script in this README
5. Make scripts executable: `chmod +x script_name.sh`
6. Test thoroughly before committing

## Documentation

For detailed validation reports and results:
- [CogServer Integration Validation](../../docs/COGSERVER_INTEGRATION_VALIDATION.md)
- [Development Roadmap](../../docs/DEVELOPMENT-ROADMAP.md)
- [Main README](../../README.md)

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
