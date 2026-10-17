# OpenCog Guix Packaging - Example Usage

## Quick Start Example

Once you have Guix installed, you can use the OpenCog packages in several ways:

### 1. Development Environment

Create a development environment with all OpenCog dependencies:

```bash
# Clone this repository
git clone https://github.com/EchoCog/opencog-central.git
cd opencog-central

# Create development environment
guix environment -m guix.scm

# Now you have access to all OpenCog components and dependencies
```

### 2. Install Specific Packages

```bash
# Add this repository as a Guix channel first
# Then install individual packages:

guix install cogutil      # Core utilities
guix install atomspace    # Hypergraph database
guix install opencog      # Full platform
```

### 3. Using in Other Projects

Create a `guix.scm` manifest in your project:

```scheme
(use-modules (gnu packages opencog)
             (gnu packages guile))

(packages->manifest
  (list opencog
        atomspace
        cogutil
        guile-3.0))
```

### 4. Container Deployment

```bash
# Create a container with OpenCog
guix pack -f docker opencog
```

### 5. Building from Source

```bash
# Build a specific package from source
guix build cogutil --no-substitutes

# Build with debugging information
guix build atomspace --with-debug-info=atomspace
```

## Package Dependencies

The packages automatically handle dependencies:

- **cogutil**: Boost, GMP, CMake, C++ testing frameworks
- **atomspace**: cogutil + Guile 3.0, PostgreSQL, Python, Cython
- **opencog**: atomspace + cogutil + additional cognitive modules

## Development Workflow

1. Set up the environment: `guix environment -m guix.scm`
2. Make changes to OpenCog components
3. Test builds: `guix build cogutil atomspace opencog`
4. Deploy: Use `guix pack` or container images

This provides a fully reproducible OpenCog development and deployment environment.