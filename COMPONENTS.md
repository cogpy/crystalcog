# CrystalCog Components

## Overview

CrystalCog is organized into multiple components, each providing specific functionality. This document lists all buildable components and their purposes.

---

## Component Architecture

```
CrystalCog
├── Core Libraries (5)
│   ├── cogutil
│   ├── atomspace
│   ├── opencog
│   ├── pln
│   └── ure
│
├── Main Executables (9)
│   ├── atomspace_main
│   ├── cogserver
│   ├── attention
│   ├── pattern_matching
│   ├── pattern_mining
│   ├── nlp
│   ├── moses
│   ├── learning
│   └── ml
│
└── Main Application (1)
    └── crystalcog
```

---

## Core Libraries

### 1. CogUtil
**File**: `src/cogutil/cogutil.cr`  
**Purpose**: Core utilities and helper functions  
**Build**: `crystal build src/cogutil/cogutil.cr -o bin/cogutil`

**Features**:
- Configuration management
- Logging utilities
- Performance monitoring
- Common data structures

---

### 2. AtomSpace
**File**: `src/atomspace/atomspace.cr`  
**Purpose**: Core knowledge representation system  
**Build**: `crystal build src/atomspace/atomspace.cr -o bin/atomspace`

**Features**:
- Atom storage and retrieval
- Type system
- Truth values
- Attention values
- Distributed storage with LRU caching

---

### 3. OpenCog
**File**: `src/opencog/opencog.cr`  
**Purpose**: Main OpenCog framework integration  
**Build**: `crystal build src/opencog/opencog.cr -o bin/opencog`

**Features**:
- Framework initialization
- Component coordination
- System-wide configuration

---

### 4. PLN (Probabilistic Logic Networks)
**File**: `src/pln/pln.cr`  
**Purpose**: Probabilistic reasoning engine  
**Build**: `crystal build src/pln/pln.cr -o bin/pln`

**Features**:
- Inference rules
- Probabilistic reasoning
- Logical deduction
- Uncertainty handling

---

### 5. URE (Unified Rule Engine)
**File**: `src/ure/ure.cr`  
**Purpose**: Generic rule-based reasoning engine  
**Build**: `crystal build src/ure/ure.cr -o bin/ure`

**Features**:
- Rule application
- Forward/backward chaining
- Rule selection
- Inference control

---

## Main Executables

### 1. AtomSpace Main
**File**: `src/atomspace/atomspace_main.cr`  
**Purpose**: Standalone AtomSpace server  
**Build**: `crystal build src/atomspace/atomspace_main.cr -o bin/atomspace_main`

**Usage**:
```bash
./bin/atomspace_main [options]
```

---

### 2. CogServer
**File**: `src/cogserver/cogserver_main.cr`  
**Purpose**: Network server for AtomSpace operations  
**Build**: `crystal build src/cogserver/cogserver_main.cr -o bin/cogserver`

**Features**:
- REST API
- WebSocket support
- Real-time monitoring
- Remote atom operations

**Usage**:
```bash
./bin/cogserver --port 18080
```

---

### 3. Attention
**File**: `src/attention/attention_main.cr`  
**Purpose**: Attention allocation mechanism  
**Build**: `crystal build src/attention/attention_main.cr -o bin/attention`

**Features**:
- Importance spreading
- Attention focus
- Resource allocation
- Forgetting mechanism

---

### 4. Pattern Matching
**File**: `src/pattern_matching/pattern_matching_main.cr`  
**Purpose**: Pattern matching engine  
**Build**: `crystal build src/pattern_matching/pattern_matching_main.cr -o bin/pattern_matching`

**Features**:
- Graph pattern matching
- Variable binding
- Pattern queries
- Subgraph isomorphism

---

### 5. Pattern Mining
**File**: `src/pattern_mining/pattern_mining_main.cr`  
**Purpose**: Pattern discovery and mining  
**Build**: `crystal build src/pattern_mining/pattern_mining_main.cr -o bin/pattern_mining`

**Features**:
- Frequent pattern mining
- Surprising pattern detection
- Pattern evaluation
- Knowledge discovery

---

### 6. NLP (Natural Language Processing)
**File**: `src/nlp/nlp_main.cr`  
**Purpose**: Natural language processing pipeline  
**Build**: `crystal build src/nlp/nlp_main.cr -o bin/nlp`

**Features**:
- Text parsing
- Semantic analysis
- Language understanding
- Text generation

---

### 7. MOSES (Meta-Optimizing Semantic Evolutionary Search)
**File**: `src/moses/moses_main.cr`  
**Purpose**: Program learning and evolution  
**Build**: `crystal build src/moses/moses_main.cr -o bin/moses`

