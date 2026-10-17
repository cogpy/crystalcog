# OpenCog Guix Packaging

This directory contains GNU Guix package definitions for OpenCog and related components.

## Using the Packages

### As a Guix Channel

1. Add this repository as a Guix channel by creating/editing `~/.config/guix/channels.scm`:

```scheme
(cons* (channel
        (name 'opencog-central)
        (url "https://github.com/EchoCog/opencog-central.git")
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

To create a development environment with all OpenCog packages:

```bash
guix environment -m guix.scm
```

Or to install the packages:

```bash
guix install -m guix.scm
```

### Installing Individual Packages

```bash
# Core utilities
guix install cogutil

# AtomSpace hypergraph database
guix install atomspace

# Full OpenCog platform
guix install opencog
```

## Package Structure

- **cogutil**: Low-level C++ utilities used across OpenCog projects
- **atomspace**: The hypergraph database, query system and rule engine
- **opencog**: The main cognitive architecture platform

## Development

### Testing Package Definitions

To test the package definitions locally:

```bash
# Test syntax
guile -c "(use-modules (gnu packages opencog))"

# Build a package
guix build cogutil --no-substitutes
```

### Building from Source

The packages are configured to build from upstream Git repositories. To modify 
the source or use local development versions, you can:

1. Fork the packages and modify the source URLs
2. Use `guix environment` with `--ad-hoc git` to work with development versions
3. Create local package variants using `package/inherit`

## Dependencies

The OpenCog packages require several dependencies that are automatically 
handled by Guix:

- **Build tools**: CMake, GCC toolchain, pkg-config
- **Libraries**: Boost, GMP, Guile 3.0, PostgreSQL
- **Python**: Python 3 with Cython and testing frameworks

## License

The package definitions are licensed under GPL v3+, matching the OpenCog
project licensing.