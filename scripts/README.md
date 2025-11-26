# CrystalCog Scripts

This directory contains utility scripts for the CrystalCog project.

## Available Scripts

### `validation/test_nlp_structure.sh` - NLP Module Structure Validation
Comprehensive validation script for the Natural Language Processing (NLP) module structure, dependencies, and integration.

**Purpose:**
- Validates all NLP module files exist and are properly structured
- Checks module definitions and method signatures
- Verifies dependency compatibility (CogUtil, AtomSpace, PLN, URE)
- Validates integration with reasoning systems
- Ensures Guix environment compatibility

**Usage:**
```bash
# Must be run from repository root
cd /path/to/crystalcog
bash scripts/validation/test_nlp_structure.sh
```

**What It Validates:**
- **Core NLP Files (9):**
  - `nlp.cr` - Main NLP module
  - `tokenizer.cr` - Text tokenization
  - `text_processor.cr` - Text normalization and processing
  - `linguistic_atoms.cr` - Linguistic knowledge representation
  - `nlp_main.cr` - CLI interface
  - `link_grammar.cr` - Link Grammar parsing integration
  - `dependency_parser.cr` - Dependency tree parsing
  - `language_generation.cr` - Natural language generation
  - `semantic_understanding.cr` - Semantic analysis

- **Test Files (7):**
  - Basic module tests (nlp_spec.cr, tokenizer_spec.cr, etc.)
  - Advanced integration tests (link_grammar_spec.cr, language_processing_capabilities_spec.cr)

- **Dependencies:**
  - CogUtil (logging, configuration)
  - AtomSpace (knowledge representation)
  - Cross-module dependencies (LinkGrammar → DependencyParser → SemanticUnderstanding)

- **Integration Points:**
  - Main file integration (src/crystalcog.cr)
  - Spec helper integration (spec/spec_helper.cr)
  - Reasoning system integration (PLN/URE compatibility)
  - Guix package manifest configuration

**Validation Status:**
- ✅ All 9 core NLP module files validated
- ✅ All 7 test files validated
- ✅ Dependency graph fully validated
- ✅ Cross-module dependencies verified
- ✅ Guix environment compatibility confirmed
- ✅ Reasoning system integration validated
- ✅ Advanced NLP features (Link Grammar, Dependency Parsing, Language Generation, Semantic Understanding) verified

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