**Features**:
- Evolutionary programming
- Program synthesis
- Optimization
- Feature selection

---

### 8. Learning
**File**: `src/learning/learning_main.cr`  
**Purpose**: Machine learning algorithms  
**Build**: `crystal build src/learning/learning_main.cr -o bin/learning`

**Features**:
- Supervised learning
- Unsupervised learning
- Reinforcement learning
- Model training

---

### 9. ML (Machine Learning)
**File**: `src/ml/ml_main.cr`  
**Purpose**: Machine learning utilities and tools  
**Build**: `crystal build src/ml/ml_main.cr -o bin/ml`

**Features**:
- Data preprocessing
- Model evaluation
- Feature engineering
- ML pipeline management

---

## Main Application

### CrystalCog
**File**: `src/crystalcog.cr`  
**Purpose**: Main integrated application  
**Build**: `crystal build src/crystalcog.cr`

**Features**:
- Integrates all components
- Unified command-line interface
- Configuration management
- Component coordination

**Usage**:
```bash
./crystalcog [command] [options]
```

---

## Building All Components

### Quick Build
```bash
# Build main application
crystal build src/crystalcog.cr

# Build all components
mkdir -p bin

# Core libraries
crystal build src/cogutil/cogutil.cr -o bin/cogutil
crystal build src/atomspace/atomspace.cr -o bin/atomspace
crystal build src/opencog/opencog.cr -o bin/opencog
crystal build src/pln/pln.cr -o bin/pln
crystal build src/ure/ure.cr -o bin/ure

# Main executables
crystal build src/atomspace/atomspace_main.cr -o bin/atomspace_main
crystal build src/cogserver/cogserver_main.cr -o bin/cogserver
crystal build src/attention/attention_main.cr -o bin/attention
crystal build src/pattern_matching/pattern_matching_main.cr -o bin/pattern_matching
crystal build src/pattern_mining/pattern_mining_main.cr -o bin/pattern_mining
crystal build src/nlp/nlp_main.cr -o bin/nlp
crystal build src/moses/moses_main.cr -o bin/moses
crystal build src/learning/learning_main.cr -o bin/learning
crystal build src/ml/ml_main.cr -o bin/ml
```

### Build Script
```bash
#!/bin/bash
# build_all.sh

set -e

echo "Building CrystalCog components..."
mkdir -p bin

# Main application
echo "Building crystalcog..."
crystal build src/crystalcog.cr

# Core libraries
for lib in cogutil atomspace opencog pln ure; do
    echo "Building $lib..."
    crystal build src/$lib/$lib.cr -o bin/$lib || echo "⚠️  $lib skipped"
done

# Main executables
for exe in atomspace_main cogserver attention pattern_matching pattern_mining nlp moses learning ml; do
    echo "Building $exe..."
    if [ "$exe" = "atomspace_main" ]; then
        crystal build src/atomspace/atomspace_main.cr -o bin/$exe || echo "⚠️  $exe skipped"
    elif [ "$exe" = "cogserver" ]; then
        crystal build src/cogserver/cogserver_main.cr -o bin/$exe || echo "⚠️  $exe skipped"
    else
        crystal build src/$exe/${exe}_main.cr -o bin/$exe || echo "⚠️  $exe skipped"
    fi
done

echo ""
echo "Build complete!"
ls -lh bin/
```

---

## GitHub Actions Integration

All components are automatically built in CI/CD workflows:

### Workflows Building All Components
1. **CrystalCog E2E CI/CD** (`.github/workflows/ci-e2e.yml`)
2. **Comprehensive Crystal CI** (`.github/workflows/crystal-comprehensive-ci.yml`)

### Build Steps
```yaml
- name: Build all components
  run: |
    mkdir -p bin
    
    # Core libraries (5)
    crystal build src/cogutil/cogutil.cr -o bin/cogutil
    crystal build src/atomspace/atomspace.cr -o bin/atomspace
    crystal build src/opencog/opencog.cr -o bin/opencog
    crystal build src/pln/pln.cr -o bin/pln
    crystal build src/ure/ure.cr -o bin/ure
    
    # Main executables (9)
    crystal build src/atomspace/atomspace_main.cr -o bin/atomspace_main
    crystal build src/cogserver/cogserver_main.cr -o bin/cogserver
    crystal build src/attention/attention_main.cr -o bin/attention
    crystal build src/pattern_matching/pattern_matching_main.cr -o bin/pattern_matching
    crystal build src/pattern_mining/pattern_mining_main.cr -o bin/pattern_mining
    crystal build src/nlp/nlp_main.cr -o bin/nlp
    crystal build src/moses/moses_main.cr -o bin/moses
    crystal build src/learning/learning_main.cr -o bin/learning
    crystal build src/ml/ml_main.cr -o bin/ml
```

