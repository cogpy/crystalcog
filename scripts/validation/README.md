# CrystalCog Validation Scripts

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
