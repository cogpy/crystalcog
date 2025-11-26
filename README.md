


# CrystalCog - OpenCog in Crystal Language

CrystalCog is a comprehensive rewrite of the OpenCog artificial intelligence framework in the Crystal programming language. This project provides better performance, memory safety, and maintainability while preserving all the functionality of the original OpenCog system.

## Quick Start

### Prerequisites

CrystalCog automatically handles Crystal language installation. No manual setup required!

### Installation

1. Clone the repository:
```bash
git clone https://github.com/EchoCog/crystalcog.git
cd crystalcog
```

2. Run tests (Crystal will be installed automatically):
```bash
./scripts/test-runner.sh --all
```

3. Install Crystal manually (optional):
```bash
./scripts/install-crystal.sh --help
./scripts/install-crystal.sh  # Auto-install
```

## Crystal Language Installation

CrystalCog includes robust Crystal installation methods for environments where standard installation may not work:

- **Automatic Installation**: Scripts automatically install Crystal when needed
- **Multiple Methods**: Snap, APT, binary, and source installation options
- **Offline Support**: Works without internet access using bundled resources
- **Development Mode**: Fallback wrappers for development environments

For detailed installation instructions, see: [docs/CRYSTAL_INSTALLATION.md](docs/CRYSTAL_INSTALLATION.md)

## Project Structure

```
crystalcog/
├── src/                    # Crystal source code
│   ├── cogutil/           # Core utilities (logging, config, random)
│   ├── atomspace/         # AtomSpace hypergraph knowledge representation
│   ├── pln/               # Probabilistic Logic Networks
│   ├── ure/               # Unified Rule Engine
│   ├── opencog/           # Main OpenCog reasoning interface
│   ├── cogserver/         # Network server with REST API
│   ├── pattern_matching/  # Advanced pattern matching engine
│   ├── nlp/               # Natural language processing
│   ├── moses/             # Evolutionary optimization
│   ├── agent-zero/        # Distributed agent networks
│   └── ...                # Additional components
├── spec/                  # Formal test specifications (Crystal spec framework)
├── examples/              # Example programs and demos
│   ├── demos/            # Interactive demonstrations
│   └── tests/            # Test programs and debugging utilities
├── benchmarks/           # Performance benchmarking programs
├── scripts/              # Build, deployment, and development scripts
│   ├── validation/       # Validation and integration test scripts
│   └── production/       # Production deployment scripts
├── docs/                 # Comprehensive documentation
│   └── INDEX.md         # Documentation index
└── crystal-lang/         # Crystal installation resources
```

## Development

### Running Tests

The test runner script provides comprehensive testing capabilities with automatic Crystal installation:

```bash
# Run all tests
./scripts/test-runner.sh --all

# Run specific component tests
./scripts/test-runner.sh --component atomspace

# Run with linting and formatting
./scripts/test-runner.sh --lint

# Run benchmarks
./scripts/test-runner.sh --benchmarks

# Show all available options
./scripts/test-runner.sh --help
```

**Note**: The test runner has been validated and approved for production use. See [Test Runner Validation Report](docs/TEST_RUNNER_VALIDATION_REPORT.md) for detailed validation results.

### Building

```bash
# Build main executable
crystal build src/crystalcog.cr

# Build specific components
crystal build src/cogutil/cogutil.cr
crystal build src/atomspace/atomspace.cr
```

### Installing Dependencies

```bash
shards install
```

### Testing

#### Running the Test Suite

```bash
# Run all formal specifications
crystal spec

# Run specific component specs
crystal spec spec/atomspace/
crystal spec spec/pln/
crystal spec spec/cogutil/
```

#### Example Programs

```bash
# Run basic examples
crystal run examples/tests/test_basic.cr
crystal run examples/tests/test_pln.cr

# Run demonstrations
crystal run examples/demos/demo.cr
crystal run examples/demos/demo_advanced_reasoning.cr

# See examples/README.md for complete catalog
```

#### CogServer Integration Test

The CogServer includes a comprehensive integration test that validates all network API functionality:

```bash
# Build the CogServer
crystal build src/cogserver/cogserver_main.cr -o cogserver_bin

# Start CogServer for testing
crystal run examples/tests/start_test_cogserver.cr &

# Run integration test script
./scripts/validation/test_cogserver_integration.sh
```

The integration test validates:
- HTTP REST API endpoints (7 endpoints)
- Telnet command interface (4 commands)
- WebSocket protocol upgrade
- Atom CRUD operations
- Error handling and validation

#### Full Test Suite

```bash
# Run all Crystal specs
crystal spec

# Run example test programs
crystal run examples/tests/test_cogserver_api.cr
crystal run examples/tests/test_enhanced_api.cr
crystal run examples/tests/test_persistence.cr

# See examples/README.md for all available test programs
```

## Components

CrystalCog implements the complete OpenCog stack:

- **CogUtil**: Core utilities and logging
- **AtomSpace**: Hypergraph knowledge representation with comprehensive persistence
- **PLN**: Probabilistic Logic Networks for reasoning
- **URE**: Unified Rule Engine for inference
- **CogServer**: Network server for distributed processing with REST API
- **Pattern Matching**: Advanced pattern matching and query engine with recursive composition, temporal analysis, machine learning, and statistical inference
- **Persistence**: Multiple storage backends (File, SQLite, Network)
- **Cognitive Kernels**: Agent-Zero Genesis cognitive processing units with hypergraph state persistence
- **Tensor Field Encoding**: Mathematical sequence generators for cognitive state representation

### Key Features

#### AtomSpace Persistence
- **RocksDB Storage**: High-performance key-value storage (0.9ms store, 0.5ms load)
- **PostgreSQL Storage**: Enterprise-grade database for production and multi-user access
- **SQLite Storage**: Relational database with indexing for medium datasets  
- **File Storage**: Human-readable Scheme format for small datasets and debugging
- **Network Storage**: Distributed AtomSpace access via CogServer
- **Multiple Storage**: Attach multiple backends for redundancy and performance
- **Hypergraph State Persistence**: Complete cognitive kernel state management

#### Cognitive Kernel System (Agent-Zero Genesis)
- **Cognitive Kernels**: Complete cognitive processing units with state persistence
- **Tensor Field Encoding**: Mathematical sequence generators (prime, fibonacci, harmonic, factorial, powers of two)
- **Attention Allocation**: Adaptive priority management across multiple kernels
- **Meta-Cognitive Processing**: Recursive self-description and meta-level tracking
- **Operation-Specific Encodings**: Specialized tensor configurations for reasoning, learning, memory, attention

#### Enhanced Network API
- **REST Endpoints**: Complete HTTP API for AtomSpace operations
- **Storage Management**: Attach/detach storage via REST API
- **WebSocket Support**: Real-time communication capabilities
- **Session Management**: Track client connections and state

#### Example Usage
```crystal
# Create AtomSpace with persistence
atomspace = AtomSpace::AtomSpace.new

# Add some knowledge
dog = atomspace.add_concept_node("dog")
animal = atomspace.add_concept_node("animal") 
atomspace.add_inheritance_link(dog, animal)

# Save to high-performance RocksDB storage
rocksdb_storage = atomspace.create_rocksdb_storage("main", "knowledge.rocks")
rocksdb_storage.open
rocksdb_storage.store_atomspace(atomspace)

# Or use PostgreSQL for production/enterprise
postgres_storage = atomspace.create_postgres_storage("prod", "user:pass@localhost/opencog")

# Or traditional file storage for debugging
file_storage = atomspace.create_file_storage("debug", "knowledge.scm")
file_storage.open
file_storage.store_atomspace(atomspace)

# Create cognitive kernel with hypergraph state persistence
kernel = AtomSpace::CognitiveKernel.new([128, 64], 0.8, 1, "reasoning")
kernel.add_concept_node("agent-zero")

# Store complete cognitive state
hypergraph_storage = kernel.atomspace.create_hypergraph_storage("cognitive", "state.scm")
hypergraph_storage.open
kernel.store_hypergraph_state(hypergraph_storage)

# Generate tensor field encodings
prime_encoding = kernel.tensor_field_encoding("prime", include_attention: true)
hypergraph_encoding = kernel.hypergraph_tensor_encoding

# Save via REST API
curl -X POST http://localhost:18080/storage/save
```

## Validation & Dependency Checking

CrystalCog includes comprehensive validation scripts to ensure your environment is correctly configured:

### Profiling Tools Validation

Validate that all performance profiling tools are correctly installed and functional:

```bash
# Run the profiling tools validation
./scripts/validation/validate_profiling_tools.sh
```

This validates:
- All 9 profiling tool files exist
- Executable permissions are correct
- Script execution and output format
- Documentation completeness
- Test suite coverage
- Optional Crystal syntax validation (when Crystal is installed)

### Dependency Compatibility Check

Check that all required dependencies are installed and compatible:

```bash
# Run the dependency compatibility check
./scripts/validation/check_dependencies.sh
```

This checks:
- Crystal compiler and version compatibility
- Database dependencies (SQLite3, PostgreSQL)
- Shard dependencies from shard.yml
- Profiling tool component files
- Guix environment (if available)

### Guix Package Validation

For Guix users, validate the Guix package definitions:

```bash
# Run Guix package validation
./scripts/validation/validate-guix-packages.sh
```

This validates:
- Package definition files exist (gnu/packages/opencog.scm)
- Guix manifest exists (guix.scm)
- Channel definition exists (.guix-channel)
- Optional Scheme syntax validation (when Guile is installed)

### Complete Validation Suite

Run all validation checks at once:

```bash
# Run profiling tools validation
./scripts/validation/validate_profiling_tools.sh

# Run dependency compatibility check
./scripts/validation/check_dependencies.sh

# Run Guix package validation
./scripts/validation/validate-guix-packages.sh
```