---

## Component Dependencies

```
crystalcog
  ├─ cogutil (base utilities)
  ├─ atomspace
  │   └─ cogutil
  ├─ opencog
  │   ├─ cogutil
  │   └─ atomspace
  ├─ pln
  │   ├─ atomspace
  │   └─ ure
  ├─ ure
  │   └─ atomspace
  ├─ attention
  │   └─ atomspace
  ├─ pattern_matching
  │   └─ atomspace
  ├─ pattern_mining
  │   ├─ atomspace
  │   └─ pattern_matching
  ├─ nlp
  │   └─ atomspace
  ├─ moses
  │   └─ atomspace
  ├─ learning
  │   └─ atomspace
  └─ ml
      └─ atomspace
```

---

## Testing Components

Each component has associated tests in the `spec/` directory:

```bash
# Run all tests
crystal spec

# Run specific component tests
crystal spec spec/cogutil/
crystal spec spec/atomspace/
crystal spec spec/pln/
```

---

## Component Status

| Component | Type | Build Status | Tests | Documentation |
|-----------|------|--------------|-------|---------------|
| cogutil | Library | ✅ | ✅ | ✅ |
| atomspace | Library | ✅ | ✅ | ✅ |
| opencog | Library | ✅ | ✅ | ✅ |
| pln | Library | ✅ | ✅ | ✅ |
| ure | Library | ✅ | ✅ | ✅ |
| atomspace_main | Executable | ✅ | ✅ | ✅ |
| cogserver | Executable | ✅ | ✅ | ✅ |
| attention | Executable | ⚠️ | ⚠️ | ⚠️ |
| pattern_matching | Executable | ⚠️ | ⚠️ | ⚠️ |
| pattern_mining | Executable | ⚠️ | ⚠️ | ⚠️ |
| nlp | Executable | ⚠️ | ⚠️ | ⚠️ |
| moses | Executable | ⚠️ | ⚠️ | ⚠️ |
| learning | Executable | ⚠️ | ⚠️ | ⚠️ |
| ml | Executable | ⚠️ | ⚠️ | ⚠️ |

Legend:
- ✅ Complete and working
- ⚠️ Work in progress
- ❌ Not implemented

---

## Development Guidelines

### Adding a New Component

1. **Create component directory**: `src/my_component/`
2. **Create library file**: `src/my_component/my_component.cr`
3. **Create main file** (if executable): `src/my_component/my_component_main.cr`
4. **Add tests**: `spec/my_component/my_component_spec.cr`
5. **Update workflows**: Add build step to CI/CD workflows
6. **Update this document**: Add component to the list

### Component Structure

```
src/my_component/
├── my_component.cr          # Main library file
├── my_component_main.cr     # Executable entry point (optional)
├── core.cr                  # Core functionality
├── types.cr                 # Type definitions
└── utils.cr                 # Utility functions

spec/my_component/
├── my_component_spec.cr     # Main test file
├── core_spec.cr             # Core tests
└── utils_spec.cr            # Utility tests
```

---

## Performance Considerations

### Build Times (Approximate)

| Component | Build Time | Binary Size |
|-----------|------------|-------------|
| cogutil | 10-15s | 5 MB |
| atomspace | 15-20s | 8 MB |
| opencog | 20-25s | 10 MB |
| pln | 15-20s | 7 MB |
| ure | 15-20s | 7 MB |
| atomspace_main | 20-30s | 12 MB |
| cogserver | 25-35s | 15 MB |
| crystalcog | 30-45s | 21 MB |

### Optimization Tips

1. **Use `--release` flag** for production builds
2. **Enable `--static` flag** for standalone binaries
3. **Use `--no-debug` flag** to reduce binary size
4. **Cache dependencies** in CI/CD workflows

---

## Troubleshooting

### Common Build Issues

#### Missing Dependencies
```bash
# Install system dependencies
sudo apt-get install libsqlite3-dev librocksdb-dev libevent-dev
```

#### Compilation Errors
```bash
# Clean and rebuild
rm -rf lib/ shard.lock
shards install
crystal build src/crystalcog.cr
```

#### Linker Errors
```bash
# Clear Crystal cache
rm -rf ~/.cache/crystal
crystal build src/crystalcog.cr
```

---

## Resources

- **Main Repository**: https://github.com/cogpy/crystalcog
- **Documentation**: See `docs/` directory
- **Examples**: See `examples/` directory
- **Tests**: See `spec/` directory

---

**Last Updated**: December 12, 2025  
**Total Components**: 15 (5 libraries + 9 executables + 1 main app)  
**Build System**: Crystal 1.14.0
