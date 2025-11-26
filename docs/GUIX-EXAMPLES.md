# CrystalCog Guix Packaging - Example Usage

## Quick Start Example

Once you have Guix installed, you can use the CrystalCog packages in several ways:

### 1. Development Environment

Create a development environment with all CrystalCog dependencies:

```bash
# Clone this repository
git clone https://github.com/cogpy/crystalcog.git
cd crystalcog

# Create development environment
guix environment -m guix.scm

# Now you have access to all CrystalCog components and dependencies
# Now you have access to Crystal, databases, and all dependencies
```

### 2. Install Specific Packages

```bash
# Add this repository as a Guix channel first
# Then install individual packages:

guix install crystalcog           # Main platform
guix install crystalcog-cogutil   # Core utilities
guix install crystalcog-atomspace # Hypergraph database
guix install crystalcog           # Complete platform
guix install crystalcog-cogutil   # Core utilities
guix install crystalcog-atomspace # Hypergraph database
guix install crystalcog-opencog   # Cognitive architecture
```

### 3. Using in Other Projects

Create a `guix.scm` manifest in your project:

```scheme
(use-modules (gnu packages crystalcog)
             (gnu packages crystal)
             (gnu packages guile))
             (gnu packages databases))

(packages->manifest
  (list crystalcog
        crystalcog-atomspace
        crystalcog-cogutil
        guile-3.0
        crystal))
        crystal
        sqlite
        postgresql))
```

### 4. Container Deployment

```bash
# Create a container with CrystalCog
guix pack -f docker crystalcog

# Create a tarball with CrystalCog and dependencies
guix pack -f tarball crystalcog
# Create a tarball for deployment
guix pack crystalcog crystalcog-atomspace
```

### 5. Building from Source

```bash
# Build a specific package from source
guix build crystalcog --no-substitutes

# Build with debugging information
guix build crystalcog-atomspace --with-debug-info=crystalcog-atomspace

# Build all components
guix build crystalcog crystalcog-cogutil crystalcog-atomspace crystalcog-opencog
```

## Package Dependencies

The packages automatically handle dependencies:

- **crystalcog-cogutil**: Crystal compiler, pkg-config
- **crystalcog-atomspace**: crystalcog-cogutil + Crystal + PostgreSQL + SQLite
- **crystalcog**: crystalcog-atomspace + crystalcog-cogutil + all cognitive modules

## Guile Bindings

The Agent-Zero cognitive packages provide Guile bindings for Scheme access:

```bash
# Install Guile bindings
guix install guile-pln guile-ecan guile-moses

# Use in Guile REPL
guile -c "(use-modules (agent-zero packages cognitive))"
```
- **crystalcog-cogutil**: Crystal runtime
- **crystalcog-atomspace**: crystalcog-cogutil + SQLite, PostgreSQL
- **crystalcog-opencog**: crystalcog-atomspace + crystalcog-cogutil
- **crystalcog**: All components together

## Development Workflow

1. Set up the environment: `guix environment -m guix.scm`
2. Make changes to CrystalCog components
3. Test builds: `crystal build src/crystalcog.cr`
4. Run tests: `crystal spec`
5. Deploy: Use `guix pack` or container images
3. Run tests: `./scripts/test-runner.sh --all`
4. Build: `crystal build src/crystalcog.cr`
5. Deploy: Use `guix pack` or container images

## Validation

Validate the Guix package setup:

```bash
# Run validation script
./scripts/validation/validate-guix-packages.sh

# Test package syntax (requires Guile)
guile -c "(add-to-load-path \".\") (use-modules (gnu packages crystalcog))"

# Test manifest
guile -c "(add-to-load-path \".\") (load \"guix.scm\")"
```

This provides a fully reproducible CrystalCog development and deployment environment.