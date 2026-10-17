# Tools

This directory contains utility and debug tools for the CrystalCog project.

## Directory Structure

```
tools/
├── debug/                 # Debug utilities
│   ├── debug_atomspace.cr # AtomSpace debugging tool
│   └── debug_storage.cr   # Storage debugging tool
└── start_test_cogserver.cr # CogServer test launcher
```

## Usage

### Debug Tools

```bash
# Debug AtomSpace operations
crystal run tools/debug/debug_atomspace.cr

# Debug storage backends
crystal run tools/debug/debug_storage.cr
```

### Test CogServer

```bash
# Start a test CogServer instance
crystal run tools/start_test_cogserver.cr
```
