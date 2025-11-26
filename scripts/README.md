# CrystalCog Scripts

This directory contains utility scripts for the CrystalCog project.

## Available Scripts

### `test-runner.sh` - Comprehensive Test Runner
A comprehensive testing script that provides local development testing capabilities matching the CI/CD pipeline.

**Usage:**
```bash
./test-runner.sh [OPTIONS]

Options:
  -h, --help          Show help message
  -v, --verbose       Run tests with verbose output
  -c, --coverage      Generate coverage reports  
  -b, --benchmarks    Run performance benchmarks
  -i, --integration   Run integration tests
  -l, --lint          Run code linting and formatting checks
  -B, --build         Build all targets before testing
  -C, --component     Run tests for specific component
  -a, --all          Run all tests (comprehensive)
```

**Examples:**
```bash
# Run complete test suite
./test-runner.sh --all

# Run unit tests with linting
./test-runner.sh --lint --verbose

# Test specific component
./test-runner.sh --component atomspace

# Run benchmarks only
./test-runner.sh --benchmarks

# Build and test with integration tests
./test-runner.sh --build --integration
```

**Validation Status:**
- ✅ Script functionality validated on Crystal 1.11.2
- ✅ All test modes working correctly (unit, integration, benchmarks, coverage)
- ✅ Component-specific testing operational
- ✅ Build process working with proper target naming
- ✅ Error handling improved for problematic spec files
- ✅ Dependencies cleaned up and working correctly

## Validation Scripts

### `validation/test_integration.sh` - Crystal Integration Test
Validates the CrystalCog Crystal implementation with comprehensive checks.

**Usage:**
```bash
./scripts/validation/test_integration.sh
```

**Features:**
- ✅ Crystal compiler and dependencies validation
- ✅ Crystal spec suite execution with error handling
- ✅ Individual component test execution
- ✅ Dependency compatibility checks
- ✅ Guix environment validation
- ✅ Proper exit codes on test failures
- ✅ Graceful handling of incomplete implementations

**Validation Checks:**
1. Prerequisites (Crystal, Shards, libevent)
2. Crystal specs compilation and execution
3. Individual component tests (test_basic.cr, test_attention_simple.cr, test_pattern_matching.cr)
4. Dependency compatibility (shard.yml, shard.lock, installed dependencies)
5. Guix environment configuration (guix.scm, .guix-channel)
6. Repository structure and symlinks

**Exit Codes:**
- 0: All tests passed or skipped (expected during development)
- 1: One or more critical tests failed

**Validation Status:**
- ✅ Script functionality validated and improved
- ✅ Proper error detection and reporting
- ✅ Dependency checking implemented
- ✅ Guix environment validation added
- ✅ Test result tracking and summary

### `validation/test_cogserver_integration.sh` - CogServer API Test
Tests the CogServer network API functionality.

### `validation/test_nlp_structure.sh` - NLP Structure Validation
Validates the natural language processing component structure.

### `validation/validate-guix-packages.sh` - Guix Package Validation
Validates Guix package definitions and manifest files.

### `validation/validate-setup-production.sh` - Production Setup Validation
Validates production deployment configuration.

### `validation/validate_integration_test.sh` - Integration Test Validator
Meta-validator that tests the integration testing framework itself.

### `generate-system-image.sh` - Agent-Zero System Image Generation
Generates bootable system images for the Agent-Zero Genesis cognitive operating system using Guix.

**Prerequisites:**
- Guix package manager must be installed
- Agent-Zero build must be completed first (`make agent-zero`)

**Usage:**
```bash
./generate-system-image.sh [OPTIONS] [IMAGE_TYPE] [OUTPUT_NAME]

IMAGE_TYPE:
  disk-image    Generate a disk image (default)
  vm-image      Generate a VM image  
  iso-image     Generate an ISO image

OUTPUT_NAME:
  Custom name for the output image (default: agent-zero-system)

OPTIONS:
  --minimal     Use minimal configuration for faster builds
  --help        Show this help message
```

**Examples:**
```bash
# Generate default disk image
./generate-system-image.sh

# Generate VM image with custom name
./generate-system-image.sh vm-image agent-zero-vm

# Generate minimal disk image for testing
./generate-system-image.sh --minimal disk-image

# Generate ISO image
./generate-system-image.sh iso-image agent-zero-live
```

**Makefile Integration:**
```bash
# Build Agent-Zero and generate system image
make agent-zero-image

# Generate VM image
make agent-zero-vm-image

# Generate ISO image  
make agent-zero-iso-image

# Generate minimal image for testing
make agent-zero-minimal-image
```

**Validation Status:**
- ✅ Script functionality validated and tested
- ✅ Proper error handling for missing Guix dependency
- ✅ Integration with existing Agent-Zero build system
- ✅ Support for multiple image types (disk, VM, ISO)
- ✅ Makefile targets configured and working

### `build-monorepo.sh` - Monorepo Build Script
Legacy build script for the monorepo structure (primarily C++ components).

### `demo-monorepo.sh` - Monorepo Demo Script  
Interactive demo script for the monorepo build system.

## Production Scripts

### `production/` Directory
Contains production deployment and management scripts:

- **`healthcheck.sh`** - Comprehensive health monitoring for all CrystalCog services
- **`deploy.sh`** - Production deployment with Docker Compose orchestration  
- **`setup-production.sh`** - Initial production environment setup

See [production/README.md](production/README.md) for detailed documentation.

**Key Features:**
- ✅ Automated health monitoring with graceful fallbacks
- ✅ Docker-based deployment with rollback capabilities
- ✅ Guix environment compatibility
- ✅ Robust error handling and monitoring
- ✅ Integration with CI/CD pipelines

## CI/CD Integration

The test-runner.sh script is designed to mirror the CI/CD pipeline behavior locally:
- Same test execution order
- Same component organization
- Compatible output formats
- Matching quality gates

This allows developers to run the same tests locally that will run in the CI/CD pipeline.

## Script Permissions

Make sure scripts are executable:
```bash
chmod +x scripts/*.sh
```

## Adding New Scripts

When adding new utility scripts:
1. Make them executable (`chmod +x`)
2. Include appropriate error handling
3. Provide help/usage information
4. Update this README
5. Follow existing naming conventions