For detailed validation reports, see:
- [Profiling Tools Validation Report](scripts/validation/PROFILING_TOOLS_VALIDATION_REPORT.md)

## Production Deployment

CrystalCog includes comprehensive production deployment scripts for enterprise-ready environments:

### Automated Production Setup

```bash
# Run the production environment setup (requires root)
sudo ./scripts/production/setup-production.sh

# Or with custom configuration
sudo ./scripts/production/setup-production.sh \
  --install-dir /opt/crystalcog \
  --service-user crystalcog \
  --backup-dir /backup/crystalcog
```

The production setup script automatically configures:
- **Docker & Docker Compose**: Containerized deployment
- **System Security**: UFW firewall, fail2ban intrusion detection
- **SSL Certificates**: Automated certificate management
- **Service Management**: Systemd service for auto-start
- **Monitoring Stack**: Prometheus, Grafana, and ELK stack
- **Backup System**: Automated backup cron jobs
- **Log Rotation**: Automatic log management

### Deployment Features

- **High Availability**: Multi-container architecture with health checks
- **Security Hardened**: Minimal attack surface, non-root containers
- **Monitoring Ready**: Complete observability stack included
- **Backup & Recovery**: Automated data protection
- **Scalable**: Resource limits and scaling configuration

### Validation & Testing

Validate your production setup:

```bash
# Comprehensive validation
./validate-setup-production.sh

# Docker Compose validation  
docker-compose -f docker-compose.production.yml config

# Health check
./scripts/production/healthcheck.sh
```

### Deployment Options

- **Container Deployment**: `docker-compose.production.yml`
- **Kubernetes Deployment**: `deployments/k8s/`
- **Guix System**: `guix environment -m guix.scm`
- **Manual Installation**: Traditional system installation

## Troubleshooting

### Common Issues

#### RocksDB Dependency Not Found

If you encounter RocksDB linking errors during build or test:

```bash
# Error: cannot find -lrocksdb
# Solution: Use the DISABLE_ROCKSDB environment variable

export DISABLE_ROCKSDB=1
./scripts/test-runner.sh --all

# Or for individual commands:
DISABLE_ROCKSDB=1 crystal spec spec/atomspace/
DISABLE_ROCKSDB=1 crystal build src/crystalcog.cr
```

RocksDB is an optional high-performance storage backend. The system will use SQLite and PostgreSQL backends when RocksDB is disabled.

#### Crystal Installation Issues

The test runner automatically installs Crystal if it's not found. If automatic installation fails:

```bash
# Manual installation
./scripts/install-crystal.sh --help
./scripts/install-crystal.sh

# Or use system package manager
# Ubuntu/Debian:
curl -fsSL https://crystal-lang.org/install.sh | sudo bash

# macOS:
brew install crystal
```

#### Test Failures

If tests fail unexpectedly:

```bash
# 1. Ensure dependencies are installed
shards install

# 2. Try with verbose output
./scripts/test-runner.sh --component atomspace --verbose

# 3. Run specific test file
crystal spec spec/atomspace/atomspace_spec.cr --verbose

# 4. Check formatting issues
crystal tool format --check src/ spec/
```

For more troubleshooting information, see the [Test Runner Validation Report](docs/TEST_RUNNER_VALIDATION_REPORT.md).

## Set up (Legacy Python/Rust Environment)
CrystalCog is a complete Crystal language implementation with all functionality.

## Documentation

For complete documentation, see the [Documentation Index](docs/INDEX.md).

**Key Documents:**
- [Development Roadmap](docs/DEVELOPMENT-ROADMAP.md) - Project roadmap and implementation plan
- [Crystal Installation Guide](docs/CRYSTAL_INSTALLATION.md) - Installation instructions
- [API Documentation](docs/API_DOCUMENTATION.md) - Complete API reference
- [Examples Guide](examples/README.md) - Example programs and usage
- [Persistence API](docs/PERSISTENCE_API_DOCUMENTATION.md) - Storage backend documentation
- [Advanced Pattern Matching](docs/ADVANCED_PATTERN_MATCHING.md) - Pattern matching guide
- [PLN Reasoning](docs/PLN-REASONING-MODULE.md) - Probabilistic Logic Networks
- [Production Deployment](docs/PRODUCTION_DEPLOYMENT.md) - Deployment guide
- [Integration Test Validation](docs/INTEGRATION_TEST_VALIDATION.md) - Integration test validation
- [Security Policy](docs/SECURITY.md) - Security and vulnerability reporting

## Contributing

1. Install Crystal using the provided scripts
2. Run the test suite to verify your environment
3. Make changes and test thoroughly
4. Submit pull requests with comprehensive tests

## License

This repository is licensed under the AGPL-3.0 License. See the `LICENSE` file for more information.

---

**Note**: CrystalCog represents a next-generation implementation of OpenCog, providing improved performance and safety while maintaining full compatibility with OpenCog concepts and APIs.
