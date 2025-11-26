# CrystalCog Guix Packaging

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

Or to install the packages:

```bash
guix install -m guix.scm
```

### Installing Individual Packages

```bash
# Main CrystalCog platform
guix install crystalcog

# Core utilities
guix install crystalcog-cogutil

# AtomSpace hypergraph database
guix install crystalcog-atomspace

# Main cognitive architecture
guix install crystalcog-opencog
```

## Package Structure

- **crystalcog**: The complete CrystalCog platform (meta-package)
- **crystalcog-cogutil**: Low-level Crystal utilities (logging, config, random)
- **crystalcog-atomspace**: The hypergraph database and knowledge representation system
- **crystalcog-opencog**: The main cognitive architecture reasoning platform

## Development

### Testing Package Definitions

To test the package definitions locally:

```bash
# Validate package syntax
./scripts/validation/validate-guix-packages.sh

# Test with Guile (if available)
guile -c "(add-to-load-path \".\") (use-modules (gnu packages crystalcog))"

# Build a package
guix build crystalcog --no-substitutes
```

### Building from Source

The packages are configured to build from the Git repository. To modify 
the source or use local development versions, you can:

1. Fork the packages and modify the source URLs
2. Use `guix environment` with `--ad-hoc crystal` to work with development versions
3. Create local package variants using `package/inherit`

## Dependencies

The CrystalCog packages require several dependencies that are automatically 
handled by Guix:

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