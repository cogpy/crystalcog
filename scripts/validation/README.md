# Validation Scripts

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
