# CrystalCog Guix Packaging

This directory contains GNU Guix package definitions for CrystalCog and related components.

## Package Structure

CrystalCog provides two package module locations:

1. **gnu/packages/crystalcog.scm** - Main CrystalCog package definitions following Guix conventions
2. **agent-zero/packages/cognitive.scm** - Agent-Zero cognitive packages with Guile bindings
This directory contains GNU Guix package definitions for CrystalCog and Agent-Zero components.
This directory contains GNU Guix package definitions for CrystalCog and related components.

## Using the Packages

### As a Guix Channel

1. Add this repository as a Guix channel by creating/editing `~/.config/guix/channels.scm`:

```scheme
(cons* (channel
        (name 'crystalcog)
        (url "https://github.com/cogpy/crystalcog.git")
        (branch "main")
        (introduction
         (make-channel-introduction
          "COMMIT_HASH_HERE"
          (openpgp-fingerprint "FINGERPRINT_HERE"))))
       %default-channels)
```

2. Update Guix to include the new channel:

```bash
guix pull
```

### Using the Manifest

To create a development environment with all CrystalCog packages:

```bash
guix environment -m guix.scm
```

Or use the newer `guix shell` command:

```bash
guix shell -m guix.scm
```

### Installing Individual Packages

Note: Individual package installation is currently not supported as these are
placeholder packages for development environment setup. The packages will be
properly installable once CrystalCog reaches production maturity.

For now, use the manifest-based development environment:

```bash
# Enter development shell with all dependencies
guix shell -m guix.scm
```bash
# Main CrystalCog platform
guix install crystalcog

# Core utilities
guix install crystalcog-cogutil

# AtomSpace hypergraph database
guix install crystalcog-atomspace

# Guile bindings for specific components
guix install guile-pln guile-ecan guile-moses
# Main cognitive architecture
guix install crystalcog-opencog
```

## Package Structure

### Core Packages (gnu/packages/crystalcog.scm)

- **crystalcog**: Main Crystal-based cognitive architecture platform
  - Includes all components: AtomSpace, PLN, URE, MOSES, NLP, etc.
- **crystalcog-cogutil**: Core utilities (logging, config, random)
- **crystalcog-atomspace**: Hypergraph database and reasoning engine

### Agent-Zero Cognitive Packages (agent-zero/packages/cognitive.scm)

- **opencog**: Re-exported crystalcog package for compatibility
- **ggml**: Tensor library for machine learning integration
- **guile-pln**: Guile bindings for Probabilistic Logic Networks
- **guile-ecan**: Guile bindings for attention allocation
- **guile-moses**: Guile bindings for evolutionary optimization
- **guile-pattern-matcher**: Guile bindings for pattern matching
- **guile-relex**: Guile bindings for natural language processing
CrystalCog provides the following Guix packages:

- **opencog**: Core cognitive architecture implemented in Crystal
- **ggml**: Tensor library integration for machine learning
- **guile-pln**: Probabilistic Logic Networks Guile bindings
- **guile-ecan**: Economic Attention Network Guile bindings  
- **guile-moses**: MOSES evolutionary learning Guile bindings
- **guile-pattern-matcher**: Pattern matching engine Guile bindings
- **guile-relex**: Natural language processing Guile bindings
- **crystalcog**: The complete CrystalCog platform (meta-package)
- **crystalcog-cogutil**: Low-level Crystal utilities (logging, config, random)
- **crystalcog-atomspace**: The hypergraph database and knowledge representation system
- **crystalcog-opencog**: The main cognitive architecture reasoning platform

## Development

### Testing Package Definitions

To validate the package definitions:

```bash
# Run the validation script
./scripts/validation/validate-guix-packages.sh

# Test syntax (requires Guile)
guile -c "(add-to-load-path \".\") (use-modules (gnu packages crystalcog))"

# Build a package (requires Guix)
# Validate package module syntax
guix shell guile -- guile -c "(use-modules (agent-zero packages cognitive))"

# Test manifest loading
guix shell guile -- guile -c "(load \"guix.scm\")"

# Run validation script
./scripts/validation/validate-guix-packages.sh
# Validate package syntax
./scripts/validation/validate-guix-packages.sh

# Test with Guile (if available)
guile -c "(add-to-load-path \".\") (use-modules (gnu packages crystalcog))"

# Build a package
guix build crystalcog --no-substitutes
```

### Building from Source

The packages are configured to build from the CrystalCog Git repository. To modify 
The packages are currently placeholders for development environment setup.
To build CrystalCog from source:

```bash
# Enter Guix development shell
guix shell -m guix.scm

# Build CrystalCog components
crystal build src/crystalcog.cr
crystal spec

# Or use the test runner
./scripts/test-runner.sh --all
```

## Dependencies

The CrystalCog development environment includes:

- **Build tools**: CMake, GCC toolchain, pkg-config
- **Libraries**: Boost, Guile 3.0
- **Crystal Language**: Installed via the project's installation scripts
- **Cognitive packages**: PLN, ECAN, MOSES, pattern matcher, RelEx bindings

Note: Crystal itself is not yet available in Guix, so it should be installed
using the project's installation scripts (`./scripts/install-crystal.sh`).
The packages are configured to build from the Git repository. To modify 
the source or use local development versions, you can:

1. Fork the packages and modify the source URLs
2. Use `guix environment` with `--ad-hoc crystal` to work with development versions
3. Create local package variants using `package/inherit`

## Dependencies

The CrystalCog packages require several dependencies that are automatically 
handled by Guix:

- **Build tools**: Crystal compiler, shards (Crystal dependency manager), pkg-config
- **Libraries**: PostgreSQL, SQLite (for persistent storage)
- **Runtime**: Crystal runtime libraries

For Guile bindings:
- **Guile**: Guile 3.0 or later
- **guile-lib**: Guile utility libraries

## License

The package definitions are licensed under GPL v3+, matching the OpenCog
project licensing. CrystalCog itself is licensed under AGPL-3.0.
- **Build tools**: Crystal compiler, pkg-config
- **Databases**: SQLite, PostgreSQL
- **Runtime**: Crystal runtime libraries

## Compatibility

For compatibility with existing OpenCog documentation and tooling, we provide:

- `(gnu packages opencog)`: Re-exports CrystalCog packages with OpenCog-compatible names

This allows existing Guix channels and scripts to work without modification.

## License

The package definitions are licensed under AGPL v3+, matching the CrystalCog
project licensing.
